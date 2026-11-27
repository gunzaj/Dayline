import AppKit
import DaylineCore
import Combine
import SwiftUI

@MainActor
final class SessionUI: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var reps = 0
    @Published var sets = 1
    @Published var restUntil: Date?
}

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = SessionUI()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session = model.session {
                content(session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(DL.calm)
                    Text("Break finished").font(.system(size: 16, weight: .semibold))
                    Text("You can close this window.").font(.system(size: 12)).foregroundStyle(DL.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DL.window)
            }
        }
        .frame(minWidth: 520, minHeight: 600)
        .background(DL.window)
        .onAppear { ui.elapsed = 0 }
        .onReceive(ticker) { date in
            guard let session = model.session else { return }
            ui.elapsed = max(0, date.timeIntervalSince(session.startedAt))
            if let rest = ui.restUntil, date >= rest {
                ui.restUntil = nil
            }
        }
    }

    private func content(_ session: BreakSession) -> some View {
        let total = max(1, session.endsAt.timeIntervalSince(session.startedAt))
        let remaining = max(0, total - ui.elapsed)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(text: session.isLunch ? "Lunch away from desk" : "Guided break")
                    Text(session.exercise.name)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(DL.ink)
                    Text("\(session.minutes) min · \(session.kind.title)\(session.meetingTitle.map { " · during \($0)" } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(DL.muted)
                }
                Spacer()
                Button {
                    model.abandonSession()
                } label: {
                    Text("End early")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(DL.line, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, 1 - remaining / total)))
                        .stroke(DL.calm, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(clockString(remaining))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DL.ink)
                        Text("left").font(.system(size: 10.5)).foregroundStyle(DL.muted)
                    }
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 5) {
                    Chip(text: session.kind.title, style: session.kind == .boxBreathing ? .calm : .accent,
                         symbol: session.kind.symbol)
                    Text(guidanceLine(session))
                        .font(.system(size: 13))
                        .foregroundStyle(DL.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Auto-verified in \(model.settings.verification == .honorSystem ? "honor system" : "auto + confirm") mode.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DL.muted)
                }
                Spacer(minLength: 0)
            }

            guidance(session)

            if !session.exercise.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "How")
                    ForEach(Array(session.exercise.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 7) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(DL.muted)
                                .frame(width: 14, height: 14)
                                .background(Circle().stroke(DL.line, lineWidth: 1))
                            Text(step)
                                .font(.system(size: 11.5))
                                .foregroundStyle(DL.muted)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Skip this break") { model.abandonSession() }
                    .buttonStyle(GhostDestructiveButtonStyle())
                Spacer()
                Button(session.isLunch ? "I'm back" : "Done") { model.endSession(early: true) }
                    .buttonStyle(PrimaryButtonStyle())
            }

            Text("A break counts once it ends. Closing this window ends the session without credit.")
                .font(.system(size: 10))
                .foregroundStyle(DL.muted)
        }
        .padding(24)
    }

    // MARK: Guidance

    @ViewBuilder
    private func guidance(_ session: BreakSession) -> some View {
        switch session.exercise.guidance {
        case .breathingSquare:
            BreathingSquare(elapsed: ui.elapsed, accent: DL.calm)
                .frame(height: 230)
        case .repCounter:
            repContent(session)
        case .stepCards, .poseSequence:
            stepsContent(session)
        case .countdown, .lunchTimer:
            countdownContent(session)
        case .intervalTimer:
            intervalContent()
        case .setsReps:
            gripsContent()
        }
    }

    private func repContent(_ session: BreakSession) -> some View {
        let target = session.exercise.targetReps ?? 10
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(ui.reps)")
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ui.reps >= target ? DL.calm : DL.ink)
                Text("of \(target) reps")
                    .font(.system(size: 14))
                    .foregroundStyle(DL.muted)
            }
            Meter(progress: Double(ui.reps) / Double(max(1, target)), tint: ui.reps >= target ? DL.calm : DL.accent, height: 8)
                .frame(width: 260)
            HStack(spacing: 10) {
                Button("＋ One rep") {
                    if ui.reps < target { ui.reps += 1 }
                    if ui.reps % 3 == 0 { SoundPlayer.tick(enabled: model.settings.sounds) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Reset") { ui.reps = 0 }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Text(ui.reps >= target ? "All reps done. Nice." : "Slow down on the way down. Two seconds up.")
                .font(.system(size: 11.5))
                .foregroundStyle(DL.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func stepsContent(_ session: BreakSession) -> some View {
        let steps = session.exercise.steps
        let total = max(1, session.endsAt.timeIntervalSince(session.startedAt))
        let perStep = total / Double(max(1, steps.count))
        let index = min(steps.count - 1, Int(ui.elapsed / perStep))
        let stepElapsed = ui.elapsed - Double(index) * perStep
        let stepRemaining = max(0, perStep - stepElapsed)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Chip(text: "Step \(index + 1) of \(steps.count)", style: .accent)
                Spacer()
                Text("\(Int(ceil(stepRemaining)))s on this one")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DL.muted)
            }
            Text(steps.indices.contains(index) ? steps[index] : "Move gently")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(DL.ink)
                .fixedSize(horizontal: false, vertical: true)
            Meter(progress: stepElapsed / max(1, perStep), tint: DL.calm, height: 7)
            HStack(spacing: 5) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? DL.calm : DL.line)
                        .frame(height: 4)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func countdownContent(_ session: BreakSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: session.kind == .lunch ? "fork.knife" : (session.kind == .walkingPad ? "figure.walk" : "figure.stand"))
                    .font(.system(size: 22))
                    .foregroundStyle(DL.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countdownHeadline(session))
                        .font(.system(size: 14, weight: .semibold))
                    Text(countdownDetail(session))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            ProgressView(value: min(1, ui.elapsed / max(1, session.endsAt.timeIntervalSince(session.startedAt))))
                .tint(DL.calm)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.accentSoft))
    }

    private func countdownHeadline(_ session: BreakSession) -> String {
        switch session.kind {
        case .standingBlock: return "Standing. Let the desk do the work."
        case .walkingPad: return "Easy pace. No sprinting."
        case .lunch: return "Away from the Mac."
        default: return "Keep going."
        }
    }

    private func countdownDetail(_ session: BreakSession) -> String {
        switch session.kind {
        case .standingBlock: return "Shift your weight every minute. The sit-down cue comes at the end."
        case .walkingPad: return "2 km/h to start. Timer and your confirmation verify this one."
        case .lunch: return "Eat away from the screen. Come back when you are done; the welcome-back check-in follows."
        default: return "Stay with it until the timer ends."
        }
    }

    private func intervalContent() -> some View {
        let cycle = 60.0
        let inCycle = ui.elapsed.truncatingRemainder(dividingBy: cycle)
        let isWork = inCycle < 40
        let round = min(5, Int(ui.elapsed / cycle) + 1)
        let remaining = isWork ? 40 - inCycle : 60 - inCycle
        return VStack(spacing: 10) {
            HStack {
                Chip(text: isWork ? "Rock" : "Rest", style: isWork ? .accent : .calm)
                Spacer()
                Text("Round \(round) of 5")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DL.muted)
            }
            Text("\(Int(ceil(remaining)))")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isWork ? DL.ink : DL.calm)
            Text(isWork ? "Small circles, knees soft." : "Step off if you need to.")
                .font(.system(size: 11.5))
                .foregroundStyle(DL.muted)
            Meter(progress: isWork ? inCycle / 40 : (inCycle - 40) / 20,
                  tint: isWork ? DL.accent : DL.calm, height: 7)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private func gripsContent() -> some View {
        let target = 10
        let resting = ui.restUntil != nil
        return VStack(spacing: 10) {
            HStack {
                ForEach(1...3, id: \.self) { set in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(set < ui.sets ? DL.calm : (set == ui.sets ? DL.accentSoft : DL.line))
                            .frame(width: 9, height: 9)
                        Text("Set \(set)")
                            .font(.system(size: 11, weight: set == ui.sets ? .semibold : .regular))
                            .foregroundStyle(set == ui.sets ? DL.ink : DL.muted)
                    }
                }
                Spacer()
                Text(resting ? "Rest" : "10 reps per hand")
                    .font(.system(size: 11))
                    .foregroundStyle(DL.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(ui.reps)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of \(target)")
                    .font(.system(size: 13))
                    .foregroundStyle(DL.muted)
            }
            Meter(progress: Double(ui.reps) / Double(target), tint: ui.reps >= target ? DL.calm : DL.accent, height: 7)
            HStack(spacing: 8) {
                Button("＋ Rep") {
                    guard !resting else { return }
                    ui.reps = min(target, ui.reps + 1)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(resting)
                Button(resting ? "Skip rest" : (ui.reps >= target ? "Finish set" : "Rest 30 s")) {
                    if resting {
                        ui.restUntil = nil
                    } else if ui.reps >= target {
                        if ui.sets >= 3 {
                            model.endSession(early: true)
                        } else {
                            ui.reps = 0
                            ui.sets += 1
                            ui.restUntil = Date().addingTimeInterval(30)
                        }
                    } else {
                        ui.restUntil = Date().addingTimeInterval(30)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    // MARK: Copy

    private func guidanceLine(_ session: BreakSession) -> String {
        switch session.exercise.guidance {
        case .breathingSquare: return "Follow the square. Four counts in, four hold, four out, four hold."
        case .repCounter: return "Tap after each rep. Ten slow reps is the whole set."
        case .stepCards: return "One card at a time. The timer moves you on."
        case .countdown: return "A countdown you can leave running. Come back when it ends."
        case .poseSequence: return "A pose at a time, with a timer for each."
        case .intervalTimer: return "Forty seconds on, twenty off. Five rounds."
        case .setsReps: return "Ten reps per hand, thirty seconds rest, three sets."
        case .lunchTimer: return "Thirty minutes away. The Mac stays here."
        }
    }

    private func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Breathing square

struct BreathingSquare: View {
    var elapsed: TimeInterval
    var accent: Color

    private var cycle: Double { elapsed.truncatingRemainder(dividingBy: 16) }

    private var phaseIndex: Int { Int(cycle / 4) }

    private var phaseName: String {
        ["Breathe in", "Hold", "Breathe out", "Hold"][phaseIndex]
    }

    private var phaseProgress: Double { (cycle - Double(phaseIndex) * 4) / 4 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DL.line, lineWidth: 1.5)
                    .frame(width: 180, height: 180)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .trim(from: 0, to: perimeterProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)
                    .offset(dotOffset)
                    .shadow(color: accent.opacity(0.4), radius: 8)
                VStack(spacing: 2) {
                    Text(phaseName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DL.ink)
                    Text("\(max(1, 4 - Int(phaseProgress * 4)))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
            }
            .frame(height: 200)
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= phaseIndex ? accent : DL.line)
                        .frame(width: 42, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }

    private var perimeterProgress: Double {
        let segment = Double(phaseIndex) * 0.25
        switch phaseIndex {
        case 0: return segment + phaseProgress * 0.25
        case 1: return segment + phaseProgress * 0.25
        case 2: return segment + phaseProgress * 0.25
        default: return segment + phaseProgress * 0.25
        }
    }

    private var dotOffset: CGSize {
        let side: Double = 180
        let p = perimeterProgress
        let t = p * 4 // 0...4 sides
        let inset: Double = 0
        switch Int(t) {
        case 0:
            return CGSize(width: -side / 2 + (t - 0) * side + inset, height: -side / 2)
        case 1:
            return CGSize(width: side / 2, height: -side / 2 + (t - 1) * side)
        case 2:
            return CGSize(width: side / 2 - (t - 2) * side, height: side / 2)
        default:
            return CGSize(width: -side / 2, height: side / 2 - (t - 3) * side)
        }
    }
}
