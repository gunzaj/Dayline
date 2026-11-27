import AppKit
import DaylineCore
import Foundation
import SwiftUI

enum WindowRoute: String, Identifiable {
    case main, journal, reflection, summaries, settings, plan, checkIn, session, insight

    var id: String { rawValue }
}

/// The sections of the desktop window's sidebar.
enum MainSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case plan = "Today's plan"
    case activities = "Activities"
    case journal = "Journal"
    case summaries = "Summaries"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .plan: return "calendar.day.timeline.left"
        case .activities: return "figure.walk"
        case .journal: return "book.closed"
        case .summaries: return "chart.bar"
        }
    }
}

enum SummaryTab: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case year = "Year"
    var id: String { rawValue }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case breaks = "Breaks"
    case equipment = "Equipment"
    case calendar = "Calendar"
    case garmin = "Garmin"
    case journal = "Journal"
    case ai = "AI"
    case general = "General"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .schedule: return "calendar.day.timeline.left"
        case .breaks: return "figure.walk"
        case .equipment: return "dumbbell"
        case .calendar: return "calendar"
        case .garmin: return "waveform.path.ecg"
        case .journal: return "book.closed"
        case .ai: return "sparkles"
        case .general: return "gearshape"
        }
    }
}

struct BreakSession: Identifiable {
    var id: String
    var eventID: String
    var exercise: ExerciseDef
    var kind: BreakKind
    var startedAt: Date
    var endsAt: Date
    var plannedAt: Date
    var meetingTitle: String?
    var isLunch: Bool

    var secondsRemaining: Int { max(0, Int(endsAt.timeIntervalSinceNow.rounded())) }
    var minutes: Int { max(1, Int(endsAt.timeIntervalSince(startedAt) / 60)) }
    var progress: Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(startedAt) / total))
    }
}

struct GarminMFARequest: Identifiable {
    var id = UUID()
    var clientState: String
}

struct PendingConfirmation: Identifiable {
    var id: String { eventID }
    var eventID: String
    var kind: BreakKind
    /// The activity's own name (custom equipment), or the kind's.
    var title: String
    var minutes: Int
    var prompt: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var state: AppState
    @Published private(set) var now = Date()
    @Published private(set) var decision: BreakDecision
    @Published private(set) var health = HealthSnapshot()
    @Published private(set) var media = MediaState.clear
    @Published private(set) var session: BreakSession?
    @Published private(set) var sessionSecondsRemaining = 0
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var toast: String?
    /// The last save failure, if the most recent save did not succeed.
    @Published private(set) var storageError: String?
    @Published var garminBusy = false
    @Published var garminMFA: GarminMFARequest?
    @Published var garminError: String?
    @Published var aiBusy = false
    @Published var aiError: String?
    @Published var summaryTab: SummaryTab = .day
    @Published var settingsTab: SettingsTab = .schedule
    @Published var mainSection: MainSection = .overview
    /// The day shown in the activity editor.
    @Published var activitiesDayKey: String = DayKey.make(Date())
    @Published var reflectionDayKey: String = DayKey.make(Date())
    @Published var pendingWrapUpDay: String?
    @Published var isPopoverOpen = false
    @Published var lastSyncedText = ""

    /// Why the next check-in window opens. Read and reset by the window code.
    var nextCheckInSource: CheckInSource = .manual

    var requestWindow: ((WindowRoute) -> Void)?
    var closePopover: (() -> Void)?
    var onDecisionChanged: (() -> Void)?

    let store: Store
    let calendarService = CalendarService()
    let notifications = NotificationService()
    let hotKeys = HotKeyManager()

    private let idleMonitor = IdleMonitor()
    private let mediaMonitor = MediaMonitor()
    private var timer: Timer?
    private var lastTick = Date()
    private var lastCalendarRefresh: Date = .distantPast
    private var lastGarminSync: Date = .distantPast
    private var lastPromptedDue: Date?
    private var lastOverlayDue: Date?
    private var lastStandingNoticeEventID: String?
    private var lastSaved = Date()
    private var dirty = false
    private var sessionIdleSeconds: TimeInterval = 0
    private var sessionStepBaseline: Int?
    private var lastMediaSample: Date = .distantPast
    private var lastMorningCheckInDay: String?
    private var seatedClock = SeatedClock()
    private var windDownNotBefore: Date?

    /// Demo runs get their own folder so sample data never touches real data.
    nonisolated static var isDemoRun: Bool { ProcessInfo.processInfo.environment["DAYLINE_DEMO"] == "1" }

    nonisolated static func defaultStore() -> Store {
        isDemoRun ? Store(directory: Store.defaultDirectory(named: "Dayline-Demo")) : Store()
    }

    init(store: Store = AppModel.defaultStore()) {
        self.store = store
        var loaded = store.load()
        if AppModel.isDemoRun && loaded.days.isEmpty {
            DemoData.seed(into: &loaded)
        }
        self.state = loaded
        let today = loaded.day(DayKey.make(Date()))
        let plan = AppModel.plan(for: Date(), events: loaded.calendarSnapshots[DayKey.make(Date())] ?? [],
                                 settings: loaded.settings)
        self.decision = BreakEngine.decide(now: Date(), day: today, settings: loaded.settings,
                                          plan: plan, health: HealthSnapshot(), media: .clear,
                                          activeBreak: false)
        SettingsRef.ignoreBundleIDs = loaded.settings.micIgnoreBundleIDs
        notifications.onStartBreak = { [weak self] in self?.startBreakNow() }
        notifications.onSnooze = { [weak self] in self?.snoozeBreak() }
        notifications.onSkip = { [weak self] in self?.skipBreak(reason: .busy) }
        notifications.onWindDownLater = { [weak self] in self?.postponeWindDown() }
        notifications.onOpenReflection = { [weak self] in
            self?.openReflection()
        }
        notifications.onTakeStandingCall = { [weak self] in self?.takeStandingCall() }
        calendarService.onChange = { [weak self] in
            Task { @MainActor in self?.refreshCalendar(force: true) }
        }
        registerHotKey()
        self.health = snapshotHealth()
        self.toast = store.loadWarning
        self.lastSyncedText = relativeSyncText()
    }

    // MARK: - Lifecycle

    func start() {
        notifications.configure(snoozeMinutes: state.settings.snoozeMinutes)
        GarminClient.removeLegacyTokenStore(storeDirectory: store.directory)
        applyAppearance()
        refreshCalendar(force: true)
        evaluate(forceTick: true)
        timer?.invalidate()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        requestCalendarIfNeeded()
        syncGarminIfPossible(force: false)
        restorePendingWrapUp()
    }

