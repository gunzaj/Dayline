import Foundation
import DaylineCore

// A tiny check runner. XCTest ships with Xcode, which Dayline does not require,
// so the same assertions live in an executable (`swift run dayline-checks`).

var checks = 0
var failures: [String] = []

func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures.append("\(name)\(detail().isEmpty ? "" : " — \(detail())")")
    }
}

func equal<T: Equatable>(_ a: T, _ b: T, _ name: String) {
    checks += 1
    if a != b { failures.append("\(name) — expected \(b), got \(a)") }
}

NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
let cal = Calendar.current

func day(_ key: String) -> Date {
    DayKey.date(from: key, calendar: cal)!
}

func at(_ key: String, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(key))!
}

func baseSettings() -> AppSettings {
    var s = AppSettings()
    s.standingRules = [
        StandingRule(kind: .titleContains, textValue: "standup, 1:1, sync", target: .pad),
        StandingRule(kind: .attendeeCount, numberValue: 6, target: .desk),
        StandingRule(kind: .minimumLength, enabled: false, numberValue: 30, target: .either),
        StandingRule(kind: .recurring, enabled: false, target: .either),
        StandingRule(kind: .titleContains, isExclude: true, textValue: "workshop, design review", target: .either),
    ]
    return s
}

// MARK: - Primitives

check(TimeOfDay("09:30") == TimeOfDay(hour: 9, minute: 30), "TimeOfDay parses")
check(TimeOfDay("24:00") == nil, "TimeOfDay rejects 24:00")
check(TimeRange.minutesBetween(at("2026-11-27", 9), at("2026-11-27", 10, 30)) == 90, "minutesBetween")
check(DayKey.mondayIndex(at("2026-11-27", 9)) == 4, "Friday is monday index 4")

// MARK: - Planner

func sampleEvents() -> [CalendarEvent] {
    let d = "2026-11-27"
    return [
        CalendarEvent(id: "allday", title: "Holiday", start: at(d, 0), end: at(d, 23, 59), isAllDay: true),
        CalendarEvent(id: "declined", title: "Declined", start: at(d, 9), end: at(d, 9, 30), isDeclined: true),
        CalendarEvent(id: "free", title: "Optional", start: at(d, 9), end: at(d, 9, 30), isBusy: false),
        CalendarEvent(id: "m1", title: "Design review", start: at(d, 10), end: at(d, 11), attendeeCount: 12),
        CalendarEvent(id: "m2", title: "Product planning", start: at(d, 13), end: at(d, 14, 30), attendeeCount: 12),
        CalendarEvent(id: "m3", title: "Research sync", start: at(d, 14, 30), end: at(d, 15), attendeeCount: 5),
    ]
}

let settings = baseSettings()
let plan = Planner.plan(events: sampleEvents(), date: day("2026-11-27"), settings: settings, calendar: cal)!

equal(plan.meetingMinutes, 180, "meeting minutes count only busy events")
equal(plan.longestMeetingMinutes, 90, "longest single meeting")
equal(plan.longestBackToBackMinutes, 120, "longest back-to-back run")
equal(plan.freeGaps.count, 3, "free gaps")
equal(plan.freeGaps[0].minutes, 60, "first gap is 9:00–10:00")
equal(plan.freeGaps[1].minutes, 120, "second gap is 11:00–13:00")
equal(plan.lunchGap?.minutes, 90, "lunch gap inside 11:30–14:00")

let standup = CalendarEvent(id: "s", title: "1:1 with Sam", start: at("2026-11-27", 12),
                            end: at("2026-11-27", 12, 30), attendeeCount: 2)
let workshop = CalendarEvent(id: "w", title: "Design review workshop", start: at("2026-11-27", 12),
                             end: at("2026-11-27", 13), attendeeCount: 20)
let bigSync = CalendarEvent(id: "b", title: "All hands", start: at("2026-11-27", 12),
                            end: at("2026-11-27", 13), attendeeCount: 8)
equal(Planner.standingSuggestion(for: standup, rules: settings.standingRules)?.target, .pad,
      "title rule suggests the walking pad")
equal(Planner.standingSuggestion(for: bigSync, rules: settings.standingRules)?.target, .desk,
      "attendee rule suggests the standing desk")
check(Planner.standingSuggestion(for: workshop, rules: settings.standingRules) == nil,
      "exclude rule wins over attendee rule")
