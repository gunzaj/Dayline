import Foundation

// MARK: - Break catalog

public enum BreakKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case boxBreathing
    case squats
    case standUpStretch
    case standingBlock
    case walkingPad
    case matMobility
    case balanceBoard
    case gripSets
    case lunch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .boxBreathing: return "Box breathing"
        case .squats: return "Squats"
        case .standUpStretch: return "Stand-up stretch"
        case .standingBlock: return "Standing block"
        case .walkingPad: return "Walking-pad session"
        case .matMobility: return "Mat mobility"
        case .balanceBoard: return "Balance board"
        case .gripSets: return "Grip sets"
        case .lunch: return "Lunch away from desk"
        }
    }

    public var shortTitle: String {
        switch self {
        case .boxBreathing: return "Breathe"
        case .squats: return "Squats"
        case .standUpStretch: return "Stretch"
        case .standingBlock: return "Stand"
        case .walkingPad: return "Walk"
        case .matMobility: return "Mat"
        case .balanceBoard: return "Balance"
        case .gripSets: return "Grips"
        case .lunch: return "Lunch"
        }
    }

    public var equipment: EquipmentKind? {
        switch self {
        case .boxBreathing, .squats, .standUpStretch, .lunch: return nil
        case .standingBlock: return .standingDesk
        case .walkingPad: return .walkingPad
        case .matMobility: return .pranaMat
        case .balanceBoard: return .balanceBoard
        case .gripSets: return .handGrips
        }
    }

    public var defaultMinutes: Int {
        switch self {
        case .boxBreathing: return 3
        case .squats: return 2
        case .standUpStretch: return 2
        case .standingBlock: return 30
        case .walkingPad: return 15
        case .matMobility: return 7
        case .balanceBoard: return 5
        case .gripSets: return 2
        case .lunch: return 30
        }
    }

    public var symbol: String {
        switch self {
        case .boxBreathing: return "square.dashed"
        case .squats: return "figure.strengthtraining.functional"
        case .standUpStretch: return "figure.flexibility"
        case .standingBlock: return "figure.stand"
        case .walkingPad: return "figure.walk"
        case .matMobility: return "figure.yoga"
        case .balanceBoard: return "figure.surfing"
        case .gripSets: return "hand.raised.fill"
        case .lunch: return "fork.knife"
        }
    }

    public var isMovement: Bool {
        switch self {
        case .boxBreathing, .lunch: return false
        default: return true
        }
    }

    public var isStanding: Bool {
        switch self {
        case .standingBlock, .walkingPad, .lunch: return true
        default: return false
        }
    }

    public var countsAsBreak: Bool {
        switch self {
        case .lunch, .standingBlock: return false
        default: return true
        }
    }
}

public enum EquipmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case standingDesk
    case walkingPad
    case pranaMat
    case balanceBoard
    case handGrips

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standingDesk: return "Standing desk"
        case .walkingPad: return "Walking pad"
        case .pranaMat: return "Prana mat"
        case .balanceBoard: return "Balance board"
        case .handGrips: return "Hand grips"
        }
    }

    public var defaultNote: String {
        switch self {
        case .standingDesk: return "Standing blocks, 30 min with a sit-down cue"
        case .walkingPad: return "Walking sessions, 15–30 min"
        case .pranaMat: return "Mobility sequences, 5–10 min"
        case .balanceBoard: return "Interval sets, 5 min"
        case .handGrips: return "Sets with rest timer, 2–3 min"
        }
    }

    public var breakKind: BreakKind {
        switch self {
        case .standingDesk: return .standingBlock
        case .walkingPad: return .walkingPad
        case .pranaMat: return .matMobility
        case .balanceBoard: return .balanceBoard
        case .handGrips: return .gripSets
        }
    }
}

public struct Equipment: Codable, Identifiable, Hashable, Sendable {
    public var id: EquipmentKind
    public var enabled: Bool
    public var note: String

    public init(_ id: EquipmentKind, enabled: Bool = true, note: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.note = note ?? id.defaultNote
    }

    public static var defaults: [Equipment] {
        EquipmentKind.allCases.map { Equipment($0, enabled: true) }
    }
}

// MARK: - Guidance

public enum GuidanceType: String, Codable, Sendable {
    case breathingSquare
    case repCounter
    case stepCards
    case countdown
    case poseSequence
    case intervalTimer
    case setsReps
    case lunchTimer
}

