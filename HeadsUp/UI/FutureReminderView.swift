import SwiftUI

/// A self-contained visual draft. Nothing in this view writes tracker settings
/// or talks to the system notification or Screen Time APIs.
struct FutureReminderView: View {
    @State private var remindersEnabled = true
    @State private var firstReminderMinutes = 10
    @State private var resetMinutes = 3
    @State private var soundEnabled = true
    @State private var replyEnabled = true
    @State private var messageIndex = 0
    @State private var previewPaused = false
    @State private var showPauseResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureReminderPreviewNote()

                FutureCard {
                    Toggle("开启提醒", isOn: $remindersEnabled)
                        .tint(FutureTheme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }

                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("提醒规则")
                    FutureCard {
                        VStack(spacing: 0) {
                            FutureSettingsRow("计时范围", value: "所选 App 共同累计", chevron: false)
                            rowDivider
                            NavigationLink {
                                FutureReminderTimingView(minutes: $firstReminderMinutes)
                            } label: {
                                FutureSettingsRow("提醒时机", value: "本轮累计\(firstReminderMinutes)分钟")
                            }
                            rowDivider
                            NavigationLink {
                                FutureReminderResetView(minutes: $resetMinutes)
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    FutureSettingsRow("重新计时", value: "离开\(resetMinutes)分钟")
                                    Text("连续离开全部所选 App")
                                        .font(.subheadline)
                                        .foregroundStyle(FutureTheme.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 14)
                                }
                            }
                            rowDivider
                            NavigationLink {
                                FutureReminderFollowUpView(firstReminderMinutes: firstReminderMinutes)
                            } label: {
                                FutureSettingsRow("后续提醒", value: "间隔逐次减半")
                            }
                        }
                    }
                }

                FutureCard {
                    NavigationLink {
                        FutureReminderContentView(
                            firstReminderMinutes: firstReminderMinutes,
                            soundEnabled: $soundEnabled,
                            replyEnabled: $replyEnabled,
                            messageIndex: $messageIndex
                        )
                    } label: {
                        FutureSettingsRow("提醒内容", value: "预览与声音")
                    }
                }

                VStack(spacing: 9) {
                    Button {
                        previewPaused.toggle()
                        showPauseResult = true
                    } label: {
                        Text(previewPaused ? "恢复监控" : "暂停监控")
                            .font(.body.weight(.medium))
                            .foregroundStyle(FutureTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FutureTheme.card, in: RoundedRectangle(cornerRadius: 15))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .strokeBorder(FutureTheme.secondary.opacity(0.14), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    Text(previewPaused ? "预览状态：已暂停" : "仅演示暂停状态")
                        .font(.footnote)
                        .foregroundStyle(FutureTheme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(FutureTheme.background)
        .navigationTitle("提醒")
        .tint(FutureTheme.accent)
        .buttonStyle(.plain)
        .alert(previewPaused ? "暂停预览" : "恢复预览", isPresented: $showPauseResult) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(previewPaused
                 ? "页面已切换为暂停样式。当前记录和真实提醒没有改变。"
                 : "页面已恢复为开启样式。当前记录和真实提醒没有改变。")
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16)
    }
}

private struct FutureReminderPreviewNote: View {
    var body: some View {
        Text("样式预览 · 不影响当前提醒")
            .font(.footnote)
            .foregroundStyle(FutureTheme.secondary)
    }
}

private struct FutureReminderTimingView: View {
    @Binding var minutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureReminderPreviewNote()
                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("第一次提醒")
                    FutureCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("本轮累计")
                                Spacer()
                                Menu {
                                    ForEach([5, 10, 15, 20, 30], id: \.self) { value in
                                        Button("\(value) 分钟") { minutes = value }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("\(minutes) 分钟")
                                            .monospacedDigit()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(FutureTheme.accent)
                                }
                            }
                            .padding(16)
                            Divider().padding(.leading, 16)
                            Stepper(value: $minutes, in: 1...60) {
                                Text("调整分钟数")
                                    .foregroundStyle(FutureTheme.secondary)
                            }
                            .padding(16)
                        }
                    }
                    Text("所选 App 在同一轮内共同累计，达到 \(minutes) 分钟时提醒一次。")
                        .font(.subheadline)
                        .foregroundStyle(FutureTheme.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(FutureTheme.background)
        .navigationTitle("提醒时机")
        .navigationBarTitleDisplayMode(.large)
        .tint(FutureTheme.accent)
    }
}

private struct FutureReminderResetView: View {
    @Binding var minutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureReminderPreviewNote()
                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("重新开始一轮")
                    FutureCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("连续离开")
                                Spacer()
                                Menu {
                                    ForEach([1, 3, 5, 10], id: \.self) { value in
                                        Button("\(value) 分钟") { minutes = value }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("\(minutes) 分钟")
                                            .monospacedDigit()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(FutureTheme.accent)
                                }
                            }
                            .padding(16)
                            Divider().padding(.leading, 16)
                            Stepper(value: $minutes, in: 1...30) {
                                Text("调整分钟数")
                                    .foregroundStyle(FutureTheme.secondary)
                            }
                            .padding(16)
                        }
                    }
                    Text("连续离开全部所选 App 满 \(minutes) 分钟后，本轮累计归零。只在所选 App 之间切换，不会重新计时。")
                        .font(.subheadline)
                        .foregroundStyle(FutureTheme.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(FutureTheme.background)
        .navigationTitle("重新计时")
        .navigationBarTitleDisplayMode(.large)
        .tint(FutureTheme.accent)
    }
}

