import AppIntents
import Foundation

struct StartTrackedUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "开始累计使用"
    static let description = IntentDescription("进入任一受监控 App 时开始或恢复累计计时。")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        try await UsageStore.shared.handleOpen()
        return .result()
    }
}

struct StopTrackedUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "暂停累计使用"
    static let description = IntentDescription("离开受监控 App 时暂停累计计时并取消提醒。")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        try await UsageStore.shared.handleClose()
        return .result()
    }
}

struct HeadsUpShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTrackedUsageIntent(),
            phrases: ["用 \(.applicationName) 开始累计使用"],
            shortTitle: "开始累计使用",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: StopTrackedUsageIntent(),
            phrases: ["用 \(.applicationName) 暂停累计使用"],
            shortTitle: "暂停累计使用",
            systemImageName: "stop.circle.fill"
        )
    }
}