check(Planner.plan(events: sampleEvents(), date: day("2026-11-28"), settings: settings) == nil,
      "no plan on Saturday")

// MARK: - Engine

func makeDay(_ key: String = "2026-11-27", startHour: Int = 9) -> WorkDay {
    var d = WorkDay(dayKey: key, date: day(key), targets: settings.targets)
    d.start = at(key, startHour)
    d.startSource = .auto
    return d
}

func decide(_ now: Date, day: WorkDay?, events: [CalendarEvent] = [], health: HealthSnapshot = HealthSnapshot(),
            media: MediaState = .clear, activeBreak: Bool = false) -> BreakDecision {
    let p = Planner.plan(events: events, date: now, settings: settings, calendar: cal)
    return BreakEngine.decide(now: now, day: day, settings: settings, plan: p, health: health,
                              media: media, activeBreak: activeBreak, calendar: cal)
}

var engineDay = makeDay()
engineDay.nextBreakDue = at("2026-11-27", 10)
var decision = decide(at("2026-11-27", 9, 30), day: engineDay)
check(!decision.isDue, "break not due before its time")
equal(decision.menuLabel, "30m", "menu shows countdown")

decision = decide(at("2026-11-27", 10, 1), day: engineDay)
check(decision.isDue, "break due at 10:00")
equal(decision.step, .hint, "hint at due time")
equal(decision.exercise?.kind, .squats, "normal energy picks squats")

decision = decide(at("2026-11-27", 10, 5), day: engineDay)
equal(decision.step, .notification, "notification 5 min after due")
decision = decide(at("2026-11-27", 10, 11), day: engineDay)
equal(decision.step, .overlay, "overlay 10 min after due")

var focusDay = engineDay
focusDay.focusUntil = at("2026-11-27", 11)
decision = decide(at("2026-11-27", 10, 12), day: focusDay)
equal(decision.step, .notification, "focus mode caps escalation at notification")

var meetingDay = makeDay()
meetingDay.nextBreakDue = at("2026-11-27", 9, 30)
let meetingEvents = [CalendarEvent(id: "m", title: "Design review", start: at("2026-11-27", 10),
                                   end: at("2026-11-27", 11), attendeeCount: 5)]
decision = decide(at("2026-11-27", 10, 20), day: meetingDay, events: meetingEvents)
check(!decision.isDue, "never due during a meeting")
check(decision.waitingForMeeting != nil, "reports the meeting it waits for")
equal(decision.step, .none, "no escalation during a meeting")

var mediaDay = makeDay()
mediaDay.nextBreakDue = at("2026-11-27", 9, 30)
decision = decide(at("2026-11-27", 10, 20), day: mediaDay,
                  media: MediaState(microphoneInUse: true))
check(!decision.isDue, "microphone pauses escalation")
check(decision.isPausedByMedia, "reports the media pause")
equal(decision.step, .hint, "media pause keeps only the hint")

decision = decide(at("2026-11-27", 10, 20), day: mediaDay,
                  media: MediaState(microphoneInUse: true, openMicrophoneMinutes: 120,
                                    microphoneIgnored: false))
equal(decision.step, .notification, "open mic with no meeting stops at notification")

var ignDay = makeDay()
ignDay.nextBreakDue = at("2026-11-27", 9, 30)
decision = decide(at("2026-11-27", 10, 20), day: ignDay,
                  media: MediaState(microphoneInUse: true, microphoneIgnored: true))
check(decision.isDue, "ignored microphone does not pause")

var snoozeDay = makeDay()
snoozeDay.nextBreakDue = at("2026-11-27", 10)
snoozeDay.snoozedUntil = at("2026-11-27", 10, 15)
snoozeDay.snoozeCount = 1
decision = decide(at("2026-11-27", 10, 5), day: snoozeDay)
check(!decision.isDue, "snoozed break is not due")
equal(decision.snoozesLeft, 1, "snooze limit is counted")

var stressDay = makeDay()
stressDay.nextBreakDue = at("2026-11-27", 9, 30)
decision = decide(at("2026-11-27", 10), day: stressDay,
                  health: HealthSnapshot(stress: 70, bodyBattery: 50))
equal(decision.exercise?.kind, .boxBreathing, "high stress picks box breathing")

