import AppKit
import DaylineCore
import SwiftUI

/// The desktop window: a sidebar over everything Dayline knows, so the menu bar
/// is a shortcut rather than the only way in.
struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Group {
                switch model.mainSection {
                case .overview: OverviewView()
                case .plan: PlanView()
                case .activities: ActivitiesView()
                case .journal: JournalView()
                case .summaries: SummariesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DL.window)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dayline")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DL.muted)
                .padding(.horizontal, 10)
                .padding(.top, 20)
                .padding(.bottom, 8)
            ForEach(MainSection.allCases) { section in
                row(title: section.rawValue, symbol: section.symbol,
                    active: model.mainSection == section) {
                    model.mainSection = section
                }
            }
            Spacer()
            row(title: "Settings", symbol: "gearshape", active: false) {
                model.openSettings(tab: model.settingsTab)
            }
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DL.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DL.line).frame(width: 1)
        }
    }

    private func row(title: String, symbol: String, active: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? DL.accent : DL.muted)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(DL.ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? DL.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? DL.accentBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Overview

/// Where today stands: the next break, the five goals, streaks and the week.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    private var todayKey: String { model.todayKey() }
    private var metrics: DayMetrics { model.todayMetrics }
    private var targets: DayTargets { model.today?.targets ?? model.settings.targets }

    var body: some View {
        let metrics = self.metrics
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(eyebrow: "\(Fmt.weekdayLong.string(from: model.now)), \(Fmt.dayMonth.string(from: model.now))",
                           title: headline,
                           subtitle: model.decision.why.isEmpty ? nil : model.decision.why)
                statusCard
                HStack(spacing: 12) {
                    StatCard(value: Fmt.compactDuration(metrics.movedMinutes),
                             label: "standing / walking · target \(Fmt.compactDuration(targets.standingMinutes))")
                    StatCard(value: "\(metrics.breaksTaken)",
                             label: "breaks · \(metrics.breaksSkipped) skipped")
                    StatCard(value: "\(metrics.lunchMinutes) min", label: "lunch away")
                    StatCard(value: Fmt.compactDuration(metrics.longestSeatedMinutes),
                             label: "longest seated stretch")
                    StatCard(value: String(format: "%.1f h", metrics.meetingHours), label: "meetings")
                }
                HStack(alignment: .top, spacing: 16) {
                    goalsCard(metrics)
                    activitiesCard
                }
                streaksCard
                weekCard
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(DL.window)
    }

    private var headline: String {
        switch model.decision.phase {
        case .dayOff: return "Day off"
        case .notStarted, .beforeHours: return "Not started yet"
        case .ended, .afterHours: return "Day closed"
        case .inBreak: return "In a break"
        case .active: return model.decision.nextBreakLabel
        }
    }

    private var statusCard: some View {
        DlCard {
            HStack(spacing: 10) {
                switch model.decision.phase {
                case .notStarted, .beforeHours:
                    Button("Start day") { model.startDay() }
                        .buttonStyle(PrimaryButtonStyle())
                case .active:
                    Button(model.decision.isDue ? "Start break" : "Start a break now") { model.startBreakNow() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("End day") { model.endDay() }
                        .buttonStyle(SecondaryButtonStyle())
                case .inBreak:
                    Button("Open session") { model.requestWindow?(.session) }
                        .buttonStyle(PrimaryButtonStyle())
                case .ended, .afterHours:
                    if !metrics.hasReflection {
                        Button("Reflect now") { model.openReflection(dayKey: todayKey) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                case .dayOff:
                    Button("Back on today") { model.toggleOffToday() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Check in") { model.requestWindow?(.checkIn) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("New journal entry") { model.openJournal() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                if let pending = model.pendingWrapUpDay {
                    Button("Wrap up \(Fmt.weekdayLong.string(from: DayKey.date(from: pending) ?? model.now))") {
                        model.openReflection(dayKey: pending)
                    }
                    .buttonStyle(LinkButtonStyle())
                }
            }
        }
    }

    private func goalsCard(_ metrics: DayMetrics) -> some View {
        DlCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Today's goals")
                    Spacer()
                    Text("\(metrics.goalsHit) of \(metrics.goalsTotal) hit")
                        .font(.system(size: 11)).foregroundStyle(DL.muted)
                }
                ForEach(metrics.goals) { goal in
                    HStack(spacing: 10) {
                        Image(systemName: goal.hit ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(goal.hit ? DL.calm : DL.muted)
                        Text(goal.goal.title)
                            .font(.system(size: 12.5))
                            .frame(width: 150, alignment: .leading)
                        Meter(progress: goal.progress, tint: goal.hit ? DL.calm : DL.accent)
                        Text(goal.goal.targetLabel(targets))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DL.muted)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(goal.hit ? "Hit" : "\(Int(goal.progress * 100)) percent")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var activitiesCard: some View {
        let items = model.activities(on: todayKey)
        return DlCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Today's activities")
                    Spacer()
                    Button("Edit") {
                        model.activitiesDayKey = todayKey
                        model.mainSection = .activities
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                if items.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.system(size: 11.5)).foregroundStyle(DL.muted)
                } else {
                    ForEach(items.suffix(6)) { item in
                        HStack(spacing: 8) {
                            Text(Fmt.time.string(from: item.startedAt ?? item.plannedAt))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(DL.muted)
                            Image(systemName: item.outcome == .done ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 10.5))
                                .foregroundStyle(item.outcome == .done ? DL.calm : DL.muted)
                            Text(item.displayTitle).font(.system(size: 12))
                            Spacer()
                            Text(item.outcome == .done ? "\(item.minutes) min" : "skipped")
                                .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var streaksCard: some View {
        let streaks = Summarizer.streaks(state: model.state, today: model.now)
        return DlCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Streaks")
                HStack(spacing: 12) {
                    ForEach(streaks) { streak in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(streak.current)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text(streak.current == 1 ? "day" : "days")
                                    .font(.system(size: 11)).foregroundStyle(DL.muted)
                            }
                            Text(streak.goal.shortTitle)
                                .font(.system(size: 11.5)).foregroundStyle(DL.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        let week = Summarizer.week(containing: model.now, state: model.state)
        return DlCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Standing and walking this week")
                    Spacer()
                    Button("Week") { model.openSummaries(tab: .week) }
                        .buttonStyle(LinkButtonStyle())
                    Button("Year") { model.openSummaries(tab: .year) }
                        .buttonStyle(LinkButtonStyle())
                }
                WeekBars(days: week.days, target: targets.standingMinutes)
                    .frame(height: 130)
            }
        }
    }
}
