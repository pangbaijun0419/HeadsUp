import Foundation

public struct UsageExportCounts: Codable, Equatable, Sendable {
    public let events: Int
    public let segments: Int
    public let rounds: Int

    public init(events: Int, segments: Int, rounds: Int) {
        self.events = events
        self.segments = segments
        self.rounds = rounds
    }
}

/// One immutable snapshot. File sharing and copying must use these same bytes.
public struct UsageDataExport: Sendable {
    public let data: Data
    public let exportedAt: Date
    public let recordCounts: UsageExportCounts

    public init(data: Data, exportedAt: Date, recordCounts: UsageExportCounts) {
        self.data = data
        self.exportedAt = exportedAt
        self.recordCounts = recordCounts
    }

    public var byteCount: Int { data.count }

    /// An app policy, not a limit imposed by iOS or an AI model.
    public var canCopy: Bool { byteCount <= UsageDataExporter.maximumCopyBytes }

    public var copyText: String? {
        guard canCopy else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "heads-up-data-\(formatter.string(from: exportedAt)).json"
    }
}

public enum UsageDataExporter {
    public static let maximumCopyBytes = 100_000
    public static let exportSchemaVersion = 1

    /// Does not reconcile the tracker, synthesize missing usage, or alter array order.
    public static func make(
        database: HeadsUpDatabase,
        preferences: TrackerPreferences,
        pausedUntil: Date?,
        exportedAt: Date,
        timeZoneIdentifier: String,
        appVersion: String,
        buildNumber: String
    ) throws -> UsageDataExport {
        let counts = UsageExportCounts(
            events: database.events.count,
            segments: database.segments.count,
            rounds: database.rounds.count
        )
        let document = ExportDocument(
            exportSchemaVersion: exportSchemaVersion,
            format: "heads-up-usage-export",
            metadata: ExportMetadata(
                exportedAt: exportedAt,
                timeZoneIdentifier: timeZoneIdentifier,
                timestampFormat: "ISO 8601, UTC (Z), with nanosecond fractional digits",
                dataSource: "shortcuts_open_close_aggregate",
                app: AppMetadata(name: "Heads Up", version: appVersion, build: buildNumber),
                copyPolicy: CopyPolicy(
                    maximumUTF8Bytes: maximumCopyBytes,
                    scope: "app_clipboard_safety_policy",
                    isSystemOrAIModelLimit: false
                )
            ),
            currentSettings: CurrentSettings(
                preferences: preferences,
                rules: RulesSnapshot(preferences.rules),
                pausedUntil: pausedUntil
            ),
            recordCounts: counts,
            fieldGuide: fieldGuide,
            limitations: limitations,
            database: database
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Timestamp(date, codingPath: encoder.codingPath))
        }
        return UsageDataExport(
            data: try encoder.encode(document),
            exportedAt: exportedAt,
            recordCounts: counts
        )
    }

    private static let fieldGuide: [String: String] = [
        "exportSchemaVersion": "导出文件结构版本；与 database.schemaVersion（本地数据库结构版本）独立。",
        "metadata.exportedAt": "导出快照的时间，不代表记录结束时间。所有时间戳均为 UTC ISO 8601；按本地日期分析时参考 metadata.timeZoneIdentifier。",
        "metadata.dataSource": "通过快捷指令接收的打开、关闭信号汇总；不是 iOS 屏幕使用时间或逐 App 监控数据。",
        "currentSettings": "导出时的当前设置及规则，不是每条历史记录发生时的设置。pausedUntil 为 null 表示没有保存暂停截止时间；非空时可能已经过期。",
        "currentSettings.preferences": "firstReminderMinutes、resetAfterMinutes 的单位为分钟。",
        "currentSettings.rules": "时间间隔单位均为秒；scheduledReminderCount 的单位为条。",
        "database.state": "原始计时状态快照，包括进行中的轮次、使用片段、待确认关闭及去重状态；未在导出时推进或补算。",
        "database.events": "原始事件列表；date 为事件时间，duration（若有）单位为秒，message 为当时保存的说明。数组保留存储顺序，不能仅凭数组位置推断时间顺序。",
        "database.segments": "已保存的使用片段；roundID 关联 rounds.id，openedAt、closedAt 为边界时间，activeSeconds 单位为秒。",
        "database.rounds": "原始轮次；activeSeconds 单位为秒；openCount、shortBreakCount、reminderCount 是保存的累计计数；endedAt（若有）为结束时间。",
        "database.rounds.openCount": "被计时逻辑接受的打开信号数，不是设备实际打开次数的精确测量。",
        "database.rounds.reminderCount": "累计达到提醒阈值、应触发的提醒数，不是系统已送达或用户已看到的通知数。",
        "database.events.type.reminderDue": "应触发提醒的事件，不是通知送达回执。",
        "database.rounds.completedRest": "计时规则判断的休息完成状态，不代表对用户真实行为的直接观测。",
        "database.*.quality": "trusted 表示没有被现有规则标为不完整，不能当成已核验真值；incomplete 表示存在规则识别的不完整或异常。",
        "recordCounts": "原始 events、segments、rounds 数组长度；文件完整保留这些数组，不因复制大小限制而截断。"
    ]

    private static let limitations: [String] = [
        "仅包含本机实际保存的聚合计时数据，不包含未来版本页面的示例数据；导出过程不读取账号凭据、访问令牌或其他密钥。",
        "数据没有具体 App 身份，不能生成可信的逐 App 排名或推断用户当时使用了哪个 App。",
        "快捷指令信号可能缺失、重复或延迟；计时规则会合并或忽略部分信号，记录不等于完整的设备使用历史。",
        "openCount 是被接受的信号计数；reminderDue 和 reminderCount 是应触发记录，不能推断通知已经送达或被阅读。",
        "trusted 仅为内部数据质量标记，不证明数据准确或完整；分析时应保留 incomplete 与异常记录带来的不确定性。",
        "若 database.state.isOpen 为 true，当前片段可能仍未完成；保存的 activeSeconds 不包含尚未结算的尾部，导出不会补算它。pendingCloseAt 非空时还可能存在待确认关闭。",
        "currentSettings 仅反映导出时设置，不能据此断言历史记录始终使用同一提醒或休息规则。",
        "这是 exportedAt 时刻的只读快照，不会停止计时，也不会因导出动作改变原有记录。",
        "复制大小上限是本 App 的剪贴板体验策略，不是 iOS 或 AI 模型的容量上限；超出时仍可导出完整 JSON 文件。"
    ]

    /// Foundation's usual `.iso8601` strategy drops subsecond precision. Calendar
    /// components preserve it here without mutable shared formatters or locale drift.
    private static func iso8601Timestamp(_ date: Date, codingPath: [any CodingKey]) throws -> String {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw EncodingError.invalidValue(date, .init(codingPath: codingPath, debugDescription: "Cannot export a non-finite date."))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        guard let year = parts.year, (1...9999).contains(year),
              let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute,
              let second = parts.second, let nanosecond = parts.nanosecond else {
            throw EncodingError.invalidValue(date, .init(codingPath: codingPath, debugDescription: "Date is outside the supported ISO 8601 calendar range."))
        }
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%09dZ", year, month, day, hour, minute, second, nanosecond)
    }
}