public struct ExerciseDef: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: BreakKind
    public var name: String
    public var equipment: EquipmentKind?
    public var minutesLow: Int
    public var minutesHigh: Int
    public var intensity: Int          // 1 = light, 2 = moderate, 3 = stronger
    public var steps: [String]
    public var guidance: GuidanceType
    /// Used by the rep counter and grip sessions.
    public var targetReps: Int?

    public init(id: String, kind: BreakKind, name: String, equipment: EquipmentKind? = nil,
                minutesLow: Int, minutesHigh: Int, intensity: Int, steps: [String],
                guidance: GuidanceType, targetReps: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.equipment = equipment
        self.minutesLow = minutesLow
        self.minutesHigh = minutesHigh
        self.intensity = intensity
        self.steps = steps
        self.guidance = guidance
        self.targetReps = targetReps
    }

    public func minutes(for gapMinutes: Int) -> Int {
        min(minutesHigh, max(minutesLow, min(gapMinutes, minutesHigh)))
    }
}

/// The exercise library is data, not code: edit this list to add exercises.
public enum ExerciseLibrary {
    public static let all: [ExerciseDef] = [
        ExerciseDef(id: "breathing-box", kind: .boxBreathing, name: "Box breathing",
                    minutesLow: 2, minutesHigh: 4, intensity: 1,
                    steps: ["Inhale 4", "Hold 4", "Exhale 4", "Hold 4"],
                    guidance: .breathingSquare),
        ExerciseDef(id: "squats-10", kind: .squats, name: "Squats",
                    minutesLow: 2, minutesHigh: 2, intensity: 3,
                    steps: ["Feet shoulder-width", "Sit back, chest up", "Two seconds up", "Ten slow reps"],
                    guidance: .repCounter, targetReps: 10),
        ExerciseDef(id: "stretch-neck-shoulders", kind: .standUpStretch, name: "Neck and shoulder release",
                    minutesLow: 2, minutesHigh: 2, intensity: 1,
                    steps: ["Stand tall, shoulders down", "Ear to shoulder, 20 s each side", "Roll shoulders back, 10 times", "Open the chest, 20 s"],
                    guidance: .stepCards),
        ExerciseDef(id: "stretch-hip-flexor", kind: .standUpStretch, name: "Hip flexor stretch",
                    minutesLow: 2, minutesHigh: 3, intensity: 1,
                    steps: ["Step one foot forward", "Tuck the back hip", "Reach the arm up, 30 s", "Switch sides"],
                    guidance: .stepCards),
        ExerciseDef(id: "standing-block", kind: .standingBlock, name: "Standing block",
                    equipment: .standingDesk, minutesLow: 30, minutesHigh: 30, intensity: 1,
                    steps: ["Desk to standing height", "Sit down cue at the end", "Keep moving your weight"],
                    guidance: .countdown),
        ExerciseDef(id: "walking-pad", kind: .walkingPad, name: "Walking pad",
                    equipment: .walkingPad, minutesLow: 15, minutesHigh: 30, intensity: 2,
                    steps: ["Start slow, 2 km/h", "Build to an easy pace", "Confirm at the end"],
                    guidance: .countdown),
        ExerciseDef(id: "mat-mobility", kind: .matMobility, name: "Mat mobility",
                    equipment: .pranaMat, minutesLow: 5, minutesHigh: 10, intensity: 2,
                    steps: ["Cat–cow, 8 breaths", "Child's pose, 45 s", "Thread the needle, 30 s each side", "Figure four, 40 s each side", "Hamstring reach, 30 s each side"],
                    guidance: .poseSequence),
        ExerciseDef(id: "mat-hips", kind: .matMobility, name: "Hips and low back",
                    equipment: .pranaMat, minutesLow: 5, minutesHigh: 8, intensity: 2,
                    steps: ["90/90 hip switch, 8 each side", "Glute bridge, 10 reps", "Supine twist, 45 s each side", "Knees to chest, 45 s"],
                    guidance: .poseSequence),
        ExerciseDef(id: "balance-intervals", kind: .balanceBoard, name: "Balance board intervals",
                    equipment: .balanceBoard, minutesLow: 5, minutesHigh: 5, intensity: 2,
                    steps: ["40 s rock, 20 s rest", "Five rounds", "Keep knees soft"],
                    guidance: .intervalTimer),
        ExerciseDef(id: "grips-sets", kind: .gripSets, name: "Grip sets",
                    equipment: .handGrips, minutesLow: 2, minutesHigh: 3, intensity: 3,
                    steps: ["10 reps per hand", "Rest 30 s", "Three sets"],
                    guidance: .setsReps, targetReps: 10),
        ExerciseDef(id: "lunch-away", kind: .lunch, name: "Lunch away from desk",
                    minutesLow: 30, minutesHigh: 45, intensity: 1,
                    steps: ["Leave the Mac", "Eat away from the screen", "Come back after 30 min"],
                    guidance: .lunchTimer),
    ]

