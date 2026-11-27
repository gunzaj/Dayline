import Foundation

// MARK: - Goals

public enum GoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case standing, breaks, lunch, breathing, reflection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standing: return "Standing / walking"
        case .breaks: return "Breaks taken"
        case .lunch: return "Protected lunch"
        case .breathing: return "Breathing sessions"
        case .reflection: return "End-of-day reflection"
        }
    }

    public var shortTitle: String {
        switch self {
        case .standing: return "Standing"
        case .breaks: return "Breaks"
        case .lunch: return "Lunch"
        case .breathing: return "Breathing"
        case .reflection: return "Reflection"
        }
    }

    public var symbol: String {
        switch self {
        case .standing: return "figure.stand"
        case .breaks: return "figure.walk.motion"
        case .lunch: return "fork.knife"
        case .breathing: return "wind"
        case .reflection: return "text.book.closed"
        }
    }

    public func targetLabel(_ targets: DayTargets) -> String {
        switch self {
        case .standing: return Fmt.duration(targets.standingMinutes)
        case .breaks: return "\(targets.breaks)"
        case .lunch: return "\(targets.lunchMinutes)+ min"
        case .breathing: return "\(targets.breathing)"
        case .reflection: return "1"
        }
    }
}

public struct GoalResult: Identifiable, Hashable, Sendable {
    public var goal: GoalKind
    public var hit: Bool
    public var progress: Double

    public var id: String { goal.rawValue }

    public init(goal: GoalKind, hit: Bool, progress: Double) {
        self.goal = goal
        self.hit = hit
        self.progress = max(0, min(1, progress))
    }
}

// MARK: - Day metrics

public struct DayMetrics: Identifiable, Hashable, Sendable {
    public var dayKey: String
    public var date: Date
    public var isWorkday: Bool
    public var isOff: Bool
    public var hasData: Bool

    public var standingMinutes: Int
    public var walkingMinutes: Int
    public var breaksTaken: Int
    public var breaksSkipped: Int
    public var snoozes: Int
    public var breathingCount: Int
    public var lunchMinutes: Int
    public var longestSeatedMinutes: Int
    public var meetingMinutes: Int
    public var longestBackToBackMinutes: Int
    public var stressAverage: Int?
    public var stressMax: Int?
    public var bodyBatteryStart: Int?
    public var bodyBatteryEnd: Int?

    public var checkInCount: Int
    public var hasReflection: Bool
    public var energy: Int?
    public var mood: Int?
    public var quadrant: MoodQuadrant?
    public var moodWord: String?

    public var goals: [GoalResult]

    public var id: String { dayKey }
    public var goalsHit: Int { goals.filter(\.hit).count }
    public var goalsTotal: Int { goals.count }
    public var movedMinutes: Int { standingMinutes + walkingMinutes }
    public var meetingHours: Double { Double(meetingMinutes) / 60.0 }

    public func goal(_ kind: GoalKind) -> GoalResult? { goals.first { $0.goal == kind } }
}

public struct Streak: Identifiable, Hashable, Sendable {
    public var goal: GoalKind
    public var current: Int
    public var recent: [Bool]   // oldest → newest, last five workdays

    public var id: String { goal.rawValue }
}

public struct WeekSummary: Sendable {
    public var monday: Date
    public var days: [DayMetrics]
    public var streaks: [Streak]
    public var insights: [Insight]

    public var workedDays: [DayMetrics] { days.filter { $0.hasData && $0.isWorkday } }

    public var moodTrend: [(String, MoodQuadrant?)] {
        days.map { (Fmt.weekdayShort.string(from: $0.date), $0.quadrant) }
    }
}

// MARK: - Summarizer

public enum Summarizer {

    // MARK: Day

    /// Records grouped by day, built once for work that needs many days
    /// (heat map, streaks, week) instead of rescanning every array per day.
    public struct DayIndex: Sendable {
        var days: [String: WorkDay] = [:]
        var breaks: [String: [BreakEvent]] = [:]
        var checkIns: [String: [CheckIn]] = [:]
        var journal: [String: [JournalEntry]] = [:]
        var samples: [String: [HealthSample]] = [:]
        var daily: [String: DailyHealth] = [:]

