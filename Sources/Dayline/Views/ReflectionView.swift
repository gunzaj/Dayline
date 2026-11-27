import AppKit
import DaylineCore
import SwiftUI

@MainActor
final class ReflectionUI: ObservableObject {
    @Published var selection: MoodSelection?
    @Published var prompts: [String] = []
    @Published var answers: [String] = []
    @Published var addToJournal = true
    @Published var saved = false
    /// The day the fields above belong to.
    var dayKey: String?
}

struct ReflectionView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = ReflectionUI()

    private var dayKey: String { model.reflectionDayKey }
    private var date: Date { DayKey.date(from: dayKey) ?? model.now }
    private var metrics: DayMetrics { Summarizer.metrics(dayKey: dayKey, state: model.state) }
    private var day: WorkDay? { model.state.day(dayKey) }
    private var entries: [JournalEntry] { model.state.journal(on: dayKey) }
    private var breaks: [BreakEvent] { model.state.breaks(on: dayKey) }
    private var targets: DayTargets { day?.targets ?? model.settings.targets }

    private var canSave: Bool {
        guard let selection = ui.selection, !selection.word.isEmpty else { return false }
        // With no prompts configured, the mood alone is a complete reflection.
        if ui.prompts.isEmpty { return true }
        return ui.answers.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if metrics.isOff {
                        NoticeCard(title: "Day off", message: "This day is marked off. A reflection still saves, and streaks stay paused.", tint: DL.calm, background: DL.calmSoft)
                    }
                    summaryGrid
                    chartsRow
                    goalsAndBreaks
                    moodCard
                    promptsCard
                    if !entries.filter({ $0.kind == .reflection }).isEmpty {
                        Text("A reflection already exists for this day. Saving adds another entry.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DL.muted)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            Divider().overlay(DL.line)
            footer
        }
        .background(DL.window)
        .onAppear { loadDayIfChanged() }
        .onChange(of: model.reflectionDayKey) { _, _ in loadDayIfChanged() }
    }

    /// The window is reused, so answers typed for one day must not carry over
    /// when it is pointed at another.
    private func loadDayIfChanged() {
        guard ui.dayKey != dayKey else { return }
        ui.dayKey = dayKey
        ui.selection = nil
        ui.saved = false
        ui.prompts = model.reflectionPrompts(dayKey: dayKey)
        ui.answers = Array(repeating: "", count: ui.prompts.count)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: dayKey == DayKey.make(model.now) ? "End of day" : "Wrap up")
                Text("\(Fmt.weekdayLong.string(from: date)), \(Fmt.dayMonthYear.string(from: date))")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.4)
                Text(dayKey == DayKey.make(model.now)
                     ? "Still at the desk. Two minutes to close the loop."
                     : "The day is over. What stayed with you?")
                    .font(.system(size: 14))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            CloseButton { close() }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            StatCard(value: Fmt.compactDuration(metrics.movedMinutes), label: "standing / walking · target \(Fmt.compactDuration(targets.standingMinutes))")
            StatCard(value: "\(metrics.breaksTaken)", label: "breaks · \(metrics.breaksSkipped) skipped · \(metrics.snoozes) snoozed")
            StatCard(value: "\(metrics.lunchMinutes) min", label: metrics.lunchMinutes >= targets.lunchMinutes ? "lunch away · protected" : "lunch · under target")
            StatCard(value: Fmt.compactDuration(metrics.longestSeatedMinutes), label: "longest seated stretch")
            StatCard(value: String(format: "%.1f h", metrics.meetingHours), label: "meetings · longest run \(Fmt.compactDuration(metrics.longestBackToBackMinutes))")
            StatCard(value: "\(metrics.goalsHit)/5", label: "daily goals hit")
        }
    }

    private var chartsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Eyebrow(text: "Stress and Body Battery")
                    Spacer()
                    if let stress = metrics.stressAverage {
                        Chip(text: "stress avg \(stress)", style: stress >= model.settings.garmin.stressHigh ? .warn : .plain)
                    }
                    if let end = metrics.bodyBatteryEnd {
                        Chip(text: "battery \(end)", style: .calm)
                    }
                }
                DayCurveChart(samples: model.state.healthSamples.filter { DayKey.make($0.at) == dayKey },
                              breaks: breaks,
                              start: day?.start ?? (DayKey.date(from: dayKey) ?? model.now).adding(minutes: 9 * 60),
                              end: day?.end ?? (DayKey.date(from: dayKey) ?? model.now).adding(minutes: 17 * 60 + 30))
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: "Goals")
                GoalRows(metrics: metrics, targets: targets)
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
        }
    }

    private var goalsAndBreaks: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Breaks")
                if breaks.isEmpty {
                    Text("No breaks recorded.").font(.system(size: 11)).foregroundStyle(DL.muted)
                } else {
                    ForEach(breaks.filter { $0.outcome != .planned }) { brk in
                        HStack(spacing: 7) {
                            Image(systemName: brk.outcome == .done ? "checkmark" : (brk.outcome == .skipped ? "arrow.right" : "zzz"))
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(brk.outcome == .done ? DL.calm : DL.muted)
                            Text(Fmt.time.string(from: brk.startedAt ?? brk.plannedAt))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DL.muted)
                            Text("\(brk.displayTitle) · \(brk.minutes) min")
                                .font(.system(size: 11))
                            Spacer()
                            if let reason = brk.skipReason {
                                Chip(text: reason.rawValue, style: .warn)
                            }
                            if brk.outcome == .snoozed {
                                Chip(text: "Snoozed", style: .plain)
                            }
                        }
                    }
                }
                if let reason = mostCommonSkip {
                    Text("Most common skip reason: \(reason).")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Meetings")
                if let events = model.state.planEvents(for: dayKey), !events.isEmpty {
                    ForEach(events.filter(\.blocksTime)) { event in
                        HStack(spacing: 7) {
                            Text(Fmt.time.string(from: event.start))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DL.muted)
                            Text(event.title)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Text("\(event.minutes)m")
                                .font(.system(size: 10))
                                .foregroundStyle(DL.muted)
                        }
                    }
                } else {
                    Text("No calendar snapshots for this day.").font(.system(size: 11)).foregroundStyle(DL.muted)
                }
            }
            .padding(11)
            .frame(width: 300, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
        }
    }

    private var mostCommonSkip: String? {
        let reasons = breaks.compactMap(\.skipReason)
        guard !reasons.isEmpty else { return nil }
        return reasons.max { a, b in
            reasons.filter { $0 == a }.count < reasons.filter { $0 == b }.count
        }?.rawValue
    }

    private var moodCard: some View {
        DlCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Mood and energy")
                    Spacer()
                    Text("No default. Pick a side on both axes.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                }
                MoodGridView(selection: $ui.selection)
            }
        }
    }

    private var promptsCard: some View {
        DlCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Guided prompts")
                    Spacer()
                    Text("Answer what matters. One is enough.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                }
                ForEach(Array(ui.prompts.enumerated()), id: \.offset) { index, prompt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt)
                            .font(.system(size: 12.5, weight: .semibold))
                        TextEditor(text: bindingFor(index))
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 52, maxHeight: 110)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func bindingFor(_ index: Int) -> Binding<String> {
        Binding(
            get: { ui.answers.indices.contains(index) ? ui.answers[index] : "" },
            set: { value in
                while ui.answers.count <= index { ui.answers.append("") }
                ui.answers[index] = value
            }
        )
    }

    private var footer: some View {
        HStack {
            if let selection = ui.selection, !selection.word.isEmpty {
                HStack(spacing: 5) {
                    QuadrantDot(quadrant: selection.quadrant)
                    Text("\(selection.quadrant.name) · \(selection.word)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(DL.warnFill).frame(width: 7, height: 7)
                    Text("Pick a square and a word to save.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DL.warn)
                }
            }
            Spacer()
            Toggle("Add prompts to journal", isOn: $ui.addToJournal)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Button("Later") { close() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Save reflection") {
                guard let selection = ui.selection else { return }
                let promptAnswers = zip(ui.prompts, ui.answers).map { PromptAnswer(prompt: $0.0, answer: $0.1) }
                model.saveReflection(dayKey: dayKey, selection: selection,
                                     answers: promptAnswers, addToJournal: ui.addToJournal)
                ui.saved = true
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(DL.titlebar)
    }

    private func close() {
        NSApp.windows.first { $0.identifier?.rawValue == "dayline.reflection" }?.close()
    }
}

struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DL.muted)
                .padding(6)
                .background(Circle().fill(DL.field))
                .overlay(Circle().strokeBorder(DL.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
