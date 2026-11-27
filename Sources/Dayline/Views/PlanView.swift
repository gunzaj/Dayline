import AppKit
import DaylineCore
import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var model: AppModel

    private var dayKey: String { DayKey.make(model.now) }
    private var plan: DayPlan? { model.todayPlan }
    private var day: WorkDay? { model.today }
    private var metrics: DayMetrics { model.todayMetrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let plan {
                    morningStats(plan)
                    intensityLine(plan)
                    timelineSection(plan)
                    protectionCards(plan)
                    standingSection(plan)
                } else {
                    EmptyStateView(symbol: "calendar.badge.clock", title: "No work hours today",
                                   message: "The schedule is off for this weekday. Turn it on in Settings → Schedule, or mark today back on from the menu bar.")
                }
                footer
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(DL.window)
        .onAppear { model.evaluate(forceTick: true) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: "Today's plan")
                Text("\(Fmt.weekdayLong.string(from: model.now)), \(Fmt.dayMonth.string(from: model.now))")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(DL.ink)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                if day?.start == nil {
                    Button("Start day") { model.startDay() }
                        .buttonStyle(PrimaryButtonStyle())
                } else if day?.end == nil {
                    Button("End day") { model.endDay() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Refresh") { model.refreshCalendar(force: true) }
                    .buttonStyle(LinkButtonStyle())
            }
        }
    }

    private var subtitle: String {
        guard let plan else { return "No plan for today." }
        let free = plan.freeGaps.reduce(0) { $0 + $1.minutes }
        return "\(String(format: "%.1f", plan.meetingHours)) h of calls · \(free / 60) h \(free % 60) min free · \(plan.freeGaps.count) gaps"
    }

    private func morningStats(_ plan: DayPlan) -> some View {
        let daily = model.state.dailyHealth(dayKey)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            StatCard(value: daily?.sleepMinutes.map { Fmt.compactDuration($0) } ?? "—",
                     label: "sleep" + (daily?.sleepScore.map { " · score \($0)" } ?? ""))
            StatCard(value: daily?.hrvStatus ?? "—", label: "overnight HRV", mono: false)
            StatCard(value: model.health.bodyBatteryWake.map(String.init) ?? "—", label: "Body Battery at wake", tint: DL.calm)
            StatCard(value: String(format: "%.1f h", plan.meetingHours), label: "meetings today")
        }
    }

    private func intensityLine(_ plan: DayPlan) -> some View {
        let sleep = model.state.dailyHealth(dayKey)?.sleepScore
        let battery = model.health.bodyBatteryWake
        let stress = model.health.stress
        var label = "Normal intensity day"
        var detail = "Breaks follow the usual interval."
        var style: ChipStyle = .accent
        // Same thresholds the break engine uses.
        if let sleep, model.settings.garmin.useSleepAndHRV, sleep < 65 {
            label = "Lighter day"
            detail = "Sleep was short, so the first movement break is lighter and breathing comes earlier."
            style = .warn
        } else if let battery, battery < model.settings.garmin.batteryLow {
            label = "Low battery"
            detail = "Body Battery started low. Walking and mat work get priority over squats."
            style = .warn
        } else if let stress, stress >= model.settings.garmin.stressHigh {
            label = "Stress is up"
            detail = "Box breathing is offered before movement breaks."
            style = .calm
        }
        return HStack(spacing: 8) {
            Chip(text: label, style: style)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(DL.muted)
            Spacer()
        }
    }

    private func timelineSection(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "The day")
                Spacer()
                HStack(spacing: 10) {
                    legend(DL.muted, "meeting")
                    legend(DL.accent, "break")
                    legend(DL.warnFill, "lunch")
                    legend(DL.faint, "wind-down")
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(plan.timeline.enumerated()), id: \.element.id) { index, item in
                    let current = item.start <= model.now && item.end > model.now
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.time.string(from: item.start))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text(Fmt.time.string(from: item.end))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DL.muted.opacity(0.7))
                        }
                        .frame(width: 42, alignment: .trailing)

                        VStack(spacing: 0) {
                            Circle()
                                .fill(color(item.kind))
                                .frame(width: current ? 10 : 7, height: current ? 10 : 7)
                                .overlay(Circle().stroke(DL.panel, lineWidth: 2))
                            if index < plan.timeline.count - 1 {
                                Rectangle().fill(DL.line).frame(width: 1.5)
                                    .frame(minHeight: 22)
                            }
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: current ? .semibold : .regular))
                                    .foregroundStyle(current ? DL.ink : DL.ink.opacity(0.92))
                                if current {
                                    Chip(text: "Now", style: .accent)
                                }
                                Spacer()
                                if !item.chip.isEmpty {
                                    Chip(text: item.chip, style: chipStyle(item.chipStyle))
                                }
                            }
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(DL.muted)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
        }
    }

    private func protectionCards(_ plan: DayPlan) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Lunch")
                if let lunch = plan.lunchGap {
                    Text("Protected · \(lunch.minutes >= 60 ? "\(lunch.minutes / 60) h" : "\(lunch.minutes) min") free")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Around \(Fmt.time.string(from: max(lunch.start, model.settings.lunchWindowStart.date(on: model.now)))). The engine will not book a break over it.")
                        .font(.system(size: 12))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No protected gap")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DL.warn)
                    Text("The calendar has no \(model.settings.lunchTargetMinutes)-minute gap between \(model.settings.lunchWindowStart.display) and \(model.settings.lunchWindowEnd.display). The engine still offers lunch when a gap opens.")
                        .font(.system(size: 12))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Chip(text: metrics.lunchMinutes >= model.settings.lunchTargetMinutes ? "Taken" : "Not yet",
                         style: metrics.lunchMinutes >= model.settings.lunchTargetMinutes ? .calm : .plain)
                    if metrics.lunchMinutes > 0 {
                        Text("\(metrics.lunchMinutes) min").font(.system(size: 10.5)).foregroundStyle(DL.muted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Long blocks")
                Text(longBlockText(plan))
                    .font(.system(size: 14, weight: .semibold))
                Text("A meeting of \(model.settings.longMeetingMinutes)+ min or \(model.settings.backToBackMinutes)+ min back-to-back asks for a break in the next gap.")
                    .font(.system(size: 11))
                    .foregroundStyle(DL.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let run = plan.events.isEmpty ? nil : plan.longestBackToBackMinutes, run > 0 {
                    Chip(text: "Longest run \(Fmt.compactDuration(run))", style: run >= model.settings.backToBackMinutes ? .warn : .plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
        }
    }

    private func longBlockText(_ plan: DayPlan) -> String {
        if plan.longestBackToBackMinutes >= model.settings.backToBackMinutes {
            return "Back-to-back · \(Fmt.compactDuration(plan.longestBackToBackMinutes))"
        }
        if plan.longestMeetingMinutes >= model.settings.longMeetingMinutes {
            return "Long meeting · \(plan.longestMeetingMinutes) min"
        }
        return "No long block today"
    }

    private func standingSection(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Standing calls")
                Spacer()
                Button("Edit rules") { model.openSettings(tab: .calendar) }
                    .buttonStyle(LinkButtonStyle())
            }
            if plan.standingSuggestions.isEmpty {
                Text("No calls match your standing rules today.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DL.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(plan.standingSuggestions) { suggestion in
                        HStack(spacing: 8) {
                            Text(Fmt.time.string(from: suggestion.event.start))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(DL.muted)
                                .frame(width: 40, alignment: .leading)
                            Text(suggestion.event.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Text(suggestion.rule.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(DL.muted)
                            Chip(text: suggestion.target.title, style: .accent)
                        }
                        .padding(.vertical, 5)
                        if suggestion.id != plan.standingSuggestions.last?.id {
                            Rectangle().fill(DL.line.opacity(0.6)).frame(height: 1)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Journal") { model.openJournal() }.buttonStyle(LinkButtonStyle())
            Button("Summaries") { model.openSummaries(tab: .day) }.buttonStyle(LinkButtonStyle())
            Button("Settings") { model.openSettings(tab: .schedule) }.buttonStyle(LinkButtonStyle())
            Spacer()
            if let toast = model.toast {
                Text(toast).font(.system(size: 10.5)).foregroundStyle(DL.muted)
            }
        }
        .padding(.top, 4)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9.5)).foregroundStyle(DL.muted)
        }
    }

    private func color(_ kind: PlanItemKind) -> Color {
        switch kind {
        case .meeting: return DL.muted
        case .breakOpportunity: return DL.accent
        case .lunch: return DL.warnFill
        case .standingSuggestion: return DL.accent
        case .windDown: return DL.faint
        }
    }

    private func chipStyle(_ value: String) -> ChipStyle {
        switch value {
        case "warn": return .warn
        case "calm": return .calm
        case "accent": return .accent
        default: return .plain
        }
    }
}
