import SwiftUI

struct FutureStatisticsView: View {
    @EnvironmentObject private var preview: FuturePreviewState
    @State private var period: FutureStatisticsPeriod = .today
    @State private var anchorDate = FutureStatisticsSample.referenceDate
    @State private var selectedWeekIndex = 6
    @State private var showingDatePicker = false

    private var weekDates: [Date] {
        (0..<7).map { FutureStatisticsSample.addDays($0 - 6, to: anchorDate) }
    }

    private var selectedDate: Date {
        period == .today ? anchorDate : weekDates[selectedWeekIndex]
    }

    private var weekMinutes: [Int] {
        weekDates.map { FutureStatisticsSample.total(on: $0, apps: preview.apps) }
    }

    private var totalMinutes: Int {
        period == .today
            ? FutureStatisticsSample.total(on: anchorDate, apps: preview.apps)
            : weekMinutes.reduce(0, +)
    }

    private var canMoveForward: Bool {
        anchorDate < FutureStatisticsSample.referenceDate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FutureStatisticsSampleBadge()
                periodPicker

                Text("本机 · 所选 App")
                    .font(.subheadline)
                    .foregroundStyle(FutureTheme.secondary)

                dateNavigator
                summary

                if period == .week {
                    FutureStatisticsWeekChart(
                        dates: weekDates,
                        minutes: weekMinutes,
                        selection: $selectedWeekIndex
                    )
                }

                appBreakdown
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(FutureTheme.background)
        .navigationTitle("统计")
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker(
                        "示例日期",
                        selection: $anchorDate,
                        in: ...FutureStatisticsSample.referenceDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    Text("仅切换示例日期，不读取本机用量。")
                        .font(.footnote)
                        .foregroundStyle(FutureTheme.secondary)
                    Spacer(minLength: 0)
                }
                .padding(20)
                .background(FutureTheme.background)
                .navigationTitle("选择示例日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            anchorDate = FutureStatisticsSample.calendar.startOfDay(for: anchorDate)
                            selectedWeekIndex = 6
                            showingDatePicker = false
                        }
                    }
                }
            }
            .tint(FutureTheme.accent)
            .presentationDetents([.medium, .large])
        }
        .tint(FutureTheme.accent)
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(FutureStatisticsPeriod.allCases) { option in
                Button {
                    period = option
                    selectedWeekIndex = 6
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(period == option ? .semibold : .regular))
                        .foregroundStyle(period == option ? FutureTheme.accent : FutureTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if period == option {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(FutureTheme.card)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(FutureTheme.secondary.opacity(0.12), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(period == option ? "已选择" : "")
                .accessibilityIdentifier("future.statistics.period.\(option.id)")
            }
        }
        .background(FutureTheme.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(FutureTheme.secondary.opacity(0.1), lineWidth: 1)
        }
    }

    private var dateNavigator: some View {
        HStack(spacing: 8) {
            Button { moveDate(by: period == .today ? -1 : -7) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(period == .today ? "前一天" : "前七天")

            Button { showingDatePicker = true } label: {
                Text(period == .today
                     ? FutureStatisticsSample.dateLabel(anchorDate)
                     : "\(FutureStatisticsSample.dateLabel(weekDates[0]))—\(FutureStatisticsSample.dateLabel(anchorDate))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("选择示例日期")
            .accessibilityIdentifier("future.statistics.date")

            Button { moveDate(by: period == .today ? 1 : 7) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canMoveForward)
            .accessibilityLabel(period == .today ? "后一天" : "后七天")
        }
        .buttonStyle(.plain)
        .foregroundStyle(FutureTheme.secondary)
        .padding(.vertical, -8)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(period == .week ? "近7天用时" : (FutureStatisticsSample.isReferenceDay(anchorDate) ? "今日用时" : "当日用时"))
                .font(.subheadline)
                .foregroundStyle(FutureTheme.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    FutureStatisticsDuration(minutes: totalMinutes, size: period == .today ? 48 : 36)
                    if period == .week { dailyAverage }
                }
                VStack(alignment: .leading, spacing: 6) {
                    FutureStatisticsDuration(minutes: totalMinutes, size: 36)
                    if period == .week { dailyAverage }
                }
            }

            if period == .today {
                Text(FutureStatisticsSample.isReferenceDay(anchorDate) ? "截至23:41" : "示例日汇总")
                    .font(.footnote)
                    .foregroundStyle(FutureTheme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dailyAverage: some View {
        Text("日均\(FutureStatisticsSample.durationLabel(Int((Double(totalMinutes) / 7).rounded())))")
            .font(.caption)
            .foregroundStyle(FutureTheme.secondary)
    }

    private var appBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            FutureSectionTitle(period == .today ? "各 App" : FutureStatisticsSample.daySummary(selectedDate))

            FutureCard {
                if preview.apps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有选择 App")
                            .font(.subheadline.weight(.medium))
                        Text("在首页添加 App 后查看示例统计。")
                            .font(.footnote)
                            .foregroundStyle(FutureTheme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(preview.apps.enumerated()), id: \.element.id) { index, app in
                            let minutes = FutureStatisticsSample.minutes(for: app, on: selectedDate, apps: preview.apps)
                            NavigationLink {
                                FutureAppStatisticsDetailView(app: app, date: selectedDate, minutes: minutes)
                            } label: {
                                appRow(app, minutes: minutes)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(app.name)，\(minutes)分钟，查看使用时段")
                            .accessibilityIdentifier("future.statistics.app.\(app.id)")

                            if index < preview.apps.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ app: FutureApp, minutes: Int) -> some View {
        HStack(spacing: 14) {
            FutureAppIcon(app: app, size: 44)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(app.name).font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text("\(minutes)分钟")
                        .font(.footnote)
                        .foregroundStyle(FutureTheme.secondary)
                }
                if period == .today {
                    FutureStatisticsProgress(
                        value: Double(minutes),
                        maximum: Double(max(1, FutureStatisticsSample.total(on: selectedDate, apps: preview.apps)))
                    )
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FutureTheme.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, period == .today ? 14 : 11)
        .contentShape(Rectangle())
    }

    private func moveDate(by days: Int) {
        anchorDate = min(FutureStatisticsSample.addDays(days, to: anchorDate), FutureStatisticsSample.referenceDate)
        selectedWeekIndex = 6
    }
}

private enum FutureStatisticsPeriod: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "7天"

    var id: String { self == .today ? "today" : "week" }
}

private struct FutureStatisticsSampleBadge: View {
    var body: some View {
        Text("示例数据")
            .font(.caption2.weight(.medium))
            .foregroundStyle(FutureTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FutureTheme.accent.opacity(0.07), in: Capsule())
    }
}

private struct FutureStatisticsDuration: View {
    let minutes: Int
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if minutes >= 60 {
                Text("\(minutes / 60)")
                    .font(.system(size: size, weight: .semibold))
                Text("小时").font(.subheadline)
            }
            Text("\(minutes % 60)")
                .font(.system(size: size, weight: .semibold))
            Text("分钟").font(.subheadline)
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FutureStatisticsSample.durationLabel(minutes))
    }
}

private struct FutureStatisticsWeekChart: View {
    let dates: [Date]
    let minutes: [Int]
    @Binding var selection: Int

    private var ceiling: Int { max(20, Int(ceil(Double(minutes.max() ?? 0) / 20)) * 20) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("分钟")
                .font(.caption2)
                .foregroundStyle(FutureTheme.secondary)
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .trailing) {
                    Text("\(ceiling)")
                    Spacer()
                    Text("\(ceiling / 2)")
                    Spacer()
                    Text("0")
                }
                .font(.caption2)
                .foregroundStyle(FutureTheme.secondary)
                .frame(width: 25, height: 140)
                .accessibilityHidden(true)

                HStack(alignment: .top, spacing: 9) {
                    ForEach(dates.indices, id: \.self) { index in
                        Button { selection = index } label: {
                            VStack(spacing: 6) {
                                VStack(spacing: 5) {
                                    Spacer(minLength: 0)
                                    Text("\(minutes[index])")
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(FutureTheme.accent.opacity(selection == index ? 1 : 0.25))
                                        .frame(height: max(1, CGFloat(minutes[index]) / CGFloat(ceiling) * 116))
                                }
                                .frame(height: 140, alignment: .bottom)
                                Text(FutureStatisticsSample.shortDateLabel(dates[index]))
                                    .font(.caption2)
                                    .foregroundStyle(selection == index ? FutureTheme.accent : FutureTheme.secondary)
                                Text(FutureStatisticsSample.isReferenceDay(dates[index]) ? "今天" : " ")
                                    .font(.caption2)
                                    .foregroundStyle(FutureTheme.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(FutureStatisticsSample.dateLabel(dates[index]))，\(minutes[index])分钟")
                        .accessibilityValue(selection == index ? "已选择" : "")
                        .accessibilityHint("查看当天 App 用时")
                    }
                }
                .background(alignment: .top) {
                    VStack {
                        Spacer()
                        Rectangle().fill(FutureTheme.secondary.opacity(0.18)).frame(height: 1)
                    }
                    .frame(height: 140)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct FutureAppStatisticsDetailView: View {
    let app: FutureApp
    let date: Date
    let minutes: Int

    private var intervals: [Int] {
        FutureStatisticsSample.distribute(total: minutes, weights: [0, 2, 8, 6, 10, 5])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FutureStatisticsSampleBadge()

                HStack(spacing: 14) {
                    FutureAppIcon(app: app, size: 44)
                    Text(app.name).font(.title2.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(FutureStatisticsSample.dateLabel(date)).font(.subheadline)
                    Text(FutureStatisticsSample.isReferenceDay(date) ? "本机 · 截至23:41" : "本机 · 示例日汇总")
                        .font(.footnote)
                        .foregroundStyle(FutureTheme.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle(FutureStatisticsSample.isReferenceDay(date) ? "今日用时" : "当日用时")
                    FutureStatisticsDuration(minutes: minutes, size: 44)
                }

                VStack(alignment: .leading, spacing: 10) {
                    FutureSectionTitle("使用时段")
                    FutureCard {
                        VStack(spacing: 0) {
                            ForEach(intervals.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Text(FutureStatisticsSample.intervalLabel(index))
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(intervals[index])分钟")
                                            .font(.footnote)
                                            .foregroundStyle(FutureTheme.secondary)
                                    }
                                    if intervals[index] > 0 {
                                        FutureStatisticsProgress(
                                            value: Double(intervals[index]),
                                            maximum: Double(max(1, intervals.max() ?? 0))
                                        )
                                    }
                                    if index == 5 && FutureStatisticsSample.isReferenceDay(date) {
                                        Text("截至23:41")
                                            .font(.caption2)
                                            .foregroundStyle(FutureTheme.secondary)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .accessibilityElement(children: .combine)

                                if index < intervals.count - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(FutureTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FutureStatisticsProgress: View {
    let value: Double
    let maximum: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(FutureTheme.secondary.opacity(0.1))
                Capsule()
                    .fill(FutureTheme.accent)
                    .frame(width: geometry.size.width * min(1, max(0, value / max(1, maximum))))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// A fixed local fixture. All date navigation and selection stays inside this preview.
private enum FutureStatisticsSample {
    static let calendar = Calendar(identifier: .gregorian)
    static let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
    static let dailyMinutes = [105, 95, 110, 90, 115, 85, 100]

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func isReferenceDay(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: referenceDate)
    }

    static func baseMinutes(on date: Date) -> Int {
        let offset = calendar.dateComponents([.day], from: referenceDate, to: calendar.startOfDay(for: date)).day ?? 0
        return dailyMinutes[((offset + 6) % 7 + 7) % 7]
    }

    static func total(on date: Date, apps: [FutureApp]) -> Int {
        let weight = apps.reduce(0) { $0 + max(0, $1.minutes) }
        return Int((Double(baseMinutes(on: date)) * Double(weight) / 100).rounded())
    }

    static func minutes(for app: FutureApp, on date: Date, apps: [FutureApp]) -> Int {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return 0 }
        return distribute(total: total(on: date, apps: apps), weights: apps.map { max(0, $0.minutes) })[index]
    }

    /// Largest-remainder allocation keeps each breakdown equal to its displayed total.
    static func distribute(total: Int, weights: [Int]) -> [Int] {
        let weightSum = weights.reduce(0, +)
        guard total > 0, weightSum > 0 else { return weights.map { _ in 0 } }
        let exact = weights.map { Double(total) * Double($0) / Double(weightSum) }
        var values = exact.map { Int($0.rounded(.down)) }
        let remainder = total - values.reduce(0, +)
        let order = weights.indices.sorted {
            let left = exact[$0] - Double(values[$0])
            let right = exact[$1] - Double(values[$1])
            return left == right ? $0 < $1 : left > right
        }
        for index in order.prefix(remainder) { values[index] += 1 }
        return values
    }

    static func dateLabel(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    static func shortDateLabel(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    static func daySummary(_ date: Date) -> String {
        "\(dateLabel(date)) · \(isReferenceDay(date) ? "截至23:41" : "示例日汇总")"
    }

    static func durationLabel(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分钟" : "\(minutes)分钟"
    }

    static func intervalLabel(_ index: Int) -> String {
        String(format: "%02d:00—%02d:00", index * 4, (index + 1) * 4)
    }
}
