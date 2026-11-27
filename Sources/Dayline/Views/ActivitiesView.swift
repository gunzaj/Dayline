import AppKit
import DaylineCore
import SwiftUI

/// A day's logged activities, editable: change the time, the exercise, the
/// length or the outcome, remove one, or add one that was never logged.
struct ActivitiesView: View {
    @EnvironmentObject private var model: AppModel

    private var dayKey: String { model.activitiesDayKey }
    private var date: Date { DayKey.date(from: dayKey) ?? model.now }
    private var isToday: Bool { dayKey == model.todayKey() }

    var body: some View {
        let items = model.activities(on: dayKey)
        let metrics = Summarizer.metrics(dayKey: dayKey, state: model.state)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    PageHeader(eyebrow: "Activities",
                               title: "\(Fmt.weekdayLong.string(from: date)), \(Fmt.dayMonthYear.string(from: date))",
                               subtitle: "Fix what was logged wrong, or add what was missed. Totals and goals follow.")
                    dayStepper
                }
                HStack(spacing: 12) {
                    StatCard(value: "\(metrics.breaksTaken)", label: "breaks done")
                    StatCard(value: "\(metrics.standingMinutes) min", label: "standing")
                    StatCard(value: "\(metrics.walkingMinutes) min", label: "walking")
                    StatCard(value: "\(metrics.lunchMinutes) min", label: "lunch away")
                    StatCard(value: "\(metrics.goalsHit)/\(metrics.goalsTotal)", label: "goals hit")
                }
                DlCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Eyebrow(text: "Logged")
                            Spacer()
                            Button {
                                addActivity()
                            } label: {
                                Label("Add activity", systemImage: "plus")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .padding(.bottom, 6)
                        if items.isEmpty {
                            Text("Nothing logged on this day.")
                                .font(.system(size: 12)).foregroundStyle(DL.muted)
                                .padding(.vertical, 8)
                        } else {
                            columnTitles
                            ForEach(items) { item in
                                row(item)
                                Divider().overlay(DL.line)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(DL.window)
    }

    private var dayStepper: some View {
        HStack(spacing: 6) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Previous day")
            Button("Today") { model.activitiesDayKey = model.todayKey() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isToday)
            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 10) {
            Text("Start").frame(width: 56, alignment: .leading)
            Text("Activity").frame(maxWidth: .infinity, alignment: .leading)
            Text("Minutes").frame(width: 62, alignment: .leading)
            Text("Outcome").frame(width: 150, alignment: .leading)
            Color.clear.frame(width: 20, height: 1)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(DL.muted)
        .padding(.bottom, 2)
    }

    private func row(_ item: BreakEvent) -> some View {
        let start = item.startedAt ?? item.plannedAt
        let isRunning = item.id == model.session?.eventID
        return HStack(spacing: 10) {
            TimeField(value: Fmt.time.string(from: start)) { parsed in
                // The field reports its initial text too; only a different time is an edit.
                guard parsed.display != Fmt.time.string(from: start) else { return }
                let moved = parsed.date(on: date)
                model.updateActivity(id: item.id) {
                    $0.plannedAt = moved
                    $0.startedAt = moved
                }
            }
            Menu {
                ForEach(model.loggableExercises) { exercise in
                    Button(exercise.name) {
                        model.setActivityExercise(id: item.id, exerciseID: exercise.id)
                    }
                }
            } label: {
                Text(exerciseName(item))
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Activity")
            minutesField(Binding(
                get: { item.minutes },
                set: { value in model.updateActivity(id: item.id) { $0.minutes = max(0, min(600, value)) } }
            ))
            SegmentedPicker(options: [(BreakOutcome.done, "Done"), (BreakOutcome.skipped, "Skipped")],
                            selection: Binding(
                                get: { item.outcome },
                                set: { value in model.updateActivity(id: item.id) { $0.outcome = value } }
                            ))
                .frame(width: 150)
            Button {
                model.confirmDeleteActivity(id: item.id)
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DL.muted)
            .frame(width: 20)
            .accessibilityLabel("Delete \(item.displayTitle)")
            .help("Delete")
        }
        .padding(.vertical, 5)
        .disabled(isRunning)
        .opacity(isRunning ? 0.5 : 1)
        .help(isRunning ? "This session is still running." : "")
    }

    /// The exercise's own name where it is still known, else what was recorded.
    private func exerciseName(_ item: BreakEvent) -> String {
        if item.kind == .custom { return item.displayTitle }
        return ExerciseLibrary.find(item.exerciseID, settings: model.settings)?.name ?? item.displayTitle
    }

    private func minutesField(_ value: Binding<Int>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12.5, design: .monospaced))
            .frame(width: 62)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            .accessibilityLabel("Minutes")
    }

    private func shiftDay(_ offset: Int) {
        let moved = DayKey.adding(days: offset, to: date)
        guard moved <= DayKey.startOfDay(model.now) else { return }
        model.activitiesDayKey = DayKey.make(moved)
    }

    /// New activities start at the current time today, or at noon on a past day,
    /// and are then edited in place.
    private func addActivity() {
        guard let exercise = model.loggableExercises.first(where: { $0.kind != .lunch })
                ?? model.loggableExercises.first else { return }
        let start = isToday ? model.now : TimeOfDay(hour: 12).date(on: date)
        model.addActivity(dayKey: dayKey, exerciseID: exercise.id, start: start,
                          minutes: exercise.minutesLow)
    }
}
