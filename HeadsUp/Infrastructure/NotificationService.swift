import Foundation
@preconcurrency import UserNotifications

struct NotificationHealth: Sendable {
    var authorization: UNAuthorizationStatus
    var alertsEnabled: Bool
    var soundsEnabled: Bool
    var pendingCount: Int

    static let unknown = NotificationHealth(
        authorization: .notDetermined,
        alertsEnabled: false,
        soundsEnabled: false,
        pendingCount: 0
    )
}

actor NotificationService {
    static let shared = NotificationService()
    static let commitmentActionIdentifier = "heads-up.commitment-action"
    static let commitmentCategoryPrefix = "heads-up.commitment-category."

    private let center = UNUserNotificationCenter.current()
    private var dataGeneration: UInt64 = 0
    // Actor methods may interleave while notification requests are being added.
    // A reset invalidates only work that began before it, not later reminders.
    private var resetGeneration: UInt64 = 0

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func apply(_ effects: TrackerEffects, dataGeneration: UInt64) async throws {
        guard acceptDataGeneration(dataGeneration) else { return }
        let generation = resetGeneration
        registerCommitmentCategories()
        if effects.cancelReminders {
            guard await removeTrackingReminders(generation: generation) else { return }
        }

        if let message = effects.shortBreakMessage {
            let content = baseContent()
            content.title = "休息还不到 3 分钟"
            content.body = message
            let request = UNNotificationRequest(
                identifier: "heads-up.short-break.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            guard try await add(request, generation: generation) else { return }
        }

        for reminder in effects.reminders {
            let content = baseContent()
            let titleIndex = (reminder.ordinal * 17 + 5) % reminderTitles.count
            let bodyIndex = (reminder.ordinal * 29 + 11) % reminderMessages.count
            content.title = reminderTitles[titleIndex]
            content.body = reminderMessages[bodyIndex]
            if Int.random(in: 0..<100) < 65 {
                let buttonIndex = Int.random(in: commitmentButtonTitles.indices)
                let buttonTitle = commitmentButtonTitles[buttonIndex]
                content.categoryIdentifier = Self.commitmentCategoryPrefix + String(buttonIndex)
                content.userInfo["commitmentButtonTitle"] = buttonTitle
            }
            let delay = max(1, reminder.date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: reminder.repeatsEvery ?? delay,
                repeats: reminder.repeatsEvery != nil
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: trigger
            )
            guard try await add(request, generation: generation) else { return }
        }
    }

    func scheduleTestNotification() async throws {
        let generation = resetGeneration
        let content = baseContent()
        content.title = "Heads up 测试提醒"
        content.body = "通知和声音链路正常。"
        let request = UNNotificationRequest(
            identifier: "heads-up.diagnostic.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        _ = try await add(request, generation: generation)
    }

    func health() async -> NotificationHealth {
        let settings = await center.notificationSettings()
        let requests = await center.pendingNotificationRequests()
        return NotificationHealth(
            authorization: settings.authorizationStatus,
            alertsEnabled: settings.alertSetting == .enabled,
            soundsEnabled: settings.soundSetting == .enabled,
            pendingCount: requests.filter { $0.identifier.hasPrefix("heads-up.") }.count
        )
    }

    func removeAll(dataGeneration: UInt64) {
        // A newer apply may reach this actor before its reset message. Its
        // generation already performed the clear, so this must be idempotent.
        _ = acceptDataGeneration(dataGeneration)
    }

    func removeTrackingReminders(dataGeneration: UInt64) async {
        guard acceptDataGeneration(dataGeneration) else { return }
        _ = await removeTrackingReminders(generation: resetGeneration)
    }

    private func acceptDataGeneration(_ generation: UInt64) -> Bool {
        guard generation >= dataGeneration else { return false }
        if generation > dataGeneration {
            dataGeneration = generation
            resetGeneration &+= 1
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
        return true
    }

    private func removeTrackingReminders(generation: UInt64) async -> Bool {
        guard generation == resetGeneration else { return false }
        let requests = await center.pendingNotificationRequests()
        // An old query must not cancel requests created after a reset.
        guard generation == resetGeneration else { return false }
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("heads-up.") && !$0.hasPrefix("heads-up.diagnostic.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        return true
    }

    private func add(_ request: UNNotificationRequest, generation: UInt64) async throws -> Bool {
        guard generation == resetGeneration else { return false }
        do {
            try await center.add(request)
        } catch {
            guard generation == resetGeneration else {
                removeRequest(identifier: request.identifier)
                return false
            }
            throw error
        }
        guard generation == resetGeneration else {
            // The add may finish after removeAll. Remove only this stale request,
            // including an immediate short-break notification already delivered.
            removeRequest(identifier: request.identifier)
            return false
        }
        return true
    }

    private func removeRequest(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func registerCommitmentCategories() {
        let categories = Set(commitmentButtonTitles.enumerated().map { index, title in
            let action = UNNotificationAction(
                identifier: Self.commitmentActionIdentifier,
                title: title,
                options: []
            )
            return UNNotificationCategory(
                identifier: Self.commitmentCategoryPrefix + String(index),
                actions: [action],
                intentIdentifiers: [],
                options: []
            )
        })
        center.setNotificationCategories(categories)
    }

    private func baseContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "heads-up.xiaohongshu"
        return content
    }
}

// 示例回应按钮：可以在数组中自行添加更多文案，请至少保留一项。
let commitmentButtonTitles = [
    "我先放下手机"
]

// 示例通知标题：可以在数组中自行添加更多文案，请至少保留一项。
private let reminderTitles = [
    "抬头看看"
]

// 示例通知正文：可以在数组中自行添加更多文案，请至少保留一项。
private let reminderMessages = [
    "你已经看了一会儿了，先放下手机，看看身边。"
]
