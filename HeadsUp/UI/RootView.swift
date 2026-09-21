import Charts
import SwiftUI
import UserNotifications

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot.empty
    @Published var notificationHealth = NotificationHealth.unknown
    @Published var preferences = TrackerPreferences()
    @Published var pausedUntil: Date? = nil
    @Published var message: String?

    func refresh(full: Bool = false) async {
        do {
            snapshot = try await UsageStore.shared.snapshot()
            pausedUntil = await UsageStore.shared.currentPauseUntil()
            if full { notificationHealth = await NotificationService.shared.health() }
        } catch {
            message = error.localizedDescription
        }
    }

    func requestNotifications() async {
        do {
            let granted = try await NotificationService.shared.requestAuthorization()
            notificationHealth = await NotificationService.shared.health()
            message = granted ? "通知权限已开启。" : "通知未授权，计时仍会记录。"
        } catch { message = error.localizedDescription }
    }

    func loadPreferences() async {
        preferences = await UsageStore.shared.currentPreferences()
    }

    func savePreferences() async {
        await UsageStore.shared.updatePreferences(preferences)
        message = "设置已保存，将从下一次进入受监控 App 开始生效。"
        await refresh(full: true)
    }

    func pause(for seconds: TimeInterval) async {
        do {
            try await UsageStore.shared.pause(for: seconds)
            pausedUntil = await UsageStore.shared.currentPauseUntil()
            message = "已暂停到 \(pausedUntil?.formatted(date: .abbreviated, time: .shortened) ?? "稍后")。"
        } catch { message = error.localizedDescription }
    }

    func resumeNow() async {
        await UsageStore.shared.resumeNow()
        pausedUntil = nil
        message = "暂停已解除。"
    }

    func testNotification() async {
        do {
            try await NotificationService.shared.scheduleTestNotification()
            notificationHealth = await NotificationService.shared.health()
            message = "已安排 10 秒后的测试提醒。"
        } catch { message = error.localizedDescription }
    }

    func reset() async {
        do {
            try await UsageStore.shared.reset()
            await refresh(full: true)
            message = "本机记录和待触发提醒已清除。"
        } catch { message = error.localizedDescription }
    }
}

struct RootView: View {
    @StateObject private var model = DashboardModel()
    @StateObject private var futurePreview = FuturePreviewState()
    @AppStorage(InterfaceVersion.storageKey) private var interfaceVersion = InterfaceVersion.current.rawValue
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var blankAfterNotification = false

    var body: some View {
        Group {
            if blankAfterNotification {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            } else if interfaceVersion == InterfaceVersion.future.rawValue {
                FutureRootView(selectedTab: $selectedTab)
                    .environmentObject(futurePreview)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { TodayView(model: model) }
                        .tabItem { Label("今日", systemImage: "timer") }.tag(0)
                    NavigationStack { WeekView(model: model) }
                        .tabItem { Label("7 天", systemImage: "chart.bar") }.tag(1)
                    NavigationStack { SetupView(model: model) }
                        .tabItem { Label("设置", systemImage: "checklist") }.tag(3)
                }
            }
        }
        .task {
            await model.loadPreferences()
            var tick = 0
            while !Task.isCancelled {
                await model.refresh(full: tick % 10 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Heads up", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("好") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .headsUpReminderOpened)) { _ in
            blankAfterNotification = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { blankAfterNotification = false }
        }
        .onChange(of: interfaceVersion) { _, _ in selectedTab = 3 }
    }
}

private struct TodayView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.snapshot.database.state.isOpen ? "受监控 App 正在前台" : "等待受监控 App 打开")
                        .font(.headline)
                    Text(duration(model.snapshot.currentActiveSeconds))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(value: min(1, model.snapshot.currentActiveSeconds / Double(model.preferences.firstReminderMinutes * 60)))
                    Text("累计 \(model.preferences.firstReminderMinutes) 分钟首次提醒，随后逐级缩短至 10 秒")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()

                let today = model.snapshot.today
                HStack {
                    Metric(title: "今日累计", value: duration(model.snapshot.todayTotalSeconds))
                    Metric(title: "打开次数", value: "\(today?.opens ?? 0)")
                }
                HStack {
                    Metric(title: "提醒应触发", value: "\(today?.reminders ?? 0)")
                    Metric(title: "休息不足", value: "\(today?.shortBreaks ?? 0)")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("今日事件").font(.headline)
                    let events = model.snapshot.database.events
                        .filter { Calendar.current.isDateInToday($0.date) }
                        .sorted { $0.date > $1.date }
                    if events.isEmpty {
                        Text("完成两条个人自动化后，这里会出现打开和关闭记录。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            HStack(alignment: .top) {
                                Image(systemName: symbol(event.type))
                                VStack(alignment: .leading) {
                                    Text(event.message)
                                    Text(event.date.formatted(date: .omitted, time: .standard))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Divider()
                        }
                    }
                }
                .cardStyle()
            }
            .padding()
        }
        .navigationTitle("Heads up")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PauseMenu(model: model)
            }
        }
    }
}

