import Foundation
import Testing
@testable import HeadsUpCore

private let rules = TrackerRules(
    firstReminder: 600,
    repeatReminder: 300,
    minimumRest: 180,
    scheduledReminderCount: 4
)
private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

@Test func legacyDatabaseWithoutPendingCloseStillDecodes() throws {
    let json = #"{"schemaVersion":1,"nextRoundSequence":1,"state":{"isOpen":false},"rounds":[],"segments":[],"events":[]}"#
    let database = try JSONDecoder().decode(HeadsUpDatabase.self, from: Data(json.utf8))
    #expect(database.state.pendingCloseAt == nil)
}

@Test func initialOpenSchedulesTenThenFiveMinuteReminders() {
    var database = HeadsUpDatabase()
    let effects = TrackerReducer.open(&database, at: t0, rules: rules)
    #expect(database.state.isOpen)
    #expect(effects.reminders.prefix(4).map(\.threshold) == [600, 900, 1050, 1125])
}

@Test func escalatingRemindersReachTenSecondFloor() {
    let fastRules = TrackerRules(
        firstReminder: 80,
        repeatReminder: 40,
        minimumRest: 180,
        scheduledReminderCount: 6
    )
    var database = HeadsUpDatabase()
    let effects = TrackerReducer.open(&database, at: t0, rules: fastRules)
    #expect(effects.reminders.prefix(6).map(\.threshold) == [80, 120, 140, 150, 160, 170])
    #expect(effects.reminders.count == 6)
    #expect(effects.reminders.last?.repeatsEvery == nil)
}

@Test func appSwitchOpenBeforeOldCloseKeepsTimerRunning() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    _ = TrackerReducer.open(&database, at: t0.addingTimeInterval(60), rules: rules)
    let closeEffects = TrackerReducer.close(&database, at: t0.addingTimeInterval(61), rules: rules)
    #expect(database.state.isOpen)
    #expect(!closeEffects.cancelReminders)
}

@Test func shortBreakResumesWithoutCountingGap() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    _ = TrackerReducer.close(&database, at: t0.addingTimeInterval(590), rules: rules)
    let effects = TrackerReducer.open(&database, at: t0.addingTimeInterval(700), rules: rules)
    #expect(database.rounds.count == 1)
    #expect(database.rounds[0].activeSeconds == 590)
    #expect(effects.reminders[0].date == t0.addingTimeInterval(710))
    #expect(effects.shortBreakMessage != nil)
}

@Test func closeWaitsForConfirmationAndQuickReopenContinuesRound() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    let closeEffects = TrackerReducer.close(&database, at: t0.addingTimeInterval(60), rules: rules)

    #expect(closeEffects.cancelReminders)
    #expect(database.state.isOpen)
    #expect(database.state.pendingCloseAt == t0.addingTimeInterval(60))
    #expect(database.rounds[0].activeSeconds == 0)

    _ = TrackerReducer.open(&database, at: t0.addingTimeInterval(70), rules: rules)

    #expect(database.state.isOpen)
    #expect(database.state.pendingCloseAt == nil)
    #expect(database.state.currentSegmentStartedAt == t0.addingTimeInterval(70))
    #expect(database.rounds.count == 1)
    #expect(database.rounds[0].activeSeconds == 60)
    #expect(database.rounds[0].shortBreakCount == 0)
    #expect(database.events.filter { $0.type == .anomaly }.isEmpty)
}

@Test func duplicateCloseInsideConfirmationWindowIsAbsorbed() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    _ = TrackerReducer.close(&database, at: t0.addingTimeInterval(60), rules: rules)
    _ = TrackerReducer.close(&database, at: t0.addingTimeInterval(68), rules: rules)

    #expect(database.state.pendingCloseAt == t0.addingTimeInterval(60))
    #expect(database.events.filter { $0.type == .anomaly }.isEmpty)

    TrackerReducer.reconcileRest(&database, at: t0.addingTimeInterval(69), rules: rules)
    #expect(!database.state.isOpen)
    #expect(database.rounds[0].activeSeconds == 60)
}

@Test func fullRestStartsNewRound() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    _ = TrackerReducer.close(&database, at: t0.addingTimeInterval(60), rules: rules)
    _ = TrackerReducer.open(&database, at: t0.addingTimeInterval(240), rules: rules)
    #expect(database.rounds.count == 2)
    #expect(database.rounds[0].completedRest)
    #expect(database.rounds[1].sequence == 2)
}

@Test func duplicateOpenIsIgnored() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    let effects = TrackerReducer.open(&database, at: t0.addingTimeInterval(2), rules: rules)
    #expect(database.rounds.count == 1)
    #expect(database.events.filter { $0.type == .opened }.count == 1)
    #expect(effects.reminders.isEmpty)
}

@Test func reminderCountIsRecordedAsExpectedDue() {
    var database = HeadsUpDatabase()
    _ = TrackerReducer.open(&database, at: t0, rules: rules)
    _ = TrackerReducer.close(&database, at: t0.addingTimeInterval(901), rules: rules)
    TrackerReducer.reconcileRest(&database, at: t0.addingTimeInterval(902), rules: rules)
    #expect(database.rounds[0].reminderCount == 2)
    #expect(database.events.filter { $0.type == .reminderDue }.count == 2)
}