var lowDay = makeDay()
lowDay.nextBreakDue = at("2026-11-27", 9, 30)
lowDay.seatedMinutes = 100
let shortGapEvents = [CalendarEvent(id: "x", title: "Sync", start: at("2026-11-27", 10, 1),
                                    end: at("2026-11-27", 10, 20), attendeeCount: 5)]
decision = decide(at("2026-11-27", 9, 30), day: lowDay, events: shortGapEvents,
                  health: HealthSnapshot(stress: 20, bodyBattery: 18))
equal(decision.exercise?.kind, .walkingPad, "low Body Battery picks the walking pad")

var varietyDay = makeDay()
varietyDay.nextBreakDue = at("2026-11-27", 9, 30)
varietyDay.lastBreakKind = .squats
decision = decide(at("2026-11-27", 10), day: varietyDay,
                  health: HealthSnapshot(stress: 20, bodyBattery: 60))
check(decision.exercise?.kind != .squats, "the same exercise does not repeat twice in a row")

let lunchDay = makeDay()
let lunchEvents = [CalendarEvent(id: "a", title: "Morning", start: at("2026-11-27", 9),
                                 end: at("2026-11-27", 11), attendeeCount: 3),
                   CalendarEvent(id: "b", title: "Afternoon", start: at("2026-11-27", 14),
                                 end: at("2026-11-27", 16), attendeeCount: 3)]
decision = decide(at("2026-11-27", 12), day: lunchDay, events: lunchEvents)
check(decision.isDue, "lunch is due in the midday window")
equal(decision.exercise?.kind, .lunch, "lunch wins inside the window")

var skippedLunch = lunchDay
skippedLunch.lunchSkipped = true
decision = decide(at("2026-11-27", 12), day: skippedLunch, events: lunchEvents)
check(decision.exercise?.kind != .lunch, "skipped lunch is not offered again")

var longDay = makeDay()
longDay.nextBreakDue = at("2026-11-27", 17)
let longEvents = [CalendarEvent(id: "long", title: "Design review", start: at("2026-11-27", 9, 30),
                                end: at("2026-11-27", 10, 30), attendeeCount: 5)]
decision = decide(at("2026-11-27", 10, 35), day: longDay, events: longEvents)
check(decision.isDue, "break right after a long block")
if case .afterLongBlock = decision.reason {
    check(true, "long-block reason")
} else {
    check(false, "long-block reason", "\(decision.reason)")
}

decision = decide(at("2026-11-27", 9), day: nil)
equal(decision.phase, .notStarted, "day has not started")
decision = decide(at("2026-11-27", 9), day: makeDay(startHour: 9))
equal(decision.phase, .active, "running day is active")

var offSettings = settings
offSettings.offDays = ["2026-11-27"]
var offDay = makeDay()
offDay.isOff = true
let offDecision = BreakEngine.decide(now: at("2026-11-27", 10), day: offDay, settings: offSettings,
                                     plan: nil, health: HealthSnapshot(), media: .clear,
                                     activeBreak: false, calendar: cal)
equal(offDecision.phase, .dayOff, "off day has no prompts")

// MARK: - Demo data, summaries, heat map

var demo = AppState(settings: settings)
DemoData.seed(into: &demo, endingAt: at("2026-11-27", 12), days: 365, calendar: cal)
check(demo.days.count > 200, "demo seeded a year of workdays", "\(demo.days.count) days")
check(!demo.breaks.isEmpty, "demo seeded breaks")

let todayMetrics = Summarizer.metrics(dayKey: "2026-11-27", state: demo)
check(todayMetrics.isWorkday, "today is a workday")
check(todayMetrics.goals.count == 5, "five goals")
check(todayMetrics.breaksTaken > 0, "breaks counted")

let streak = Summarizer.streak(.reflection, state: demo, today: at("2026-11-27", 12), calendar: cal)
check(streak.current > 3, "reflection streak builds from demo data", "\(streak.current)")

let heatmap = Summarizer.heatmap(state: demo, endingAt: at("2026-11-27", 12), calendar: cal)
equal(heatmap.weeks.count, 52, "52 week columns")
check(heatmap.weeks.allSatisfy { $0.cells.count == 5 }, "five workday rows per week")
check(heatmap.allCells.allSatisfy { DayKey.weekday($0.date, calendar: cal) != 1 && DayKey.weekday($0.date, calendar: cal) != 7 },
      "weekends absent from the heat map")
