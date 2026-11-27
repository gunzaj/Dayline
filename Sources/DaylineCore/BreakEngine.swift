import Foundation

// MARK: - Media state

public struct MediaState: Codable, Equatable, Sendable {
    public var cameraInUse: Bool
    public var microphoneInUse: Bool
    public var screenSharing: Bool
    public var openMicrophoneMinutes: Int
    /// True when the only microphone user is on the ignore list.
    public var microphoneIgnored: Bool

    public init(cameraInUse: Bool = false, microphoneInUse: Bool = false,
                screenSharing: Bool = false, openMicrophoneMinutes: Int = 0,
                microphoneIgnored: Bool = false) {
        self.cameraInUse = cameraInUse
        self.microphoneInUse = microphoneInUse
        self.screenSharing = screenSharing
        self.openMicrophoneMinutes = openMicrophoneMinutes
        self.microphoneIgnored = microphoneIgnored
    }

    public static let clear = MediaState()

    public var isBlocking: Bool {
        if cameraInUse || screenSharing { return true }
        return microphoneInUse && !microphoneIgnored
    }

    public var summary: String? {
        if screenSharing { return "Screen sharing" }
        if cameraInUse { return "Camera on" }
        if microphoneInUse && !microphoneIgnored { return "Microphone on" }
        return nil
    }
}

// MARK: - Seated time

/// Turns the app's short ticks into whole seated minutes.
///
/// Ticks arrive every few seconds, so each one is a fraction of a minute and
/// has to be carried forward. A tick that took far longer than expected means
/// the Mac slept, and a long idle time means nobody is at the keyboard; neither
/// counts as sitting at the desk.
public struct SeatedClock: Sendable {
    /// A gap between ticks longer than this is treated as sleep.
    public static let suspendedGap: TimeInterval = 90
    /// With no input for this long, the person is not counted as seated.
    public static let idleLimit: TimeInterval = 5 * 60

    private var carry: TimeInterval = 0

    public init() {}

    public static func wasSuspended(_ delta: TimeInterval) -> Bool { delta > suspendedGap }

    /// Returns the whole seated minutes this tick completes.
    public mutating func advance(by delta: TimeInterval, idleSeconds: TimeInterval) -> Int {
        guard !SeatedClock.wasSuspended(delta), idleSeconds < SeatedClock.idleLimit else {
            carry = 0
            return 0
        }
        carry += max(0, delta)
        let minutes = Int(carry / 60)
        carry -= TimeInterval(minutes * 60)
        return minutes
    }
}

// MARK: - Escalation

public enum EscalationStep: Int, Codable, Comparable, Sendable {
    case none = 0
    case hint = 1
    case notification = 2
    case overlay = 3

    public static func < (lhs: EscalationStep, rhs: EscalationStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .none: return "None"
        case .hint: return "Hint"
        case .notification: return "Notification"
        case .overlay: return "Overlay"
        }
    }
}

// MARK: - Decision

public enum EnginePhase: String, Sendable {
    case dayOff, beforeHours, afterHours, notStarted, ended, active, inBreak
}

public enum BreakReason: Equatable, Sendable {
    case seated(Int)
    case afterLongBlock(Int)
    case lunchWindow
    case standingBehind
    case stressHigh(Int)
    case lowEnergy(Int)
    case none
}

public struct BreakDecision: Sendable {
    public var phase: EnginePhase
    public var now: Date
    public var isDue: Bool
    public var dueAt: Date?
    public var step: EscalationStep
    public var exercise: ExerciseDef?
    public var kind: BreakKind?
    public var reason: BreakReason
    public var snoozesUsed: Int
    public var snoozesLeft: Int
    public var snoozedUntil: Date?
    public var focusUntil: Date?
    public var isPausedByMedia: Bool
    public var media: MediaState
    public var isCappedAtNotification: Bool
    public var waitingForMeeting: CalendarEvent?
    public var gapMinutes: Int?
    public var gapEnd: Date?
    public var microBreak: Bool
    public var suggestedStandingCall: StandingSuggestion?
    public var menuLabel: String
    public var why: String
    public var seatedMinutes: Int
    public var dayTargets: DayTargets

