import Foundation

public enum Planner {

    // MARK: Busy ranges

    public static func busyRanges(_ events: [CalendarEvent], clippedTo window: TimeRange? = nil) -> [TimeRange] {
        var ranges = events.filter(\.blocksTime).map(\.range).sorted { $0.start < $1.start }
        if let window {
            ranges = ranges.compactMap { $0.intersection(window) }
        }
        var merged: [TimeRange] = []
        for r in ranges {
            if let last = merged.last, r.start <= last.end.adding(minutes: 1) {
                merged[merged.count - 1] = TimeRange(start: last.start, end: max(last.end, r.end))
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    public static func freeGaps(in window: TimeRange, busy: [TimeRange]) -> [TimeRange] {
        var gaps: [TimeRange] = []
        var cursor = window.start
        for r in busy.sorted(by: { $0.start < $1.start }) {
            if r.start > cursor {
                gaps.append(TimeRange(start: cursor, end: min(r.start, window.end)))
            }
            cursor = max(cursor, r.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            gaps.append(TimeRange(start: cursor, end: window.end))
        }
        return gaps.filter { $0.minutes >= 1 }
    }

    // MARK: Stats

    public static func meetingMinutes(_ events: [CalendarEvent], in window: TimeRange) -> Int {
        busyRanges(events, clippedTo: window).reduce(0) { $0 + $1.minutes }
    }

    public static func longestMeeting(_ events: [CalendarEvent]) -> Int {
        events.filter(\.blocksTime).map(\.minutes).max() ?? 0
    }

    /// Longest run of back-to-back calls. A gap of 5 minutes or less counts as back-to-back.
    public static func longestBackToBack(_ events: [CalendarEvent], toleranceMinutes: Int = 5) -> Int {
        let sorted = events.filter(\.blocksTime).sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return 0 }
        var best = 0
        var runStart = sorted[0].start
        var runEnd = sorted[0].end
        for e in sorted.dropFirst() {
            if e.start <= runEnd.adding(minutes: toleranceMinutes) {
                runEnd = max(runEnd, e.end)
            } else {
                best = max(best, TimeRange.minutesBetween(runStart, runEnd))
                runStart = e.start
                runEnd = e.end
            }
        }
        best = max(best, TimeRange.minutesBetween(runStart, runEnd))
        return best
    }

    // MARK: Standing rules

    public static func standingSuggestion(for event: CalendarEvent,
                                          rules: [StandingRule]) -> (target: StandingTarget, rule: StandingRule)? {
        guard event.blocksTime else { return nil }
        let excludes = rules.filter { $0.isExclude && $0.matches(event) }
        if !excludes.isEmpty { return nil }
        guard let include = rules.first(where: { !$0.isExclude && $0.matches(event) }) else { return nil }
        return (include.target, include)
    }

    // MARK: Day plan

    public static func plan(events: [CalendarEvent],
                            date: Date,
                            settings: AppSettings,
                            calendar: Calendar = .current) -> DayPlan? {
        guard let hours = settings.schedule(for: date, calendar: calendar) else { return nil }
        let workStart = hours.start.date(on: date, calendar: calendar)
        let workEnd = hours.end.date(on: date, calendar: calendar)
        let window = TimeRange(start: workStart, end: workEnd)

        let relevant = events.filter { $0.blocksTime && $0.end > window.start && $0.start < window.end }
        let busy = busyRanges(relevant, clippedTo: window)
        let gaps = freeGaps(in: window, busy: busy)

        let lunchWindowStart = settings.lunchWindowStart.date(on: date, calendar: calendar)
        let lunchWindowEnd = settings.lunchWindowEnd.date(on: date, calendar: calendar)
        let lunchWindow = TimeRange(start: max(lunchWindowStart, workStart),
                                    end: min(lunchWindowEnd, workEnd))

        let lunchGaps = gaps.compactMap { $0.intersection(lunchWindow) }
            .filter { $0.minutes >= settings.lunchTargetMinutes }
        let lunchGap = lunchGaps.max { $0.minutes < $1.minutes }

        let suggestions: [StandingSuggestion] = relevant.compactMap { event in
            guard let match = standingSuggestion(for: event, rules: settings.standingRules),
                  event.start > workStart else { return nil }
            return StandingSuggestion(event: event, target: match.target, rule: match.rule)
        }

        var timeline: [PlanItem] = []

        // Meetings
        for e in relevant.sorted(by: { $0.start < $1.start }) {
            let match = standingSuggestion(for: e, rules: settings.standingRules)
            let chip: String
            let style: String
            if let match {
                chip = match.target.title
                style = "accent"
            } else {
                chip = "Busy"
                style = "plain"
            }
            let detail = e.attendeeCount.map { "\($0) people" } ?? ""
            timeline.append(PlanItem(id: "meet-" + e.id, kind: .meeting, start: e.start, end: e.end,
                                     title: e.title, detail: detail, chip: chip, chipStyle: style))
        }

        // Break opportunities: one per qualifying gap, plus one after long blocks.
        let blockThreshold = settings.longMeetingMinutes
        let runThreshold = settings.backToBackMinutes
        let longBlockEnd = longBlock(after: workStart, events: relevant, block: blockThreshold, run: runThreshold)
        for gap in gaps where gap.minutes >= 5 {
            let length = gap.minutes >= 30 ? 30 : (gap.minutes >= 5 ? 5 : 2)
            let start = gap.start
            let end = start.adding(minutes: min(length, gap.minutes))
            var item = PlanItem(kind: .breakOpportunity, start: start, end: end,
                                title: length >= 30 ? "Standing block or walk" : "Movement break",
                                detail: "Fits the gap", chip: "Break", chipStyle: "plain")
            if let lb = longBlockEnd, abs(gap.start.timeIntervalSince(lb.end)) < 60 {
                item.title = "Break after a long block"
                item.detail = "\(lb.minutes) min of calls"
                item.chip = "After long block"
            }
            timeline.append(item)
        }

        // Lunch
        if let lunchGap {
            let start = max(lunchGap.start, lunchWindow.start)
            let end = start.adding(minutes: min(max(settings.lunchTargetMinutes, 30), lunchGap.minutes))
            timeline.append(PlanItem(kind: .lunch, start: start, end: end,
                                     title: "Lunch away from desk", detail: "Protected window",
                                     chip: "Protected", chipStyle: "warn"))
        }

        // Wind-down
        let lastMeetingEnd = relevant.map(\.end).max()
        var windDown = settings.windDown.date(on: date, calendar: calendar)
        if let lastMeetingEnd, lastMeetingEnd > windDown { windDown = lastMeetingEnd }
        timeline.append(PlanItem(kind: .windDown, start: windDown, end: windDown.adding(minutes: 15),
                                 title: "Wind-down and reflection", detail: "",
                                 chip: "Reflect", chipStyle: "plain"))

        timeline.sort { $0.start < $1.start }

        return DayPlan(events: relevant.sorted { $0.start < $1.start },
                       workStart: workStart,
                       workEnd: workEnd,
                       meetingMinutes: meetingMinutes(relevant, in: window),
                       longestMeetingMinutes: longestMeeting(relevant),
                       longestBackToBackMinutes: longestBackToBack(relevant),
                       freeGaps: gaps,
                       lunchWindow: lunchWindow,
                       lunchGap: lunchGap,
                       standingSuggestions: suggestions,
                       timeline: timeline)
    }

    /// The most recent long block (60+ meeting or 90+ back-to-back run) that ended before now.
    public static func longBlockEndingBefore(_ date: Date, events: [CalendarEvent],
                                             settings: AppSettings) -> TimeRange? {
        let runs = backToBackRuns(events)
        var candidates: [TimeRange] = []
        for e in events where e.blocksTime && e.minutes >= settings.longMeetingMinutes {
            candidates.append(e.range)
        }
        for r in runs where r.minutes >= settings.backToBackMinutes {
            candidates.append(r)
        }
        return candidates.filter { $0.end <= date }.max { $0.end < $1.end }
    }

    public static func longBlock(after start: Date, events: [CalendarEvent],
                                 block: Int, run: Int) -> TimeRange? {
        var candidates: [TimeRange] = events.filter { $0.blocksTime && $0.minutes >= block }.map(\.range)
        candidates += backToBackRuns(events).filter { $0.minutes >= run }
        return candidates.filter { $0.start >= start }.max { $0.end < $1.end }
    }

    public static func backToBackRuns(_ events: [CalendarEvent], toleranceMinutes: Int = 5) -> [TimeRange] {
        let sorted = events.filter(\.blocksTime).sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        var runs: [TimeRange] = []
        var start = sorted[0].start
        var end = sorted[0].end
        for e in sorted.dropFirst() {
            if e.start <= end.adding(minutes: toleranceMinutes) {
                end = max(end, e.end)
            } else {
                runs.append(TimeRange(start: start, end: end))
                start = e.start
                end = e.end
            }
        }
        runs.append(TimeRange(start: start, end: end))
        return runs
    }
}
