import Foundation

struct DashboardSnapshot: Sendable {
    var database: HeadsUpDatabase
    var days: [DailySummary]
    var generatedAt: Date

    var today: DailySummary? { days.last }

    var currentActiveSeconds: TimeInterval {
        guard let id = database.state.currentRoundID,
              let round = database.rounds.first(where: { $0.id == id }) else { return 0 }
        var seconds = round.activeSeconds
        if database.state.isOpen, let start = database.state.currentSegmentStartedAt {
            seconds += max(0, generatedAt.timeIntervalSince(start))
        }
        return seconds
    }

    var todayTotalSeconds: TimeInterval {
        var seconds = today?.activeSeconds ?? 0
        if database.state.isOpen, let start = database.state.currentSegmentStartedAt {
            let dayStart = Calendar.autoupdatingCurrent.startOfDay(for: generatedAt)
            seconds += max(0, generatedAt.timeIntervalSince(max(start, dayStart)))
        }
        return seconds
    }

    static let empty = DashboardSnapshot(
        database: HeadsUpDatabase(),
        days: [],
        generatedAt: Date()
    )
}

actor UsageStore {
    static let shared = UsageStore()

    private let fileURL: URL
    private var cache: HeadsUpDatabase?
    private var preferences = TrackerPreferences()
    private var pausedUntil: Date?
    // Stamp effects before crossing actors so a reset cannot make an old batch
    // look new merely because NotificationService receives it late.
    private var dataGeneration: UInt64 = 0

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("HeadsUp", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("heads-up-v1.json")
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "firstReminderMinutes") != nil {
            preferences.firstReminderMinutes = max(1, defaults.integer(forKey: "firstReminderMinutes"))
        }
        if defaults.object(forKey: "resetAfterMinutes") != nil {
            preferences.resetAfterMinutes = max(1, defaults.integer(forKey: "resetAfterMinutes"))
        }
        if let value = defaults.object(forKey: "pausedUntil") as? Double {
            pausedUntil = Date(timeIntervalSince1970: value)
        }
    }

    func handleOpen(at now: Date = Date()) async throws {
        guard !isPaused(at: now) else {
            await NotificationService.shared.removeTrackingReminders(dataGeneration: dataGeneration)
            return
        }
        var database = try load()
        let effects = TrackerReducer.open(&database, at: now, rules: preferences.rules)
        try save(database)
        try await NotificationService.shared.apply(effects, dataGeneration: dataGeneration)
    }

    func handleClose(at now: Date = Date()) async throws {
        guard !isPaused(at: now) else {
            await NotificationService.shared.removeTrackingReminders(dataGeneration: dataGeneration)
            return
        }
        var database = try load()
        let effects = TrackerReducer.close(&database, at: now, rules: preferences.rules)
        try save(database)
        try await NotificationService.shared.apply(effects, dataGeneration: dataGeneration)
    }

    func snapshot(at now: Date = Date()) throws -> DashboardSnapshot {
        var database = try load()
        let before = database
        TrackerReducer.reconcileRest(&database, at: now, rules: preferences.rules)
        if database != before { try save(database) }
        return DashboardSnapshot(
            database: database,
            days: TrackerReducer.dailySummaries(database: database, now: now),
            generatedAt: now
        )
    }

    func reset() async throws {
        let recoveryFiles = try recoveryCopyURLs()
        try save(HeadsUpDatabase())
        dataGeneration += 1
        await NotificationService.shared.removeAll(dataGeneration: dataGeneration)
        var failedRecoveryCopies = 0
        for url in recoveryFiles {
            do { try FileManager.default.removeItem(at: url) }
            catch { failedRecoveryCopies += 1 }
        }
        if failedRecoveryCopies > 0 {
            throw UsageDataResetError.recoveryCopiesRemain(failedRecoveryCopies)
        }
    }

    func dataFileURL() -> URL { fileURL }

    /// Capture the real stored data without reconciling or rewriting the timer.
    /// Encoding is performed away from this actor by the export screen.
    func exportSnapshot(at now: Date = Date()) throws -> UsageExportSnapshot {
        UsageExportSnapshot(
            database: try readForExport(),
            preferences: preferences,
            pausedUntil: pausedUntil,
            exportedAt: now,
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    func currentPreferences() -> TrackerPreferences { preferences }

    func currentPauseUntil(at now: Date = Date()) -> Date? {
        isPaused(at: now) ? pausedUntil : nil
    }

    func pause(for duration: TimeInterval, at now: Date = Date()) async throws {
        var database = try load()
        if database.state.isOpen {
            _ = TrackerReducer.close(&database, at: now, rules: preferences.rules)
            try save(database)
        }
        let until = now.addingTimeInterval(duration)
        pausedUntil = until
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: "pausedUntil")
        await NotificationService.shared.removeTrackingReminders(dataGeneration: dataGeneration)
    }

    func resumeNow() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: "pausedUntil")
    }

    func recordCommitment(_ label: String, at now: Date = Date()) throws {
        var database = try load()
        database.events.append(.init(
            date: now,
            type: .commitment,
            message: "主动回应：\(label)"
        ))
        try save(database)
    }

    func updatePreferences(_ value: TrackerPreferences) async {
        preferences = value
        UserDefaults.standard.set(value.firstReminderMinutes, forKey: "firstReminderMinutes")
        UserDefaults.standard.set(value.resetAfterMinutes, forKey: "resetAfterMinutes")
        await NotificationService.shared.removeTrackingReminders(dataGeneration: dataGeneration)
    }

    private func readForExport() throws -> HeadsUpDatabase {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return HeadsUpDatabase() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Unlike load(), an export failure must not repair, rename, or replace data.
        return try decoder.decode(HeadsUpDatabase.self, from: Data(contentsOf: fileURL))
    }

    private func recoveryCopyURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.range(
                of: "^heads-up-corrupt-[0-9]+\\.json$", options: .regularExpression
            ) != nil else { return false }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }

    private func load() throws -> HeadsUpDatabase {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let database = HeadsUpDatabase()
            cache = database
            return database
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let database = try decoder.decode(HeadsUpDatabase.self, from: Data(contentsOf: fileURL))
            cache = database
            return database
        } catch {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("heads-up-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            var database = HeadsUpDatabase()
            database.events.append(.init(
                date: Date(),
                type: .anomaly,
                message: "旧数据无法读取，已保留损坏副本并新建记录。"
            ))
            try save(database)
            return database
        }
    }

    private func save(_ database: HeadsUpDatabase) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 快捷指令可能在锁屏时触发。首次解锁后保持可访问，同时继续使用系统文件保护。
        try encoder.encode(database).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        cache = database
    }

    private func isPaused(at now: Date) -> Bool {
        guard let pausedUntil else { return false }
        if pausedUntil > now { return true }
        self.pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: "pausedUntil")
        return false
    }
}

struct UsageExportSnapshot: Sendable {
    let database: HeadsUpDatabase
    let preferences: TrackerPreferences
    let pausedUntil: Date?
    let exportedAt: Date
    let timeZoneIdentifier: String
}

private enum UsageDataResetError: LocalizedError {
    case recoveryCopiesRemain(Int)

    var errorDescription: String? {
        switch self {
        case .recoveryCopiesRemain(let count):
            "使用记录已清空，但还有 \(count) 份本机恢复副本未能删除，请重试。"
        }
    }
}