    public var isFocusActive: Bool {
        if let focusUntil { return focusUntil > now }
        return false
    }

    public var secondsUntilDue: Int? {
        guard let dueAt, dueAt > now else { return nil }
        return Int(dueAt.timeIntervalSince(now))
    }

    public var nextBreakLabel: String {
        if isDue {
            return exercise?.displayTitle ?? "Break"
        }
        if let seconds = secondsUntilDue {
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "Break in \(minutes) min"
        }
        return "No break planned"
    }
}

// MARK: - Engine

public enum BreakEngine {

    public static func interval(_ settings: AppSettings, health: HealthSnapshot) -> Int {
        let lo = max(20, min(settings.moveIntervalMin, settings.moveIntervalMax))
        let hi = max(lo, settings.moveIntervalMax)
        if let stress = health.stress, stress >= settings.garmin.stressHigh + 15 { return lo }
        if let battery = health.bodyBattery, battery < settings.garmin.batteryLow { return lo }
        if let sleep = health.sleepScore, settings.garmin.useSleepAndHRV, sleep < 65 { return lo }
        if let sleep = health.sleepScore, settings.garmin.useSleepAndHRV, sleep >= 85,
           let battery = health.bodyBattery, battery >= 60 {
            return hi
        }
        return (lo + hi) / 2
    }