        public init(state: AppState) {
            for day in state.days { days[day.dayKey] = day }
            for item in state.breaks { breaks[item.dayKey, default: []].append(item) }
            for item in state.checkIns.sorted(by: { $0.at < $1.at }) {
                checkIns[DayKey.make(item.at), default: []].append(item)
            }
            for item in state.journal.sorted(by: { $0.at < $1.at }) {
                journal[DayKey.make(item.at), default: []].append(item)
            }
            for item in state.healthSamples.sorted(by: { $0.at < $1.at }) {
                samples[DayKey.make(item.at), default: []].append(item)
            }
            for item in state.healthDaily { daily[item.dayKey] = item }
        }
    }

    public static func metrics(dayKey: String, state: AppState, index: DayIndex? = nil) -> DayMetrics {
        let date = DayKey.date(from: dayKey) ?? Date()
        let day = index.map { $0.days[dayKey] } ?? state.day(dayKey)
        let checkIns = index.map { $0.checkIns[dayKey] ?? [] } ?? state.checkIns(on: dayKey)
        let entries = index.map { $0.journal[dayKey] ?? [] } ?? state.journal(on: dayKey)
        let breaks = index.map { $0.breaks[dayKey] ?? [] } ?? state.breaks(on: dayKey)
        let done = breaks.filter { $0.outcome == .done && $0.kind.countsAsBreak }
        let skipped = breaks.filter { $0.outcome == .skipped }
        let snoozes = breaks.filter { $0.outcome == .snoozed }.count
        let targets = day?.targets ?? state.settings.targets
        let reflection = entries.last { $0.kind == .reflection }
        // A reflection saved without journal text still counts: its check-in marks it.
        let reflected = reflection != nil || checkIns.contains { $0.source == .reflection }
        let linkedCheckIn = reflection?.checkInID.flatMap { id in checkIns.first { $0.id == id } }
        let lastCheckIn = linkedCheckIn ?? checkIns.last

        let samples = index.map { $0.samples[dayKey] ?? [] } ?? state.healthSamples(on: dayKey)
        let stresses = samples.compactMap(\.stress)
        let batteries = samples.compactMap(\.bodyBattery)
        let daily = index.map { $0.daily[dayKey] } ?? state.dailyHealth(dayKey)

        let breathing = done.filter { $0.kind == .boxBreathing }.count
        let lunch = max(day?.lunchMinutes ?? 0, done.filter { $0.kind == .lunch }.map(\.minutes).max() ?? 0)
        let isWorkday = state.settings.schedule(for: date) != nil
        let isOff = state.isOffDay(dayKey)
        let hasData = day != nil || !checkIns.isEmpty || !entries.isEmpty || !breaks.isEmpty

        let stressAvg = stresses.isEmpty ? daily?.stressAverage : stresses.reduce(0, +) / max(1, stresses.count)
        let stressMax = stresses.max()
        let batteryStart = batteries.first ?? daily?.bodyBatteryWake
        let batteryEnd = batteries.last ?? daily?.bodyBatteryEnd

        let standing = (day?.standingMinutes ?? 0) + (day?.walkingMinutes ?? 0)
        let standingProgress = targets.standingMinutes > 0 ? Double(standing) / Double(targets.standingMinutes) : 0
        let breaksProgress = targets.breaks > 0 ? Double(done.count) / Double(targets.breaks) : 0
        let lunchProgress = targets.lunchMinutes > 0 ? Double(lunch) / Double(targets.lunchMinutes) : 0
        let breathingProgress = targets.breathing > 0 ? Double(breathing) / Double(targets.breathing) : 0
        let reflectionProgress: Double = reflected ? 1 : 0

        let goals: [GoalResult] = [
            GoalResult(goal: .standing, hit: standing >= targets.standingMinutes, progress: standingProgress),
            GoalResult(goal: .breaks, hit: done.count >= targets.breaks, progress: breaksProgress),
            GoalResult(goal: .lunch, hit: lunch >= targets.lunchMinutes, progress: lunchProgress),
            GoalResult(goal: .breathing, hit: breathing >= targets.breathing, progress: breathingProgress),
            GoalResult(goal: .reflection, hit: reflected, progress: reflectionProgress),
        ]

        return DayMetrics(
            dayKey: dayKey,
            date: date,
            isWorkday: isWorkday,
            isOff: isOff,
            hasData: hasData,
            standingMinutes: day?.standingMinutes ?? 0,
            walkingMinutes: day?.walkingMinutes ?? 0,
            breaksTaken: done.count,
            breaksSkipped: skipped.count,
            snoozes: snoozes,
            breathingCount: breathing,
            lunchMinutes: lunch,
            longestSeatedMinutes: day?.longestSeatedMinutes ?? 0,
            meetingMinutes: day?.meetingMinutes ?? 0,
            longestBackToBackMinutes: day?.longestBackToBackMinutes ?? 0,
            stressAverage: stressAvg,
            stressMax: stressMax,
            bodyBatteryStart: batteryStart,
            bodyBatteryEnd: batteryEnd,
            checkInCount: checkIns.count,
            hasReflection: reflected,
            energy: lastCheckIn?.energy,
            mood: lastCheckIn?.mood,
            quadrant: lastCheckIn?.quadrant,
            moodWord: lastCheckIn?.word,
            goals: goals
        )
    }

