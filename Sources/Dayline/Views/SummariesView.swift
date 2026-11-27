import AppKit
import DaylineCore
import SwiftUI

enum InsightRange: String, CaseIterable, Identifiable {
    case week = "This week"
    case last7 = "Last 7 days"
    case last30 = "Last 30 days"
    var id: String { rawValue }
}

@MainActor
final class SummariesUI: ObservableObject {
    @Published var dayKey: String = DayKey.make(Date())
    @Published var weekOffset: Int = 0
    @Published var heatMetric: HeatmapMetric = .goals
    @Published var selectedCellKey: String?
    @Published var question = ""
    @Published var insightRange: InsightRange = .last7
}

struct SummariesView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = SummariesUI()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DL.line)
            ScrollView {
                Group {
                    switch model.summaryTab {
                    case .day: dayView
                    case .week: weekView
                    case .year: yearView
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
        }
        .background(DL.window)
        .onAppear {
            ui.dayKey = DayKey.make(model.now)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Summaries and insights")
                Text("The shape of the work")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.4)
            }
            Spacer()
            SegmentedPicker(options: SummaryTab.allCases.map { ($0, $0.rawValue) },
                            selection: $model.summaryTab)
                .frame(width: 260)
            Button("Journal") { model.openJournal() }
                .buttonStyle(LinkButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DL.titlebar)
    }

    // MARK: - Day

    private var dayView: some View {
        let metrics = Summarizer.metrics(dayKey: ui.dayKey, state: model.state)
        let date = DayKey.date(from: ui.dayKey) ?? model.now
        let day = model.state.day(ui.dayKey)
        let targets = day?.targets ?? model.settings.targets
        let breaks = model.state.breaks(on: ui.dayKey).filter { $0.outcome != .planned }
        let checkIns = model.state.checkIns(on: ui.dayKey)
        let entries = model.state.journal(on: ui.dayKey)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(DL.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Fmt.weekdayLong.string(from: date)), \(Fmt.dayMonthYear.string(from: date))")
                        .font(.system(size: 20, weight: .semibold))
                    Text(daySubtitle(metrics))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                }
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).foregroundStyle(DL.muted)
                Spacer()
                if ui.dayKey != DayKey.make(model.now) {
                    Button("Today") { ui.dayKey = DayKey.make(model.now) }
                        .buttonStyle(LinkButtonStyle())
                }
                Button("Reflect") { model.openReflection(dayKey: ui.dayKey) }
                    .buttonStyle(SecondaryButtonStyle())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                StatCard(value: Fmt.compactDuration(metrics.movedMinutes), label: "standing / walking · \(targets.standingMinutes) min target")
                StatCard(value: "\(metrics.breaksTaken)", label: "breaks · \(metrics.breaksSkipped) skipped · \(metrics.snoozes) snoozed")
                StatCard(value: "\(metrics.lunchMinutes) min", label: "lunch away · \(metrics.lunchMinutes >= targets.lunchMinutes ? "protected" : "missed")")
                StatCard(value: Fmt.compactDuration(metrics.longestSeatedMinutes), label: "longest seated stretch")
                StatCard(value: String(format: "%.1f h", metrics.meetingHours), label: "meetings")
                StatCard(value: Fmt.compactDuration(metrics.longestBackToBackMinutes), label: "longest back-to-back run")
                StatCard(value: metrics.stressAverage.map(String.init) ?? "—", label: "average stress", tint: stressTint(metrics.stressAverage))
                StatCard(value: metrics.bodyBatteryEnd.map { "\(metrics.bodyBatteryStart.map(String.init) ?? "—")→\($0)" } ?? "—",
                         label: "Body Battery", tint: DL.calm)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Eyebrow(text: "Stress and Body Battery")
                        Spacer()
                        if let mood = metrics.moodWord { Chip(text: mood, style: .accent) }
                    }
                    DayCurveChart(samples: model.state.healthSamples.filter { DayKey.make($0.at) == ui.dayKey },
                                  breaks: breaks,
                                  start: day?.start ?? date.adding(minutes: 9 * 60),
                                  end: day?.end ?? date.adding(minutes: 17 * 60 + 30))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Daily goals")
                    GoalRows(metrics: metrics, targets: targets)
                    Divider().overlay(DL.line)
                    HStack(spacing: 5) {
                        Text("\(metrics.goalsHit) of 5").font(.system(size: 12, weight: .semibold))
                        Text("goals hit").font(.system(size: 11)).foregroundStyle(DL.muted)
                    }
                }
                .padding(12)
                .frame(width: 250, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            }

            HStack(alignment: .top, spacing: 10) {
                breaksCard(breaks)
                checkInsCard(checkIns)
            }

            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Journal")
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Fmt.time.string(from: entry.at))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DL.muted)
                                .frame(width: 38, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.promptAnswers.isEmpty ? entry.text : (entry.promptAnswers.first?.answer ?? entry.text))
                                    .font(.system(size: 12))
                                    .lineLimit(3)
                                if entry.kind == .reflection {
                                    Text("End-of-day reflection").font(.system(size: 9.5)).foregroundStyle(DL.muted)
                                }
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DL.panel))
                    }
                }
            }
        }
    }

    private func daySubtitle(_ metrics: DayMetrics) -> String {
        if metrics.isOff { return "Day off. Streaks paused." }
        if !metrics.hasData { return "No data for this day yet." }
        if let q = metrics.quadrant, let word = metrics.moodWord {
            return "\(q.name) · \(word)"
        }
        return "\(metrics.checkInCount) check-in\(metrics.checkInCount == 1 ? "" : "s")"
    }

    private func breaksCard(_ breaks: [BreakEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow(text: "Breaks and reasons")
                Spacer()
                Text("\(breaks.filter { $0.outcome == .done }.count) done")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
            }
            if breaks.isEmpty {
                Text("No breaks recorded.").font(.system(size: 11)).foregroundStyle(DL.muted)
            } else {
                ForEach(breaks.sorted { ($0.startedAt ?? $0.plannedAt) < ($1.startedAt ?? $1.plannedAt) }) { brk in
                    HStack(spacing: 7) {
                        Text(Fmt.time.string(from: brk.startedAt ?? brk.plannedAt))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DL.muted)
                        Image(systemName: brk.outcome == .done ? "checkmark.circle.fill" : (brk.outcome == .skipped ? "xmark.circle" : "zzz.circle"))
                            .font(.system(size: 10))
                            .foregroundStyle(brk.outcome == .done ? DL.calm : DL.muted)
                        Text(brk.displayTitle)
                            .font(.system(size: 11.5))
                        if brk.minutes > 0 {
                            Text("\(brk.minutes)m").font(.system(size: 10)).foregroundStyle(DL.muted)
                        }
                        Spacer()
                        if let reason = brk.skipReason {
                            Chip(text: reason.rawValue, style: .warn)
                        } else if brk.outcome == .snoozed {
                            Chip(text: "Snoozed", style: .plain)
                        } else if brk.verifiedBy == .auto {
                            Chip(text: "Auto", style: .plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func checkInsCard(_ checkIns: [CheckIn]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Mood and energy")
            if checkIns.isEmpty {
                Text("No check-ins.").font(.system(size: 11)).foregroundStyle(DL.muted)
            }
            ForEach(checkIns) { checkIn in
                HStack(spacing: 7) {
                    QuadrantDot(quadrant: checkIn.quadrant)
                    Text(checkIn.word).font(.system(size: 12, weight: .medium))
                    Text("E\(checkIn.energy) · P\(checkIn.mood)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DL.muted)
                    Spacer()
                    Text(Fmt.time.string(from: checkIn.at))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DL.muted)
                }
            }
        }
        .padding(12)
        .frame(width: 270, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func stressTint(_ stress: Int?) -> Color {
        guard let stress else { return DL.ink }
        if stress >= model.settings.garmin.stressHigh { return DL.crit }
        if stress >= model.settings.garmin.stressHigh - 15 { return DL.warn }
        return DL.calm
    }

    private func shiftDay(_ offset: Int) {
        let date = (DayKey.date(from: ui.dayKey) ?? model.now).adding(days: offset)
        ui.dayKey = DayKey.make(date)
    }

    // MARK: - Week

    private var weekView: some View {
        let monday = DayKey.monday(of: model.now).adding(days: ui.weekOffset * 7)
        let week = Summarizer.week(containing: monday, state: model.state)
        let targets = model.settings.targets
        let worked = week.workedDays
        let totalMoved = worked.reduce(0) { $0 + $1.movedMinutes }
        let totalBreaks = worked.reduce(0) { $0 + $1.breaksTaken }
        let totalMeetings = worked.reduce(0) { $0 + $1.meetingMinutes }
        let goalsHit = worked.reduce(0) { $0 + $1.goalsHit }
        let goalsPossible = worked.count * 5
        let insight = week.insights.max { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { ui.weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(DL.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Week of \(Fmt.dayMonth.string(from: monday))")
                        .font(.system(size: 20, weight: .semibold))
                    Text("\(worked.count) workday\(worked.count == 1 ? "" : "s") with data · \(goalsHit) of \(goalsPossible) goals hit")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                }
                Button { ui.weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).foregroundStyle(DL.muted)
                Spacer()
                if ui.weekOffset != 0 {
                    Button("This week") { ui.weekOffset = 0 }
                        .buttonStyle(LinkButtonStyle())
                }
                Button("Export journal") { model.exportJournal() }
                    .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                StatCard(value: Fmt.compactDuration(totalMoved), label: "standing / walking all week")
                StatCard(value: "\(totalBreaks)", label: "breaks taken")
                StatCard(value: String(format: "%.1f h", Double(totalMeetings) / 60), label: "meetings")
                StatCard(value: "\(goalsHit)/\(goalsPossible)", label: "goals hit")
            }

            weekTable(week, targets: targets)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Eyebrow(text: "Standing and walking")
                        Spacer()
                        Text("target \(targets.standingMinutes) min").font(.system(size: 10)).foregroundStyle(DL.muted)
                    }
                    WeekBars(days: week.days, target: targets.standingMinutes)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "Mood and energy")
                    ForEach(week.days) { day in
                        HStack(spacing: 6) {
                            Text(Fmt.weekdayShort.string(from: day.date))
                                .font(.system(size: 10.5, weight: .medium))
                                .frame(width: 28, alignment: .leading)
                            if let q = day.quadrant {
                                QuadrantDot(quadrant: q)
                                Text(day.moodWord ?? q.shortName)
                                    .font(.system(size: 11))
                                Spacer()
                                Text("E\(day.energy ?? 0) · P\(day.mood ?? 0)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(DL.muted)
                            } else {
                                Text(day.isOff ? "Day off" : "No check-in")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(DL.muted)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(12)
                .frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            }

            streaksRow(week.streaks)
            insightSection(problemPeriod: InsightPeriod.week(containing: monday), existing: insight)
        }
    }

    private func weekTable(_ week: WeekSummary, targets: DayTargets) -> some View {
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text("")
                        .frame(width: 108, alignment: .leading)
                    ForEach(week.days) { day in
                        VStack(spacing: 1) {
                            Text(Fmt.weekdayShort.string(from: day.date))
                                .font(.system(size: 11, weight: .semibold))
                            Text(Fmt.dayMonth.string(from: day.date))
                                .font(.system(size: 9.5))
                                .foregroundStyle(DL.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)

                tableRow("Meetings", week.days, width: 108) { day in
                    day.meetingHours > 0 ? String(format: "%.1f h", day.meetingHours) : "—"
                }
                tableRow("Breaks", week.days, width: 108) { day in "\(day.breaksTaken)" }
                tableRow("Standing", week.days, width: 108) { day in Fmt.compactDuration(day.movedMinutes) }
                tableRow("Lunch", week.days, width: 108) { day in day.lunchMinutes > 0 ? "\(day.lunchMinutes)m" : "—" }
                tableRow("Longest seated", week.days, width: 108) { day in Fmt.compactDuration(day.longestSeatedMinutes) }
                tableRow("Stress", week.days, width: 108) { day in day.stressAverage.map(String.init) ?? "—" }
                GridRow {
                    Text("Goals")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                        .frame(width: 108, alignment: .leading)
                        .padding(.vertical, 5)
                    ForEach(week.days) { day in
                        GoalDots(metrics: day)
                            .frame(maxWidth: .infinity)
                    }
                }
                GridRow {
                    Text("Mood")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                        .frame(width: 108, alignment: .leading)
                        .padding(.vertical, 5)
                    ForEach(week.days) { day in
                        HStack(spacing: 4) {
                            if let q = day.quadrant {
                                QuadrantDot(quadrant: q)
                                Text(day.moodWord ?? "")
                                    .font(.system(size: 10.5))
                            } else {
                                Text("—").font(.system(size: 10.5)).foregroundStyle(DL.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func tableRow(_ label: String, _ days: [DayMetrics], width: CGFloat,
                          value: @escaping (DayMetrics) -> String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(DL.muted)
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 3)
            ForEach(days) { day in
                Text(value(day))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(day.hasData ? DL.ink : DL.muted.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func streaksRow(_ streaks: [Streak]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "Streaks")
            HStack(spacing: 8) {
                ForEach(streaks) { streak in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: streak.goal.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(streak.current > 0 ? DL.calm : DL.muted)
                            Text("\(streak.current)")
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(streak.current > 0 ? DL.ink : DL.muted)
                            Text(streak.current == 1 ? "day" : "days")
                                .font(.system(size: 10))
                                .foregroundStyle(DL.muted)
                        }
                        Text(streak.goal.shortTitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DL.muted)
                        HStack(spacing: 3) {
                            ForEach(Array(streak.recent.enumerated()), id: \.offset) { _, hit in
                                Circle()
                                    .fill(hit ? DL.calm : DL.line)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Year

    private var yearView: some View {
        let heatmap = Summarizer.heatmap(state: model.state, endingAt: model.now)
        let selected = heatmap.allCells.first { $0.dayKey == ui.selectedCellKey }
            ?? heatmap.allCells.last { $0.hasData }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last 12 months")
                        .font(.system(size: 20, weight: .semibold))
                    Text("\(heatmap.dataCells.count) workdays · \(Fmt.dayMonthYear.string(from: heatmap.start)) to \(Fmt.dayMonthYear.string(from: heatmap.end))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                }
                Spacer()
                SegmentedPicker(options: HeatmapMetric.allCases.map { ($0, $0.shortTitle) },
                                selection: $ui.heatMetric)
                    .frame(width: 390)
            }

            HStack(alignment: .top, spacing: 12) {
                heatmapGrid(heatmap, targets: heatmap.targets)
                if let cell = selected {
                    cellDetail(cell, metric: ui.heatMetric, targets: heatmap.targets)
                }
            }

            HStack(spacing: 8) {
                ForEach(Array(heatmap.stats(for: ui.heatMetric).enumerated()), id: \.offset) { _, stat in
                    StatCard(value: stat.value, label: stat.label)
                }
            }

            NoticeCard(title: "Pattern",
                       message: heatmap.pattern(for: ui.heatMetric),
                       tint: ui.heatMetric.isWarning ? DL.warn : DL.accent,
                       background: ui.heatMetric.isWarning ? DL.warnSoft : DL.accentSoft)

            HStack(spacing: 6) {
                Text(ui.heatMetric.lowLabel).font(.system(size: 9.5)).foregroundStyle(DL.muted)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(level: level, metric: ui.heatMetric, quadrant: nil))
                        .frame(width: 12, height: 12)
                }
                Text(ui.heatMetric.highLabel).font(.system(size: 9.5)).foregroundStyle(DL.muted)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(DL.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 12, height: 12)
                Text("day off").font(.system(size: 9.5)).foregroundStyle(DL.muted)
            }

            let period = InsightPeriod.lastDays(365, endingAt: model.now)
            insightSection(problemPeriod: period, existing: model.latestInsight(period: period))
        }
    }

    private func heatmapGrid(_ heatmap: Heatmap, targets: DayTargets) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 8.5))
                        .foregroundStyle(DL.muted)
                        .frame(height: 12)
                }
            }
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .bottomLeading) {
                    Color.clear.frame(height: 12)
                    ForEach(heatmap.months) { month in
                        Text(month.label)
                            .font(.system(size: 8.5))
                            .foregroundStyle(DL.muted)
                            .fixedSize()
                            .offset(x: CGFloat(month.index) * 13)
                    }
                }
                .frame(height: 12, alignment: .bottomLeading)

                HStack(alignment: .top, spacing: 2) {
                    ForEach(heatmap.weeks) { week in
                        VStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { index in
                                cellView(week.cells[index], metric: ui.heatMetric, targets: targets)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func cellView(_ cell: HeatmapCell?, metric: HeatmapMetric, targets: DayTargets) -> some View {
        let selected = cell?.dayKey == ui.selectedCellKey
        return Button {
            if let cell { ui.selectedCellKey = cell.dayKey }
        } label: {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(cell.map { cellFill($0, metric: metric, targets: targets) } ?? Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(strokeColor(cell, selected: selected),
                                      style: StrokeStyle(lineWidth: selected ? 1.6 : 0.8,
                                                         dash: cell?.isOff == true ? [2, 1.5] : []))
                )
                .frame(width: 11, height: 11)
        }
        .buttonStyle(.plain)
        .help(cell.map { "\(Fmt.dayMonth.string(from: $0.date)) · \(metric.formatted($0))" } ?? "No data")
    }

    private func cellFill(_ cell: HeatmapCell, metric: HeatmapMetric, targets: DayTargets) -> Color {
        guard cell.hasData, !cell.isOff else { return DL.line.opacity(0.25) }
        if metric == .mood {
            guard cell.quadrant != nil else { return DL.line.opacity(0.25) }
            return MoodGrid.color(energy: cell.energy ?? 2, mood: cell.mood ?? 2)
        }
        guard let level = metric.level(cell, targets: targets) else {
            return DL.line.opacity(0.25)
        }
        return cellColor(level: level, metric: metric, quadrant: cell.quadrant)
    }

    private func cellColor(level: Int, metric: HeatmapMetric, quadrant: MoodQuadrant?) -> Color {
        if metric == .mood {
            return quadrant.map { DL.quadrant($0).opacity(0.35 + Double(level) * 0.15) } ?? DL.line.opacity(0.25)
        }
        let base = metric.isWarning ? DL.crit : DL.accent
        if level <= 0 { return DL.line.opacity(0.5) }
        return base.opacity(0.12 + Double(level) * 0.2)
    }

    private func strokeColor(_ cell: HeatmapCell?, selected: Bool) -> Color {
        if selected { return DL.ink }
        if cell == nil { return .clear }
        return DL.line.opacity(0.5)
    }

    private func cellDetail(_ cell: HeatmapCell, metric: HeatmapMetric, targets: DayTargets) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(Fmt.weekdayShort.string(from: cell.date)) \(Fmt.dayMonth.string(from: cell.date))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let q = cell.quadrant { QuadrantDot(quadrant: q) }
            }
            Text(metric.formatted(cell))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(metric.isWarning ? DL.crit : DL.accent)
            Divider().overlay(DL.line)
            detailRow("Mood", cell.moodWord.map { "\($0) · \(cell.quadrant?.name ?? "")" } ?? "No check-in")
            detailRow("Goals", "\(cell.goals) of 5")
            detailRow("Standing", "\(cell.standingMinutes) min")
            detailRow("Breaks", "\(cell.breaks)")
            detailRow("Meetings", String(format: "%.1f h", Double(cell.meetingMinutes) / 60))
            detailRow("Stress", cell.stress.map(String.init) ?? "—")
            detailRow("Energy", cell.energy.map { "\($0) of 4" } ?? "—")
            Spacer(minLength: 0)
            Button("Open day") { ui.dayKey = cell.dayKey; model.summaryTab = .day }
                .buttonStyle(LinkButtonStyle())
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10.5)).foregroundStyle(DL.muted)
            Spacer()
            Text(value).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
        }
    }

    // MARK: - Insights

    private func insightSection(problemPeriod: InsightPeriod, existing: Insight?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "AI insights")
                Spacer()
                Text("\(model.settings.ai.provider.shortTitle) · \(model.settings.ai.effectiveModel)")
                    .font(.system(size: 10))
                    .foregroundStyle(DL.muted)
            }
            // An answer to a typed question covers its own range, so it is shown
            // wherever insights are, not only in the period it happens to start in.
            if let answer = model.latestQuestionInsight, answer.id != existing?.id {
                insightCard(answer)
            }
            if let insight = existing {
                insightCard(insight)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(DL.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No insight for this period yet")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Find patterns across breaks, calendar load, Garmin data and journal text. Only daily aggregates and the text you allow leave the Mac.")
                            .font(.system(size: 11))
                            .foregroundStyle(DL.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(model.aiBusy ? "Thinking…" : "Generate insight") {
                            model.runInsights(period: problemPeriod)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.aiBusy)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            }
            if let error = model.aiError {
                Text(error).font(.system(size: 11)).foregroundStyle(DL.crit)
            }
            insightComposer
        }
    }

    private var insightComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow(text: "Ask your own question")
                Spacer()
                SegmentedPicker(options: InsightRange.allCases.map { ($0, $0.rawValue) },
                                selection: $ui.insightRange)
                    .frame(width: 340)
            }
            HStack(spacing: 8) {
                TextField("What has been draining me lately?", text: $ui.question)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                Button(model.aiBusy ? "Thinking…" : "Ask") {
                    let period: InsightPeriod
                    switch ui.insightRange {
                    case .week: period = .week(containing: model.now)
                    case .last7: period = .lastDays(7, endingAt: model.now)
                    case .last30: period = .lastDays(30, endingAt: model.now)
                    }
                    model.runInsights(period: period, question: ui.question)
                    // Keep the text if the request did not start (no key, for example).
                    if model.aiBusy { ui.question = "" }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.aiBusy)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func insightCard(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Chip(text: insight.periodLabel, style: .accent, symbol: "sparkles")
                Chip(text: insight.provider, style: .plain)
                Spacer()
                Text("\(insight.observations.count) observations · \(insight.basedOnDays.count) days")
                    .font(.system(size: 10))
                    .foregroundStyle(DL.muted)
            }
            if let question = insight.question {
                Text(question)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DL.calm)
            }
            ForEach(Array(insight.observations.enumerated()), id: \.offset) { index, observation in
                HStack(alignment: .top, spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(DL.accentInk)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(DL.accent))
                    Text(observation)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !insight.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Try")
                    ForEach(insight.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(DL.calm)
                            Text(suggestion).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.accentBorder, lineWidth: 1))
    }
}