    public static func forKind(_ kind: BreakKind) -> [ExerciseDef] {
        all.filter { $0.kind == kind }
    }

    public static func find(_ id: String) -> ExerciseDef? {
        all.first { $0.id == id }
    }

    public static func available(settings: AppSettings) -> [ExerciseDef] {
        let enabled = Set(settings.equipment.filter(\.enabled).map(\.id))
        let disabledExercises = Set(settings.disabledExerciseIDs)
        return all.filter { ex in
            if disabledExercises.contains(ex.id) { return false }
            if let eq = ex.equipment, !enabled.contains(eq) { return false }
            if ex.kind == .lunch { return true }
            return true
        }
    }
}

// MARK: - Calendar

public struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isBusy: Bool
    public var isDeclined: Bool
    public var attendeeCount: Int?
    public var isRecurring: Bool
    public var calendarID: String
    public var calendarTitle: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                isBusy: Bool = true, isDeclined: Bool = false, attendeeCount: Int? = nil,
                isRecurring: Bool = false, calendarID: String = "", calendarTitle: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.isDeclined = isDeclined
        self.attendeeCount = attendeeCount
        self.isRecurring = isRecurring
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
    }

    /// Events that actually block a break.
    public var blocksTime: Bool { !isAllDay && isBusy && !isDeclined }

    public var minutes: Int { TimeRange.minutesBetween(start, end) }
    public var range: TimeRange { TimeRange(start: start, end: end) }

    public func isActive(at date: Date) -> Bool { blocksTime && date >= start && date < end }
}

// MARK: - Work day and break records

public enum DayEdgeSource: String, Codable, Sendable {
    case auto, manual
}

public struct DayTargets: Codable, Hashable, Sendable {
    public var standingMinutes: Int
    public var breaks: Int
    public var breathing: Int
    public var lunchMinutes: Int
    public var reflection: Int

    public init(standingMinutes: Int = 120, breaks: Int = 6, breathing: Int = 2,
                lunchMinutes: Int = 30, reflection: Int = 1) {
        self.standingMinutes = standingMinutes
        self.breaks = breaks
        self.breathing = breathing
        self.lunchMinutes = lunchMinutes
        self.reflection = reflection
    }
}

public struct WorkDay: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var dayKey: String
    public var start: Date?
    public var end: Date?
    public var startSource: DayEdgeSource?
    public var endSource: DayEdgeSource?
    public var isOff: Bool
    public var targets: DayTargets

    // Live counters, updated by the app while the day runs.
    public var seatedMinutes: Int
    public var seatedSince: Date?
    public var longestSeatedMinutes: Int
    public var standingMinutes: Int
    public var walkingMinutes: Int
    public var lunchMinutes: Int
    public var meetingMinutes: Int
    public var longestBackToBackMinutes: Int
    public var lunchSkipped: Bool

    // Break engine runtime, persisted so a restart does not reset the day.
    public var nextBreakDue: Date?
    public var escalationStep: Int
    public var snoozeCount: Int
    public var snoozedUntil: Date?
    public var suggestedExerciseID: String?
    public var lastBreakKind: BreakKind?
    public var lastBreakEnd: Date?
    public var longBlockHandledAt: Date?
    public var windDownPromptedAt: Date?
    public var wrapUpPromptedAt: Date?
    public var focusUntil: Date?

    public init(dayKey: String, date: Date, targets: DayTargets = DayTargets()) {
        self.id = "day-" + dayKey
        self.dayKey = dayKey
        self.start = nil
        self.end = nil
        self.startSource = nil
        self.endSource = nil
        self.isOff = false
        self.targets = targets
        self.seatedMinutes = 0
        self.seatedSince = nil
        self.longestSeatedMinutes = 0
        self.standingMinutes = 0
        self.walkingMinutes = 0
        self.lunchMinutes = 0
        self.meetingMinutes = 0
        self.longestBackToBackMinutes = 0
        self.lunchSkipped = false
        self.nextBreakDue = nil
        self.escalationStep = 0
        self.snoozeCount = 0
        self.snoozedUntil = nil
        self.suggestedExerciseID = nil
        self.lastBreakKind = nil
        self.lastBreakEnd = nil
        self.longBlockHandledAt = nil
        self.windDownPromptedAt = nil
        self.wrapUpPromptedAt = nil
        self.focusUntil = nil
    }

    public var isRunning: Bool { start != nil && end == nil }
    public var isFinished: Bool { end != nil }
}