    public static func healthCurve(dayKey: String, state: AppState) -> [HealthSample] {
        state.healthSamples(on: dayKey)
    }

    // MARK: Streaks

    public static func streak(_ goal: GoalKind, state: AppState, today: Date = Date(),
                              calendar: Calendar = .current, limitDays: Int = 365,
                              index: DayIndex? = nil) -> Streak {
        let index = index ?? DayIndex(state: state)
        var count = 0
        var recent: [Bool] = []
        var cursor = DayKey.startOfDay(today, calendar: calendar)
        let cutoff = DayKey.adding(days: -limitDays, to: cursor, calendar: calendar)
        let todayKey = DayKey.make(today, calendar: calendar)
        var isFirstWorkday = true

        while cursor >= cutoff {
            let key = DayKey.make(cursor, calendar: calendar)
            let workday = state.settings.schedule(for: cursor, calendar: calendar) != nil
            let off = state.isOffDay(key)
            if workday && !off {
                let metrics = metrics(dayKey: key, state: state, index: index)
                let hit = metrics.goal(goal)?.hit ?? false
                let isToday = key == todayKey
                let dayRunning = state.day(key)?.end == nil && isToday

                if recent.count < 5 { recent.insert(hit, at: 0) }

                if hit {
                    count += 1
                } else if isFirstWorkday && (isToday && dayRunning) {
                    // Today is still open: an unfinished goal does not break the streak.
                } else {
                    break
                }
                isFirstWorkday = false
            }
            cursor = DayKey.adding(days: -1, to: cursor, calendar: calendar)
        }
        return Streak(goal: goal, current: count, recent: recent)
    }

    public static func streaks(state: AppState, today: Date = Date()) -> [Streak] {
        let index = DayIndex(state: state)
        return GoalKind.allCases.map { streak($0, state: state, today: today, index: index) }
    }

    // MARK: Week

    public static func week(containing date: Date, state: AppState, calendar: Calendar = .current) -> WeekSummary {
        let monday = DayKey.monday(of: date, calendar: calendar)
        var days: [DayMetrics] = []
        for offset in 0..<5 {
            let d = DayKey.adding(days: offset, to: monday, calendar: calendar)
            days.append(metrics(dayKey: DayKey.make(d, calendar: calendar), state: state))
        }
        let weekEnd = DayKey.adding(days: 5, to: monday, calendar: calendar)
        let insights = state.insights.filter { $0.periodStart >= monday && $0.periodStart < weekEnd }
        return WeekSummary(monday: monday, days: days, streaks: streaks(state: state), insights: insights)
    }

