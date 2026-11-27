import Foundation

// MARK: - Work hours

public struct DayHoursSetting: Codable, Identifiable, Hashable, Sendable {
    public var weekday: Int      // 1 = Sunday ... 7 = Saturday
    public var enabled: Bool
    public var start: TimeOfDay
    public var end: TimeOfDay

    public var id: Int { weekday }

    public init(weekday: Int, enabled: Bool, start: TimeOfDay, end: TimeOfDay) {
        self.weekday = weekday
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    public var name: String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[max(0, min(7, weekday))]
    }

    public var shortName: String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[max(0, min(7, weekday))]
    }

    public static var defaults: [DayHoursSetting] {
        (1...7).map { weekday in
            let works = (2...6).contains(weekday)
            return DayHoursSetting(weekday: weekday, enabled: works,
                                   start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 17, minute: 30))
        }
    }
}

// MARK: - AI

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .custom: return "Custom"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openai: return "gpt-4o-mini"
        case .custom: return ""
        }
    }

    public var keychainAccount: String { "ai." + rawValue + ".key" }
}

public struct AISettings: Codable, Equatable, Sendable {
    public var provider: AIProvider = .anthropic
    public var model: String = AIProvider.anthropic.defaultModel
    public var baseURL: String = ""
    public var shareJournalText: Bool = true
    public var shareCalendarTitles: Bool = false
    public var weeklyInsights: Bool = true
    public var customModel: String = ""

    public init() {}

    public var effectiveModel: String {
        if provider == .custom { return customModel.isEmpty ? model : customModel }
        return model.isEmpty ? provider.defaultModel : model
    }
}

// MARK: - Garmin

public struct GarminSettings: Codable, Equatable, Sendable {
    public var email: String = ""
    public var stressHigh: Int = 55
    public var batteryLow: Int = 30
    public var useSleepAndHRV: Bool = true
    public var connected: Bool = false
    public var lastLoginAt: Date?
    public var lastError: String?
    public var syncMinutes: Int = 15
    public var walkStepsThreshold: Int = 150

    public init() {}
}

// MARK: - Appearance and hotkey

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public struct HotkeySetting: Codable, Equatable, Sendable {
    /// Virtual key code (Carbon), default J = 38.
    public var keyCode: UInt32 = 38
    public var command: Bool = true
    public var option: Bool = true
    public var control: Bool = false
    public var shift: Bool = false
    public var display: String = "⌥⌘J"

    public init() {}
}

// MARK: - Settings

public struct AppSettings: Codable, Equatable, Sendable {
    // Schedule
    public var dayHours: [DayHoursSetting] = DayHoursSetting.defaults
    public var autoStartDay: Bool = true
    public var windDown: TimeOfDay = TimeOfDay(hour: 17, minute: 15)
    public var offerWrapUpYesterday: Bool = true
    public var offDays: [String] = []          // explicit ISO day keys

    // Breaks
    public var moveIntervalMin: Int = 45
    public var moveIntervalMax: Int = 60
    public var standingTargetMinutes: Int = 120
    public var breaksTarget: Int = 6
    public var breathingTarget: Int = 2
    public var lunchTargetMinutes: Int = 30
    public var lunchWindowStart: TimeOfDay = TimeOfDay(hour: 11, minute: 30)
    public var lunchWindowEnd: TimeOfDay = TimeOfDay(hour: 14)
    public var escalationNotificationAfter: Int = 5
    public var escalationOverlayAfter: Int = 10
    public var snoozeLimit: Int = 2
    public var snoozeMinutes: Int = 10
    public var verification: VerificationMode = .autoConfirm
    public var micIgnoreBundleIDs: [String] = [
        "com.apple.VoiceInput",
    ]
    public var openMicCapMinutes: Int = 90
    public var pauseOnMedia: Bool = true
    public var focusLengths: [Int] = [60, 120]

    // Equipment and exercises
    public var equipment: [Equipment] = Equipment.defaults
    public var disabledExerciseIDs: [String] = []

    // Calendar
    public var selectedCalendarIDs: [String] = []
    public var calendarAccessRequested: Bool = false
    public var longMeetingMinutes: Int = 60
    public var backToBackMinutes: Int = 90
    public var standingRules: [StandingRule] = StandingRule.defaults
    public var ignoreAllDay: Bool = true

    // Journal
    public var checkInMorning: Bool = true
    public var checkInAfterLunch: Bool = true
    public var checkInEndOfDay: Bool = true
    public var prompts: [String] = AppSettings.defaultPrompts
    public var hotkey: HotkeySetting = HotkeySetting()
    public var lastExportFolder: String = ""

    // AI
    public var ai: AISettings = AISettings()

    // Garmin
    public var garmin: GarminSettings = GarminSettings()