private struct FutureReminderFollowUpView: View {
    let firstReminderMinutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureReminderPreviewNote()
                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("提醒节奏")
                    FutureCard {
                        HStack {
                            Text("间隔逐次减半")
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(FutureTheme.accent)
                        }
                        .padding(16)
                    }
                    Text("第一次提醒后，继续使用所选 App，下一段提醒间隔减为上一段的一半，最短为 10 秒。")
                        .font(.subheadline)
                        .foregroundStyle(FutureTheme.secondary)
                        .padding(.horizontal, 4)
                }
                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("前几次提醒示意")
                    FutureCard {
                        VStack(spacing: 0) {
                            FutureSettingsRow("第一次", value: "累计 \(firstReminderMinutes) 分钟", chevron: false)
                            Divider().padding(.leading, 16)
                            FutureSettingsRow("第二次", value: "再过 \(intervalText(divisor: 2))", chevron: false)
                            Divider().padding(.leading, 16)
                            FutureSettingsRow("第三次", value: "再过 \(intervalText(divisor: 4))", chevron: false)
                            Divider().padding(.leading, 16)
                            FutureSettingsRow("第四次", value: "再过 \(intervalText(divisor: 8))", chevron: false)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(FutureTheme.background)
        .navigationTitle("后续提醒")
        .navigationBarTitleDisplayMode(.large)
    }

    private func intervalText(divisor: Int) -> String {
        let seconds = max(10, Double(firstReminderMinutes * 60) / Double(divisor))
        let wholeMinutes = Int(seconds) / 60
        let remainder = seconds - Double(wholeMinutes * 60)
        let secondsText = remainder.formatted(.number.precision(.fractionLength(0...1)))
        if remainder == 0 { return "\(wholeMinutes) 分钟" }
        if wholeMinutes == 0 { return "\(secondsText) 秒" }
        return "\(wholeMinutes) 分 \(secondsText) 秒"
    }
}

private struct FutureReminderContentView: View {
    let firstReminderMinutes: Int
    @Binding var soundEnabled: Bool
    @Binding var replyEnabled: Bool
    @Binding var messageIndex: Int
    @State private var showReminderPreview = false
    @State private var showReplyPreview = false

    private let titles = ["该抬头啦", "给眼睛放个小假", "先看看身边吧"]
    private let endings = ["休息一下？", "把目光交给远处一会儿。", "放下屏幕，伸个懒腰。"]

    private var reminderTitle: String { titles[messageIndex % titles.count] }
    private var reminderBody: String {
        "所选 App 本轮累计已到 \(firstReminderMinutes) 分钟。\n\(endings[messageIndex % endings.count])"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureReminderPreviewNote()

                VStack(alignment: .leading, spacing: 12) {
                    FutureSectionTitle("通知预览 · 应用内预览")
                    notificationCard
                    Button {
                        messageIndex = (messageIndex + 1) % titles.count
                    } label: {
                        Text("换一句")
                            .font(.body.weight(.medium))
                            .foregroundStyle(FutureTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(FutureTheme.accent.opacity(0.3), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                FutureCard {
                    VStack(spacing: 0) {
                        Toggle("声音", isOn: $soundEnabled)
                            .padding(16)
                        Divider().padding(.leading, 16)
                        Toggle("回复按钮", isOn: $replyEnabled)
                            .padding(16)
                    }
                    .tint(FutureTheme.accent)
                }

                Button {
                    showReminderPreview = true
                } label: {
                    Text("预览提醒")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FutureTheme.actionBackground, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(FutureTheme.background)
        .navigationTitle("提醒内容")
        .navigationBarTitleDisplayMode(.large)
        .tint(FutureTheme.accent)
        .alert("应用内预览 · HEADS UP", isPresented: $showReminderPreview) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("\(reminderTitle)\n\(reminderBody)\n\n没有发送系统通知。")
        }
        .alert("回复按钮预览", isPresented: $showReplyPreview) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("这是应用内示意，没有回应或改变真实提醒。")
        }
    }

    private var notificationCard: some View {
        FutureCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 11) {
                        FutureBrandIcon(size: 44)
                        Text("HEADS UP")
                            .font(.subheadline)
                            .foregroundStyle(FutureTheme.secondary)
                        Spacer()
                        Text("应用内预览")
                            .font(.caption)
                            .foregroundStyle(FutureTheme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reminderTitle)
                            .font(.headline)
                        Text(reminderBody)
                            .font(.body)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(17)
                if replyEnabled {
                    Divider()
                    Button {
                        showReplyPreview = true
                    } label: {
                        Text("知道了")
                            .font(.body.weight(.medium))
                            .foregroundStyle(FutureTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