    /// The live midnight rollover is missed when the app was not running
    /// overnight, so look for an unreflected previous workday at launch too.
    private func restorePendingWrapUp() {
        guard pendingWrapUpDay == nil, state.settings.offerWrapUpYesterday else { return }
        let today = todayKey()
        let recent = DayKey.make(now.adding(days: -4))
        guard let previous = state.days.last(where: { $0.dayKey < today && $0.start != nil && !$0.isOff }),
              previous.dayKey >= recent,
              !Summarizer.metrics(dayKey: previous.dayKey, state: state).hasReflection else { return }
        pendingWrapUpDay = previous.dayKey
    }

    private static func plan(for date: Date, events: [CalendarEvent], settings: AppSettings) -> DayPlan? {
        Planner.plan(events: events, date: date, settings: settings)
    }

    func todayKey() -> String { DayKey.make(now) }

    var today: WorkDay? { state.day(todayKey()) }

    var settings: AppSettings { state.settings }

    var todayPlan: DayPlan? {
        let key = todayKey()
        let events = state.calendarSnapshots[key] ?? []
        return Planner.plan(events: events, date: now, settings: state.settings)
    }

    var todayMetrics: DayMetrics { Summarizer.metrics(dayKey: todayKey(), state: state) }

    var todayStandingSuggestion: StandingSuggestion? {
        guard let plan = todayPlan else { return nil }
        return plan.standingSuggestions.first { $0.event.start > now && $0.event.start.timeIntervalSince(now) <= 15 * 60 }
    }

    var pendingBreaksCount: Int {
        state.breaks.filter { $0.outcome == .planned }.count
    }

    // MARK: - Tick

    func evaluate(forceTick: Bool = false) {
        let previous = now
        now = Date()
        let delta = max(0, now.timeIntervalSince(previous))
        rolloverDayIfNeeded(previous: previous)
        autoStartIfNeeded()
        accumulateSeated(delta: delta)
        refreshMedia()
        updateSession(delta: delta)
        if forceTick || now.timeIntervalSince(lastCalendarRefresh) > 180 {
            refreshCalendar(force: false)
        }
        recomputeDecision()
        escalateIfNeeded()
        checkWindDown()
        checkStandingSuggestion()
        if now.timeIntervalSince(lastGarminSync) > TimeInterval(max(5, state.settings.garmin.syncMinutes) * 60) {
            syncGarminIfPossible(force: false)
        }
        if dirty && now.timeIntervalSince(lastSaved) > 20 {
            save()
        }
        updateHealthSnapshot()
        objectWillChange.send()
        onDecisionChanged?()
    }

    private func rolloverDayIfNeeded(previous: Date) {
        let previousKey = DayKey.make(previous)
        guard previousKey != todayKey() else { return }
        lastPromptedDue = nil
        lastOverlayDue = nil
        pendingConfirmation = nil
        if let yesterday = state.day(previousKey),
           !yesterday.isOff,
           state.settings.offerWrapUpYesterday,
           !Summarizer.metrics(dayKey: previousKey, state: state).hasReflection,
           state.settings.schedule(for: DayKey.date(from: previousKey) ?? previous) != nil {
            pendingWrapUpDay = previousKey
        }
        refreshCalendar(force: true)
    }

    private func autoStartIfNeeded() {
        guard state.settings.autoStartDay else { return }
        let key = todayKey()
        // A day record can exist before the day starts (marked off, or ended).
        let existing = state.day(key)
        guard existing?.start == nil, existing?.isOff != true else { return }
        guard let range = state.settings.workRange(for: now) else { return }
        guard now >= range.start, now < range.end else { return }
        guard !state.settings.isConfiguredOffDay(now) else { return }
        guard idleMonitor.idleSeconds() < 10 * 60 else { return }
        startDay(auto: true)
    }

    private func accumulateSeated(delta: TimeInterval) {
        guard var day = today, day.start != nil, day.end == nil else { return }
        let idle = idleMonitor.idleSeconds()
        guard session == nil else {
            // During a break, time asleep or idle is time away from the keyboard.
            if SeatedClock.wasSuspended(delta) || idle > 90 { sessionIdleSeconds += delta }
            return
        }
        guard !day.isOff else { return }
        let minutes = seatedClock.advance(by: delta, idleSeconds: idle)
        guard minutes > 0 else { return }
        day.seatedMinutes += minutes
        if day.seatedSince == nil { day.seatedSince = now }
        day.longestSeatedMinutes = max(day.longestSeatedMinutes, day.seatedMinutes)
        updateDay(day)
    }

    private func refreshMedia() {
        guard now.timeIntervalSince(lastMediaSample) >= 10 else { return }
        lastMediaSample = now
        let inEvent = todayPlan?.currentMeeting(at: now) != nil
        media = mediaMonitor.sample(now: now, hasCalendarEvent: inEvent)
    }

    private func updateSession(delta: TimeInterval) {
        guard let active = session else { return }
        sessionSecondsRemaining = max(0, Int(active.endsAt.timeIntervalSince(now).rounded()))
        if sessionSecondsRemaining == 0 {
            finishSessionTimeUp()
        }
    }

    private func recomputeDecision() {
        let key = todayKey()
        let day = state.day(key)
        let events = state.calendarSnapshots[key] ?? []
        let plan = Planner.plan(events: events, date: now, settings: state.settings)
        decision = BreakEngine.decide(now: now, day: day, settings: state.settings, plan: plan,
                                      health: health, media: media,
                                      activeBreak: session != nil)
    }

    private func escalateIfNeeded() {
        guard decision.isDue else { return }
        guard decision.dueAt != lastPromptedDue else {
            if decision.step == .overlay, lastOverlayDue != decision.dueAt {
                lastOverlayDue = decision.dueAt
                showOverlay()
            }
            return
        }
        if decision.step >= .notification {
            lastPromptedDue = decision.dueAt
            let title = decision.exercise?.displayTitle ?? "Time to move"
            notifications.postBreak(title: title,
                                    body: decision.why.isEmpty ? "You have been seated for a while." : decision.why,
                                    dueAt: decision.dueAt ?? now)
            SoundPlayer.breakStart(enabled: state.settings.sounds)
        }
        if decision.step == .overlay, decision.dueAt != lastOverlayDue {
            lastOverlayDue = decision.dueAt
            showOverlay()
        }
    }