check(!heatmap.months.isEmpty, "month labels present")
for metric in HeatmapMetric.allCases {
    equal(heatmap.stats(for: metric).count, 4, "four stats for \(metric.rawValue)")
    check(!heatmap.pattern(for: metric).isEmpty, "pattern for \(metric.rawValue)")
}
check(heatmap.allCells.contains { $0.dayKey == "2026-11-27" }, "today is in the heat map")

let week = Summarizer.week(containing: at("2026-11-27", 12), state: demo, calendar: cal)
equal(week.days.count, 5, "week has five days")
equal(week.days.first.map { DayKey.make($0.date) }, "2026-11-23", "week starts on Monday")

// Streak must skip off days and weekends.
var streakState = AppState(settings: settings)
for key in ["2026-11-19", "2026-11-20", "2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26"] {
    var d = WorkDay(dayKey: key, date: day(key), targets: settings.targets)
    d.start = at(key, 9)
    if key != "2026-11-26" {
        d.end = at(key, 17)
        streakState.days.append(d)
        streakState.journal.append(JournalEntry(at: at(key, 17), kind: .reflection, text: "x"))
    } else {
        d.isOff = true
        streakState.days.append(d)
    }
}
let skippedStreak = Summarizer.streak(.reflection, state: streakState, today: at("2026-11-27", 12), calendar: cal)
equal(skippedStreak.current, 5, "off day does not break a streak")

// MARK: - Store and export

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("dayline-check-\(UUID().uuidString)")
let store = Store(directory: temp)
var saved = AppState()
saved.journal.append(JournalEntry(at: at("2026-11-27", 17), kind: .reflection, text: "A real thought"))
check(store.save(saved), "store saves")
let loaded = store.load()
equal(loaded.journal.count, 1, "store round-trips")
check(loaded.journal.first?.text == "A real thought", "journal text survives")
let exportFolder = temp.appendingPathComponent("exports")
equal(store.exportJournal(saved, to: exportFolder), 1, "one markdown file per day")
let markdown = JournalExport.markdown(dayKey: "2026-11-27", state: saved)
check(markdown.contains("A real thought"), "markdown export contains the entry")
try? FileManager.default.removeItem(at: temp)

// MARK: - AI request and privacy

var aiSettings = AISettings()
aiSettings.provider = .custom
aiSettings.baseURL = "http://llm.local:8080/v1"
aiSettings.model = "local-model"
let endpoint = AIClient.endpoint(for: aiSettings)
equal(endpoint?.absoluteString, "http://llm.local:8080/v1/chat/completions", "custom endpoint")

var anthropic = AISettings()
anthropic.provider = .anthropic
let request = try AIClient.buildRequest(settings: anthropic, apiKey: "secret",
                                        system: "sys", user: "hello")
