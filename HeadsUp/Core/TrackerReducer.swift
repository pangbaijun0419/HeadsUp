import Foundation

public enum TrackerReducer {
    public static func open(
        _ database: inout HeadsUpDatabase,
        at now: Date,
        rules: TrackerRules = .production
    ) -> TrackerEffects {
        var effects = TrackerEffects(cancelReminders: true)

        // “关闭”先进入待确认状态。若快捷指令的“打开”信号稍晚到达，
        // 先按真实关闭时刻结算上一段，再无缝恢复，避免显示为 0。
        finalizePendingClose(&database, rules: rules)

        if database.state.isOpen {
            // 从一个受监控 App 横滑到另一个时，“打开”有时会先于旧 App 的
            // “关闭”到达。聚合计时无需切段，忽略随后到达的旧关闭事件。
            database.state.ignoreCloseBefore = now.addingTimeInterval(rules.seamlessSwitchWindow)
            database.state.lastAcceptedEventAt = now
            return TrackerEffects()
        }

        var resumed = false
        if let roundID = database.state.currentRoundID,
           let lastClosed = database.state.lastClosedAt,
           let index = database.rounds.firstIndex(where: { $0.id == roundID }) {
            let gap = max(0, now.timeIntervalSince(lastClosed))
            if gap < rules.minimumRest {
                resumed = true
                if gap > rules.seamlessSwitchWindow {
                    database.rounds[index].shortBreakCount += 1
                    database.events.append(.init(
                        date: now,
                        type: .shortBreak,
                        message: "只休息了 \(durationText(gap))，继续上一轮。",
                        duration: gap
                    ))
                    effects.shortBreakMessage = "刚才只离开 \(durationText(gap))，还没达到你设置的休息时间。"
                }
            } else {
                database.rounds[index].endedAt = lastClosed
                database.rounds[index].completedRest = true
                database.events.append(.init(
                    date: lastClosed.addingTimeInterval(rules.minimumRest),
                    type: .restCompleted,
                    message: "已完成 3 分钟休息。"
                ))
                database.state = TrackerState()
            }
        }

        if database.state.currentRoundID == nil {
            let round = UsageRound(sequence: database.nextRoundSequence, startedAt: now)
            database.nextRoundSequence += 1
            database.rounds.append(round)
            database.state.currentRoundID = round.id
        }

        guard let roundID = database.state.currentRoundID,
              let index = database.rounds.firstIndex(where: { $0.id == roundID }) else {
            return effects
        }

        database.rounds[index].openCount += 1
        database.state.isOpen = true
        database.state.currentSegmentStartedAt = now
        database.state.lastClosedAt = nil
        database.state.lastAcceptedEventAt = now
        database.events.append(.init(
            date: now,
            type: .opened,
            message: resumed ? "重新进入受监控 App，继续第 \(database.rounds[index].sequence) 轮。" : "开始第 \(database.rounds[index].sequence) 轮。"
        ))

        effects.reminders = makeReminders(
            roundID: roundID,
            accumulated: database.rounds[index].activeSeconds,
            openedAt: now,
            rules: rules
        )
        return effects
    }

    public static func close(
        _ database: inout HeadsUpDatabase,
        at now: Date,
        rules: TrackerRules = .production
    ) -> TrackerEffects {
        if let deadline = database.state.ignoreCloseBefore, now <= deadline {
            database.state.ignoreCloseBefore = nil
            database.state.lastAcceptedEventAt = now
            return TrackerEffects()
        }
        let effects = TrackerEffects(cancelReminders: true)

        if let pending = database.state.pendingCloseAt {
            if now.timeIntervalSince(pending) <= rules.seamlessSwitchWindow {
                // 同一轮快速切换可能产生多个关闭信号，只保留第一个真实边界。
                database.state.lastAcceptedEventAt = now
                return effects
            }
            finalizePendingClose(&database, rules: rules)
        }

        guard database.state.isOpen,
              database.state.currentSegmentStartedAt != nil,
              database.state.currentRoundID != nil else {
            if let last = database.state.lastAcceptedEventAt,
               now.timeIntervalSince(last) <= rules.duplicateWindow {
                return TrackerEffects()
            }
            database.events.append(.init(
                date: now,
                type: .anomaly,
                message: "收到无对应开始的关闭信号，已忽略。"
            ))
            database.state.lastAcceptedEventAt = now
            return effects
        }

        database.state.pendingCloseAt = now
        database.state.lastAcceptedEventAt = now
        return effects
    }

    public static func reconcileRest(
        _ database: inout HeadsUpDatabase,
        at now: Date,
        rules: TrackerRules = .production
    ) {
        // Heads up 回到前台时，用户显然已经离开受监控 App，可立即按收到
        // “关闭”的原始时刻结算，不必让界面继续显示为正在使用。
        finalizePendingClose(&database, rules: rules)
        guard !database.state.isOpen,
              let closed = database.state.lastClosedAt,
              now.timeIntervalSince(closed) >= rules.minimumRest,
              let roundID = database.state.currentRoundID,
              let index = database.rounds.firstIndex(where: { $0.id == roundID }) else { return }
        database.rounds[index].endedAt = closed
        database.rounds[index].completedRest = true
        database.events.append(.init(
            date: closed.addingTimeInterval(rules.minimumRest),
            type: .restCompleted,
                message: "已完成设置的休息时间。"
        ))
        database.state = TrackerState()
    }