    private func checkWindDown() {
        guard var day = today, day.start != nil, day.end == nil, !day.isOff else { return }
        guard day.windDownPromptedAt == nil else { return }
        if let notBefore = windDownNotBefore, now < notBefore { return }
        var target = state.settings.windDown.date(on: now)
        if let last = state.calendarSnapshots[todayKey()]?.filter({ $0.blocksTime }).map(\.end).max(),
           last > target {
            target = last.adding(minutes: 2)
        }
        guard now >= target else { return }
        day.windDownPromptedAt = now
        updateDay(day)
        let summary = Summarizer.metrics(dayKey: todayKey(), state: state)
        notifications.postWindDown(body: "\(summary.movedMinutes) min moving, \(summary.breaksTaken) breaks, lunch \(summary.lunchMinutes) min. Take two minutes to close the day.")
        openReflection(dayKey: todayKey())
    }

    /// "In 15 min" on the wind-down notification.
    func postponeWindDown() {
        guard var day = today, day.end == nil else { return }
        windDownNotBefore = now.adding(minutes: 15)
        day.windDownPromptedAt = nil
        updateDay(day)
    }

    private func checkStandingSuggestion() {
        guard let suggestion = decision.suggestedStandingCall ?? todayStandingSuggestion else { return }
        guard now >= suggestion.suggestAt else { return }
        guard lastStandingNoticeEventID != suggestion.event.id else { return }
        lastStandingNoticeEventID = suggestion.event.id
        let where_ = suggestion.target == .pad ? "walking pad" : (suggestion.target == .desk ? "standing desk" : "standing")
        notifications.postStandingCall(eventID: suggestion.event.id, title: suggestion.event.title,
                                       body: "Starts in 2 min. Take it on the \(where_).")
    }
}

// MARK: - Day lifecycle

extension AppModel {
    func startDay(auto: Bool = false) {
        let key = todayKey()
        var day = state.day(key) ?? WorkDay(dayKey: key, date: now, targets: state.settings.targets)
        guard day.start == nil else { return }
        day.start = now
        day.startSource = auto ? .auto : .manual
        day.targets = state.settings.targets
        day.nextBreakDue = now.adding(minutes: BreakEngine.interval(state.settings, health: health))
        day.seatedSince = now
        updateDay(day)
        save()
        refreshCalendar(force: true)
        if !auto {
            toast = "Day started."
        }
        if state.settings.checkInMorning,
           state.checkIns(on: key).isEmpty,
           lastMorningCheckInDay != key {
            lastMorningCheckInDay = key
            nextCheckInSource = .morning
            requestWindow?(.checkIn)
        }
    }

    func endDay() {
        guard var day = today else { return }
        if day.end == nil {
            day.end = now
            day.endSource = .manual
            day.nextBreakDue = nil
            day.snoozedUntil = nil
            updateDay(day)
            save()
            toast = "Day ended. \(todayMetrics.breaksTaken) breaks, \(Fmt.compactDuration(todayMetrics.movedMinutes)) moving."
            weeklyInsightIfNeeded()
            if state.settings.checkInEndOfDay {
                openReflection(dayKey: todayKey())
            }
        }
    }

    func toggleOffToday() {
        let key = todayKey()
        var day = state.day(key) ?? WorkDay(dayKey: key, date: now, targets: state.settings.targets)
        day.isOff.toggle()
        if day.isOff {
            day.end = now
            day.endSource = .manual
            if !state.offDays.contains(key) { state.offDays.append(key) }
            toast = "Off today. No prompts."
        } else {
            day.end = nil
            if day.start == nil {
                day.start = now
                day.startSource = .manual
            }
            state.offDays.removeAll { $0 == key }
            toast = "Day back on."
        }
        updateDay(day)
        save()
    }

    func markOff(dayKey: String) {
        var day = state.day(dayKey) ?? WorkDay(dayKey: dayKey, date: DayKey.date(from: dayKey) ?? now,
                                               targets: state.settings.targets)
        day.isOff = true
        updateDay(day)
        if !state.offDays.contains(dayKey) { state.offDays.append(dayKey) }
        save()
    }

    func openDay(_ dayKey: String) {
        summaryTab = .day
        requestWindow?(.summaries)
    }

    func windDownTime() -> Date {
        state.settings.windDown.date(on: now)
    }
}

// MARK: - Breaks

extension AppModel {
    func startBreakNow() {
        guard let exercise = decision.exercise ?? ExerciseLibrary.available(settings: state.settings).first else {
            toast = "No break available right now."
            return
        }
        startBreak(exercise: exercise, kind: exercise.kind, plannedAt: decision.dueAt ?? now,
                   minutes: nil, meetingTitle: nil)
    }

    func startBreak(exercise: ExerciseDef, kind: BreakKind, plannedAt: Date,
                    minutes: Int?, meetingTitle: String?) {
        guard let day = today, day.start != nil, day.end == nil else {
            toast = "Start the day first."
            return
        }
        closePopover?()
        dismissOverlay()
        let length = max(1, minutes ?? exercise.minutes(for: decision.gapMinutes ?? 60))
        let event = BreakEvent(dayKey: todayKey(), exerciseID: exercise.id, kind: kind,
                               plannedAt: plannedAt,
                               escalationStep: decision.step.rawValue,
                               startedAt: now,
                               outcome: .planned,
                               minutes: length,
                               needsConfirmation: state.settings.verification == .autoConfirm,
                               title: kind == .custom ? exercise.name : nil,
                               countsAsStanding: customCountsAsStanding(exerciseID: exercise.id))
        state.breaks.append(event)
        dirty = true
        sessionIdleSeconds = 0
        sessionStepBaseline = latestSteps()
        session = BreakSession(id: event.id, eventID: event.id, exercise: exercise, kind: kind,
                               startedAt: now, endsAt: now.adding(minutes: length),
                               plannedAt: plannedAt, meetingTitle: meetingTitle,
                               isLunch: kind == .lunch)
        sessionSecondsRemaining = length * 60
        lastPromptedDue = nil
        lastOverlayDue = nil
        SoundPlayer.breakStart(enabled: state.settings.sounds)
        requestWindow?(.session)
        recomputeDecision()
    }

    func takeStandingCall() {
        guard let suggestion = decision.suggestedStandingCall ?? todayStandingSuggestion else { return }
        let kind: BreakKind = suggestion.target == .pad ? .walkingPad : .standingBlock
        guard let exercise = ExerciseLibrary.forKind(kind).first else { return }
        let minutes = max(5, suggestion.event.minutes)
        startBreak(exercise: exercise, kind: kind, plannedAt: suggestion.suggestAt,
                   minutes: minutes, meetingTitle: suggestion.event.title)
    }