    // MARK: Heat map

    public static func heatmap(state: AppState, endingAt: Date = Date(),
                               weeks: Int = 52, calendar: Calendar = .current) -> Heatmap {
        let today = DayKey.startOfDay(endingAt, calendar: calendar)
        let thisMonday = DayKey.monday(of: today, calendar: calendar)
        let index = DayIndex(state: state)
        let firstMonday = DayKey.adding(days: -7 * (weeks - 1), to: thisMonday, calendar: calendar)

        var resultWeeks: [HeatmapWeek] = []
        var allCells: [HeatmapCell] = []

        for w in 0..<weeks {
            let monday = DayKey.adding(days: 7 * w, to: firstMonday, calendar: calendar)
            var cells: [HeatmapCell?] = []
            for d in 0..<5 {
                let date = DayKey.adding(days: d, to: monday, calendar: calendar)
                if date > today {
                    cells.append(nil)
                    continue
                }
                let key = DayKey.make(date, calendar: calendar)
                let metrics = metrics(dayKey: key, state: state, index: index)
                let cell = HeatmapCell(
                    dayKey: key, date: date,
                    isOff: metrics.isOff || !metrics.isWorkday,
                    goals: metrics.goalsHit,
                    quadrant: metrics.quadrant,
                    energy: metrics.energy, mood: metrics.mood,
                    moodWord: metrics.moodWord,
                    standingMinutes: metrics.movedMinutes,
                    breaks: metrics.breaksTaken,
                    meetingMinutes: metrics.meetingMinutes,
                    stress: metrics.stressAverage,
                    hasData: metrics.hasData
                )
                cells.append(cell)
                allCells.append(cell)
            }
            resultWeeks.append(HeatmapWeek(monday: monday, cells: cells))
        }

        let months = resultWeeks.enumerated().compactMap { index, week -> HeatmapMonth? in
            let month = calendar.component(.month, from: week.monday)
            let previous = index > 0 ? calendar.component(.month, from: resultWeeks[index - 1].monday) : -1
            guard month != previous else { return nil }
            return HeatmapMonth(index: index, label: Fmt.monthShort.string(from: week.monday))
        }

        return Heatmap(weeks: resultWeeks, months: months, start: firstMonday, end: today,
                       targets: state.settings.targets, allCells: allCells)
    }
}

// MARK: - Heat map types

public enum HeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    case goals, mood, standing, breaks, meetings, stress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .goals: return "Goals"
        case .mood: return "Mood"
        case .standing: return "Standing"
        case .breaks: return "Breaks"
        case .meetings: return "Meetings"
        case .stress: return "Stress"
        }
    }

    /// Compact segmented-control label.
    public var shortTitle: String {
        switch self {
        case .goals: return "Goals"
        case .mood: return "Mood"
        case .standing: return "Stand"
        case .breaks: return "Breaks"
        case .meetings: return "Calls"
        case .stress: return "Stress"
        }
    }

    public var lowLabel: String {
        switch self {
        case .goals: return "0 goals"
        case .mood: return "Paler = middle"
        case .standing: return "under 30 min"
        case .breaks: return "0 to 1"
        case .meetings: return "under 1 h"
        case .stress: return "under 25"
        }
    }

    public var highLabel: String {
        switch self {
        case .goals: return "5 goals"
        case .mood: return "Stronger = corner"
        case .standing: return "2 h target"
        case .breaks: return "6+ breaks"
        case .meetings: return "5 h+"
        case .stress: return "50+"
        }
    }

    public var isWarning: Bool { self == .meetings || self == .stress }

    public func level(_ cell: HeatmapCell, targets: DayTargets) -> Int? {
        switch self {
        case .goals:
            guard cell.hasData else { return nil }
            switch cell.goals {
            case 0: return 0
            case 1: return 1
            case 2: return 1
            case 3: return 2
            case 4: return 3
            default: return 4
            }
        case .mood:
            guard cell.quadrant != nil else { return nil }
            return nil
        case .standing:
            guard cell.hasData else { return nil }
            if cell.standingMinutes < 30 { return 0 }
            if cell.standingMinutes < 60 { return 1 }
            if cell.standingMinutes < 90 { return 2 }
            if cell.standingMinutes < targets.standingMinutes { return 3 }
            return 4
        case .breaks:
            guard cell.hasData else { return nil }
            switch cell.breaks {
            case 0, 1: return 0
            case 2, 3: return 1
            case 4: return 2
            case 5: return 3
            default: return 4
            }
        case .meetings:
            guard cell.hasData else { return nil }
            let h = Double(cell.meetingMinutes) / 60.0
            if h < 1 { return 0 }
            if h < 2 { return 1 }
            if h < 3.5 { return 2 }
            if h < 5 { return 3 }
            return 4
        case .stress:
            guard let stress = cell.stress else { return nil }
            if stress < 25 { return 0 }
            if stress < 32 { return 1 }
            if stress < 40 { return 2 }
            if stress < 50 { return 3 }
            return 4
        }
    }

    public func formatted(_ cell: HeatmapCell) -> String {
        switch self {
        case .goals: return "\(cell.goals) of 5 goals"
        case .mood: return cell.quadrant.map { "\(cell.moodWord ?? "") · \($0.name)" } ?? "No check-in"
        case .standing: return "\(cell.standingMinutes) min standing or walking"
        case .breaks: return "\(cell.breaks) breaks taken"
        case .meetings: return String(format: "%.2g h of meetings", Double(cell.meetingMinutes) / 60.0)
        case .stress: return "Average stress \(cell.stress.map(String.init) ?? "—")"
        }
    }
}