public enum BreakOutcome: String, Codable, Sendable {
    case planned, done, skipped, snoozed
}

public enum SkipReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case busy = "Busy"
    case notFeelingIt = "Not feeling it"
    case alreadyMoved = "Already moved"

    public var id: String { rawValue }
}

public enum VerificationMode: String, Codable, CaseIterable, Sendable {
    case autoConfirm = "Auto + confirm"
    case honorSystem = "Honor system"
}

public enum VerifiedBy: String, Codable, Sendable {
    case auto, confirm, honor
}

public struct BreakEvent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var dayKey: String
    public var exerciseID: String
    public var kind: BreakKind
    public var plannedAt: Date
    public var escalationStep: Int
    public var startedAt: Date?
    public var endedAt: Date?
    public var outcome: BreakOutcome
    public var skipReason: SkipReason?
    public var verifiedBy: VerifiedBy?
    public var minutes: Int
    public var needsConfirmation: Bool

    public init(id: String = IDGen.make("break"), dayKey: String, exerciseID: String,
                kind: BreakKind, plannedAt: Date, escalationStep: Int = 0,
                startedAt: Date? = nil, endedAt: Date? = nil, outcome: BreakOutcome = .planned,
                skipReason: SkipReason? = nil, verifiedBy: VerifiedBy? = nil,
                minutes: Int = 0, needsConfirmation: Bool = false) {
        self.id = id
        self.dayKey = dayKey
        self.exerciseID = exerciseID
        self.kind = kind
        self.plannedAt = plannedAt
        self.escalationStep = escalationStep
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.skipReason = skipReason
        self.verifiedBy = verifiedBy
        self.minutes = minutes
        self.needsConfirmation = needsConfirmation
    }

    public var isDone: Bool { outcome == .done }
}

// MARK: - Health

public struct HealthSample: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var stress: Int?
    public var bodyBattery: Int?
    public var steps: Int?
    public var heartRate: Int?

    public init(id: String = IDGen.make("hs"), at: Date, stress: Int? = nil,
                bodyBattery: Int? = nil, steps: Int? = nil, heartRate: Int? = nil) {
        self.id = id
        self.at = at
        self.stress = stress
        self.bodyBattery = bodyBattery
        self.steps = steps
        self.heartRate = heartRate
    }
}

public struct DailyHealth: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var dayKey: String
    public var sleepScore: Int?
    public var sleepMinutes: Int?
    public var hrvStatus: String?
    public var bodyBatteryWake: Int?
    public var restingHeartRate: Int?
    public var stressAverage: Int?
    public var bodyBatteryEnd: Int?

    public init(id: String = IDGen.make("dh"), dayKey: String, sleepScore: Int? = nil,
                sleepMinutes: Int? = nil, hrvStatus: String? = nil,
                bodyBatteryWake: Int? = nil, restingHeartRate: Int? = nil,
                stressAverage: Int? = nil, bodyBatteryEnd: Int? = nil) {
        self.id = id
        self.dayKey = dayKey
        self.sleepScore = sleepScore
        self.sleepMinutes = sleepMinutes
        self.hrvStatus = hrvStatus
        self.bodyBatteryWake = bodyBatteryWake
        self.restingHeartRate = restingHeartRate
        self.stressAverage = stressAverage
        self.bodyBatteryEnd = bodyBatteryEnd
    }
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
    public var stress: Int?
    public var bodyBattery: Int?
    public var steps: Int?
    public var heartRate: Int?
    public var sleepScore: Int?
    public var sleepMinutes: Int?
    public var hrvStatus: String?
    public var bodyBatteryWake: Int?
    public var lastSyncedAt: Date?
    public var isOffline: Bool

    public init(stress: Int? = nil, bodyBattery: Int? = nil, steps: Int? = nil,
                heartRate: Int? = nil, sleepScore: Int? = nil, sleepMinutes: Int? = nil,
                hrvStatus: String? = nil, bodyBatteryWake: Int? = nil,
                lastSyncedAt: Date? = nil, isOffline: Bool = true) {
        self.stress = stress
        self.bodyBattery = bodyBattery
        self.steps = steps
        self.heartRate = heartRate
        self.sleepScore = sleepScore
        self.sleepMinutes = sleepMinutes
        self.hrvStatus = hrvStatus
        self.bodyBatteryWake = bodyBatteryWake
        self.lastSyncedAt = lastSyncedAt
        self.isOffline = isOffline
    }
}