    func snoozeBreak() {
        guard var day = today else { return }
        let left = max(0, state.settings.snoozeLimit - day.snoozeCount)
        guard left > 0 else {
            toast = "No snoozes left. Start or skip."
            return
        }
        day.snoozeCount += 1
        day.snoozedUntil = now.adding(minutes: state.settings.snoozeMinutes)
        day.nextBreakDue = day.snoozedUntil
        updateDay(day)
        state.breaks.append(BreakEvent(dayKey: todayKey(),
                                       exerciseID: decision.exercise?.id ?? "snooze",
                                       kind: decision.kind ?? .standUpStretch,
                                       plannedAt: decision.dueAt ?? now,
                                       escalationStep: decision.step.rawValue,
                                       outcome: .snoozed,
                                       minutes: 0))
        dismissOverlay()
        closePopover?()
        save()
        lastPromptedDue = nil
        lastOverlayDue = nil
        toast = "Snoozed \(state.settings.snoozeMinutes) min. \(left - 1) left."
        recomputeDecision()
    }

    func skipBreak(reason: SkipReason, plannedAt: Date? = nil, kind: BreakKind? = nil) {
        guard var day = today else { return }
        let event = BreakEvent(dayKey: todayKey(),
                               exerciseID: (kind ?? decision.kind).map { $0.rawValue } ?? "skip",
                               kind: kind ?? decision.kind ?? .standUpStretch,
                               plannedAt: plannedAt ?? decision.dueAt ?? now,
                               escalationStep: decision.step.rawValue,
                               endedAt: now,
                               outcome: .skipped,
                               skipReason: reason,
                               minutes: 0)
        state.breaks.append(event)
        day.snoozeCount = 0
        day.snoozedUntil = nil
        day.longBlockHandledAt = now
        day.nextBreakDue = now.adding(minutes: reason == .busy ? 20 : 15)
        updateDay(day)
        dismissOverlay()
        closePopover?()
        save()
        lastPromptedDue = nil
        lastOverlayDue = nil
        toast = "Skipped. \(reason.rawValue.lowercased()) noted."
        recomputeDecision()
    }

    func finishSessionTimeUp() {
        guard let active = session else { return }
        session = nil
        sessionSecondsRemaining = 0
        SoundPlayer.breakEnd(enabled: state.settings.sounds)
        let idleAway = sessionIdleSeconds
        let stepDelta = latestSteps().map { max(0, $0 - (sessionStepBaseline ?? $0)) } ?? 0
        let duration = active.minutes * 60
        // Lunch only counts on a clear away-from-the-Mac signal; otherwise ask.
        let clearSignal: Bool
        if active.kind == .lunch {
            clearSignal = idleAway >= Double(duration) * 0.8
        } else {
            clearSignal = idleAway >= Double(duration) * 0.4 || stepDelta >= 60 || active.kind.isStanding
        }
        if state.settings.verification == .honorSystem {
            pendingConfirmation = PendingConfirmation(eventID: active.eventID, kind: active.kind, title: active.exercise.displayTitle,
                                                      minutes: active.minutes,
                                                      prompt: "How did it go?")
        } else if clearSignal {
            completeBreak(eventID: active.eventID, outcome: .done, verifiedBy: .auto,
                          minutes: active.minutes, kind: active.kind)
        } else {
            pendingConfirmation = PendingConfirmation(eventID: active.eventID, kind: active.kind, title: active.exercise.displayTitle,
                                                      minutes: active.minutes,
                                                      prompt: "Did you do it?")
        }
        closeSessionWindow()
        recomputeDecision()
    }

    func endSession(early: Bool = false) {
        guard let active = session else { return }
        let elapsed = max(1, Int(now.timeIntervalSince(active.startedAt) / 60))
        let minutes = early ? max(1, elapsed) : active.minutes
        session = nil
        sessionSecondsRemaining = 0
        SoundPlayer.breakEnd(enabled: state.settings.sounds)
        if state.settings.verification == .honorSystem {
            pendingConfirmation = PendingConfirmation(eventID: active.eventID, kind: active.kind, title: active.exercise.displayTitle,
                                                      minutes: minutes, prompt: "Done?")
        } else {
            completeBreak(eventID: active.eventID, outcome: .done, verifiedBy: .confirm,
                          minutes: minutes, kind: active.kind)
        }
        closeSessionWindow()
        recomputeDecision()
    }

    func abandonSession() {
        guard let active = session else { return }
        session = nil
        sessionSecondsRemaining = 0
        pendingConfirmation = PendingConfirmation(eventID: active.eventID, kind: active.kind, title: active.exercise.displayTitle,
                                                  minutes: 0, prompt: "You stopped early.")
        closeSessionWindow()
        recomputeDecision()
    }

    func confirmPending(done: Bool, reason: SkipReason = .notFeelingIt) {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        if done {
            completeBreak(eventID: pending.eventID, outcome: .done, verifiedBy: .confirm,
                          minutes: pending.minutes, kind: pending.kind)
        } else {
            resolveBreak(eventID: pending.eventID, outcome: .skipped,
                         verifiedBy: nil, minutes: 0, kind: pending.kind, skipReason: reason)
        }
        save()
        recomputeDecision()
    }

    private func completeBreak(eventID: String, outcome: BreakOutcome, verifiedBy: VerifiedBy,
                               minutes: Int, kind: BreakKind) {
        resolveBreak(eventID: eventID, outcome: outcome, verifiedBy: verifiedBy,
                     minutes: minutes, kind: kind, skipReason: nil)
    }

    private func resolveBreak(eventID: String, outcome: BreakOutcome, verifiedBy: VerifiedBy?,
                              minutes: Int, kind: BreakKind, skipReason: SkipReason?) {
        guard var day = today else { return }
        if let idx = state.breaks.firstIndex(where: { $0.id == eventID }) {
            state.breaks[idx].endedAt = now
            state.breaks[idx].outcome = outcome
            state.breaks[idx].verifiedBy = verifiedBy
            state.breaks[idx].minutes = minutes
            state.breaks[idx].needsConfirmation = false
            state.breaks[idx].skipReason = skipReason
        }
        if outcome == .done {
            // Standing, walking and lunch totals always follow the activity list.
            DayTotals.apply(to: &day, breaks: state.breaks(on: day.dayKey))
            day.lastExerciseID = state.breaks.first { $0.id == eventID }?.exerciseID
            day.seatedMinutes = 0
            day.seatedSince = now
            day.lastBreakEnd = now
            day.lastBreakKind = kind
            day.longBlockHandledAt = now
            day.snoozeCount = 0
            day.snoozedUntil = nil
            day.nextBreakDue = now.adding(minutes: BreakEngine.interval(state.settings, health: health))
            if kind == .lunch && state.settings.checkInAfterLunch,
               state.checkIns(on: todayKey()).count < 2,
               now.hour >= 12 {
                nextCheckInSource = .afterLunch
                requestWindow?(.checkIn)
            }
        } else if outcome == .skipped {
            day.longBlockHandledAt = now
            day.nextBreakDue = now.adding(minutes: 15)
            day.snoozeCount = 0
            day.snoozedUntil = nil
        }
        updateDay(day)
        save()
        lastPromptedDue = nil
        lastOverlayDue = nil
    }

