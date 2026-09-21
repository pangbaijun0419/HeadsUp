import Foundation
import Testing
@testable import HeadsUpCore

private let exportDate = Date(timeIntervalSince1970: 1_788_832_800)

private func makeExport(
    _ database: HeadsUpDatabase = HeadsUpDatabase(),
    preferences: TrackerPreferences = TrackerPreferences(),
    pausedUntil: Date? = nil,
    exportedAt: Date = exportDate
) throws -> UsageDataExport {
    try UsageDataExporter.make(
        database: database,
        preferences: preferences,
        pausedUntil: pausedUntil,
        exportedAt: exportedAt,
        timeZoneIdentifier: "Asia/Shanghai",
        appVersion: "1.0",
        buildNumber: "4"
    )
}

private func parsedExport(_ export: UsageDataExport) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: export.data) as? [String: Any])
}

private func exportDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
    }
    return decoder
}

private struct DecodedDocument: Decodable {
    var exportSchemaVersion: Int
    var database: HeadsUpDatabase
}

private func populatedDatabase() -> HeadsUpDatabase {
    let t = Date(timeIntervalSinceReferenceDate: 800_000_000.1234567)
    var database = HeadsUpDatabase()
    database.schemaVersion = 3
    database.nextRoundSequence = 12
    let olderID = UUID()
    let newerID = UUID()
    // Deliberately reverse chronological order to detect accidental sorting.
    database.rounds = [
        UsageRound(id: newerID, sequence: 11, startedAt: t, activeSeconds: 17.75, openCount: 3, shortBreakCount: 1, reminderCount: 2, quality: .incomplete),
        UsageRound(id: olderID, sequence: 10, startedAt: t.addingTimeInterval(-600), endedAt: t.addingTimeInterval(-500), activeSeconds: 80.5, openCount: 2, completedRest: true, quality: .trusted)
    ]
    database.segments = [
        UsageSegment(roundID: newerID, openedAt: t, closedAt: t.addingTimeInterval(17.75), activeSeconds: 17.75, quality: .incomplete),
        UsageSegment(roundID: olderID, openedAt: t.addingTimeInterval(-600), closedAt: t.addingTimeInterval(-519.5), activeSeconds: 80.5, quality: .trusted)
    ]
    database.events = [
        UsageEvent(date: t.addingTimeInterval(30), type: .anomaly, message: "信号延迟 ⚠️", duration: 0.5),
        UsageEvent(date: t, type: .opened, message: "接受打开信号"),
        UsageEvent(date: t.addingTimeInterval(-550), type: .reminderDue, message: "应触发提醒", duration: 50)
    ]
    database.state.isOpen = true
    database.state.currentRoundID = newerID
    database.state.currentSegmentStartedAt = t.addingTimeInterval(20)
    database.state.pendingCloseAt = t.addingTimeInterval(30)
    database.state.lastClosedAt = t.addingTimeInterval(17.75)
    database.state.lastAcceptedEventAt = t.addingTimeInterval(30)
    database.state.ignoreCloseBefore = t.addingTimeInterval(25)
    return database
}

@Test func usageExportRoundTripsCompleteDatabaseWithoutMutatingOrSorting() throws {
    let input = populatedDatabase()
    let before = input
    let export = try makeExport(input)
    let decoded = try exportDecoder().decode(DecodedDocument.self, from: export.data)

    #expect(decoded.database == before)
    #expect(input == before)
    #expect(decoded.database.state == before.state)
    #expect(decoded.database.rounds.map(\.id) == before.rounds.map(\.id))
    #expect(decoded.database.events.map(\.id) == before.events.map(\.id))
    #expect(export.recordCounts == UsageExportCounts(events: 3, segments: 2, rounds: 2))
}

@Test func usageExportUsesSeparateSchemaAndCurrentSettingsMetadata() throws {
    var preferences = TrackerPreferences()
    preferences.firstReminderMinutes = 12
    preferences.resetAfterMinutes = 4
    let pause = exportDate.addingTimeInterval(600)
    let export = try makeExport(populatedDatabase(), preferences: preferences, pausedUntil: pause)
    let document = try parsedExport(export)
    let metadata = try #require(document["metadata"] as? [String: Any])
    let current = try #require(document["currentSettings"] as? [String: Any])
    let currentPreferences = try #require(current["preferences"] as? [String: Any])
    let currentRules = try #require(current["rules"] as? [String: Any])
    let copyPolicy = try #require(metadata["copyPolicy"] as? [String: Any])
    let app = try #require(metadata["app"] as? [String: Any])

    #expect(document["exportSchemaVersion"] as? Int == 1)
    #expect(document["format"] as? String == "heads-up-usage-export")
    #expect(metadata["dataSource"] as? String == "shortcuts_open_close_aggregate")
    #expect(metadata["timeZoneIdentifier"] as? String == "Asia/Shanghai")
    #expect(app["version"] as? String == "1.0")
    #expect(app["build"] as? String == "4")
    #expect(currentPreferences["firstReminderMinutes"] as? Int == 12)
    #expect(currentPreferences["resetAfterMinutes"] as? Int == 4)
    #expect(currentRules["firstReminder"] as? Int == 720)
    #expect(currentRules["repeatReminder"] as? Int == 360)
    #expect(currentRules["minimumRest"] as? Int == 240)
    #expect(currentRules.count == 8)
    let pausedUntil = try #require(current["pausedUntil"] as? String)
    #expect(try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(pausedUntil) == pause)
    #expect(copyPolicy["maximumUTF8Bytes"] as? Int == 100_000)
    #expect(copyPolicy["isSystemOrAIModelLimit"] as? Bool == false)
}