    public static func decide(now: Date,
                              day: WorkDay?,
                              settings: AppSettings,
                              plan: DayPlan?,
                              health: HealthSnapshot,
                              media: MediaState,
                              activeBreak: Bool,
                              calendar: Calendar = .current) -> BreakDecision {
        let workRange = plan.map { TimeRange(start: $0.workStart, end: $0.workEnd) }
            ?? settings.workRange(for: now, calendar: calendar)
        let configuredOff = settings.isConfiguredOffDay(now, calendar: calendar)
        let targets = day?.targets ?? settings.targets

        func base(_ phase: EnginePhase) -> BreakDecision {
            BreakDecision(phase: phase, now: now, isDue: false, dueAt: nil, step: .none,
                          exercise: nil, kind: nil, reason: .none,
                          snoozesUsed: day?.snoozeCount ?? 0,
                          snoozesLeft: max(0, settings.snoozeLimit - (day?.snoozeCount ?? 0)),
                          snoozedUntil: day?.snoozedUntil, focusUntil: day?.focusUntil,
                          isPausedByMedia: false, media: media, isCappedAtNotification: false,
                          waitingForMeeting: nil, gapMinutes: nil, gapEnd: nil,
                          microBreak: false, suggestedStandingCall: nil,
                          menuLabel: "", why: "", seatedMinutes: day?.seatedMinutes ?? 0,
                          dayTargets: targets)
        }

        if day?.isOff == true || configuredOff {
            var d = base(.dayOff)
            d.menuLabel = "Off"
            d.why = "Off today. No prompts, streaks paused."
            return d
        }
        guard let day, let start = day.start else {
            var d = base(.notStarted)
            if let workRange, now >= workRange.start {
                d.phase = .notStarted
                d.menuLabel = "Start day"
                d.why = "Inside work hours. Start the day to plan breaks."
            } else if let workRange {
                d.phase = .beforeHours
                d.menuLabel = "From " + Fmt.time.string(from: workRange.start)
                d.why = "Work hours start at \(Fmt.time.string(from: workRange.start))."
            } else {
                d.menuLabel = "Off"
                d.why = "No work hours configured for today."
            }
            return d
        }
        if day.end != nil {
            var d = base(.ended)
            d.menuLabel = "Done"
            d.why = "Day ended."
            return d
        }
        if activeBreak {
            var d = base(.inBreak)
            d.menuLabel = "In break"
            d.why = "Guided session in progress."
            d.step = .none
            return d
        }
        if let workRange {
            if now >= workRange.end && day.startSource != .manual {
                var d = base(.afterHours)
                d.menuLabel = "Done"
                d.why = "Work hours ended at \(Fmt.time.string(from: workRange.end))."
                return d
            }
            if now < workRange.start && day.startSource != .manual {
                var d = base(.beforeHours)
                d.menuLabel = "From " + Fmt.time.string(from: workRange.start)
                d.why = "Work hours start at \(Fmt.time.string(from: workRange.start))."
                return d
            }
        }

        var decision = base(.active)
        decision.reason = .none
        let currentMeeting = plan?.currentMeeting(at: now)
        let nextMeeting = plan?.nextMeeting(after: now)
        decision.waitingForMeeting = currentMeeting
        if let currentMeeting {
            decision.menuLabel = "In call"
            decision.why = "In a meeting until \(Fmt.time.string(from: currentMeeting.end)). Waiting for the gap."
            decision.isPausedByMedia = true
            decision.media = media
            // No escalation during a call. A due break waits.
            decision.dueAt = nil
            decision.step = .none
            return decision
        }

        // Gap now (or upcoming).
        let gap = plan?.gap(at: now)
        let gapEndDate = gap?.end ?? nextMeeting?.start
        let gapMinutes = gap.map { $0.minutes } ?? (gapEndDate.map { TimeRange.minutesBetween(now, $0) } ?? 0)
        decision.gapMinutes = gapMinutes
        decision.gapEnd = gapEndDate

        // Lunch: within the protected window, not taken yet.
        let lunchDone = day.lunchMinutes >= max(20, settings.lunchTargetMinutes - 10)
        let inLunchWindow = settings.lunchWindowStart.date(on: now, calendar: calendar) <= now
            && now < settings.lunchWindowEnd.date(on: now, calendar: calendar)
        let lunchGap = plan?.lunchGap.map { $0.minutes } ?? 0
        let lunchDue = inLunchWindow && !lunchDone && !day.lunchSkipped
            && lunchGap >= settings.lunchTargetMinutes && gapMinutes >= settings.lunchTargetMinutes

        // Long block that just ended and has not been answered by a break.
        var longBlockDue: Date?
        if let plan {
            if let block = Planner.longBlockEndingBefore(now, events: plan.events, settings: settings),
               block.end <= now,
               day.lastBreakEnd == nil || block.end > day.lastBreakEnd!,
               day.longBlockHandledAt == nil || block.end > day.longBlockHandledAt! {
                longBlockDue = block.end
            }
        }

        let seatedInterval = interval(settings, health: health)

        // Standing-call suggestion: two minutes before a matching call.
        if let plan, let next = plan.nextMeeting(after: now),
           next.start.timeIntervalSince(now) <= 2 * 60 + 30,
           let suggestion = plan.standingSuggestions.first(where: { $0.event.id == next.id }) {
            decision.suggestedStandingCall = suggestion
        }

        var dueAt: Date?
        var reason: BreakReason = .none
        if lunchDue {
            dueAt = now
            reason = .lunchWindow
        }
        if let longBlockDue {
            let candidate = longBlockDue.adding(minutes: 2)
            if dueAt == nil || candidate < dueAt! {
                dueAt = candidate
                reason = .afterLongBlock(0)
            }
        }
        if let next = day.nextBreakDue, dueAt == nil || next < dueAt! {
            dueAt = next
            if reason == .none { reason = .seated(day.seatedMinutes) }
        } else if day.nextBreakDue == nil,
                  day.seatedMinutes >= seatedInterval || now >= start.adding(minutes: seatedInterval) {
            let candidate = start.adding(minutes: seatedInterval)
            if dueAt == nil || candidate < dueAt! {
                dueAt = candidate
                reason = .seated(day.seatedMinutes)
            }
        }

        if let snoozedUntil = day.snoozedUntil, snoozedUntil > now, !lunchDue {
            dueAt = snoozedUntil
            reason = .seated(day.seatedMinutes)
        }

        guard let due = dueAt else {
            decision.menuLabel = ""
            decision.why = "Sitting \(day.seatedMinutes) min. Next break in \(max(0, seatedInterval - day.seatedMinutes)) min."
            decision.menuLabel = "\(max(0, seatedInterval - day.seatedMinutes))m"
            decision.reason = .seated(day.seatedMinutes)
            return decision
        }

        decision.dueAt = due
        let elapsed = max(0, TimeRange.minutesBetween(due, now))
        var step: EscalationStep
        if now < due {
            step = .none
        } else if elapsed >= settings.escalationOverlayAfter {
            step = .overlay
        } else if elapsed >= settings.escalationNotificationAfter {
            step = .notification
        } else {
            step = .hint
        }

        var capped = false
        if let focus = day.focusUntil, focus > now {
            if step > .notification { step = .notification; capped = true }
        }
        // An open mic with no calendar event stops blocking after the cap, but
        // escalation still stops at the notification rather than the overlay.
        var micBlocks = media.microphoneInUse && !media.microphoneIgnored
        if micBlocks && media.openMicrophoneMinutes >= settings.openMicCapMinutes {
            micBlocks = false
            capped = true
            if step > .notification { step = .notification }
        }
        if (media.cameraInUse || media.screenSharing || micBlocks) && settings.pauseOnMedia {
            decision.isPausedByMedia = true
            step = .hint
        }
        decision.step = step
        decision.isCappedAtNotification = capped
        decision.isDue = now >= due && !decision.isPausedByMedia
        decision.reason = reason

        if now < due, let seconds = decision.secondsUntilDue {
            decision.menuLabel = "\(max(1, Int(ceil(Double(seconds) / 60.0))))m"
            decision.why = "Next break \(Fmt.time.string(from: due))."
            return decision
        }

        // Choose what the break is.
        let choice = chooseExercise(now: now, day: day, settings: settings, health: health,
                                    gapMinutes: gapMinutes, lunchDue: lunchDue)
        decision.exercise = choice.exercise
        decision.kind = choice.exercise?.kind
        switch choice.reason {
        case .stressHigh, .lowEnergy, .standingBehind, .lunchWindow:
            decision.reason = choice.reason
        default:
            decision.reason = reason
        }
        decision.microBreak = choice.microBreak

        guard choice.exercise != nil else {
            decision.isDue = false
            decision.step = .none
            decision.menuLabel = "Waiting"
            decision.why = nextMeeting.map { "No room before \(Fmt.time.string(from: $0.start))." }
                ?? "No free gap for a break yet."
            return decision
        }

        decision.menuLabel = decision.isPausedByMedia ? "Waiting" : "Break now"
        decision.why = whyText(decision: decision, day: day, health: health, settings: settings)
        return decision
    }

