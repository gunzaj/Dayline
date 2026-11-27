import DaylineCore
import SwiftUI

/// Stress and Body Battery across a workday, with breaks marked along the floor.
struct DayCurveChart: View {
    var samples: [HealthSample]
    var breaks: [BreakEvent]
    var start: Date
    var end: Date
    var height: CGFloat = 130
    var showLegend: Bool = true

    private var window: (Date, Date) {
        let fallbackStart = start
        let fallbackEnd = end
        let first = samples.map(\.at).min() ?? fallbackStart
        let last = samples.map(\.at).max() ?? fallbackEnd
        let s = min(first, fallbackStart)
        let e = max(last, fallbackEnd)
        return (s, max(s.adding(minutes: 60), e))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let (s, e) = window
                let span = max(1, e.timeIntervalSince(s))
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack(alignment: .topLeading) {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { level in
                        let y = h - CGFloat(level) / 100 * (h - 16)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(DL.line.opacity(level == 0 ? 1 : 0.5), lineWidth: 1)
                    }

                    if samples.count > 1 {
                        line(value: { $0.stress }, color: DL.crit, s: s, span: span, w: w, h: h)
                        line(value: { $0.bodyBattery }, color: DL.calm, s: s, span: span, w: w, h: h)
                    } else {
                        Text("No Garmin curve for this day")
                            .font(.system(size: 11))
                            .foregroundStyle(DL.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ForEach(breaks) { brk in
                        let x = CGFloat(brk.startedAt?.timeIntervalSince(s) ?? brk.plannedAt.timeIntervalSince(s)) / CGFloat(span) * w
                        if x >= 0 && x <= w {
                            Rectangle()
                                .fill(brk.outcome == .done ? DL.accent.opacity(0.7) : DL.muted.opacity(0.3))
                                .frame(width: 1, height: h - 14)
                                .offset(x: x, y: 0)
                        }
                    }

                    HStack {
                        Text(Fmt.time.string(from: s))
                        Spacer()
                        Text(Fmt.time.string(from: e))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(DL.muted)
                    .offset(y: h - 11)
                }
            }
            .frame(height: height)

            if showLegend {
                HStack(spacing: 12) {
                    legend(color: DL.crit, label: "Stress")
                    legend(color: DL.calm, label: "Body Battery")
                    HStack(spacing: 4) {
                        Rectangle().fill(DL.accent.opacity(0.6)).frame(width: 2, height: 9)
                        Text("breaks").font(.system(size: 9.5)).foregroundStyle(DL.muted)
                    }
                }
            }
        }
    }

    private func line(value: (HealthSample) -> Int?, color: Color, s: Date,
                      span: TimeInterval, w: CGFloat, h: CGFloat) -> some View {
        Path { path in
            var started = false
            for sample in samples {
                guard let level = value(sample) else { continue }
                let x = CGFloat(sample.at.timeIntervalSince(s) / span) * w
                // Same mapping as the gridlines above, so 50 sits on the 50 line.
                let y = h - CGFloat(level) / 100 * (h - 16)
                if started {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9.5)).foregroundStyle(DL.muted)
        }
    }
}

/// Standing minutes per workday with the target line, for the weekly summary.
struct WeekBars: View {
    var days: [DayMetrics]
    var target: Int
    var height: CGFloat = 110

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(target, days.map(\.movedMinutes).max() ?? target, 1)
            let barWidth = (proxy.size.width - CGFloat(max(1, days.count - 1)) * 8) / CGFloat(max(1, days.count))
            let h = proxy.size.height - 22
            ZStack(alignment: .bottomLeading) {
                let targetY = h - CGFloat(target) / CGFloat(maxValue) * h
                Path { p in
                    p.move(to: CGPoint(x: 0, y: targetY))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: targetY))
                }
                .stroke(DL.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days) { day in
                        VStack(spacing: 3) {
                            Text("\(day.movedMinutes)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(DL.muted)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day.movedMinutes >= target ? DL.calm : DL.accent.opacity(0.55))
                                .frame(width: barWidth * 0.62, height: max(2, CGFloat(day.movedMinutes) / CGFloat(maxValue) * h))
                                .frame(maxWidth: .infinity)
                            Text(Fmt.weekdayShort.string(from: day.date))
                                .font(.system(size: 9.5))
                                .foregroundStyle(DL.muted)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Four goals at a glance.
struct GoalDots: View {
    var metrics: DayMetrics

    var body: some View {
        HStack(spacing: 4) {
            ForEach(metrics.goals) { goal in
                Circle()
                    .fill(goal.hit ? DL.calm : DL.line)
                    .frame(width: 7, height: 7)
                    .help("\(goal.goal.title): \(goal.hit ? "hit" : "missed")")
            }
        }
    }
}

/// Small horizontal goal progress list.
struct GoalRows: View {
    var metrics: DayMetrics
    var targets: DayTargets
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            ForEach(metrics.goals) { goal in
                HStack(spacing: 7) {
                    Image(systemName: goal.hit ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(goal.hit ? DL.calm : DL.muted.opacity(0.6))
                    Text(goal.goal.shortTitle)
                        .font(.system(size: compact ? 10.5 : 11.5))
                        .foregroundStyle(DL.ink)
                    Spacer()
                    Text(goal.goal.targetLabel(targets))
                        .font(.system(size: 10))
                        .foregroundStyle(DL.muted)
                    Meter(progress: goal.progress, tint: goal.hit ? DL.calm : DL.accent, height: 4)
                        .frame(width: compact ? 42 : 64)
                }
            }
        }
    }
}