// MARK: - Mood

public enum MoodQuadrant: String, Codable, CaseIterable, Identifiable, Sendable {
    case tenseWired = "tense"
    case energizedFocused = "energized"
    case drainedFlat = "drained"
    case calmContent = "calm"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .tenseWired: return "Tense · wired"
        case .energizedFocused: return "Energized · focused"
        case .drainedFlat: return "Drained · flat"
        case .calmContent: return "Calm · content"
        }
    }

    public var shortName: String {
        switch self {
        case .tenseWired: return "Tense"
        case .energizedFocused: return "Energized"
        case .drainedFlat: return "Drained"
        case .calmContent: return "Calm"
        }
    }

    public var words: [String] {
        switch self {
        case .tenseWired: return ["Tense", "Wired", "Anxious", "Irritated", "Frustrated", "Overwhelmed"]
        case .energizedFocused: return ["Focused", "Upbeat", "Sharp", "Motivated", "Driven", "Engaged"]
        case .drainedFlat: return ["Drained", "Flat", "Foggy", "Weary", "Sluggish", "Detached"]
        case .calmContent: return ["Calm", "Content", "Steady", "Settled", "Relaxed", "At ease"]
        }
    }

    public static func quadrant(energy: Int, mood: Int) -> MoodQuadrant {
        switch (energy >= 3, mood >= 3) {
        case (true, true): return .energizedFocused
        case (true, false): return .tenseWired
        case (false, true): return .calmContent
        case (false, false): return .drainedFlat
        }
    }

    /// Closeness to a corner of the grid, 1 (centre) to 3 (corner). Used to fade heat-map cells.
    public static func intensity(energy: Int, mood: Int) -> Double {
        abs(Double(energy) - 2.5) + abs(Double(mood) - 2.5)
    }
}

public enum CheckInSource: String, Codable, Sendable {
    case morning, afterLunch, reflection, manual
}

public struct CheckIn: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var energy: Int
    public var mood: Int
    public var quadrant: MoodQuadrant
    public var word: String
    public var note: String
    public var source: CheckInSource

    public init(id: String = IDGen.make("checkin"), at: Date, energy: Int, mood: Int,
                word: String, note: String = "", source: CheckInSource) {
        self.id = id
        self.at = at
        self.energy = max(1, min(4, energy))
        self.mood = max(1, min(4, mood))
        self.quadrant = MoodQuadrant.quadrant(energy: self.energy, mood: self.mood)
        self.word = word
        self.note = note
        self.source = source
    }
}

// MARK: - Journal

public enum JournalKind: String, Codable, Sendable {
    case free, reflection
}

public struct PromptAnswer: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var prompt: String
    public var answer: String

    public init(id: String = IDGen.make("answer"), prompt: String, answer: String) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
    }
}

/// A snapshot of the day around a journal entry, captured at write time.
public struct EntryContext: Codable, Hashable, Sendable {
    public var stress: Int?
    public var bodyBattery: Int?
    public var breaksToday: Int
    public var standingMinutes: Int
    public var meetingHours: Double
    public var lastMeetingTitle: String?
    public var lastMeetingMinutes: Int?
    public var nextMeetingTitle: String?
    public var nextMeetingMinutes: Int?
    public var note: String?