    // MARK: Choosing a break

    public struct Choice: Sendable {
        public var exercise: ExerciseDef?
        public var reason: BreakReason
        public var microBreak: Bool
    }

    public static func chooseExercise(now: Date, day: WorkDay, settings: AppSettings,
                                      health: HealthSnapshot, gapMinutes: Int,
                                      lunchDue: Bool) -> Choice {
        let candidates = ExerciseLibrary.available(settings: settings)
        let gap = max(0, gapMinutes)
        let lastKind = day.lastBreakKind

        func pick(_ kinds: [BreakKind]) -> ExerciseDef? {
            for kind in kinds {
                let pool = candidates.filter { $0.kind == kind && $0.minutesLow <= max(gap, 2) }
                guard !pool.isEmpty else { continue }
                if kind == lastKind,
                   candidates.contains(where: { $0.kind != lastKind && kinds.contains($0.kind) && $0.minutesLow <= max(gap, 2) }) {
                    continue
                }
                // Among several of one kind, avoid the one just done.
                let fresh = pool.filter { $0.id != day.lastExerciseID }
                return (fresh.isEmpty ? pool : fresh).min { $0.minutesLow < $1.minutesLow }
            }
            return nil
        }

        if lunchDue, gap >= settings.lunchTargetMinutes {
            if let lunch = candidates.first(where: { $0.kind == .lunch }) {
                return Choice(exercise: lunch, reason: .lunchWindow, microBreak: false)
            }
        }

        let standingTarget = day.targets.standingMinutes
        let moved = day.standingMinutes + day.walkingMinutes
        let behind = moved < standingTarget / 2 && day.seatedMinutes > 90

        if let stress = health.stress, stress >= settings.garmin.stressHigh, gap >= 2 {
            if let ex = pick([.boxBreathing]) {
                return Choice(exercise: ex, reason: .stressHigh(stress), microBreak: false)
            }
        }

        let lowBattery = (health.bodyBattery ?? 100) < settings.garmin.batteryLow
        let poorSleep = settings.garmin.useSleepAndHRV && (health.sleepScore ?? 100) < 65

        if gap < 2 {
            return Choice(exercise: nil, reason: .none, microBreak: true)
        }

        if lowBattery || poorSleep {
            if gap >= 15, let ex = pick([.walkingPad]) {
                return Choice(exercise: ex, reason: .lowEnergy(health.bodyBattery ?? 0), microBreak: false)
            }
            if gap >= 5, let ex = pick([.matMobility]) {
                return Choice(exercise: ex, reason: .lowEnergy(health.bodyBattery ?? 0), microBreak: false)
            }
            if let ex = pick([.standUpStretch, .boxBreathing]) {
                return Choice(exercise: ex, reason: .lowEnergy(health.bodyBattery ?? 0), microBreak: false)
            }
        }

        if behind, gap >= 30, settings.isEquipmentEnabled(.standingDesk),
           let ex = pick([.standingBlock]) {
            return Choice(exercise: ex, reason: .standingBehind, microBreak: false)
        }
        // Start after the last break's kind so the day cycles through every
        // available exercise instead of alternating between the first two.
        var normal: [BreakKind] = [.squats, .gripSets, .balanceBoard, .custom, .standUpStretch, .boxBreathing]
        if let lastKind, let position = normal.firstIndex(of: lastKind) {
            normal = Array(normal[(position + 1)...] + normal[...position])
        }
        if let ex = pick(normal) {
            return Choice(exercise: ex, reason: .seated(day.seatedMinutes), microBreak: gap < 5)
        }
        if let ex = candidates.filter({ $0.kind != .lunch }).min(by: { $0.minutesLow < $1.minutesLow }) {
            return Choice(exercise: ex, reason: .seated(day.seatedMinutes), microBreak: gap < 5)
        }
        return Choice(exercise: nil, reason: .none, microBreak: true)
    }

