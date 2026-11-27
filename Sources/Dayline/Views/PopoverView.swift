import AppKit
import DaylineCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if model.today?.isOff == true {
                        offCard
                    } else if let pending = model.pendingConfirmation {
                        confirmationCard(pending)
                    } else if model.session != nil {
                        inSessionCard
                    } else {
                        statusCard
                    }
                    if let wrap = model.pendingWrapUpDay {
                        wrapUpCard(wrap)
                    }
                    rings
                    garminRow
                    if let suggestion = model.decision.suggestedStandingCall ?? model.todayStandingSuggestion {
                        standingCallCard(suggestion)
                    }
                    upNext
                    actions
                    focusRow
                }
                .padding(14)
            }
            Divider().overlay(DL.line)
            footer
        }
        .frame(width: 392, height: 640)
        .background(DL.window)
        .onAppear { model.evaluate(forceTick: true) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: dateLine)
                Text(greeting)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(DL.ink)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            Button("Today's plan") { model.openPlan() }
                .buttonStyle(LinkButtonStyle())
        }
    }

    private var dateLine: String {
        let weekday = Fmt.weekdayLong.string(from: model.now)
        let day = Fmt.dayMonth.string(from: model.now)
        return "\(weekday), \(day)"
    }

    private var greeting: String {
        if let start = model.today?.start, model.today?.end == nil {
            let minutes = Int(model.now.timeIntervalSince(start) / 60)
            return "Workday · \(Fmt.compactDuration(minutes)) in"
        }
        let hour = Calendar.current.component(.hour, from: model.now)
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var subtitle: String {
        if model.today?.isOff == true { return "Off today. Streaks paused, not broken." }
        if model.today?.end != nil { return "Day closed. \(model.todayMetrics.breaksTaken) breaks, \(Fmt.compactDuration(model.todayMetrics.movedMinutes)) moving." }
        if model.today?.start == nil { return "Start the day when you sit down." }
        if let meeting = model.decision.waitingForMeeting {
            return "In \(meeting.title) until \(Fmt.time.string(from: meeting.end))."
        }
        if !model.settings.garmin.connected { return "Calendar and Mac activity only. Garmin offline." }
        return "Calendar, Mac activity and Garmin, together."
    }

    // MARK: Status cards

    @ViewBuilder
    private var statusCard: some View {
        let decision = model.decision
        if decision.phase == .notStarted || decision.phase == .beforeHours {
            VStack(alignment: .leading, spacing: 8) {
                Chip(text: decision.menuLabel, style: .accent, symbol: "sunrise")
                Text("Ready when you are")
                    .font(.system(size: 16, weight: .semibold))
                Text(decision.why)
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                HStack {
                    Button("Start day") { model.startDay() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Off today") { model.toggleOffToday() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(DL.accentSoft, DL.accent))
        } else if decision.phase == .ended || decision.phase == .afterHours {
            VStack(alignment: .leading, spacing: 8) {
                Chip(text: "Day complete", style: .calm, symbol: "checkmark")
                Text(model.todayMetrics.hasReflection ? "Reflection written" : "Close the day")
                    .font(.system(size: 16, weight: .semibold))
                Text(model.todayMetrics.hasReflection
                     ? "\(model.todayMetrics.movedMinutes) min moving · \(model.todayMetrics.breaksTaken) breaks · lunch \(model.todayMetrics.lunchMinutes) min"
                     : "A two-minute reflection is the last goal of the day.")
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                HStack {
                    if !model.todayMetrics.hasReflection {
                        Button("Reflect now") { model.openReflection() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Summaries") { model.openSummaries(tab: .day) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(DL.calmSoft, DL.calm))
        } else if decision.isDue {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(text: decision.step == .overlay ? "Overlay shown" : "Due now",
                         style: decision.step == .overlay ? .crit : .warn, symbol: "bell.fill")
                    if decision.microBreak {
                        Chip(text: "Micro-break", style: .plain)
                    }
                }
                Text("\(decision.exercise?.name ?? "Movement break") · \(breakLength)")
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(decision.why)
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Start") { model.startBreakNow() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Snooze \(model.settings.snoozeMinutes) min") { model.snoozeBreak() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(decision.snoozesLeft == 0)
                    Menu {
                        ForEach(SkipReason.allCases) { reason in
                            Button(reason.rawValue) { model.skipBreak(reason: reason) }
                        }
                    } label: {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DL.crit)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if decision.snoozesLeft == 0 {
                    Text("No snoozes left. Start or skip.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.warn)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(decision.step == .overlay ? DL.crit.opacity(0.12) : DL.warnSoft,
                                       decision.step == .overlay ? DL.crit : DL.warn))
        } else if decision.isFocusActive {
            VStack(alignment: .leading, spacing: 8) {
                Chip(text: "Focus until \(decision.focusUntil.map { Fmt.time.string(from: $0) } ?? "")",
                     style: .calm, symbol: "moon.zzz")
                Text("Notification only")
                    .font(.system(size: 16, weight: .semibold))
                Text("No overlay while you focus. The time still counts as sitting.")
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                HStack {
                    Button("End focus") { model.clearFocus() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Start a break") { model.startBreakNow() }
                        .buttonStyle(LinkButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(DL.calmSoft, DL.calm))
        } else if decision.isPausedByMedia {
            VStack(alignment: .leading, spacing: 8) {
                Chip(text: model.media.summary ?? "Paused", style: .calm, symbol: "pause.fill")
                Text("Waiting quietly")
                    .font(.system(size: 16, weight: .semibold))
                Text(decision.waitingForMeeting.map { "In a meeting until \(Fmt.time.string(from: $0.end)). No overlay lands in a call." }
                     ?? "Media in use. Escalation is paused until it stops.")
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(DL.calmSoft, DL.calm))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Chip(text: decision.menuLabel.isEmpty ? "Next" : decision.menuLabel,
                         style: .accent, symbol: "clock")
                    if decision.isCappedAtNotification {
                        Chip(text: "Capped at notification", style: .plain)
                    }
                }
                Text(decision.exercise.map { "\($0.name) · \($0.minutes(for: decision.gapMinutes ?? 60)) min" }
                     ?? nextBreakTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(decision.why)
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if decision.secondsUntilDue != nil {
                        Button("Start early") { model.startBreakNow() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Focus 1 h") { model.toggleFocus(minutes: 60) }
                        .buttonStyle(LinkButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(DL.panel, DL.line))
        }
    }

    private var nextBreakTitle: String {
        if let due = model.decision.dueAt {
            return "Break at \(Fmt.time.string(from: due))"
        }
        return "No break planned"
    }

    private var breakLength: String {
        guard let exercise = model.decision.exercise else { return "" }
        return "\(exercise.minutes(for: model.decision.gapMinutes ?? 60)) min"
    }

    private var inSessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(text: "In break", style: .calm, symbol: "figure.walk")
            Text(model.session?.exercise.name ?? "Break")
                .font(.system(size: 16, weight: .semibold))
            Text("\(max(1, (model.sessionSecondsRemaining + 59) / 60)) min left")
                .font(.system(size: 12))
                .foregroundStyle(DL.muted)
            Button("Open session") {
                model.requestWindow?(.session)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(DL.calmSoft, DL.calm))
    }

    private var offCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(text: "Off today", style: .calm, symbol: "moon.zzz")
            Text("No prompts until tomorrow")
                .font(.system(size: 16, weight: .semibold))
            Text("Streaks are paused, not broken. The next workday starts as normal.")
                .font(.system(size: 12))
                .foregroundStyle(DL.muted)
            Button("Undo") { model.toggleOffToday() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(DL.calmSoft, DL.calm))
    }

    private func confirmationCard(_ pending: PendingConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(text: "One tap", style: .warn, symbol: "hand.raised")
            Text(pending.prompt)
                .font(.system(size: 16, weight: .semibold))
            Text("\(pending.kind.title) · \(pending.minutes) min. \(model.settings.verification == .honorSystem ? "Honor system." : "The signal was unclear.")")
                .font(.system(size: 12))
                .foregroundStyle(DL.muted)
            HStack {
                Button("Yes, done") { model.confirmPending(done: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("No") { model.confirmPending(done: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(DL.warnSoft, DL.warn))
    }

    private func wrapUpCard(_ dayKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 18))
                .foregroundStyle(DL.calm)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wrap up yesterday?")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(Fmt.weekdayLong.string(from: DayKey.date(from: dayKey) ?? model.now)) has no reflection yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DL.muted)
                Button("Open \(Fmt.dayMonth.string(from: DayKey.date(from: dayKey) ?? model.now))") {
                    model.openReflection(dayKey: dayKey)
                }
                .buttonStyle(LinkButtonStyle())
            }
            Spacer()
            Button {
                model.pendingWrapUpDay = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DL.muted)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.calmSoft))
    }

    // MARK: Rings

    private var rings: some View {
        let metrics = model.todayMetrics
        let targets = model.today?.targets ?? model.settings.targets
        return HStack(spacing: 8) {
            Ring(progress: Double(metrics.movedMinutes) / Double(max(1, targets.standingMinutes)),
                 value: "\(metrics.movedMinutes)", label: "of \(targets.standingMinutes) min",
                 tint: metrics.movedMinutes >= targets.standingMinutes ? DL.calm : DL.accent)
            Ring(progress: Double(metrics.breaksTaken) / Double(max(1, targets.breaks)),
                 value: "\(metrics.breaksTaken)", label: "of \(targets.breaks) breaks",
                 tint: metrics.breaksTaken >= targets.breaks ? DL.calm : DL.accent)
            Ring(progress: Double(metrics.breathingCount) / Double(max(1, targets.breathing)),
                 value: "\(metrics.breathingCount)", label: "of \(targets.breathing) breathing", tint: DL.calm)
            Ring(progress: Double(metrics.lunchMinutes) / Double(max(1, targets.lunchMinutes)),
                 value: metrics.lunchMinutes > 0 ? "\(metrics.lunchMinutes)m" : "—",
                 label: "lunch", tint: metrics.lunchMinutes >= targets.lunchMinutes ? DL.calm : DL.warn)
        }
    }

    private var garminRow: some View {
        HStack(spacing: 8) {
            garminCell(label: "Stress", value: model.health.stress.map(String.init) ?? "—",
                       detail: stressBand, tint: stressTint)
            garminCell(label: "Body Battery", value: model.health.bodyBattery.map(String.init) ?? "—",
                       detail: batteryDetail, tint: DL.calm)
            garminCell(label: "Steps", value: model.health.steps.map { $0.formatted() } ?? "—",
                       detail: model.relativeSyncText(), tint: DL.ink)
        }
    }

    private func garminCell(label: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(DL.muted)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(detail).font(.system(size: 10)).foregroundStyle(DL.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private var stressBand: String {
        guard let stress = model.health.stress else { return "No reading" }
        if stress >= model.settings.garmin.stressHigh { return "High" }
        if stress >= model.settings.garmin.stressHigh - 15 { return "Medium" }
        return "Low"
    }

    private var stressTint: Color {
        guard let stress = model.health.stress else { return DL.ink }
        if stress >= model.settings.garmin.stressHigh { return DL.crit }
        if stress >= model.settings.garmin.stressHigh - 15 { return DL.warn }
        return DL.calm
    }

    private var batteryDetail: String {
        guard let now = model.health.bodyBattery else { return "No reading" }
        guard let wake = model.health.bodyBatteryWake else { return "Now" }
        let delta = now - wake
        return delta == 0 ? "Flat since wake" : "\(delta > 0 ? "Up" : "Down") \(abs(delta)) since wake"
    }

    // MARK: Up next

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Up next")
            if let plan = model.todayPlan {
                let items = plan.timeline.filter { $0.start >= model.now.adding(minutes: -5) }.prefix(4)
                if items.isEmpty {
                    Text("Nothing left on the calendar.")
                        .font(.system(size: 11.5)).foregroundStyle(DL.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items)) { item in
                            HStack(spacing: 8) {
                                Text(Fmt.time.string(from: item.start))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DL.muted)
                                    .frame(width: 38, alignment: .leading)
                                Text(item.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(DL.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if !item.chip.isEmpty {
                                    Chip(text: item.chip, style: chipStyle(item.chipStyle))
                                }
                            }
                            .padding(.vertical, 4)
                            if item.id != items.last?.id {
                                Rectangle().fill(DL.line.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                }
            } else {
                Text("Start the day to build the plan.")
                    .font(.system(size: 11.5)).foregroundStyle(DL.muted)
            }
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

    private func standingCallCard(_ suggestion: StandingSuggestion) -> some View {
        HStack(spacing: 9) {
            Image(systemName: suggestion.target == .pad ? "figure.walk" : "figure.stand")
                .font(.system(size: 15))
                .foregroundStyle(DL.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("In \(max(0, TimeRange.minutesBetween(model.now, suggestion.event.start))) min · \(suggestion.target.title.lowercased())")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            Button("Stand") { model.takeStandingCall() }
                .buttonStyle(LinkButtonStyle())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.accentSoft))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.accentBorder, lineWidth: 1))
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("New entry") { model.openJournal() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Check in") { model.requestWindow?(.checkIn) }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            if model.today == nil || model.today?.start == nil {
                Button("Start day") { model.startDay() }
                    .buttonStyle(PrimaryButtonStyle())
            } else if model.today?.end == nil {
                Button("End day") { model.endDay() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Summaries") { model.openSummaries(tab: .day) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var focusLengths: [Int] {
        Array(Set(model.settings.focusLengths.filter { $0 > 0 })).sorted()
    }

    private func focusLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }

    private var focusRow: some View {
        HStack {
            Text("Focus mode").font(.system(size: 11.5)).foregroundStyle(DL.muted)
            SegmentedPicker(options: [(0, "Off")] + focusLengths.map { ($0, focusLabel($0)) },
                            selection: Binding(
                                get: {
                                    guard model.decision.isFocusActive, let until = model.decision.focusUntil else { return 0 }
                                    let remaining = until.timeIntervalSince(model.now) / 60
                                    return focusLengths.first { Double($0) >= remaining } ?? focusLengths.last ?? 0
                                },
                                set: { value in
                                    if value == 0 { model.clearFocus() } else { model.setFocus(minutes: value) }
                                }
                            ))
            .frame(width: 150)
            Spacer()
            Button(model.today?.isOff == true ? "Back on today" : "Off today") { model.toggleOffToday() }
                .buttonStyle(LinkButtonStyle())
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Journal") { model.openJournal() }.buttonStyle(LinkButtonStyle())
            Button("Summaries") { model.openSummaries(tab: .week) }.buttonStyle(LinkButtonStyle())
            Button("Settings") { model.openSettings() }.buttonStyle(LinkButtonStyle())
            Spacer()
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DL.muted)
                    .lineLimit(1)
                    .onTapGesture { model.dismissToast() }
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DL.muted)
            .help("Quit Dayline")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DL.titlebar)
    }

    private func cardBackground(_ fill: Color, _ border: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border.opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Break overlay

struct BreakOverlayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.bgCanvas.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(DL.accentSoft).frame(width: 62, height: 62)
                    Image(systemName: model.decision.kind?.symbol ?? "figure.walk")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(DL.accent)
                }
                Kicker(text: "Dayline · break due")
                Text(model.decision.exercise?.name ?? "Time to move")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(DL.ink)
                Text("\(breakLength) · \(model.decision.kind?.title ?? "Movement")")
                    .font(.system(size: 13))
                    .foregroundStyle(DL.muted)
                Text(model.decision.why)
                    .font(.system(size: 14))
                    .foregroundStyle(DL.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                HStack(spacing: 10) {
                    Button("Start \(breakLength)") { model.startBreakNow() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Snooze \(model.settings.snoozeMinutes) min") { model.snoozeBreak() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.decision.snoozesLeft == 0)
                    Menu {
                        ForEach(SkipReason.allCases) { reason in
                            Button(reason.rawValue) { model.skipBreak(reason: reason) }
                        }
                    } label: {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DL.crit)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.top, 4)
                if model.decision.snoozesLeft == 0 {
                    Text("No snoozes left. Start or skip.")
                        .font(.system(size: 11))
                        .foregroundStyle(DL.warn)
                }
                Text("Escalation stops while camera, microphone or screen sharing is on.")
                    .font(.system(size: 12))
                    .foregroundStyle(DL.muted)
                    .padding(.top, 2)
            }
            .padding(32)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: Radius.overlayCard, style: .continuous)
                    .fill(DL.panel)
                    .shadow(color: Color.textPrimary.opacity(0.10), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.overlayCard, style: .continuous)
                    .strokeBorder(DL.line, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    model.dismissBreakPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DL.muted)
                .padding(8)
                .help("Hide until the next escalation (it will not snooze)")
            }
        }
        .onExitCommand { model.dismissBreakPrompt() }
    }

    private var breakLength: String {
        guard let exercise = model.decision.exercise else { return "2 min" }
        return "\(exercise.minutes(for: model.decision.gapMinutes ?? 60)) min"
    }
}