public struct HeatmapCell: Identifiable, Hashable, Sendable {
    public var dayKey: String
    public var date: Date
    public var isOff: Bool
    public var goals: Int
    public var quadrant: MoodQuadrant?
    public var energy: Int?
    public var mood: Int?
    public var moodWord: String?
    public var standingMinutes: Int
    public var breaks: Int
    public var meetingMinutes: Int
    public var stress: Int?
    public var hasData: Bool

    public var id: String { dayKey }
}

public struct HeatmapWeek: Identifiable, Sendable {
    public var monday: Date
    public var cells: [HeatmapCell?]
    public var id: Date { monday }
}

public struct HeatmapMonth: Identifiable, Sendable {
    public var index: Int
    public var label: String
    public var id: Int { index }
}

public struct Heatmap: Sendable {
    public var weeks: [HeatmapWeek]
    public var months: [HeatmapMonth]
    public var start: Date
    public var end: Date
    public var targets: DayTargets
    public var allCells: [HeatmapCell]

    public var dataCells: [HeatmapCell] { allCells.filter { $0.hasData && !$0.isOff } }

    public func stats(for metric: HeatmapMetric) -> [(value: String, label: String)] {
        let cells = dataCells
        guard !cells.isEmpty else { return [("—", "No days yet")] }
        let wdNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        func weekdayAverage(_ values: [HeatmapCell], _ value: (HeatmapCell) -> Double) -> (String, Double) {
            var sums = Array(repeating: 0.0, count: 5)
            var counts = Array(repeating: 0, count: 5)
            for c in values {
                let idx = DayKey.mondayIndex(c.date)
                if (0..<5).contains(idx) {
                    sums[idx] += value(c)
                    counts[idx] += 1
                }
            }
            var best = 0
            for i in 0..<5 where counts[i] > 0 {
                if counts[best] == 0 || sums[i] / Double(counts[i]) > sums[best] / Double(counts[best]) { best = i }
            }
            return (wdNames[best], counts[best] > 0 ? sums[best] / Double(counts[best]) : 0)
        }
        func average(_ value: (HeatmapCell) -> Double) -> Double {
            guard !cells.isEmpty else { return 0 }
            return cells.map(value).reduce(0, +) / Double(cells.count)
        }
        func round1(_ v: Double) -> String { String(format: "%.1f", v) }

        switch metric {
        case .goals:
            let avgGoals = average { Double($0.goals) }
            let perfect = cells.filter { $0.goals == 5 }.count
            let (wd, wdv) = weekdayAverage(cells) { Double($0.goals) }
            let low = cells.filter { $0.goals <= 1 }.count
            return [(round1(avgGoals), "goals hit on average, of 5"),
                    ("\(perfect)", "days with all 5 goals"),
                    (wd, "best day, \(round1(wdv)) goals on average"),
                    ("\(low)", "days with 0 or 1 goal")]
        case .mood:
            let withMood = cells.filter { $0.quadrant != nil }
            guard !withMood.isEmpty else { return [("—", "No mood data")] }
            return MoodQuadrant.allCases.map { q in
                let pct = Int((100.0 * Double(withMood.filter { $0.quadrant == q }.count) / Double(withMood.count)).rounded())
                return ("\(pct)%", q.name)
            }
        case .standing:
            let avg = average { Double($0.standingMinutes) }
            let target = cells.filter { $0.standingMinutes >= targets.standingMinutes }.count
            let early = cells.filter { $0.date < DayKey.adding(days: 91, to: start) }
            let late = cells.filter { $0.date >= DayKey.adding(days: -91, to: end) }
            let earlyAvg = early.isEmpty ? 0 : early.map { Double($0.standingMinutes) }.reduce(0, +) / Double(early.count)
            let lateAvg = late.isEmpty ? 0 : late.map { Double($0.standingMinutes) }.reduce(0, +) / Double(late.count)
            return [("\(Int(avg.rounded())) min", "a day on average"),
                    ("\(target)", "days on the \(Fmt.duration(targets.standingMinutes)) target"),
                    ("\(Int(earlyAvg.rounded())) min", "first three months"),
                    ("\(Int(lateAvg.rounded())) min", "last three months")]
        case .breaks:
            let avg = average { Double($0.breaks) }
            let target = cells.filter { $0.breaks >= targets.breaks }.count
            var sums = Array(repeating: 0.0, count: 5), counts = Array(repeating: 0, count: 5)
            for c in cells {
                let idx = DayKey.mondayIndex(c.date)
                if (0..<5).contains(idx) { sums[idx] += Double(c.breaks); counts[idx] += 1 }
            }
            var fewest = 0
            for i in 0..<5 where counts[i] > 0 {
                if counts[fewest] == 0 || sums[i] / Double(counts[i]) < sums[fewest] / Double(counts[fewest]) { fewest = i }
            }
            let fewestAvg = counts[fewest] > 0 ? sums[fewest] / Double(counts[fewest]) : 0
            return [(round1(avg), "breaks a day on average"),
                    ("\(target)", "days on the \(targets.breaks)-break target"),
                    (wdNames[fewest], "fewest breaks, \(round1(fewestAvg)) on average"),
                    ("\(cells.filter { $0.breaks <= 2 }.count)", "days with 2 or fewer")]
        case .meetings:
            let avg = average { Double($0.meetingMinutes) / 60.0 }
            let (wd, wdv) = weekdayAverage(cells) { Double($0.meetingMinutes) / 60.0 }
            let heavy = cells.filter { $0.meetingMinutes >= 300 }.count
            let light = cells.filter { $0.meetingMinutes < 120 }.count
            return [(String(format: "%.1f h", avg), "of meetings a day"),
                    (wd, "heaviest day, \(String(format: "%.1f", wdv)) h on average"),
                    ("\(heavy)", "days with 5+ h"),
                    ("\(light)", "light days under 2 h")]
        case .stress:
            let withStress = cells.compactMap(\.stress)
            guard !withStress.isEmpty else { return [("—", "No Garmin data")] }
            let avg = withStress.reduce(0, +) / withStress.count
            let (wd, wdv) = weekdayAverage(cells.filter { $0.stress != nil }) { Double($0.stress ?? 0) }
            return [("\(avg)", "average workday stress"),
                    (wd, "highest, \(Int(wdv.rounded())) on average"),
                    ("\(cells.filter { ($0.stress ?? 0) >= 50 }.count)", "days averaging 50+"),
                    ("\(cells.filter { ($0.stress ?? 100) < 25 }.count)", "calm days under 25")]
        }
    }