    func dismissBreakPrompt() {
        dismissOverlay()
    }

    private func latestSteps() -> Int? {
        state.latestHealthSample()?.steps ?? health.steps
    }
}

// MARK: - Editing activities

extension AppModel {
    /// Every exercise that can be logged by hand, including ones the engine
    /// would not suggest right now.
    var loggableExercises: [ExerciseDef] {
        ExerciseLibrary.everything(settings: state.settings)
    }

    private func customCountsAsStanding(exerciseID: String) -> Bool? {
        state.settings.customEquipment.first { $0.exerciseID == exerciseID }?.countsAsStanding
    }

    /// Finished and skipped activities for a day, oldest first.
    func activities(on dayKey: String) -> [BreakEvent] {
        state.breaks(on: dayKey)
            .filter { $0.outcome == .done || $0.outcome == .skipped }
            .sorted { ($0.startedAt ?? $0.plannedAt) < ($1.startedAt ?? $1.plannedAt) }
    }

    /// Logs an activity after the fact.
    func addActivity(dayKey: String, exerciseID: String, start: Date, minutes: Int) {
        guard let exercise = ExerciseLibrary.find(exerciseID, settings: state.settings) else { return }
        let length = max(1, minutes)
        state.breaks.append(BreakEvent(dayKey: dayKey, exerciseID: exercise.id, kind: exercise.kind,
                                       plannedAt: start, startedAt: start,
                                       endedAt: start.adding(minutes: length),
                                       outcome: .done, verifiedBy: .confirm, minutes: length,
                                       title: exercise.kind == .custom ? exercise.name : nil,
                                       countsAsStanding: customCountsAsStanding(exerciseID: exercise.id)))
        activitiesChanged(on: dayKey)
    }

    /// Applies an edit to one logged activity. The session in progress cannot be edited.
    func updateActivity(id: String, _ change: (inout BreakEvent) -> Void) {
        guard id != session?.eventID,
              let index = state.breaks.firstIndex(where: { $0.id == id }) else { return }
        let original = state.breaks[index]
        var item = original
        change(&item)
        // Nothing changed: leave the day's totals and the file alone.
        guard item != original else { return }
        item.minutes = max(0, item.minutes)
        if let start = item.startedAt {
            item.endedAt = start.adding(minutes: item.minutes)
        }
        if item.outcome == .done {
            item.skipReason = nil
            if item.verifiedBy == nil { item.verifiedBy = .confirm }
            if item.startedAt == nil { item.startedAt = item.plannedAt }
        } else {
            item.verifiedBy = nil
        }
        item.needsConfirmation = false
        state.breaks[index] = item
        activitiesChanged(on: item.dayKey)
    }

    /// Changes which exercise an activity was.
    func setActivityExercise(id: String, exerciseID: String) {
        guard let exercise = ExerciseLibrary.find(exerciseID, settings: state.settings) else { return }
        let standing = customCountsAsStanding(exerciseID: exercise.id)
        updateActivity(id: id) { item in
            item.exerciseID = exercise.id
            item.kind = exercise.kind
            item.title = exercise.kind == .custom ? exercise.name : nil
            item.countsAsStanding = standing
        }
    }

    func deleteActivity(id: String) {
        guard id != session?.eventID,
              let item = state.breaks.first(where: { $0.id == id }) else { return }
        state.breaks.removeAll { $0.id == id }
        if pendingConfirmation?.eventID == id { pendingConfirmation = nil }
        activitiesChanged(on: item.dayKey)
    }

    func confirmDeleteActivity(id: String) {
        guard let item = state.breaks.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(item.displayTitle)?"
        alert.informativeText = "It is removed from this day's totals and goals. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            deleteActivity(id: id)
        }
    }

    /// Re-derives the day's totals from its activities and saves.
    private func activitiesChanged(on dayKey: String) {
        var day = state.day(dayKey) ?? WorkDay(dayKey: dayKey, date: DayKey.date(from: dayKey) ?? now,
                                               targets: state.settings.targets)
        DayTotals.apply(to: &day, breaks: state.breaks(on: dayKey))
        updateDay(day)
        save()
        recomputeDecision()
        onDecisionChanged?()
    }
}

// MARK: - Equipment

extension AppModel {
    func addCustomEquipment(name: String, minutes: Int, countsAsStanding: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSettings {
            $0.customEquipment.append(CustomEquipment(name: trimmed, minutes: minutes,
                                                      countsAsStanding: countsAsStanding))
        }
    }

    func updateCustomEquipment(id: String, _ change: (inout CustomEquipment) -> Void) {
        updateSettings { settings in
            guard let index = settings.customEquipment.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.customEquipment[index])
            settings.customEquipment[index].minutes = max(1, min(240, settings.customEquipment[index].minutes))
        }
    }

    /// Removing equipment keeps the activities already logged with it.
    func removeCustomEquipment(id: String) {
        updateSettings { settings in
            if let item = settings.customEquipment.first(where: { $0.id == id }) {
                settings.disabledExerciseIDs.removeAll { $0 == item.exerciseID }
            }
            settings.customEquipment.removeAll { $0.id == id }
        }
    }
}

// MARK: - Session window plumbing

extension AppModel {
    var sessionWindowOpen: Bool { session != nil }

    func closeSessionWindow() {
        NSApp.windows.first { $0.identifier?.rawValue == "dayline.session" }?.close()
    }

    func showOverlay() {
        SoundPlayer.play("Submarine", enabled: state.settings.sounds)
        NotificationCenter.default.post(name: .daylineShowOverlay, object: nil)
    }

    func dismissOverlay() {
        NotificationCenter.default.post(name: .daylineHideOverlay, object: nil)
    }
}

extension Notification.Name {
    static let daylineShowOverlay = Notification.Name("dayline.showOverlay")
    static let daylineHideOverlay = Notification.Name("dayline.hideOverlay")
}

// MARK: - Check-ins and journal

extension AppModel {
    func saveCheckIn(_ selection: MoodSelection, note: String, source: CheckInSource) {
        guard !selection.word.isEmpty else { return }
        let checkIn = CheckIn(at: now, energy: selection.energy, mood: selection.mood,
                              word: selection.word, note: note, source: source)
        state.checkIns.append(checkIn)
        save()
    }

    func latestCheckIn(dayKey: String? = nil) -> CheckIn? {
        state.checkIns(on: dayKey ?? todayKey()).last
    }

