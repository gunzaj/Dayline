import Foundation

/// Deterministic sample data for previews and screenshots. Enabled only with
/// DAYLINE_DEMO=1 (or the button in Settings → General), never in normal use.
public enum DemoData {

    private struct RNG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let x = state >> 33
            return Double(x) / Double(UInt64(1) << 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            let span = range.upperBound - range.lowerBound + 1
            return range.lowerBound + Int(next() * Double(span)) % span
        }
        mutating func chance(_ p: Double) -> Bool { next() < p }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    }

    private static let meetings: [(String, Int, Int, Int, Bool)] = [
        // title, start hour, minutes, attendees, recurring
        ("Team standup", 9, 15, 8, true),
        ("Design review", 10, 90, 6, true),
        ("1:1 with Sam", 12, 30, 2, true),
        ("Product planning", 13, 60, 12, true),
        ("Research sync", 15, 30, 5, true),
        ("Weekly sync", 14, 45, 9, true),
        ("Workshop: onboarding", 11, 120, 14, false),
        ("Roadmap review", 16, 60, 7, true),
        ("Focus block", 9, 120, 1, false),
    ]

    public static func seed(into state: inout AppState, endingAt: Date = Date(),
                            days: Int = 365, calendar: Calendar = .current) {
        let rngSeed: UInt64 = 0xD4A11E
        var rng = RNG(seed: rngSeed)
        let end = DayKey.startOfDay(endingAt, calendar: calendar)

        var workingDays: [Date] = []
        for offset in stride(from: -days, through: 0, by: 1) {
            let date = DayKey.adding(days: offset, to: end, calendar: calendar)
            guard state.settings.schedule(for: date, calendar: calendar) != nil else { continue }
            workingDays.append(date)
        }

        let holidays = Set([
            "-12-24", "-12-25", "-12-26", "-12-29", "-12-30", "-12-31", "-01-01", "-01-02",
        ])
        let today = end

        for date in workingDays {
            let key = DayKey.make(date, calendar: calendar)
            let monthDay = String(key.suffix(6))
            let isHoliday = holidays.contains { monthDay == $0 }
            let isSummer = key.hasSuffix("-08-03") || key.hasSuffix("-08-04") || key.hasSuffix("-08-05")
                || key.hasSuffix("-08-06") || key.hasSuffix("-08-07")
            let isToday = key == DayKey.make(today, calendar: calendar)
            let weekday = DayKey.mondayIndex(date, calendar: calendar)

            if isHoliday || isSummer {
                var day = WorkDay(dayKey: key, date: date, targets: state.settings.targets)
                day.isOff = true
                state.days.append(day)
                if !state.offDays.contains(key) { state.offDays.append(key) }
                continue
            }

            // Calendar pattern: Wednesdays heavy, Fridays lighter, some workshops.
            var busyMinutes = 0
            var events: [CalendarEvent] = []
            let count = weekday == 2 ? 4 : rng.int(2...3)
            var used = Set<Int>()
            for _ in 0..<count {
                let pickIndex = rng.int(0...(meetings.count - 1))
                if used.contains(pickIndex) { continue }
                used.insert(pickIndex)
                let m = meetings[pickIndex]
                let startHour = m.1
                let start = calendar.date(bySettingHour: startHour, minute: rng.chance(0.5) ? 0 : 30, second: 0, of: date) ?? date
                let length = m.2
                let event = CalendarEvent(id: key + "-" + String(pickIndex), title: m.0,
                                          start: start, end: start.adding(minutes: length),
                                          attendeeCount: m.3, isRecurring: m.4,
                                          calendarID: "work", calendarTitle: "Work")
                events.append(event)
                busyMinutes += length
            }
            events.sort { $0.start < $1.start }
            if !events.isEmpty { state.calendarSnapshots[key] = events }

            var day = WorkDay(dayKey: key, date: date, targets: state.settings.targets)
            let startHour = 9
            day.start = calendar.date(bySettingHour: startHour, minute: rng.int(0...12), second: 0, of: date)
            day.startSource = .auto
            day.meetingMinutes = busyMinutes
            day.longestBackToBackMinutes = busyMinutes >= 150 ? busyMinutes : max(60, busyMinutes / 2)

            // Performance improves across the year.
            let yearProgress = Double(workingDays.firstIndex(of: date) ?? 0) / Double(max(1, workingDays.count - 1))
            let targetMoves = 70 + yearProgress * 65
            day.standingMinutes = Int(targetMoves * (0.55 + rng.next() * 0.45) * (weekday == 2 ? 0.72 : 1))
            day.walkingMinutes = Int(Double(day.standingMinutes) * (0.28 + rng.next() * 0.2))
            day.seatedMinutes = Int(300 + Double(busyMinutes) * 1.1)
            day.longestSeatedMinutes = Int(65 + rng.next() * 55)
            day.lunchMinutes = rng.chance(0.82) ? (30 + rng.int(0...15)) : rng.int(0...20)
            day.lastBreakEnd = day.start?.adding(minutes: 120)

            let sleepScore = 58 + Int((1 - Double(busyMinutes) / 400.0) * 22) + rng.int(-6...10)
            let batteryWake = max(18, min(92, 70 + rng.int(-20...15)))
            let avgStress = max(14, min(72, 18 + busyMinutes / 8 + rng.int(-8...12)))
            let health = DailyHealth(dayKey: key,
                                     sleepScore: max(40, min(98, sleepScore)),
                                     sleepMinutes: 330 + rng.int(0...130),
                                     hrvStatus: sleepScore > 76 ? "Balanced" : (sleepScore > 62 ? "Unbalanced" : "Low"),
                                     bodyBatteryWake: batteryWake,
                                     restingHeartRate: 52 + rng.int(0...9),
                                     stressAverage: avgStress,
                                     bodyBatteryEnd: max(5, batteryWake - 35 - busyMinutes / 12 + rng.int(-6...6)))
            state.healthDaily.removeAll { $0.dayKey == key }
            state.healthDaily.append(health)

            // Intraday samples, 30-minute buckets from 09:00 to 17:30.
            var battery = batteryWake
            var stress = 20
            var minute = 9 * 60
            let endMinute = isToday ? max(9 * 60 + 30, min(17 * 60 + 30, minutesNow(endingAt))) : 17 * 60 + 30
            while minute <= endMinute {
                guard let sampleDate = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) else { break }
                let inMeeting = events.contains { $0.isActive(at: sampleDate) }
                stress = max(12, min(88, stress + (inMeeting ? rng.int(2...9) : rng.int(-9 ... -2))))
                battery = max(4, min(100, battery - (inMeeting ? rng.int(0...3) : rng.int(-1...1))))
                state.healthSamples.append(HealthSample(at: sampleDate, stress: stress,
                                                        bodyBattery: battery,
                                                        steps: 120 + (minute - 540) * 3,
                                                        heartRate: 62 + (inMeeting ? rng.int(4...16) : rng.int(-3...7))))
                minute += 30
            }

            // Breaks.
            var breakKinds: [BreakKind] = [.boxBreathing, .squats, .standUpStretch, .walkingPad,
                                           .matMobility, .gripSets, .standingBlock, .balanceBoard]
            if weekday == 2 { breakKinds.append(.boxBreathing) }
            let breakCount = max(2, min(8, Int((Double(day.standingMinutes) / 22.0).rounded())))
            var breakStart = (day.start ?? date).adding(minutes: 50)
            for _ in 0..<breakCount {
                if breakStart > (day.start ?? date).adding(minutes: max(60, endMinute - 540)) { break }
                let kind = rng.pick(breakKinds)
                let exercise = ExerciseLibrary.forKind(kind).first
                let minutes = kind == .boxBreathing ? rng.pick([2, 3, 4]) : (kind == .walkingPad ? rng.pick([15, 20, 25]) : kind.defaultMinutes)
                let skipped = rng.chance(0.12)
                let event = BreakEvent(dayKey: key,
                                       exerciseID: exercise?.id ?? kind.rawValue,
                                       kind: kind,
                                       plannedAt: breakStart,
                                       escalationStep: 2,
                                       startedAt: skipped ? nil : breakStart,
                                       endedAt: skipped ? nil : breakStart.adding(minutes: minutes),
                                       outcome: skipped ? .skipped : .done,
                                       skipReason: skipped ? rng.pick(SkipReason.allCases) : nil,
                                       verifiedBy: skipped ? nil : rng.pick([.auto, .confirm, .honor]),
                                       minutes: minutes)
                state.breaks.append(event)
                breakStart = breakStart.adding(minutes: minutes + 35 + rng.int(0...20))
            }
            if day.lunchMinutes >= 30 {
                state.breaks.append(BreakEvent(dayKey: key, exerciseID: "lunch-away", kind: .lunch,
                                               plannedAt: (day.start ?? date).adding(minutes: 195),
                                               startedAt: (day.start ?? date).adding(minutes: 195),
                                               endedAt: (day.start ?? date).adding(minutes: 195 + day.lunchMinutes),
                                               outcome: .done, verifiedBy: .confirm,
                                               minutes: day.lunchMinutes))
            }

            // Check-ins and the reflection.
            let mood: (Int, Int, MoodQuadrant, String)
            if avgStress > 42 || busyMinutes > 240 {
                mood = (rng.chance(0.4) ? 3 : 2, rng.chance(0.25) ? 3 : 2,
                        rng.chance(0.4) ? .tenseWired : .drainedFlat,
                        rng.chance(0.4) ? "Overwhelmed" : rng.pick(["Drained", "Wired", "Foggy", "Irritated"]))
            } else {
                mood = (rng.chance(0.5) ? 3 : 2, rng.chance(0.6) ? 3 : 4,
                        rng.chance(0.5) ? .calmContent : .energizedFocused,
                        rng.chance(0.5) ? "Steady" : rng.pick(["Focused", "Calm", "Content", "Upbeat"]))
            }
            let checkInTime = (day.start ?? date).adding(minutes: rng.int(5...25))
            let checkIn = CheckIn(at: checkInTime, energy: mood.0, mood: mood.1,
                                  word: mood.3, note: "", source: .morning)
            state.checkIns.append(checkIn)

            if !isToday && rng.chance(0.75) {
                let reflectionAt = (day.start ?? date).adding(minutes: 500 + rng.int(0...60))
                let contexts: [(String, String)] = [
                    ("What drained you today?", "The long \(events.first?.title ?? "review") and the planning call back to back with only lunch between."),
                    ("What went well, even if small?", "Took a call on the walking pad. Felt sharper afterwards."),
                    ("What would make tomorrow 10% better?", "One 30-minute block with no calls before the design review."),
                    ("What frustrated you, and was it in your control?", "Scope kept changing in the thread. I could have asked for a decision owner earlier."),
                    ("When did you feel most like yourself?", "The quiet hour after the last call, when I could actually think."),
                ]
                let answers = [contexts[0], contexts[1], contexts[2]]
                let text = answers.map { $0.1 }.joined(separator: " ")
                let reflectionCheck = CheckIn(at: reflectionAt.adding(minutes: -1), energy: mood.0,
                                              mood: mood.1, word: mood.3, source: .reflection)
                state.checkIns.append(reflectionCheck)
                let prompts = answers.map { PromptAnswer(prompt: $0.0, answer: $0.1) }
                let entry = JournalEntry(at: reflectionAt, kind: .reflection, text: text,
                                         promptAnswers: prompts, checkInID: reflectionCheck.id,
                                         context: EntryContext(stress: avgStress, bodyBattery: health.bodyBatteryEnd,
                                                               breaksToday: breakCount, standingMinutes: day.standingMinutes,
                                                               meetingHours: Double(busyMinutes) / 60.0,
                                                               lastMeetingTitle: events.last?.title,
                                                               lastMeetingMinutes: events.last?.minutes))
                state.journal.append(entry)

                if rng.chance(0.3) {
                    let note = JournalEntry(at: reflectionAt.adding(minutes: -320), kind: .free,
                                            text: rng.pick([
                                                "Design review ran 30 min over again. Same discussion about empty states as last week.",
                                                "Good focus block after lunch. The walking pad call actually helped.",
                                                "Spent too long on a thread that should have been a 10-minute call.",
                                                "Noticed I skip breaks when the calendar is full, which is exactly backwards.",
                                            ]), context: EntryContext())
                    state.journal.append(note)
                }

                day.end = reflectionAt.adding(minutes: 15)
                day.endSource = .manual
            }

            day.nextBreakDue = isToday ? endingAt.adding(minutes: 12) : nil
            day.lastBreakKind = rng.pick([.boxBreathing, .squats, .walkingPad, .matMobility])
            day.windDownPromptedAt = isToday ? nil : day.end
            state.days.removeAll { $0.dayKey == key }
            state.days.append(day)
        }

        state.settings.showDemoData = true
        state.settings.garmin.connected = true
        state.settings.garmin.lastLoginAt = end.adding(days: -30)
        state.settings.garmin.lastError = nil
        if state.settings.micIgnoreBundleIDs.isEmpty {
            state.settings.micIgnoreBundleIDs = ["com.apple.VoiceInput"]
        }
        state.days.sort { $0.dayKey < $1.dayKey }
        state.breaks.sort { $0.plannedAt < $1.plannedAt }
        state.checkIns.sort { $0.at < $1.at }
        state.journal.sort { $0.at < $1.at }
        state.healthSamples.sort { $0.at < $1.at }
        state.healthDaily.sort { $0.dayKey < $1.dayKey }
        state.lastGarminSync = endingAt.adding(minutes: -6)
    }

    private static func minutesNow(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public static func clearSampleData(from state: inout AppState) {
        state.days.removeAll()
        state.breaks.removeAll()
        state.checkIns.removeAll()
        state.journal.removeAll()
        state.insights.removeAll()
        state.healthDaily.removeAll()
        state.healthSamples.removeAll()
        state.calendarSnapshots.removeAll()
        state.offDays.removeAll()
        state.settings.showDemoData = false
    }
}