    public init(stress: Int? = nil, bodyBattery: Int? = nil, breaksToday: Int = 0,
                standingMinutes: Int = 0, meetingHours: Double = 0,
                lastMeetingTitle: String? = nil, lastMeetingMinutes: Int? = nil,
                nextMeetingTitle: String? = nil, nextMeetingMinutes: Int? = nil,
                note: String? = nil) {
        self.stress = stress
        self.bodyBattery = bodyBattery
        self.breaksToday = breaksToday
        self.standingMinutes = standingMinutes
        self.meetingHours = meetingHours
        self.lastMeetingTitle = lastMeetingTitle
        self.lastMeetingMinutes = lastMeetingMinutes
        self.nextMeetingTitle = nextMeetingTitle
        self.nextMeetingMinutes = nextMeetingMinutes
        self.note = note
    }
}

public struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var kind: JournalKind
    public var text: String
    public var promptAnswers: [PromptAnswer]
    public var checkInID: String?
    public var context: EntryContext
    public var tags: [String]

    public init(id: String = IDGen.make("entry"), at: Date, kind: JournalKind, text: String,
                promptAnswers: [PromptAnswer] = [], checkInID: String? = nil,
                context: EntryContext = EntryContext(), tags: [String] = []) {
        self.id = id
        self.at = at
        self.kind = kind
        self.text = text
        self.promptAnswers = promptAnswers
        self.checkInID = checkInID
        self.context = context
        self.tags = tags
    }
}

// MARK: - Insights

public struct Insight: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var periodStart: Date
    public var periodEnd: Date
    public var periodLabel: String
    public var provider: String
    public var model: String
    public var observations: [String]
    public var suggestions: [String]
    public var basedOnDays: [String]
    public var question: String?
    public var createdAt: Date

    public init(id: String = IDGen.make("insight"), periodStart: Date, periodEnd: Date,
                periodLabel: String, provider: String, model: String,
                observations: [String], suggestions: [String],
                basedOnDays: [String], question: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodLabel = periodLabel
        self.provider = provider
        self.model = model
        self.observations = observations
        self.suggestions = suggestions
        self.basedOnDays = basedOnDays
        self.question = question
        self.createdAt = createdAt
    }
}

// MARK: - Standing-call rules

public enum StandingRuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimumLength
    case titleContains
    case attendeeCount
    case recurring

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimumLength: return "Minimum length"
        case .titleContains: return "Title contains"
        case .attendeeCount: return "Attendee count"
        case .recurring: return "Recurring events"
        }
    }
}

public enum StandingTarget: String, Codable, CaseIterable, Sendable {
    case desk, pad, either

    public var title: String {
        switch self {
        case .desk: return "Standing desk"
        case .pad: return "Walking pad"
        case .either: return "Either"
        }
    }
}

public struct StandingRule: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: StandingRuleKind
    public var isExclude: Bool
    public var enabled: Bool
    public var textValue: String
    public var numberValue: Int
    public var target: StandingTarget

    public init(id: String = IDGen.make("rule"), kind: StandingRuleKind, isExclude: Bool = false,
                enabled: Bool = true, textValue: String = "", numberValue: Int = 0,
                target: StandingTarget = .either) {
        self.id = id
        self.kind = kind
        self.isExclude = isExclude
        self.enabled = enabled
        self.textValue = textValue
        self.numberValue = numberValue
        self.target = target
    }

    public var summary: String {
        switch kind {
        case .minimumLength: return "\(numberValue) min or longer"
        case .titleContains: return textValue
        case .attendeeCount: return "\(numberValue) or more people"
        case .recurring: return "Only recurring meetings"
        }
    }

    public func matches(_ event: CalendarEvent) -> Bool {
        guard enabled else { return false }
        switch kind {
        case .minimumLength:
            return event.minutes >= numberValue
        case .titleContains:
            let needles = textValue.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }.filter { !$0.isEmpty }
            let hay = event.title.lowercased()
            return needles.contains { hay.contains($0) }
        case .attendeeCount:
            return (event.attendeeCount ?? 0) >= numberValue
        case .recurring:
            return event.isRecurring
        }
    }

    public static var defaults: [StandingRule] {
        [
            StandingRule(kind: .titleContains, textValue: "standup, 1:1, sync", target: .pad),
            StandingRule(kind: .attendeeCount, numberValue: 6, target: .desk),
            StandingRule(kind: .minimumLength, enabled: false, numberValue: 30, target: .either),
            StandingRule(kind: .recurring, enabled: false, target: .either),
            StandingRule(kind: .titleContains, isExclude: true, textValue: "workshop, design review", target: .either),
        ]
    }
}