    func addJournalEntry(text: String, tags: [String], at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = JournalEntry(at: date, kind: .free, text: trimmed,
                                 context: entryContext(at: date), tags: tags)
        state.journal.append(entry)
        save()
        toast = "Saved."
    }

    /// Deleting is permanent, so ask first.
    func confirmDeleteJournalEntry(id: String) {
        let alert = NSAlert()
        alert.messageText = "Delete this entry?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            deleteJournalEntry(id: id)
        }
    }

    func deleteJournalEntry(id: String) {
        state.journal.removeAll { $0.id == id }
        save()
    }

    func entryContext(at date: Date) -> EntryContext {
        let key = DayKey.make(date)
        let metrics = Summarizer.metrics(dayKey: key, state: state)
        let events = state.calendarSnapshots[key] ?? []
        let last = events.filter { $0.end <= date }.max { $0.end < $1.end }
        let next = events.filter { $0.start > date }.min { $0.start < $1.start }
        let sample = state.latestHealthSample()
        return EntryContext(stress: sample?.stress ?? metrics.stressAverage,
                            bodyBattery: sample?.bodyBattery ?? metrics.bodyBatteryEnd,
                            breaksToday: metrics.breaksTaken,
                            standingMinutes: metrics.movedMinutes,
                            meetingHours: metrics.meetingHours,
                            lastMeetingTitle: last?.title,
                            lastMeetingMinutes: last?.minutes,
                            nextMeetingTitle: next?.title,
                            nextMeetingMinutes: next?.minutes)
    }

    func saveReflection(dayKey: String, selection: MoodSelection, answers: [PromptAnswer],
                        addToJournal: Bool) {
        let at = dayKey == todayKey() ? now : (DayKey.date(from: dayKey) ?? now).adding(minutes: 17 * 60)
        let checkIn = CheckIn(at: at, energy: selection.energy, mood: selection.mood,
                              word: selection.word, source: .reflection)
        state.checkIns.append(checkIn)
        let text = answers.map { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        let kept = answers.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if addToJournal {
            let entry = JournalEntry(at: at, kind: .reflection, text: text,
                                     promptAnswers: kept, checkInID: checkIn.id,
                                     context: entryContext(at: at))
            state.journal.append(entry)
        }
        if dayKey == todayKey(), var day = state.day(dayKey), day.end == nil {
            day.end = now
            day.endSource = .manual
            day.windDownPromptedAt = now
            updateDay(day)
        }
        if pendingWrapUpDay == dayKey { pendingWrapUpDay = nil }
        save()
        toast = "Reflection saved."
    }

    func reflectionPrompts(dayKey: String) -> [String] {
        let pool = state.settings.prompts
        guard !pool.isEmpty else { return [] }
        let metrics = Summarizer.metrics(dayKey: dayKey, state: state)
        var picks: [String] = []
        // Stable for a given day. `hashValue` changes on every launch.
        let seed = dayKey.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        for i in 0..<3 {
            picks.append(pool[(seed + i * 3) % pool.count])
        }
        if let word = metrics.moodWord, !word.isEmpty {
            picks[0] = "You felt \(word.lowercased()) today. What shaped that?"
        }
        var unique: [String] = []
        for p in picks where !unique.contains(p) { unique.append(p) }
        return unique
    }

    func openReflection(dayKey: String? = nil) {
        reflectionDayKey = dayKey ?? pendingWrapUpDay ?? todayKey()
        requestWindow?(.reflection)
    }

    func openJournal() {
        requestWindow?(.journal)
    }

    func openSummaries(tab: SummaryTab = .day) {
        summaryTab = tab
        requestWindow?(.summaries)
    }

    func openSettings(tab: SettingsTab = .schedule) {
        settingsTab = tab
        requestWindow?(.settings)
    }

    func openPlan() {
        requestWindow?(.plan)
    }
}

// MARK: - Focus

extension AppModel {
    func toggleFocus(minutes: Int) {
        guard var day = today else {
            toast = "Start the day first."
            return
        }
        if let until = day.focusUntil, until > now {
            day.focusUntil = nil
            updateDay(day)
            save()
            toast = "Focus off."
        } else {
            day.focusUntil = now.adding(minutes: minutes)
            updateDay(day)
            save()
            toast = "Focus for \(minutes) min. No overlays."
        }
        recomputeDecision()
    }

    /// Starts or replaces focus with the given length.
    func setFocus(minutes: Int) {
        guard var day = today else {
            toast = "Start the day first."
            return
        }
        day.focusUntil = now.adding(minutes: minutes)
        updateDay(day)
        save()
        toast = "Focus for \(minutes) min. No overlays."
        recomputeDecision()
    }

    func clearFocus() {
        guard var day = today else { return }
        day.focusUntil = nil
        updateDay(day)
        save()
        recomputeDecision()
    }
}

// MARK: - Calendar

extension AppModel {
    func requestCalendarIfNeeded() {
        guard !state.settings.calendarAccessRequested else { return }
        state.settings.calendarAccessRequested = true
        save()
        Task { await calendarService.requestAccess(); await MainActor.run { refreshCalendar(force: true) } }
    }

    func requestCalendarAccess() {
        Task {
            await calendarService.requestAccess()
            await MainActor.run { refreshCalendar(force: true) }
        }
    }

    func refreshCalendar(force: Bool) {
        calendarService.refreshStatus()
        guard calendarService.authorized else { return }
        if !force && now.timeIntervalSince(lastCalendarRefresh) < 120 { return }
        lastCalendarRefresh = now
        let start = DayKey.startOfDay(now).adding(days: -1)
        let end = DayKey.startOfDay(now).adding(days: 1)
        let events = calendarService.fetch(from: start, to: end, selectedIDs: state.settings.selectedCalendarIDs)
        var grouped: [String: [CalendarEvent]] = [:]
        for event in events {
            let key = DayKey.make(event.start)
            grouped[key, default: []].append(event)
        }
        // Write every fetched day, including empty ones, so a cancelled last
        // meeting does not linger in the snapshot and keep blocking breaks.
        var cursor = start
        while cursor < end {
            let key = DayKey.make(cursor)
            let list = (grouped[key] ?? []).sorted { $0.start < $1.start }
            if !list.isEmpty || state.calendarSnapshots[key] != nil {
                if state.calendarSnapshots[key] != list { dirty = true }
                state.setPlanEvents(list, for: key)
            }
            cursor = cursor.adding(days: 1)
        }
        let todayKey = self.todayKey()
        if var day = today {
            let plan = Planner.plan(events: grouped[todayKey] ?? [], date: now, settings: state.settings)
            let meeting = plan?.meetingMinutes ?? 0
            let run = plan?.longestBackToBackMinutes ?? 0
            if day.meetingMinutes != meeting || day.longestBackToBackMinutes != run {
                day.meetingMinutes = meeting
                day.longestBackToBackMinutes = run
                updateDay(day)
            }
        }
        recomputeDecision()
    }
}