    // General
    public var launchAtLogin: Bool = false
    public var sounds: Bool = true
    public var appearance: AppearanceMode = .system
    public var showDemoData: Bool = false

    public init() {}

    public static let defaultPrompts = [
        "What drained you today?",
        "What frustrated you, and was it in your control?",
        "What are you struggling with right now?",
        "What went well, even if small?",
        "What would make tomorrow 10% better?",
        "Where did you spend energy that did not matter?",
        "What did you avoid today, and why?",
        "When did you feel most like yourself?",
    ]

    // MARK: Derived helpers

    public func schedule(for date: Date, calendar: Calendar = .current) -> DayHoursSetting? {
        let weekday = DayKey.weekday(date, calendar: calendar)
        let setting = dayHours.first { $0.weekday == weekday }
        guard let setting, setting.enabled else { return nil }
        return setting
    }

    public func isConfiguredOffDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        if offDays.contains(DayKey.make(date, calendar: calendar)) { return true }
        return schedule(for: date, calendar: calendar) == nil
    }

    public func workRange(for date: Date, calendar: Calendar = .current) -> TimeRange? {
        guard let s = schedule(for: date, calendar: calendar) else { return nil }
        let start = s.start.date(on: date, calendar: calendar)
        let end = s.end.date(on: date, calendar: calendar)
        return TimeRange(start: start, end: end)
    }

    public var enabledEquipment: Set<EquipmentKind> {
        Set(equipment.filter(\.enabled).map(\.id))
    }

    public func isEquipmentEnabled(_ kind: EquipmentKind) -> Bool {
        equipment.first { $0.id == kind }?.enabled ?? false
    }

    public mutating func setEquipment(_ kind: EquipmentKind, enabled: Bool) {
        if let idx = equipment.firstIndex(where: { $0.id == kind }) {
            equipment[idx].enabled = enabled
        } else {
            equipment.append(Equipment(kind, enabled: enabled))
        }
    }

    public var targets: DayTargets {
        DayTargets(standingMinutes: standingTargetMinutes, breaks: breaksTarget,
                   breathing: breathingTarget, lunchMinutes: lunchTargetMinutes, reflection: 1)
    }

    // MARK: Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case dayHours, autoStartDay, windDown, offerWrapUpYesterday, offDays
        case moveIntervalMin, moveIntervalMax, standingTargetMinutes, breaksTarget, breathingTarget
        case lunchTargetMinutes, lunchWindowStart, lunchWindowEnd
        case escalationNotificationAfter, escalationOverlayAfter, snoozeLimit, snoozeMinutes
        case verification, micIgnoreBundleIDs, openMicCapMinutes, pauseOnMedia, focusLengths
        case equipment, disabledExerciseIDs, selectedCalendarIDs, calendarAccessRequested
        case longMeetingMinutes, backToBackMinutes, standingRules, ignoreAllDay
        case checkInMorning, checkInAfterLunch, checkInEndOfDay, prompts, hotkey, lastExportFolder
        case ai, garmin, launchAtLogin, sounds, appearance, showDemoData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        dayHours = (try? c.decode([DayHoursSetting].self, forKey: .dayHours)) ?? d.dayHours
        autoStartDay = (try? c.decode(Bool.self, forKey: .autoStartDay)) ?? d.autoStartDay
        windDown = (try? c.decode(TimeOfDay.self, forKey: .windDown)) ?? d.windDown
        offerWrapUpYesterday = (try? c.decode(Bool.self, forKey: .offerWrapUpYesterday)) ?? d.offerWrapUpYesterday
        offDays = (try? c.decode([String].self, forKey: .offDays)) ?? d.offDays
        moveIntervalMin = (try? c.decode(Int.self, forKey: .moveIntervalMin)) ?? d.moveIntervalMin
        moveIntervalMax = (try? c.decode(Int.self, forKey: .moveIntervalMax)) ?? d.moveIntervalMax
        standingTargetMinutes = (try? c.decode(Int.self, forKey: .standingTargetMinutes)) ?? d.standingTargetMinutes
        breaksTarget = (try? c.decode(Int.self, forKey: .breaksTarget)) ?? d.breaksTarget
        breathingTarget = (try? c.decode(Int.self, forKey: .breathingTarget)) ?? d.breathingTarget
        lunchTargetMinutes = (try? c.decode(Int.self, forKey: .lunchTargetMinutes)) ?? d.lunchTargetMinutes
        lunchWindowStart = (try? c.decode(TimeOfDay.self, forKey: .lunchWindowStart)) ?? d.lunchWindowStart
        lunchWindowEnd = (try? c.decode(TimeOfDay.self, forKey: .lunchWindowEnd)) ?? d.lunchWindowEnd
        escalationNotificationAfter = (try? c.decode(Int.self, forKey: .escalationNotificationAfter)) ?? d.escalationNotificationAfter
        escalationOverlayAfter = (try? c.decode(Int.self, forKey: .escalationOverlayAfter)) ?? d.escalationOverlayAfter
        snoozeLimit = (try? c.decode(Int.self, forKey: .snoozeLimit)) ?? d.snoozeLimit
        snoozeMinutes = (try? c.decode(Int.self, forKey: .snoozeMinutes)) ?? d.snoozeMinutes
        verification = (try? c.decode(VerificationMode.self, forKey: .verification)) ?? d.verification
        micIgnoreBundleIDs = (try? c.decode([String].self, forKey: .micIgnoreBundleIDs)) ?? d.micIgnoreBundleIDs
        openMicCapMinutes = (try? c.decode(Int.self, forKey: .openMicCapMinutes)) ?? d.openMicCapMinutes
        pauseOnMedia = (try? c.decode(Bool.self, forKey: .pauseOnMedia)) ?? d.pauseOnMedia
        focusLengths = (try? c.decode([Int].self, forKey: .focusLengths)) ?? d.focusLengths
        equipment = (try? c.decode([Equipment].self, forKey: .equipment)) ?? d.equipment
        disabledExerciseIDs = (try? c.decode([String].self, forKey: .disabledExerciseIDs)) ?? d.disabledExerciseIDs
        selectedCalendarIDs = (try? c.decode([String].self, forKey: .selectedCalendarIDs)) ?? d.selectedCalendarIDs
        calendarAccessRequested = (try? c.decode(Bool.self, forKey: .calendarAccessRequested)) ?? d.calendarAccessRequested
        longMeetingMinutes = (try? c.decode(Int.self, forKey: .longMeetingMinutes)) ?? d.longMeetingMinutes
        backToBackMinutes = (try? c.decode(Int.self, forKey: .backToBackMinutes)) ?? d.backToBackMinutes
        standingRules = (try? c.decode([StandingRule].self, forKey: .standingRules)) ?? d.standingRules
        ignoreAllDay = (try? c.decode(Bool.self, forKey: .ignoreAllDay)) ?? d.ignoreAllDay
        checkInMorning = (try? c.decode(Bool.self, forKey: .checkInMorning)) ?? d.checkInMorning
        checkInAfterLunch = (try? c.decode(Bool.self, forKey: .checkInAfterLunch)) ?? d.checkInAfterLunch
        checkInEndOfDay = (try? c.decode(Bool.self, forKey: .checkInEndOfDay)) ?? d.checkInEndOfDay
        prompts = (try? c.decode([String].self, forKey: .prompts)) ?? d.prompts
        hotkey = (try? c.decode(HotkeySetting.self, forKey: .hotkey)) ?? d.hotkey
        lastExportFolder = (try? c.decode(String.self, forKey: .lastExportFolder)) ?? d.lastExportFolder
        ai = (try? c.decode(AISettings.self, forKey: .ai)) ?? d.ai
        garmin = (try? c.decode(GarminSettings.self, forKey: .garmin)) ?? d.garmin
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        sounds = (try? c.decode(Bool.self, forKey: .sounds)) ?? d.sounds
        appearance = (try? c.decode(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        showDemoData = (try? c.decode(Bool.self, forKey: .showDemoData)) ?? d.showDemoData
    }

    // Tolerant decoding for nested settings too.

    public static func decodeAISettings(from decoder: Decoder) -> AISettings {
        let d = AISettings()
        guard let c = try? decoder.container(keyedBy: DynamicKey.self) else { return d }
        var s = d
        s.provider = (try? c.decode(AIProvider.self, forKey: DynamicKey("provider"))) ?? d.provider
        s.model = (try? c.decode(String.self, forKey: DynamicKey("model"))) ?? d.model
        s.baseURL = (try? c.decode(String.self, forKey: DynamicKey("baseURL"))) ?? d.baseURL
        s.shareJournalText = (try? c.decode(Bool.self, forKey: DynamicKey("shareJournalText"))) ?? d.shareJournalText
        s.shareCalendarTitles = (try? c.decode(Bool.self, forKey: DynamicKey("shareCalendarTitles"))) ?? d.shareCalendarTitles
        s.weeklyInsights = (try? c.decode(Bool.self, forKey: DynamicKey("weeklyInsights"))) ?? d.weeklyInsights
        s.customModel = (try? c.decode(String.self, forKey: DynamicKey("customModel"))) ?? d.customModel
        return s
    }
}

public struct DynamicKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?
    public init(_ s: String) { stringValue = s }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
}

// Tolerant decoding helpers for nested settings.
extension AISettings {
    public init(from decoder: Decoder) throws {
        self = AppSettings.decodeAISettings(from: decoder)
    }
}