equal(request.value(forHTTPHeaderField: "x-api-key"), "secret", "Anthropic uses x-api-key")
equal(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01", "Anthropic version header")

let parsed = try AIClient.parseInsight("""
Sure. {"observations": ["Wednesdays cost you."], "suggestions": ["Block 30 min."], "days": ["2026-11-25"]}
""", period: InsightPeriod.lastDays(7, endingAt: at("2026-11-27", 12)), settings: anthropic)
equal(parsed.observations.count, 1, "AI JSON parsed")
equal(parsed.suggestions.first, "Block 30 min.", "AI suggestions parsed")

var privacyState = AppState(settings: settings)
privacyState.journal.append(JournalEntry(at: at("2026-11-27", 12), kind: .free, text: "Private note"))
privacyState.calendarSnapshots["2026-11-27"] = [
    CalendarEvent(id: "1", title: "Secret Acquisition Sync", start: at("2026-11-27", 10),
                  end: at("2026-11-27", 11), attendeeCount: 8)
]
privacyState.settings.ai.shareCalendarTitles = false
let privateDataset = AIPrompt.dataset(state: privacyState,
                                      period: InsightPeriod.lastDays(7, endingAt: at("2026-11-27", 12)))
check(!privateDataset.contains("Secret Acquisition"), "calendar titles stay local by default")
check(privateDataset.contains("Private note"), "journal text is shared when enabled")
privacyState.settings.ai.shareCalendarTitles = true
let sharedDataset = AIPrompt.dataset(state: privacyState,
                                     period: InsightPeriod.lastDays(7, endingAt: at("2026-11-27", 12)))
check(sharedDataset.contains("Secret Acquisition"), "calendar titles shared when enabled")
privacyState.settings.ai.shareJournalText = false
let noJournal = AIPrompt.dataset(state: privacyState,
                                 period: InsightPeriod.lastDays(7, endingAt: at("2026-11-27", 12)))
check(!noJournal.contains("Private note"), "journal text can be withheld")

// MARK: - Seated clock

var clock = SeatedClock()
var seated = 0
for _ in 0..<12 { seated += clock.advance(by: 10, idleSeconds: 1) }
equal(seated, 2, "twelve 10-second ticks make two seated minutes")
equal(clock.advance(by: 3600, idleSeconds: 1), 0, "a sleep-length gap is not seated time")
equal(clock.advance(by: 10, idleSeconds: 400), 0, "idle time is not seated time")
seated = 0
for _ in 0..<5 { seated += clock.advance(by: 10, idleSeconds: 1) }
equal(seated, 0, "the carry restarts after time away")

// MARK: - Schedule

var weekendSettings = baseSettings()
if let saturday = weekendSettings.dayHours.firstIndex(where: { $0.weekday == 7 }) {
    weekendSettings.dayHours[saturday].enabled = true
}
check(!weekendSettings.isConfiguredOffDay(day("2026-11-28"), calendar: cal), "an enabled Saturday is a workday")
check(weekendSettings.isConfiguredOffDay(day("2026-11-29"), calendar: cal), "a disabled Sunday stays off")
check(Planner.plan(events: [], date: day("2026-11-28"), settings: weekendSettings, calendar: cal) != nil,
      "an enabled Saturday gets a plan")

// MARK: - Variety

var kindsSeen: Set<BreakKind> = []
var rotatingDay = makeDay()
rotatingDay.nextBreakDue = at("2026-11-27", 9, 30)
for _ in 0..<5 {
    let next = decide(at("2026-11-27", 10), day: rotatingDay, health: HealthSnapshot(stress: 20, bodyBattery: 60))
    guard let kind = next.exercise?.kind else { break }
    kindsSeen.insert(kind)
    rotatingDay.lastBreakKind = kind
}
check(kindsSeen.count >= 4, "normal breaks cycle through the available exercises", "\(kindsSeen.count) kinds")

// MARK: - Reflection goal and day index

var reflectionOnly = AppState(settings: settings)
var reflectedDay = WorkDay(dayKey: "2026-11-26", date: day("2026-11-26"), targets: settings.targets)
reflectedDay.start = at("2026-11-26", 9)
reflectionOnly.days.append(reflectedDay)
reflectionOnly.checkIns.append(CheckIn(at: at("2026-11-26", 17), energy: 3, mood: 3, word: "Steady", source: .reflection))
check(Summarizer.metrics(dayKey: "2026-11-26", state: reflectionOnly).hasReflection,
      "a reflection without journal text still counts")

let dayIndex = Summarizer.DayIndex(state: demo)
for key in ["2026-11-27", "2026-11-25", "2026-06-10", "2026-11-28"] {
    check(Summarizer.metrics(dayKey: key, state: demo) == Summarizer.metrics(dayKey: key, state: demo, index: dayIndex),
          "indexed metrics match direct metrics for \(key)")
}

// MARK: - Store recovery

let recoveryDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayline-recovery-\(UUID().uuidString)")
let recoveryStore = Store(directory: recoveryDir)
let mixed = """
{"version":1,"journal":[
  {"id":"entry-good","at":"2026-11-27T17:00:00Z","kind":"free","text":"Keep me","promptAnswers":[],"context":{"breaksToday":0,"standingMinutes":0,"meetingHours":0},"tags":[]},
  {"id":"entry-bad","at":"not a date","kind":"free"}
],"days":[{"dayKey":"broken"}]}
"""
try mixed.write(to: recoveryStore.stateURL, atomically: true, encoding: .utf8)
let recovered = recoveryStore.load()
equal(recovered.journal.count, 1, "a bad record is skipped, not the whole collection")
equal(recovered.journal.first?.text, "Keep me", "the readable record survives")
equal(recovered.decodeIssues, 2, "skipped records are counted")
check(recoveryStore.loadWarning != nil, "skipped records raise a warning")
let keptCopies = (try? FileManager.default.contentsOfDirectory(atPath: recoveryDir.path)) ?? []
check(keptCopies.contains { $0.hasPrefix("state.unreadable-records-") }, "the original file is kept before it can be overwritten")

// A corrupt file falls back to the newest backup.
var goodState = AppState()
goodState.journal.append(JournalEntry(at: at("2026-11-26", 17), kind: .free, text: "From the backup"))
let backupDir = recoveryStore.backupsDirectory
try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
let backupEncoder = JSONEncoder()
backupEncoder.dateEncodingStrategy = .iso8601
try backupEncoder.encode(goodState).write(to: backupDir.appendingPathComponent("state-2026-11-26.json"))
try "{ this is not json".write(to: recoveryStore.stateURL, atomically: true, encoding: .utf8)
let corruptStore = Store(directory: recoveryDir)
let restored = corruptStore.load()
equal(restored.journal.first?.text, "From the backup", "a corrupt state file restores the newest backup")
check(corruptStore.loadWarning?.contains("Restored") == true, "the restore is reported")

// The first save of a day keeps the previous state as a backup.
let rollingDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayline-rolling-\(UUID().uuidString)")
let rollingStore = Store(directory: rollingDir)
check(rollingStore.save(goodState), "first save")
check(rollingStore.save(AppState()), "second save")
let rolled = (try? FileManager.default.contentsOfDirectory(atPath: rollingStore.backupsDirectory.path)) ?? []
equal(rolled.count, 1, "one backup per day")

// Queued saves collapse, and the newest state wins.
let burstStamp = at("2026-11-27", 12)
await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
    for n in 1...20 {
        var burst = AppState()
        burst.journal.append(JournalEntry(at: burstStamp, kind: .free, text: "burst \(n)"))
        rollingStore.saveAsync(burst) { _ in if n == 20 { finished.resume() } }
    }
}
equal(rollingStore.load().journal.first?.text, "burst 20", "the newest queued state is the one on disk")