// MARK: - Garmin

extension AppModel {
    var garminClient: GarminClient? {
        GarminClient.locate(storeDirectory: store.directory)
    }

    func syncGarminIfPossible(force: Bool) {
        guard state.settings.garmin.connected else { return }
        // Sample data is already a complete year; never overwrite it with a sync.
        guard !state.settings.showDemoData else { return }
        guard !garminBusy, let client = garminClient else { return }
        guard let tokens = Keychain.get("garmin.tokens") else {
            state.settings.garmin.connected = false
            state.settings.garmin.lastError = "Not signed in. Sign in again in Settings → Garmin."
            return
        }
        if !force && now.timeIntervalSince(lastGarminSync) < TimeInterval(max(5, state.settings.garmin.syncMinutes) * 60) { return }
        lastGarminSync = now
        garminBusy = true
        Task {
            do {
                let result = try await client.sync(tokens: tokens,
                                                   daysBack: state.healthSamples.isEmpty ? 7 : 0)
                await MainActor.run { apply(result) }
            } catch {
                await MainActor.run {
                    state.settings.garmin.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    garminBusy = false
                    health.isOffline = true
                }
            }
        }
    }

    func apply(_ sync: GarminSync) {
        garminBusy = false
        state.settings.garmin.lastError = nil
        if let tokens = sync.tokens { Keychain.set(tokens, account: "garmin.tokens") }
        // Samples are keyed by minute so a re-sync replaces rather than duplicates.
        func minuteKey(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded()) }
        var positions: [Int: Int] = [:]
        for (offset, sample) in state.healthSamples.enumerated() { positions[minuteKey(sample.at)] = offset }
        for var sample in sync.samples {
            let key = minuteKey(sample.at)
            if let idx = positions[key] {
                sample.id = state.healthSamples[idx].id
                state.healthSamples[idx] = sample
            } else {
                positions[key] = state.healthSamples.count
                state.healthSamples.append(sample)
            }
        }
        for var daily in sync.daily {
            if let idx = state.healthDaily.firstIndex(where: { $0.dayKey == daily.dayKey }) {
                daily.id = state.healthDaily[idx].id
                state.healthDaily[idx] = daily
            } else {
                state.healthDaily.append(daily)
            }
        }
        let cutoffDate = DayKey.startOfDay(now.adding(days: -400))
        let cutoff = DayKey.make(cutoffDate)
        state.healthSamples.removeAll { $0.at < cutoffDate }
        state.healthDaily.removeAll { $0.dayKey < cutoff }
        state.healthSamples.sort { $0.at < $1.at }
        state.healthDaily.sort { $0.dayKey < $1.dayKey }
        state.lastGarminSync = sync.fetchedAt
        health = snapshotHealth()
        health.isOffline = false
        lastSyncedText = relativeSyncText()
        lastGarminSync = now
        save()
        recomputeDecision()
    }

    func connectGarmin(email: String, password: String, mfa: String? = nil, clientState: String? = nil) {
        guard let client = garminClient else {
            garminError = "Garmin helper not found. Reinstall the app or run scripts/setup-garmin.sh."
            return
        }
        garminBusy = true
        garminError = nil
        Task {
            do {
                let result = try await client.login(email: email, password: password,
                                                   mfa: mfa, clientState: clientState)
                await MainActor.run {
                    guard Keychain.set(result.tokens, account: "garmin.tokens") else {
                        garminBusy = false
                        garminMFA = nil
                        garminError = "Signed in, but the session could not be saved to the Keychain."
                        return
                    }
                    state.settings.garmin.email = email
                    state.settings.garmin.connected = true
                    state.settings.garmin.lastLoginAt = now
                    state.settings.garmin.lastError = nil
                    garminBusy = false
                    garminMFA = nil
                    save()
                    syncGarminIfPossible(force: true)
                }
            } catch GarminError.needsMFA(let stateToken) {
                await MainActor.run {
                    garminBusy = false
                    garminMFA = GarminMFARequest(clientState: stateToken)
                }
            } catch {
                await MainActor.run {
                    garminBusy = false
                    garminError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    state.settings.garmin.lastError = garminError
                }
            }
        }
    }

    func submitGarminMFA(code: String, email: String) {
        guard let request = garminMFA else { return }
        connectGarmin(email: email, password: "", mfa: code, clientState: request.clientState)
    }

    func disconnectGarmin() {
        Keychain.delete("garmin.tokens")
        GarminClient.removeLegacyTokenStore(storeDirectory: store.directory)
        state.settings.garmin.connected = false
        state.settings.garmin.lastLoginAt = nil
        state.settings.garmin.lastError = nil
        save()
    }

    func updateHealthSnapshot() {
        health = snapshotHealth()
    }

    private func snapshotHealth() -> HealthSnapshot {
        let key = todayKey()
        let daily = state.dailyHealth(key)
        let samples = state.healthSamples(on: key)
        let latest = samples.last ?? state.latestHealthSample()
        let recent = samples.filter { $0.at > now.adding(minutes: -45) }
        let stress = recent.compactMap(\.stress).last ?? latest?.stress ?? daily?.stressAverage
        let battery = recent.compactMap(\.bodyBattery).last ?? latest?.bodyBattery ?? daily?.bodyBatteryEnd
        return HealthSnapshot(stress: stress, bodyBattery: battery,
                              steps: latest?.steps,
                              heartRate: latest?.heartRate,
                              sleepScore: daily?.sleepScore,
                              sleepMinutes: daily?.sleepMinutes,
                              hrvStatus: daily?.hrvStatus,
                              bodyBatteryWake: daily?.bodyBatteryWake,
                              lastSyncedAt: state.lastGarminSync,
                              isOffline: state.settings.garmin.connected == false || state.lastGarminSync == nil)
    }

    func relativeSyncText() -> String {
        guard let last = state.lastGarminSync else { return "Garmin offline" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        if minutes < 2 { return "Synced just now" }
        if minutes < 60 { return "Synced \(minutes) min ago" }
        let hours = minutes / 60
        return "Synced \(hours) h ago"
    }
}

// MARK: - AI