private struct PauseMenu: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Menu {
            if model.pausedUntil != nil {
                Button("立即恢复", systemImage: "play.fill") { Task { await model.resumeNow() } }
                Divider()
            }
            Button("暂停 1 小时") { Task { await model.pause(for: 60 * 60) } }
            Button("暂停 4 小时") { Task { await model.pause(for: 4 * 60 * 60) } }
            Button("暂停 6 小时") { Task { await model.pause(for: 6 * 60 * 60) } }
            Button("暂停 1 天") { Task { await model.pause(for: 24 * 60 * 60) } }
            Button("暂停 3 天") { Task { await model.pause(for: 3 * 24 * 60 * 60) } }
        } label: {
            Label(model.pausedUntil == nil ? "暂停" : "已暂停", systemImage: model.pausedUntil == nil ? "pause.circle" : "moon.zzz.fill")
        }
    }
}

private struct WeekView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Chart(model.snapshot.days) { day in
                    BarMark(
                        x: .value("日期", day.day, unit: .day),
                        y: .value("分钟", day.activeSeconds / 60)
                    )
                }
                .frame(height: 260)
                .cardStyle()

                ForEach(model.snapshot.days.reversed()) { day in
                    HStack {
                        Text(day.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        Spacer()
                        Text("\(duration(day.activeSeconds)) · \(day.opens) 次")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle("最近 7 天")
    }
}

private struct SetupView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        List {
            Section {
                InterfaceVersionPicker()
            } header: {
                Text("界面版本")
            } footer: {
                Text("当前版本保留原有功能；未来版本预览新样式，数据管理可操作本机真实记录。切换本身不改变计时与提醒。")
            }
            Section {
                NavigationLink { DataManagementView() } label: {
                    Label("数据管理", systemImage: "externaldrive")
                }
            } header: { Text("本机数据") } footer: {
                Text("导出给 AI、复制或清空使用记录。数据不会自动上传。")
            }
            Section("通知") {
                LabeledContent("授权", value: authorizationText(model.notificationHealth.authorization))
                LabeledContent("横幅", value: model.notificationHealth.alertsEnabled ? "已开启" : "未开启")
                LabeledContent("声音", value: model.notificationHealth.soundsEnabled ? "已开启" : "未开启")
                LabeledContent("待触发", value: "\(model.notificationHealth.pendingCount)")
                Button("申请通知权限") { Task { await model.requestNotifications() } }
                Button("安排 10 秒测试提醒") { Task { await model.testNotification() } }
            }


            Section("计时规则") {
                Stepper("首次提醒：\(model.preferences.firstReminderMinutes) 分钟", value: $model.preferences.firstReminderMinutes, in: 1...120)
                Stepper("重置累计：离开 \(model.preferences.resetAfterMinutes) 分钟", value: $model.preferences.resetAfterMinutes, in: 1...60)
                Button("保存计时设置") { Task { await model.savePreferences() } }
                Text("首次提醒后，间隔依次减半，最低为 10 秒。受 iOS 待处理通知数量限制，系统会预排约 60 条；离开受监控 App 会立即取消。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("必须手动建立的两条自动化") {
                Label("所选 App“已打开” → 开始累计使用", systemImage: "1.circle")
                Label("所选 App“已关闭” → 暂停累计使用", systemImage: "2.circle")
                Label("两条均选择“立即运行”", systemImage: "3.circle")
                Text("每条自动化可以同时勾选小红书、淘宝、微信或其他 App。个人自动化由 iOS 管理，Heads up 无法代替你创建。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("运行状态") {
                LabeledContent("接受的打开", value: "\(model.snapshot.database.events.filter { $0.type == .opened }.count)")
                LabeledContent("接受的关闭", value: "\(model.snapshot.database.events.filter { $0.type == .closed }.count)")
                LabeledContent("异常", value: "\(model.snapshot.database.events.filter { $0.type == .anomaly }.count)")
            }

        }
        .navigationTitle("设置与检查")
    }
}

private struct Metric: View {
    var title: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

private func symbol(_ type: UsageEventType) -> String {
    switch type {
    case .opened: "play.circle.fill"
    case .closed: "stop.circle.fill"
    case .shortBreak: "arrow.uturn.backward.circle.fill"
    case .restCompleted: "checkmark.circle.fill"
    case .reminderDue: "bell.badge.fill"
    case .anomaly: "exclamationmark.triangle.fill"
    case .commitment: "hand.thumbsup.fill"
    }
}

private func authorizationText(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "尚未询问"
    case .denied: "已拒绝"
    case .authorized: "已授权"
    case .provisional: "临时授权"
    case .ephemeral: "临时会话"
    @unknown default: "未知"
    }
}