// Sample data sets real data aside and gives it back.
check(rollingStore.stashBeforeSamples(goodState), "real data is set aside")
equal(rollingStore.restoreStashedState()?.journal.first?.text, "From the backup", "real data comes back")
check(rollingStore.restoreStashedState() == nil, "the stash is used once")

// The journal export carries the journal only.
var exportState = AppState()
exportState.settings.garmin.email = "someone@example.com"
exportState.journal.append(JournalEntry(at: at("2026-11-27", 17), kind: .free, text: "Exported"))
let exportDir = rollingDir.appendingPathComponent("export")
_ = rollingStore.exportJournal(exportState, to: exportDir)
let exportedJSON = (try? String(contentsOf: exportDir.appendingPathComponent("dayline-journal.json"), encoding: .utf8)) ?? ""
check(exportedJSON.contains("Exported"), "journal export contains entries")
check(!exportedJSON.contains("someone@example.com"), "journal export leaves settings out")
try? FileManager.default.removeItem(at: recoveryDir)
try? FileManager.default.removeItem(at: rollingDir)

// MARK: - AI periods and keyless custom endpoints

let insightWeek = InsightPeriod.week(containing: at("2026-11-25", 12))
equal(DayKey.make(insightWeek.start), "2026-11-23", "insight week starts on Monday")
equal(DayKey.make(insightWeek.end), "2026-11-27", "insight week ends on Friday")

struct StubTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = #"{"choices":[{"message":{"content":"{\"observations\":[\"ok\"],\"suggestions\":[],\"days\":[]}"}}]}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
var localState = AppState(settings: settings)
localState.settings.ai.provider = .custom
localState.settings.ai.baseURL = "http://llm.local:8080/v1"
localState.settings.ai.customModel = "local-model"
let keyless = try? await AIClient(transport: StubTransport())
    .insights(state: localState, period: .lastDays(7, endingAt: at("2026-11-27", 12)))
equal(keyless?.observations.first, "ok", "a custom endpoint works without an API key")

// MARK: - Equipment the user owns

var gear = baseSettings()
equal(gear.missingBuiltInEquipment.count, 0, "all built-in equipment is present by default")
gear.removeEquipment(.walkingPad)
check(!ExerciseLibrary.available(settings: gear).contains { $0.kind == .walkingPad },
      "removed equipment takes its exercises out")
equal(gear.missingBuiltInEquipment, [.walkingPad], "removed equipment can be added back")
gear.addEquipment(.walkingPad)
check(ExerciseLibrary.available(settings: gear).contains { $0.kind == .walkingPad }, "re-added equipment returns")