    static func whyText(decision: BreakDecision, day: WorkDay, health: HealthSnapshot,
                        settings: AppSettings) -> String {
        var parts: [String] = []
        switch decision.reason {
        case .afterLongBlock(let minutes):
            parts.append(minutes > 0 ? "\(minutes) min of calls just ended" : "Long block of calls just ended")
        case .lunchWindow:
            parts.append("Midday window is free")
        case .standingBehind:
            parts.append("Standing target is behind")
        case .stressHigh(let value):
            parts.append("Stress \(value)")
        case .lowEnergy(let value):
            parts.append("Body Battery \(value)")
        case .seated(let minutes):
            parts.append("\(max(minutes, 0)) min seated")
        case .none:
            break
        }
        if let stress = health.stress, stress >= settings.garmin.stressHigh, case .stressHigh = decision.reason {} else if let stress = health.stress {
            if stress >= settings.garmin.stressHigh { parts.append("Stress \(stress)") }
        }
        if let gapEnd = decision.gapEnd {
            parts.append("Free until \(Fmt.time.string(from: gapEnd))")
        }
        if decision.microBreak {
            parts.append("Tight gap, so a 2-minute micro-break")
        }
        if decision.isPausedByMedia, let label = decision.media.summary {
            parts.append("\(label) active, waiting")
        }
        return parts.joined(separator: " · ")
    }
}