    public func pattern(for metric: HeatmapMetric) -> String {
        let cells = dataCells
        guard !cells.isEmpty else { return "Not enough days yet. Keep the app running for a week and the pattern shows up here." }
        let wdNames = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays"]
        func weekdayNumbers(_ value: (HeatmapCell) -> Double) -> [Double] {
            var sums = Array(repeating: 0.0, count: 5), counts = Array(repeating: 0, count: 5)
            for c in cells {
                let idx = DayKey.mondayIndex(c.date)
                if (0..<5).contains(idx) { sums[idx] += value(c); counts[idx] += 1 }
            }
            return (0..<5).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : 0 }
        }
        func extreme(_ values: [Double], max: Bool) -> Int {
            var best = 0
            for i in 1..<values.count {
                if (max && values[i] > values[best]) || (!max && values[i] < values[best]) { best = i }
            }
            return best
        }
        switch metric {
        case .goals:
            let heavy = cells.filter { $0.meetingMinutes >= 300 }
            let light = cells.filter { $0.meetingMinutes < 300 }
            guard !heavy.isEmpty, !light.isEmpty else { return "Log a few more days to compare meeting-heavy and light days." }
            let ha = Double(heavy.map(\.goals).reduce(0, +)) / Double(heavy.count)
            let la = Double(light.map(\.goals).reduce(0, +)) / Double(light.count)
            return String(format: "On days with 5+ h of meetings you hit %.1f of 5 goals, against %.1f on lighter days.", ha, la)
        case .mood:
            let drained = cells.filter { $0.quadrant == .drainedFlat }
            guard !drained.isEmpty else { return "No Drained · flat days in this range." }
            var counts = Array(repeating: 0, count: 5)
            for c in drained { counts[DayKey.mondayIndex(c.date)] += 1 }
            let idx = extreme(counts.map(Double.init), max: true)
            return "Drained · flat days cluster on \(wdNames[idx]): \(counts[idx]) of \(drained.count)."
        case .standing:
            let early = cells.filter { $0.date < DayKey.adding(days: 91, to: start) }
            let late = cells.filter { $0.date >= DayKey.adding(days: -91, to: end) }
            guard !early.isEmpty, !late.isEmpty else { return "Standing time averages \(Int((Double(cells.map(\.standingMinutes).reduce(0, +)) / Double(cells.count)).rounded())) min a day." }
            let ea = Double(early.map(\.standingMinutes).reduce(0, +)) / Double(early.count)
            let la = Double(late.map(\.standingMinutes).reduce(0, +)) / Double(late.count)
            return "Standing time went from \(Int(ea.rounded())) min a day in the first months to \(Int(la.rounded())) min in the last three."
        case .breaks:
            let values = weekdayNumbers { Double($0.breaks) }
            let idx = extreme(values, max: false)
            return String(format: "%@ have the fewest breaks: %.1f on average.", wdNames[idx].capitalized, values[idx])
        case .meetings:
            let values = weekdayNumbers { Double($0.meetingMinutes) / 60.0 }
            let idx = extreme(values, max: true)
            return String(format: "%@ are your heaviest meeting day: %.1f h on average.", wdNames[idx].capitalized, values[idx])
        case .stress:
            let heavy = cells.filter { $0.stress != nil && $0.meetingMinutes >= 300 }.compactMap(\.stress)
            let light = cells.filter { $0.stress != nil && $0.meetingMinutes < 300 }.compactMap(\.stress)
            guard !heavy.isEmpty, !light.isEmpty else {
                let values = weekdayNumbers { Double($0.stress ?? 0) }
                let idx = extreme(values, max: true)
                return "Stress is highest on \(wdNames[idx])."
            }
            let ha = heavy.reduce(0, +) / heavy.count
            let la = light.reduce(0, +) / light.count
            return "Stress averages \(ha) on days with 5+ h of meetings, against \(la) on lighter days."
        }
    }
}