    private static func finalizePendingClose(
        _ database: inout HeadsUpDatabase,
        rules: TrackerRules
    ) {
        guard let closeAt = database.state.pendingCloseAt,
              let startedAt = database.state.currentSegmentStartedAt,
              let roundID = database.state.currentRoundID,
              let index = database.rounds.firstIndex(where: { $0.id == roundID }) else {
            database.state.pendingCloseAt = nil
            return
        }

        let raw = closeAt.timeIntervalSince(startedAt)
        let trusted = raw >= 0 && raw <= rules.maximumSegment
        let credited = trusted ? raw : 0
        database.segments.append(.init(
            roundID: roundID,
            openedAt: startedAt,
            closedAt: closeAt,
            activeSeconds: credited,
            quality: trusted ? .trusted : .incomplete
        ))
        database.rounds[index].activeSeconds += credited
        if !trusted { database.rounds[index].quality = .incomplete }

        let oldCount = database.rounds[index].reminderCount
        let newCount = numberOfDueReminders(database.rounds[index].activeSeconds, rules: rules)
        if newCount > oldCount {
            for ordinal in oldCount..<newCount {
                let threshold = rules.firstReminder + Double(ordinal) * rules.repeatReminder
                database.events.append(.init(
                    date: closeAt,
                    type: .reminderDue,
                    message: "累计达到 \(durationText(threshold))；系统应触发提醒。",
                    duration: threshold
                ))
            }
            database.rounds[index].reminderCount = newCount
        }

        database.events.append(.init(
            date: closeAt,
            type: .closed,
            message: trusted ? "本段使用 \(durationText(credited))。" : "本段时长异常，已标记为不完整。",
            duration: credited
        ))
        database.state.isOpen = false
        database.state.currentSegmentStartedAt = nil
        database.state.pendingCloseAt = nil
        database.state.lastClosedAt = closeAt
        database.state.lastAcceptedEventAt = closeAt
    }

    public static func dailySummaries(
        database: HeadsUpDatabase,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DailySummary] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: today) }
        return days.map { day in
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let segments = database.segments.filter { $0.closedAt > day && $0.openedAt < next }
            let seconds = segments.reduce(0.0) { total, segment in
                total + max(0, min(segment.closedAt, next).timeIntervalSince(max(segment.openedAt, day)))
            }
            let events = database.events.filter { $0.date >= day && $0.date < next }
            return DailySummary(
                day: day,
                activeSeconds: seconds,
                opens: events.filter { $0.type == .opened }.count,
                reminders: events.filter { $0.type == .reminderDue }.count,
                shortBreaks: events.filter { $0.type == .shortBreak }.count,
                completedRests: events.filter { $0.type == .restCompleted }.count,
                anomalies: events.filter { $0.type == .anomaly }.count
            )
        }
    }

    private static func makeReminders(
        roundID: UUID,
        accumulated: TimeInterval,
        openedAt: Date,
        rules: TrackerRules
    ) -> [ReminderRequest] {
        let upcoming = reminderThresholds(after: accumulated, rules: rules, count: rules.scheduledReminderCount)
        return upcoming.map { item in
            ReminderRequest(
                identifier: "heads-up.\(roundID.uuidString).\(item.ordinal).\(Int(item.threshold))",
                date: openedAt.addingTimeInterval(max(1, item.threshold - accumulated)),
                threshold: item.threshold,
                ordinal: item.ordinal,
                repeatsEvery: nil
            )
        }
    }

    private static func numberOfDueReminders(_ seconds: TimeInterval, rules: TrackerRules) -> Int {
        var threshold = rules.firstReminder
        var interval = max(rules.minimumReminderInterval, rules.firstReminder / 2)
        var count = 0
        while threshold <= seconds {
            count += 1
            threshold += interval
            interval = max(rules.minimumReminderInterval, interval / 2)
        }
        return count
    }

    private static func reminderThresholds(
        after accumulated: TimeInterval,
        rules: TrackerRules,
        count: Int
    ) -> [(threshold: TimeInterval, ordinal: Int)] {
        var threshold = rules.firstReminder
        var interval = max(rules.minimumReminderInterval, rules.firstReminder / 2)
        var ordinal = 0
        while threshold <= accumulated {
            ordinal += 1
            threshold += interval
            interval = max(rules.minimumReminderInterval, interval / 2)
        }
        return (0..<count).map { _ in
            defer {
                ordinal += 1
                threshold += interval
                interval = max(rules.minimumReminderInterval, interval / 2)
            }
            return (threshold, ordinal)
        }
    }

    private static func markCurrentRoundIncomplete(_ database: inout HeadsUpDatabase) {
        guard let id = database.state.currentRoundID,
              let index = database.rounds.firstIndex(where: { $0.id == id }) else { return }
        database.rounds[index].quality = .incomplete
        database.rounds[index].endedAt = database.state.lastAcceptedEventAt
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remainder = total % 60
        return minutes > 0 ? "\(minutes)分\(remainder)秒" : "\(remainder)秒"
    }
}