private struct ExportDocument: Encodable {
    let exportSchemaVersion: Int
    let format: String
    let metadata: ExportMetadata
    let currentSettings: CurrentSettings
    let recordCounts: UsageExportCounts
    let fieldGuide: [String: String]
    let limitations: [String]
    let database: HeadsUpDatabase
}

private struct ExportMetadata: Encodable {
    let exportedAt: Date
    let timeZoneIdentifier: String
    let timestampFormat: String
    let dataSource: String
    let app: AppMetadata
    let copyPolicy: CopyPolicy
}

private struct AppMetadata: Encodable {
    let name: String
    let version: String
    let build: String
}

private struct CopyPolicy: Encodable {
    let maximumUTF8Bytes: Int
    let scope: String
    let isSystemOrAIModelLimit: Bool
}

private struct CurrentSettings: Encodable {
    let preferences: TrackerPreferences
    let rules: RulesSnapshot
    let pausedUntil: Date?

    private enum CodingKeys: String, CodingKey { case preferences, rules, pausedUntil }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(rules, forKey: .rules)
        // Explicit null distinguishes "no saved pause" from a missing export field.
        try container.encode(pausedUntil, forKey: .pausedUntil)
    }
}

private struct RulesSnapshot: Encodable {
    let firstReminder: TimeInterval
    let repeatReminder: TimeInterval
    let minimumRest: TimeInterval
    let duplicateWindow: TimeInterval
    let maximumSegment: TimeInterval
    let scheduledReminderCount: Int
    let minimumReminderInterval: TimeInterval
    let seamlessSwitchWindow: TimeInterval

    init(_ rules: TrackerRules) {
        firstReminder = rules.firstReminder
        repeatReminder = rules.repeatReminder
        minimumRest = rules.minimumRest
        duplicateWindow = rules.duplicateWindow
        maximumSegment = rules.maximumSegment
        scheduledReminderCount = rules.scheduledReminderCount
        minimumReminderInterval = rules.minimumReminderInterval
        seamlessSwitchWindow = rules.seamlessSwitchWindow
    }
}