// MARK: - Plans

public enum PlanItemKind: String, Codable, Sendable {
    case meeting, breakOpportunity, lunch, standingSuggestion, windDown
}

public struct PlanItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: PlanItemKind
    public var start: Date
    public var end: Date
    public var title: String
    public var detail: String
    public var chip: String
    public var chipStyle: String  // "plain", "warn", "calm", "accent"

    public init(id: String = IDGen.make("plan"), kind: PlanItemKind, start: Date, end: Date,
                title: String, detail: String = "", chip: String = "", chipStyle: String = "plain") {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.title = title
        self.detail = detail
        self.chip = chip
        self.chipStyle = chipStyle
    }
}

public struct StandingSuggestion: Identifiable, Hashable, Sendable {
    public var id: String
    public var event: CalendarEvent
    public var target: StandingTarget
    public var rule: StandingRule

    public init(id: String = IDGen.make("suggest"), event: CalendarEvent, target: StandingTarget, rule: StandingRule) {
        self.id = id
        self.event = event
        self.target = target
        self.rule = rule
    }

    public var minutesBefore: Int { 2 }
    public var suggestAt: Date { event.start.adding(minutes: -2) }
}

public struct DayPlan: Sendable {
    public var events: [CalendarEvent]
    public var workStart: Date
    public var workEnd: Date
    public var meetingMinutes: Int
    public var longestMeetingMinutes: Int
    public var longestBackToBackMinutes: Int
    public var freeGaps: [TimeRange]
    public var lunchWindow: TimeRange?
    public var lunchGap: TimeRange?
    public var standingSuggestions: [StandingSuggestion]
    public var timeline: [PlanItem]

    public var meetingHours: Double { Double(meetingMinutes) / 60.0 }

    public func gap(at date: Date) -> TimeRange? {
        freeGaps.first { $0.contains(date) }
    }

    public func nextGap(after date: Date) -> TimeRange? {
        freeGaps.filter { $0.start > date }.min { $0.start < $1.start }
    }

    public func currentMeeting(at date: Date) -> CalendarEvent? {
        events.first { $0.isActive(at: date) }
    }

    public func nextMeeting(after date: Date) -> CalendarEvent? {
        events.filter { $0.start > date }.min { $0.start < $1.start }
    }
}

// MARK: - App state

/// Consumes one array element of any shape so decoding can continue past it.
private struct SkippedRecord: Decodable {
    init(from decoder: Decoder) throws {}
}

public struct AppState: Codable, Sendable {
    public var version: Int
    public var settings: AppSettings
    public var days: [WorkDay]
    public var breaks: [BreakEvent]
    public var checkIns: [CheckIn]
    public var journal: [JournalEntry]
    public var insights: [Insight]
    public var healthDaily: [DailyHealth]
    public var healthSamples: [HealthSample]
    public var calendarSnapshots: [String: [CalendarEvent]]
    public var offDays: [String]
    public var lastGarminSync: Date?
    public var lastWeeklyInsightAt: Date?
    public var lastWeeklyInsightWeek: String?
    public var lastBackupAt: Date?
    /// Records skipped while decoding. Not persisted; `Store.load` uses it to
    /// keep the original file before anything overwrites it.
    public var decodeIssues = 0

