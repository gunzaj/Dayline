import AppKit
import DaylineCore
import SwiftUI

@MainActor
final class JournalUI: ObservableObject {
    @Published var selectedDay: String = DayKey.make(Date())
    @Published var draft = ""
    @Published var tags = ""
    @Published var search = ""
    @Published var justSaved = false
}

struct JournalView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = JournalUI()

    private var allDays: [String] {
        let journalDays = model.state.journal.map { DayKey.make($0.at) }
        let checkInDays = model.state.checkIns.map { DayKey.make($0.at) }
        return Array(Set(journalDays + checkInDays)).sorted(by: >)
    }

    private var dayEntries: [JournalEntry] {
        model.state.journal(on: ui.selectedDay).reversed()
    }

    private var dayCheckIns: [CheckIn] {
        model.state.checkIns(on: ui.selectedDay)
    }

    private var searchResults: [JournalEntry] {
        guard !ui.search.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let needle = ui.search.lowercased()
        return model.state.journal
            .filter { $0.text.lowercased().contains(needle) || $0.tags.joined(separator: " ").lowercased().contains(needle) || $0.promptAnswers.contains { $0.answer.lowercased().contains(needle) } }
            .sorted { $0.at > $1.at }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DL.line)
            if !ui.search.trimmingCharacters(in: .whitespaces).isEmpty {
                searchList
            } else {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 220)
                    Divider().overlay(DL.line)
                    detail
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(DL.window)
        .onAppear {
            ui.selectedDay = DayKey.make(model.now)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Journal")
                Text("How the work felt")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(DL.ink)
                Text("Entries keep the day's context: meetings, stress, Body Battery, breaks.")
                    .font(.system(size: 14))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DL.muted)
                TextField("Search", text: $ui.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 130)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            if !model.state.settings.lastExportFolder.isEmpty {
                Text(model.state.settings.lastExportFolder.split(separator: "/").last.map(String.init) ?? "Exported")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
            }
            Button("Export") { model.exportJournal() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DL.titlebar)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                Button("New entry") {
                    ui.selectedDay = DayKey.make(model.now)
                }
                .buttonStyle(LinkButtonStyle())
                .padding(.bottom, 4)
                ForEach(allDays, id: \.self) { dayKey in
                    let date = DayKey.date(from: dayKey) ?? model.now
                    let entries = model.state.journal(on: dayKey)
                    let metrics = Summarizer.metrics(dayKey: dayKey, state: model.state)
                    Button {
                        ui.selectedDay = dayKey
                    } label: {
                        HStack(spacing: 7) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Fmt.dayMonth.string(from: date))
                                    .font(.system(size: 12, weight: ui.selectedDay == dayKey ? .semibold : .regular))
                                    .foregroundStyle(DL.ink)
                                Text("\(Fmt.weekdayShort.string(from: date)) · \(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(DL.muted)
                            }
                            Spacer()
                            if let q = metrics.quadrant {
                                QuadrantDot(quadrant: q)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ui.selectedDay == dayKey ? DL.accentSoft : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(ui.selectedDay == dayKey ? DL.accentBorder : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if allDays.isEmpty {
                    Text("No entries yet. The hotkey ⌥⌘J opens this window from anywhere.")
                        .font(.system(size: 11))
                        .foregroundStyle(DL.muted)
                        .padding(.top, 12)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DL.sidebar)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dayHeader
                if ui.selectedDay == DayKey.make(model.now) {
                    composer
                }
                if dayEntries.isEmpty && dayCheckIns.isEmpty {
                    EmptyStateView(symbol: "book.closed", title: "Nothing here yet",
                                   message: "Add a free entry, or wait for the end-of-day reflection to land.")
                } else {
                    ForEach(Array(dayCheckIns.enumerated()), id: \.element.id) { _, checkIn in
                        checkInCard(checkIn)
                    }
                    ForEach(dayEntries) { entry in
                        entryCard(entry)
                    }
                }
            }
            .padding(18)
        }
    }

    private var dayHeader: some View {
        let date = DayKey.date(from: ui.selectedDay) ?? model.now
        let metrics = Summarizer.metrics(dayKey: ui.selectedDay, state: model.state)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.weekdayLong.string(from: date))
                    .font(.system(size: 18, weight: .semibold))
                Text(Fmt.dayMonthYear.string(from: date))
                    .font(.system(size: 13))
                    .foregroundStyle(DL.muted)
                Spacer()
                if metrics.isOff {
                    Chip(text: "Day off", style: .calm)
                } else if metrics.hasReflection {
                    Chip(text: "Reflected", style: .calm, symbol: "checkmark")
                }
            }
            HStack(spacing: 6) {
                Chip(text: "\(metrics.breaksTaken) breaks", style: .plain)
                Chip(text: "\(Fmt.compactDuration(metrics.movedMinutes)) moving", style: .plain)
                Chip(text: "\(String(format: "%.1f", metrics.meetingHours)) h calls", style: .plain)
                if let stress = metrics.stressAverage { Chip(text: "stress \(stress)", style: .plain) }
                if let word = metrics.moodWord { Chip(text: word, style: .plain) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: ui.justSaved ? "Saved" : "New entry")
                Spacer()
                Text("\(ui.draft.split(separator: " ").count) words")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
            }
            TextEditor(text: $ui.draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 90, maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            HStack {
                TextField("Tags, comma separated", text: $ui.tags)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .frame(width: 200)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                Spacer()
                Button("Discard") {
                    ui.draft = ""
                    ui.tags = ""
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(ui.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Save entry") {
                    let tagList = ui.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    model.addJournalEntry(text: ui.draft, tags: tagList, at: model.now)
                    ui.draft = ""
                    ui.tags = ""
                    ui.justSaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ui.justSaved = false }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(ui.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .daylineCard()
    }

    private func entryCard(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind == .reflection ? "moon.stars" : "pencil.line")
                    .font(.system(size: 10))
                    .foregroundStyle(DL.muted)
                Text(entry.kind == .reflection ? "Reflection" : "Note")
                    .font(.system(size: 11, weight: .semibold))
                Text(Fmt.time.string(from: entry.at))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(DL.muted)
                Spacer()
                if !entry.tags.isEmpty {
                    ForEach(entry.tags, id: \.self) { tag in
                        Chip(text: tag, style: .plain)
                    }
                }
                Button {
                    model.confirmDeleteJournalEntry(id: entry.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 9.5))
                }
                .accessibilityLabel("Delete entry")
                .help("Delete entry")
                .buttonStyle(.plain)
                .foregroundStyle(DL.muted)
                .help("Delete entry")
            }
            if entry.promptAnswers.isEmpty {
                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entry.promptAnswers) { answer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(answer.prompt)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DL.muted)
                        Text(answer.answer)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DL.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 9)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DL.lineStrong).frame(width: 2)
                    }
                }
            }
            contextLine(entry.context)
        }
        .padding(14)
        .daylineCard()
    }

    private func checkInCard(_ checkIn: CheckIn) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DL.quadrantSoft(checkIn.quadrant))
                    .frame(width: 34, height: 34)
                Text(String(checkIn.word.prefix(1)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DL.quadrant(checkIn.quadrant))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(checkIn.word) · \(checkIn.quadrant.name)")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Fmt.time.string(from: checkIn.at)) · energy \(checkIn.energy) of 4, pleasantness \(checkIn.mood) of 4")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
                if !checkIn.note.isEmpty {
                    Text(checkIn.note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.ink)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.quadrantSoft(checkIn.quadrant).opacity(0.6)))
    }

    private func contextLine(_ context: EntryContext) -> some View {
        var parts: [String] = []
        if let stress = context.stress { parts.append("stress \(stress)") }
        if let battery = context.bodyBattery { parts.append("battery \(battery)") }
        parts.append("\(context.breaksToday) breaks")
        parts.append("\(context.standingMinutes) min moving")
        if context.meetingHours > 0 { parts.append(String(format: "%.1f h calls", context.meetingHours)) }
        if let last = context.lastMeetingTitle { parts.append("after \(last)") }
        return HStack(spacing: 5) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 8.5))
            Text(parts.joined(separator: " · "))
                .font(.system(size: 10))
                .lineLimit(2)
        }
        .foregroundStyle(DL.muted)
    }

    private var searchList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s") for “\(ui.search)”")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(searchResults) { entry in
                    Button {
                        ui.selectedDay = DayKey.make(entry.at)
                        ui.search = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Fmt.dayMonthYear.string(from: entry.at))
                                .font(.system(size: 10.5))
                                .foregroundStyle(DL.muted)
                            Text(entry.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(DL.ink)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if searchResults.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Try a word you remember writing.")
                }
            }
            .padding(18)
        }
    }
}