let pullUpBar = CustomEquipment(name: "Pull-up bar", minutes: 4, countsAsStanding: true)
gear.customEquipment.append(pullUpBar)
let customExercise = ExerciseLibrary.find(pullUpBar.exerciseID, settings: gear)
equal(customExercise?.name, "Pull-up bar", "custom equipment brings its own activity")
equal(customExercise?.kind, .custom, "custom activity kind")
check(ExerciseLibrary.available(settings: gear).contains { $0.id == pullUpBar.exerciseID }, "custom activity is available")
gear.customEquipment[0].enabled = false
check(!ExerciseLibrary.available(settings: gear).contains { $0.id == pullUpBar.exerciseID },
      "switched-off custom equipment is not suggested")
gear.customEquipment[0].enabled = true

// The engine reaches a custom activity in its rotation.
var customDay = makeDay()
customDay.nextBreakDue = at("2026-11-27", 9, 30)
customDay.lastBreakKind = .balanceBoard
let customPlan = Planner.plan(events: [], date: at("2026-11-27", 10), settings: gear, calendar: cal)
let customDecision = BreakEngine.decide(now: at("2026-11-27", 10), day: customDay, settings: gear,
                                        plan: customPlan, health: HealthSnapshot(stress: 20, bodyBattery: 60),
                                        media: .clear, activeBreak: false, calendar: cal)
equal(customDecision.exercise?.id, pullUpBar.exerciseID, "the engine suggests custom equipment in turn")
equal(customDecision.nextBreakLabel, "Pull-up bar", "a custom break is called by its own name")

// Settings with custom equipment survive a round trip.
let gearData = try JSONEncoder().encode(gear)
let gearBack = try JSONDecoder().decode(AppSettings.self, from: gearData)
equal(gearBack.customEquipment.first?.name, "Pull-up bar", "custom equipment is saved")

// MARK: - Day totals follow the activity list

func activity(_ kind: BreakKind, _ minutes: Int, outcome: BreakOutcome = .done,
              countsAsStanding: Bool? = nil) -> BreakEvent {
    BreakEvent(dayKey: "2026-11-27", exerciseID: kind.rawValue, kind: kind,
               plannedAt: at("2026-11-27", 10), startedAt: at("2026-11-27", 10),
               outcome: outcome, minutes: minutes, countsAsStanding: countsAsStanding)
}
var logged = [activity(.walkingPad, 20), activity(.standingBlock, 30), activity(.squats, 2),
              activity(.lunch, 35), activity(.custom, 10, countsAsStanding: true),
              activity(.custom, 10, countsAsStanding: false), activity(.balanceBoard, 5, outcome: .skipped)]
var totals = DayTotals.totals(for: logged)
equal(totals.walking, 20, "walking minutes come from walking-pad sessions")
equal(totals.standing, 30 + 1 + 10 + 5, "standing adds blocks, short breaks at half length and custom equipment")
equal(totals.lunch, 35, "lunch is the longest lunch")
logged[0].minutes = 45
logged.removeAll { $0.kind == .standingBlock }
totals = DayTotals.totals(for: logged)
equal(totals.walking, 45, "editing an activity's length changes the total")
equal(totals.standing, 1 + 10 + 5, "deleting an activity removes its minutes")
var totalsDay = makeDay()
totalsDay.standingMinutes = 999
DayTotals.apply(to: &totalsDay, breaks: logged)
equal(totalsDay.standingMinutes, 16, "applied totals replace stale counters")

// A custom activity keeps its name in history after the equipment is gone.
let named = BreakEvent(dayKey: "2026-11-27", exerciseID: pullUpBar.exerciseID, kind: .custom,
                       plannedAt: at("2026-11-27", 10), outcome: .done, minutes: 4, title: "Pull-up bar")
equal(named.displayTitle, "Pull-up bar", "custom activities show their own name")
equal(activity(.squats, 2).displayTitle, "Squats", "built-in activities show their kind")
let namedBack = try JSONDecoder().decode(BreakEvent.self, from: JSONEncoder().encode(named))
equal(namedBack.title, "Pull-up bar", "the name is saved with the activity")

// MARK: - Result

print("Ran \(checks) checks.")
if failures.isEmpty {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures.count) failed:")
    for f in failures { print("  ✗ \(f)") }
    exit(1)
}