    public init(settings: AppSettings = AppSettings()) {
        self.version = 1
        self.settings = settings
        self.days = []
        self.breaks = []
        self.checkIns = []
        self.journal = []
        self.insights = []
        self.healthDaily = []
        self.healthSamples = []
        self.calendarSnapshots = [:]
        self.offDays = []
        self.lastGarminSync = nil
        self.lastWeeklyInsightAt = nil
        self.lastWeeklyInsightWeek = nil
        self.lastBackupAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case version, settings, days, breaks, checkIns, journal, insights
        case healthDaily, healthSamples, calendarSnapshots, offDays
        case lastGarminSync, lastWeeklyInsightAt, lastWeeklyInsightWeek, lastBackupAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppState()
        var issues = 0
        // One unreadable record must not empty its whole collection: decode
        // element by element, skip what fails, and count it.
        func list<T: Decodable>(_ key: CodingKeys) -> [T] {
            guard c.contains(key) else { return [] }
            guard var items = try? c.nestedUnkeyedContainer(forKey: key) else {
                issues += 1
                return []
            }
            var out: [T] = []
            while !items.isAtEnd {
                if let item = try? items.decode(T.self) {
                    out.append(item)
                } else {
                    issues += 1
                    guard (try? items.decode(SkippedRecord.self)) != nil else { break }
                }
            }
            return out
        }
        version = (try? c.decode(Int.self, forKey: .version)) ?? d.version
        if c.contains(.settings) {
            if let decoded = try? c.decode(AppSettings.self, forKey: .settings) {
                settings = decoded
            } else {
                settings = d.settings
                issues += 1
            }
        } else {
            settings = d.settings
        }
        days = list(.days)
        breaks = list(.breaks)
        checkIns = list(.checkIns)
        journal = list(.journal)
        insights = list(.insights)
        healthDaily = list(.healthDaily)
        healthSamples = list(.healthSamples)
        if c.contains(.calendarSnapshots) {
            if let decoded = try? c.decode([String: [CalendarEvent]].self, forKey: .calendarSnapshots) {
                calendarSnapshots = decoded
            } else {
                calendarSnapshots = [:]
                issues += 1
            }
        } else {
            calendarSnapshots = [:]
        }
        offDays = list(.offDays)
        lastGarminSync = try? c.decode(Date.self, forKey: .lastGarminSync)
        lastWeeklyInsightAt = try? c.decode(Date.self, forKey: .lastWeeklyInsightAt)
        lastWeeklyInsightWeek = try? c.decode(String.self, forKey: .lastWeeklyInsightWeek)
        lastBackupAt = try? c.decode(Date.self, forKey: .lastBackupAt)
        decodeIssues = issues
    }

    // MARK: Lookups

    public func day(_ dayKey: String) -> WorkDay? {
        days.first { $0.dayKey == dayKey }
    }

    public func breaks(on dayKey: String) -> [BreakEvent] {
        breaks.filter { $0.dayKey == dayKey }
    }

    /// Midnight to midnight for a day key. Comparing dates against this is far
    /// cheaper than deriving a day key for every record.
    public static func bounds(of dayKey: String, calendar: Calendar = .current) -> Range<Date>? {
        guard let start = DayKey.date(from: dayKey, calendar: calendar) else { return nil }
        return start..<DayKey.adding(days: 1, to: start, calendar: calendar)
    }

    public func checkIns(on dayKey: String) -> [CheckIn] {
        guard let bounds = AppState.bounds(of: dayKey) else { return [] }
        return checkIns.filter { bounds.contains($0.at) }.sorted { $0.at < $1.at }
    }

    public func journal(on dayKey: String) -> [JournalEntry] {
        guard let bounds = AppState.bounds(of: dayKey) else { return [] }
        return journal.filter { bounds.contains($0.at) }.sorted { $0.at < $1.at }
    }

    public func healthSamples(on dayKey: String) -> [HealthSample] {
        guard let bounds = AppState.bounds(of: dayKey) else { return [] }
        return healthSamples.filter { bounds.contains($0.at) }.sorted { $0.at < $1.at }
    }

    public func healthSample(at date: Date) -> HealthSample? {
        let candidates = healthSamples.filter { abs($0.at.timeIntervalSince(date)) < 20 * 60 }
        return candidates.min { abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date)) }
    }

    public func latestHealthSample() -> HealthSample? {
        healthSamples.max { $0.at < $1.at }
    }

    public func dailyHealth(_ dayKey: String) -> DailyHealth? {
        healthDaily.first { $0.dayKey == dayKey }
    }

    public func planEvents(for dayKey: String) -> [CalendarEvent]? {
        calendarSnapshots[dayKey]
    }

    public mutating func setPlanEvents(_ events: [CalendarEvent], for dayKey: String) {
        if calendarSnapshots[dayKey] == events { return }
        calendarSnapshots[dayKey] = events
        // Keep roughly 15 months of calendar snapshots.
        if calendarSnapshots.count > 460 {
            let cutoff = DayKey.make(Date().adding(days: -450))
            calendarSnapshots = calendarSnapshots.filter { $0.key >= cutoff }
        }
    }

    public func isOffDay(_ dayKey: String) -> Bool {
        offDays.contains(dayKey) || (day(dayKey)?.isOff ?? false)
    }
}
