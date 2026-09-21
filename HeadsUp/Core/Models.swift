import Foundation

public enum DataQuality: String, Codable, Sendable {
    case trusted
    case incomplete
}

public enum UsageEventType: String, Codable, Sendable {
    case opened
    case closed
    case shortBreak
    case restCompleted
    case reminderDue
    case anomaly
    case commitment
}

public struct UsageEvent: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var type: UsageEventType
    public var message: String
    public var duration: TimeInterval?

    public init(date: Date, type: UsageEventType, message: String, duration: TimeInterval? = nil) {
        self.date = date
        self.type = type
        self.message = message
        self.duration = duration
    }
}

public struct UsageSegment: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var roundID: UUID
    public var openedAt: Date
    public var closedAt: Date
    public var activeSeconds: TimeInterval
    public var quality: DataQuality
}

public struct UsageRound: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var sequence: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var activeSeconds: TimeInterval = 0
    public var openCount: Int = 0
    public var shortBreakCount: Int = 0
    public var completedRest: Bool = false
    public var reminderCount: Int = 0
    public var quality: DataQuality = .trusted
}

public struct TrackerState: Codable, Equatable, Sendable {
    public var isOpen = false
    public var currentRoundID: UUID?
    public var currentSegmentStartedAt: Date?
    public var pendingCloseAt: Date? = nil
    public var lastClosedAt: Date?
    public var lastAcceptedEventAt: Date?
    public var ignoreCloseBefore: Date? = nil
}

public struct HeadsUpDatabase: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var nextRoundSequence = 1
    public var state = TrackerState()
    public var rounds: [UsageRound] = []
    public var segments: [UsageSegment] = []
    public var events: [UsageEvent] = []

    public init() {}
}

public struct TrackerRules: Equatable, Sendable {
    public var firstReminder: TimeInterval
    public var repeatReminder: TimeInterval
    public var minimumRest: TimeInterval
    public var duplicateWindow: TimeInterval
    public var maximumSegment: TimeInterval
    public var scheduledReminderCount: Int
    public var minimumReminderInterval: TimeInterval
    public var seamlessSwitchWindow: TimeInterval

    public init(
        firstReminder: TimeInterval,
        repeatReminder: TimeInterval,
        minimumRest: TimeInterval,
        duplicateWindow: TimeInterval = 8,
        maximumSegment: TimeInterval = 6 * 60 * 60,
        scheduledReminderCount: Int = 58,
        minimumReminderInterval: TimeInterval = 10,
        seamlessSwitchWindow: TimeInterval = 15
    ) {
        self.firstReminder = firstReminder
        self.repeatReminder = repeatReminder
        self.minimumRest = minimumRest
        self.duplicateWindow = duplicateWindow
        self.maximumSegment = maximumSegment
        self.scheduledReminderCount = scheduledReminderCount
        self.minimumReminderInterval = minimumReminderInterval
        self.seamlessSwitchWindow = seamlessSwitchWindow
    }

    public static let production = TrackerRules(
        firstReminder: 10 * 60,
        repeatReminder: 5 * 60,
        minimumRest: 3 * 60
    )
}

public struct ReminderRequest: Equatable, Sendable {
    public var identifier: String
    public var date: Date
    public var threshold: TimeInterval
    public var ordinal: Int
    public var repeatsEvery: TimeInterval?
}

public struct TrackerPreferences: Codable, Equatable, Sendable {
    public var firstReminderMinutes = 10
    public var resetAfterMinutes = 3

    public var rules: TrackerRules {
        TrackerRules(
            firstReminder: TimeInterval(firstReminderMinutes * 60),
            repeatReminder: TimeInterval(firstReminderMinutes * 30),
            minimumRest: TimeInterval(resetAfterMinutes * 60)
        )
    }
}

public struct TrackerEffects: Equatable, Sendable {
    public var cancelReminders = false
    public var reminders: [ReminderRequest] = []
    public var shortBreakMessage: String?
}

public struct DailySummary: Identifiable, Sendable {
    public var id: Date { day }
    public var day: Date
    public var activeSeconds: TimeInterval
    public var opens: Int
    public var reminders: Int
    public var shortBreaks: Int
    public var completedRests: Int
    public var anomalies: Int
}