@Test func usageExportEmptyDatasetIsAValidFullSnapshotWithExplicitUnpausedState() throws {
    let export = try makeExport()
    let document = try parsedExport(export)
    let current = try #require(document["currentSettings"] as? [String: Any])
    let decoded = try exportDecoder().decode(DecodedDocument.self, from: export.data)

    #expect(decoded.database == HeadsUpDatabase())
    #expect(export.recordCounts == UsageExportCounts(events: 0, segments: 0, rounds: 0))
    #expect(current["pausedUntil"] is NSNull)
    #expect(export.canCopy)
    #expect(export.copyText != nil)
}

@Test func usageExportDatesAreUTCISO8601AndPreserveSubseconds() throws {
    let snapshotDate = Date(timeIntervalSinceReferenceDate: 800_000_000.1234567)
    let export = try makeExport(populatedDatabase(), exportedAt: snapshotDate)
    let document = try parsedExport(export)
    let metadata = try #require(document["metadata"] as? [String: Any])
    let timestamp = try #require(metadata["exportedAt"] as? String)

    #expect(timestamp == "2026-05-09T06:13:20.123456716Z")
    #expect(try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp) == snapshotDate)
    #expect(export.exportedAt == snapshotDate)
}

@Test func usageExportCopyPolicyIncludesExactlyTheByteLimit() {
    let counts = UsageExportCounts(events: 0, segments: 0, rounds: 0)
    let atLimit = UsageDataExport(data: Data(repeating: 65, count: 100_000), exportedAt: exportDate, recordCounts: counts)
    let overLimit = UsageDataExport(data: Data(repeating: 65, count: 100_001), exportedAt: exportDate, recordCounts: counts)

    #expect(atLimit.canCopy)
    #expect(atLimit.copyText?.utf8.count == 100_000)
    #expect(!overLimit.canCopy)
    #expect(overLimit.copyText == nil)
    #expect(overLimit.data.count == 100_001)
}

@Test func usageExportCopyPolicyMeasuresUTF8BytesInsteadOfCharacters() {
    let text = String(repeating: "数", count: 33_334)
    let export = UsageDataExport(data: Data(text.utf8), exportedAt: exportDate, recordCounts: UsageExportCounts(events: 0, segments: 0, rounds: 0))

    #expect(text.count < 100_000)
    #expect(export.byteCount == 100_002)
    #expect(!export.canCopy)
    #expect(export.copyText == nil)
}

@Test func usageExportCopyIsByteIdenticalToFilePayloadAndDeterministic() throws {
    let database = populatedDatabase()
    let first = try makeExport(database)
    let second = try makeExport(database)
    let copy = try #require(first.copyText)

    #expect(Data(copy.utf8) == first.data)
    #expect(first.data == second.data)
    #expect(copy.contains("信号延迟 ⚠️"))
    #expect(copy.contains("Asia/Shanghai"))
    #expect(copy.contains("\n  \""))
}

@Test func usageExportLargeDatasetRemainsCompleteWhenCopyIsDisabled() throws {
    var database = populatedDatabase()
    database.events = (0..<2_000).map { index in
        UsageEvent(date: exportDate.addingTimeInterval(TimeInterval(index)), type: .opened, message: "完整保留第 \(index) 条真实记录")
    }
    let export = try makeExport(database)
    let decoded = try exportDecoder().decode(DecodedDocument.self, from: export.data)

    #expect(export.byteCount > 100_000)
    #expect(!export.canCopy)
    #expect(export.copyText == nil)
    #expect(export.recordCounts.events == 2_000)
    #expect(decoded.database == database)
    #expect(decoded.database.events.last?.message == "完整保留第 1999 条真实记录")
}

@Test func usageExportIncludesAIInterpretationBoundariesAndUnits() throws {
    let document = try parsedExport(makeExport())
    let guide = try #require(document["fieldGuide"] as? [String: String])
    let limitations = try #require(document["limitations"] as? [String])

    #expect(guide["currentSettings.preferences"]?.contains("分钟") == true)
    #expect(guide["currentSettings.rules"]?.contains("秒") == true)
    #expect(guide["database.events.type.reminderDue"]?.contains("不是通知送达回执") == true)
    #expect(guide["database.rounds.openCount"]?.contains("接受") == true)
    #expect(guide["database.*.quality"]?.contains("不能当成已核验真值") == true)
    #expect(limitations.contains { $0.contains("具体 App 身份") })
    #expect(limitations.contains { $0.contains("不包含尚未结算的尾部") })
    #expect(limitations.contains { $0.contains("不是 iOS 或 AI 模型") })
    #expect(limitations.contains { $0.contains("不包含未来版本页面的示例数据") })
}

@Test func usageExportFilenameIsStableASCIIAndUTC() throws {
    let date = try Date.ISO8601FormatStyle().parse("2026-09-08T02:00:00Z")
    let export = try makeExport(exportedAt: date)
    #expect(export.suggestedFilename == "heads-up-data-20260908T020000Z.json")
    #expect(export.suggestedFilename.unicodeScalars.allSatisfy { $0.isASCII })
}

@Test func usageExportPropagatesInvalidNumericDataInsteadOfSilentlyDroppingIt() {
    var database = populatedDatabase()
    database.rounds[0].activeSeconds = .infinity
    #expect(throws: EncodingError.self) { try makeExport(database) }
}

@Test func usageExportRejectsNonFiniteDatesWithAnEncodingError() {
    #expect(throws: EncodingError.self) {
        try makeExport(exportedAt: Date(timeIntervalSinceReferenceDate: .infinity))
    }
}