extension AppModel {
    func runInsights(period: InsightPeriod, question: String? = nil) {
        let client = AIClient()
        let key = client.apiKey(for: state.settings.ai.provider) ?? ""
        if key.isEmpty && state.settings.ai.provider != .custom {
            aiError = "Add an API key in Settings → AI."
            return
        }
        aiBusy = true
        aiError = nil
        var period = period
        if let question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            period.question = question
        }
        let snapshot = state
        Task {
            do {
                let insight = try await client.insights(state: snapshot, period: period)
                await MainActor.run {
                    state.insights.append(insight)
                    aiBusy = false
                    if period.label.hasPrefix("Week") {
                        state.lastWeeklyInsightAt = now
                        state.lastWeeklyInsightWeek = DayKey.make(period.start)
                    }
                    save()
                }
            } catch {
                await MainActor.run {
                    aiBusy = false
                    aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    /// Tests with `draftKey` when one is typed, otherwise the stored key.
    /// Testing never changes what is stored.
    func testAIConnection(draftKey: String = "", completion: @escaping (String?) -> Void) {
        let client = AIClient()
        let typed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? (client.apiKey(for: state.settings.ai.provider) ?? "") : typed
        aiBusy = true
        aiError = nil
        let settingsCopy = state.settings.ai
        Task {
            do {
                let text = try await client.testConnection(settings: settingsCopy, apiKey: key)
                await MainActor.run {
                    aiBusy = false
                    completion(text.isEmpty ? "Connected." : "Connected: \(text.prefix(80))")
                }
            } catch {
                await MainActor.run {
                    aiBusy = false
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    aiError = message
                    completion(nil)
                }
            }
        }
    }

    /// Stores the key for the current provider. Returns false if the Keychain refused.
    @discardableResult
    func saveAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Keychain.set(trimmed, account: state.settings.ai.provider.keychainAccount)
    }

    func removeAPIKey() {
        Keychain.delete(state.settings.ai.provider.keychainAccount)
    }

    /// Whether a key is stored, without reading it into memory.
    func hasStoredAPIKey() -> Bool {
        Keychain.has(state.settings.ai.provider.keychainAccount)
    }

    func weeklyInsightIfNeeded() {
        guard state.settings.ai.weeklyInsights, !aiBusy, !state.settings.showDemoData else { return }
        // Only when AI is set up; never surface a missing-key error unprompted.
        guard hasStoredAPIKey() || (state.settings.ai.provider == .custom && !state.settings.ai.baseURL.isEmpty) else { return }
        let week = InsightPeriod.week(containing: now.adding(days: -1))
        let label = DayKey.make(week.start)
        guard state.lastWeeklyInsightWeek != label else { return }
        guard DayKey.weekday(now) == 6 || DayKey.weekday(now) == 7 else { return }
        guard state.journal.count >= 3 else { return }
        runInsights(period: week)
    }

    func latestInsight(period: InsightPeriod) -> Insight? {
        // Rolling periods ("Last 365 days") start a day later every day, so match
        // on the label and a start within a week rather than the exact date.
        state.insights.filter {
            $0.question == nil && $0.periodLabel == period.label
                && abs($0.periodStart.timeIntervalSince(period.start)) < 7 * 86_400
        }.max { $0.createdAt < $1.createdAt }
    }

    /// The most recent answer to a typed question.
    var latestQuestionInsight: Insight? {
        state.insights.filter { $0.question != nil }.max { $0.createdAt < $1.createdAt }
    }
}

// MARK: - Settings helpers

extension AppModel {
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&state.settings)
        SettingsRef.ignoreBundleIDs = state.settings.micIgnoreBundleIDs
        notifications.configure(snoozeMinutes: state.settings.snoozeMinutes)
        applyAppearance()
        dirty = true
        save()
        recomputeDecision()
        onDecisionChanged?()
    }

    func applyAppearance() {
        switch state.settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let error = LaunchAtLogin.set(enabled) {
            toast = error
            updateSettings { $0.launchAtLogin = LaunchAtLogin.isEnabled }
            return
        }
        updateSettings { $0.launchAtLogin = enabled }
    }

    func registerHotKey() {
        hotKeys.onPress = { [weak self] in
            self?.openJournal()
        }
        applyHotKey()
    }

    private func applyHotKey() {
        if !hotKeys.register(state.settings.hotkey) {
            toast = "The journal shortcut \(HotKeyManager.describe(state.settings.hotkey)) is taken by another app."
        }
    }

    func reRegisterHotKey() {
        applyHotKey()
        SettingsRef.ignoreBundleIDs = state.settings.micIgnoreBundleIDs
    }

    func exportJournal() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "One Markdown file per day plus a JSON dump."
        if panel.runModal() == .OK, let url = panel.url {
            let count = store.exportJournal(state, to: url)
            updateSettings { $0.lastExportFolder = url.path }
            toast = "Exported \(count) day\(count == 1 ? "" : "s") to \(url.lastPathComponent)."
        }
    }

    /// Replaces what is on screen with a sample year. Real data is set aside
    /// first and comes back with `clearSampleData()`.
    func seedDemoData() {
        guard !state.settings.showDemoData else { return }
        guard store.stashBeforeSamples(state) else {
            toast = "Could not set your data aside, so samples were not loaded."
            return
        }
        DemoData.clearSampleData(from: &state)
        DemoData.seed(into: &state)
        save()
        toast = "Sample year loaded. Your own data is set aside."
    }

    /// Removes sample data only. It never runs against real data.
    func clearSampleData() {
        guard state.settings.showDemoData else { return }
        if let real = store.restoreStashedState() {
            state = real
            toast = "Sample data removed. Your data is back."
        } else {
            DemoData.clearSampleData(from: &state)
            state.settings.garmin.connected = Keychain.get("garmin.tokens") != nil
            toast = "Sample data removed."
        }
        health = snapshotHealth()
        save()
        recomputeDecision()
    }

    /// Queues a save. Encoding and writing happen off the main thread, and a
    /// burst of calls (typing in Settings) collapses into one write.
    func save() {
        dirty = false
        lastSaved = now
        store.saveAsync(state) { [weak self] error in
            Task { @MainActor in self?.saveFinished(error) }
        }
    }

    /// Writes now and waits. For quitting.
    func saveNow() {
        dirty = false
        lastSaved = now
        saveFinished(store.save(state) ? nil : "Could not save your data.")
    }

    private func saveFinished(_ error: String?) {
        if let error, storageError == nil { toast = error }
        storageError = error
    }

    func updateDay(_ day: WorkDay) {
        if let idx = state.days.firstIndex(where: { $0.dayKey == day.dayKey }) {
            state.days[idx] = day
        } else {
            state.days.append(day)
        }
        state.days.sort { $0.dayKey < $1.dayKey }
        dirty = true
    }

    func dismissToast() {
        toast = nil
    }
}

extension AppSettings {
    func schedule(for date: Date) -> DayHoursSetting? { schedule(for: date, calendar: .current) }
}

extension Date {
    var hour: Int { Calendar.current.component(.hour, from: self) }
}
