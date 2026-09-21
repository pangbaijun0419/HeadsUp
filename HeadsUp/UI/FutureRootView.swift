import SwiftUI

struct FutureRootView: View {
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { FutureHomeView() }
                .tabItem { Label("首页", systemImage: "house") }.tag(0)
            NavigationStack { FutureStatisticsView() }
                .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(1)
            NavigationStack { FutureReminderView() }
                .tabItem { Label("提醒", systemImage: "bell") }.tag(2)
            NavigationStack { FutureSetupView() }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        .tint(FutureTheme.accent)
    }
}

private struct FutureHomeView: View {
    @EnvironmentObject private var preview: FuturePreviewState
    @State private var showAppPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !preview.apps.isEmpty {
                    FutureCard {
                        ForEach(Array(preview.apps.enumerated()), id: \.element.id) { index, app in
                            HStack(spacing: 16) {
                                FutureAppIcon(app: app)
                                Text(app.name).font(.body.weight(.medium))
                                Spacer()
                            }
                            .padding(16)
                            .contextMenu {
                                Button("移出预览列表", systemImage: "minus.circle", role: .destructive) {
                                    preview.apps.removeAll { $0.id == app.id }
                                }
                            }
                            if index < preview.apps.count - 1 { Divider().padding(.leading, 76) }
                        }
                    }
                }
                Button { showAppPicker = true } label: {
                    Label("添加 App", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(FutureTheme.actionBackground, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityIdentifier("futureAddApp")
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background(FutureTheme.background)
        .navigationTitle("我的 App")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("样式预览").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAppPicker) { FutureAppPicker() }
    }
}

private struct FutureAppPicker: View {
    @EnvironmentObject private var preview: FuturePreviewState
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FutureApp.available) { app in
                        Button {
                            if selection.contains(app.id) { selection.remove(app.id) }
                            else { selection.insert(app.id) }
                        } label: {
                            HStack(spacing: 14) {
                                FutureAppIcon(app: app, size: 40)
                                Text(app.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selection.contains(app.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(app.id) ? FutureTheme.accent : .secondary)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityLabel(app.name)
                        .accessibilityValue(selection.contains(app.id) ? "已选择" : "未选择")
                    }
                } footer: {
                    Text("仅编辑预览列表，不读取已安装 App，也不更改当前自动化。")
                }
            }
            .navigationTitle("添加 App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        preview.apps = FutureApp.available.filter { selection.contains($0.id) }
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .tint(FutureTheme.accent)
        .onAppear { selection = Set(preview.apps.map(\.id)) }
    }
}

private struct FutureSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    FutureSectionTitle("界面版本")
                    FutureCard {
                        VStack(alignment: .leading, spacing: 12) {
                            InterfaceVersionPicker()
                            Text("未来版展示示例界面；数据管理使用本机真实记录。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(16)
                    }
                }
                VStack(spacing: 12) {
                    FutureSectionTitle("权限")
                    FutureCard {
                        NavigationLink {
                            FutureInfoView(title: "屏幕使用时间", symbol: "hourglass", bodyText: "未来版本将从这里连接屏幕使用时间。目前只展示界面，尚未接入，也不会申请授权。")
                        } label: { FutureSettingsRow("屏幕使用时间", value: "未接入") }
                        Divider().padding(.leading, 16)
                        NavigationLink {
                            FutureInfoView(title: "通知权限", symbol: "bell.badge", bodyText: "此处是未来版本的权限入口预览，不代表实际授权状态。查看或修改当前通知设置，请先切回当前版本。")
                        } label: { FutureSettingsRow("通知权限", value: "预览入口") }
                    }
                }
                VStack(spacing: 12) {
                    FutureSectionTitle("通用")
                    FutureCard {
                        FutureSettingsRow("外观", value: "跟随系统", chevron: false)
                        Divider().padding(.leading, 16)
                        NavigationLink { DataManagementView() } label: { FutureSettingsRow("数据管理", value: "本机记录") }
                        Divider().padding(.leading, 16)
                        NavigationLink { FuturePreviewDataView() } label: { FutureSettingsRow("预览数据", value: "仅示例") }
                    }
                }
                VStack(spacing: 12) {
                    FutureSectionTitle("关于")
                    FutureCard {
                        NavigationLink {
                            FutureInfoView(title: "帮助", symbol: "questionmark.circle", bodyText: "首页、统计和提醒使用示例数据，用于预览界面。\n\n“数据管理”可以导出或清空本机真实记录，清空前会再次确认。“预览数据”只恢复示例 App 列表。\n\n在设置中选择“当前版本”，即可回到原有功能。")
                        } label: { FutureSettingsRow("帮助") }
                        Divider().padding(.leading, 16)
                        NavigationLink {
                            FutureInfoView(title: "关于 Heads up", symbol: "", bodyText: "抬起头，把时间留给自己。\n\n未来版本 · 界面预览\n设计中的功能将逐步接入。")
                        } label: { FutureSettingsRow("关于 Heads up") }
                    }
                }
            }
            .padding(20)
        }
        .background(FutureTheme.background)
        .navigationTitle("设置")
        .buttonStyle(.plain)
    }
}

private struct FutureInfoView: View {
    let title: String
    let symbol: String
    let bodyText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if symbol.isEmpty { FutureBrandIcon(size: 72) }
                else { Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(FutureTheme.accent) }
                Text(bodyText).font(.body).lineSpacing(7).foregroundStyle(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .background(FutureTheme.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct FuturePreviewDataView: View {
    @EnvironmentObject private var preview: FuturePreviewState
    @State private var restored = false

    var body: some View {
        List {
            Section {
                LabeledContent("数据来源", value: "内置示例")
                LabeledContent("预览 App", value: "\(preview.apps.count) 个")
            } footer: {
                Text("预览页面使用内置示例，这里的操作不修改真实记录；现有计时与提醒继续运行。App 选择只在本次运行中保留，重启后恢复示例；界面版本选择会记住。")
            }
            Section {
                Button("恢复示例 App 列表") {
                    preview.apps = FutureApp.samples
                    restored = true
                }
            } footer: { Text("只恢复预览列表，不会清除当前版本的任何数据。") }
        }
        .navigationTitle("预览数据").navigationBarTitleDisplayMode(.inline)
        .alert("示例列表已恢复", isPresented: $restored) { Button("好", role: .cancel) {} }
    }
}
