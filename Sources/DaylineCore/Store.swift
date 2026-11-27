import Foundation

/// JSON persistence for `AppState`.
///
/// All file access runs on one serial queue, so saves can be requested from the
/// main thread without blocking it and never interleave.
public final class Store: @unchecked Sendable {
    public let directory: URL
    public let stateURL: URL

    /// Set by `load()` when the state file needed recovery. Read once at launch.
    public private(set) var loadWarning: String?

    private let queue = DispatchQueue(label: "dayline.store", qos: .utility)
    /// Guards `generation` so requesting a save never waits for a write in progress.
    private let lock = NSLock()
    private var generation = 0
    private let backupsToKeep = 7

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = Store.defaultDirectory(named: "Dayline")
        }
        self.stateURL = self.directory.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(name, isDirectory: true)
    }

    public var exportsDirectory: URL {
        directory.appendingPathComponent("Exports", isDirectory: true)
    }

    public var garminDirectory: URL {
        directory.appendingPathComponent("Garmin", isDirectory: true)
    }

    public var backupsDirectory: URL {
        directory.appendingPathComponent("Backups", isDirectory: true)
    }

    private var sampleStashURL: URL {
        directory.appendingPathComponent("state.before-samples.json")
    }

    // MARK: Load

    /// Loads the state. A file that cannot be read is moved aside and the
    /// newest readable backup is used instead. A file that reads only in part
    /// (records from a newer or older schema) is copied aside before anything
    /// can overwrite it.
    public func load() -> AppState {
        queue.sync {
            let fm = FileManager.default
            guard fm.fileExists(atPath: stateURL.path) else { return AppState() }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            do {
                let data = try Data(contentsOf: stateURL)
                let state = try Store.makeDecoder().decode(AppState.self, from: data)
                if state.decodeIssues > 0 {
                    let copy = directory.appendingPathComponent("state.unreadable-records-\(stamp).json")
                    try? fm.copyItem(at: stateURL, to: copy)
                    loadWarning = "\(state.decodeIssues) saved record\(state.decodeIssues == 1 ? "" : "s") could not be read. The original file was kept as \(copy.lastPathComponent)."
                }
                return state
            } catch {
                let corrupt = directory.appendingPathComponent("state.corrupt-\(stamp).json")
                try? fm.moveItem(at: stateURL, to: corrupt)
                if let (backup, name) = newestReadableBackup() {
                    loadWarning = "state.json could not be read and was kept as \(corrupt.lastPathComponent). Restored the backup \(name)."
                    return backup
                }
                loadWarning = "state.json could not be read and was kept as \(corrupt.lastPathComponent). Starting empty."
                return AppState()
            }
        }
    }

    // MARK: Save

    /// Encodes and writes on the store queue. If several saves are requested
    /// before one runs, only the newest state is written. `completion` receives
    /// an error message, or nil on success, on an arbitrary queue.
    public func saveAsync(_ state: AppState, completion: (@Sendable (String?) -> Void)? = nil) {
        let requested = nextGeneration()
        queue.async { [self] in
            guard requested == currentGeneration() else { return }
            completion?(write(state))
        }
    }

    /// Writes immediately and waits. Use at quit, and in checks.
    @discardableResult
    public func save(_ state: AppState) -> Bool {
        _ = nextGeneration()
        return queue.sync { write(state) == nil }
    }

    private func nextGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func currentGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// Must run on `queue`. Returns an error message, or nil on success.
    private func write(_ state: AppState) -> String? {
        do {
            let data = try Store.makeEncoder().encode(state)
            snapshotBeforeFirstWriteOfDay()
            try data.write(to: stateURL, options: .atomic)
            return nil
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Backups

    /// Before the first write of each day, keep yesterday's last state.
    private func snapshotBeforeFirstWriteOfDay() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stateURL.path) else { return }
        let target = backupsDirectory.appendingPathComponent("state-\(DayKey.make(Date())).json")
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? fm.copyItem(at: stateURL, to: target)
        let old = backupFiles().dropFirst(backupsToKeep)
        for url in old { try? fm.removeItem(at: url) }
    }

    /// Backup files, newest first. Names sort by date.
    private func backupFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("state-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func newestReadableBackup() -> (AppState, String)? {
        for url in backupFiles() {
            if let data = try? Data(contentsOf: url),
               let state = try? Store.makeDecoder().decode(AppState.self, from: data) {
                return (state, url.lastPathComponent)
            }
        }
        return nil
    }

    // MARK: Sample data

    /// Keeps the real state aside while sample data is loaded over it.
    @discardableResult
    public func stashBeforeSamples(_ state: AppState) -> Bool {
        queue.sync {
            guard let data = try? Store.makeEncoder().encode(state) else { return false }
            return (try? data.write(to: sampleStashURL, options: .atomic)) != nil
        }
    }

    /// Returns the state stashed by `stashBeforeSamples` and removes the stash.
    public func restoreStashedState() -> AppState? {
        queue.sync {
            guard let data = try? Data(contentsOf: sampleStashURL),
                  let state = try? Store.makeDecoder().decode(AppState.self, from: data) else { return nil }
            try? FileManager.default.removeItem(at: sampleStashURL)
            return state
        }
    }

    /// Writes one Markdown file per day plus a full JSON dump into `folder`.
    @discardableResult
    public func exportJournal(_ state: AppState, to folder: URL) -> Int {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written = 0
        let days = Set(state.journal.map { DayKey.make($0.at) })
            .union(state.checkIns.map { DayKey.make($0.at) })
            .sorted()
        for dayKey in days {
            let text = JournalExport.markdown(dayKey: dayKey, state: state)
            let url = folder.appendingPathComponent("\(dayKey).md")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                written += 1
            }
        }
        let encoder = Store.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let dump = try? encoder.encode(JournalDump(journal: state.journal, checkIns: state.checkIns)) {
            try? dump.write(to: folder.appendingPathComponent("dayline-journal.json"), options: .atomic)
        }
        return written
    }
}

/// The JSON export holds the journal only: no settings, calendar or health data.
struct JournalDump: Encodable {
    var journal: [JournalEntry]
    var checkIns: [CheckIn]
}

public enum JournalExport {
    public static func markdown(dayKey: String, state: AppState) -> String {
        let day = state.day(dayKey)
        let checkIns = state.checkIns(on: dayKey)
        let entries = state.journal(on: dayKey)
        let breaks = state.breaks(on: dayKey).filter { $0.outcome != .planned }
        let metrics = Summarizer.metrics(dayKey: dayKey, state: state)
        var out: [String] = []
        let date = DayKey.date(from: dayKey) ?? Date()
        out.append("# \(Fmt.weekdayLong.string(from: date)) \(Fmt.dayMonthYear.string(from: date))")
        out.append("")

        if let day {
            out.append("## Day")
            out.append("- Started: \(day.start.map { Fmt.time.string(from: $0) } ?? "—")")
            out.append("- Ended: \(day.end.map { Fmt.time.string(from: $0) } ?? "—")")
            out.append("- Standing / walking: \(day.standingMinutes) / \(day.walkingMinutes) min (target \(day.targets.standingMinutes))")
            out.append("- Breaks: \(metrics.breaksTaken) taken, \(metrics.breaksSkipped) skipped")
            out.append("- Lunch away: \(day.lunchMinutes) min")
            out.append("- Longest seated stretch: \(day.longestSeatedMinutes) min")
            out.append("- Meetings: \(Fmt.duration(day.meetingMinutes)), longest run \(Fmt.duration(day.longestBackToBackMinutes))")
            if let stress = metrics.stressAverage { out.append("- Average stress: \(stress)") }
            if let battery = metrics.bodyBatteryEnd { out.append("- Body Battery at end: \(battery)") }
            out.append("")
        }

        if !checkIns.isEmpty {
            out.append("## Check-ins")
            for c in checkIns {
                out.append("- **\(Fmt.time.string(from: c.at)) · \(c.word)** (energy \(c.energy)/4, mood \(c.mood)/4, \(c.quadrant.name))\(c.note.isEmpty ? "" : " — \(c.note)")")
            }
            out.append("")
        }

        if !breaks.isEmpty {
            out.append("## Breaks")
            for b in breaks {
                let when = b.startedAt.map { Fmt.time.string(from: $0) } ?? Fmt.time.string(from: b.plannedAt)
                switch b.outcome {
                case .done:
                    out.append("- \(when) · \(b.displayTitle) · \(b.minutes) min\(b.verifiedBy.map { " · verified by \($0.rawValue)" } ?? "")")
                case .skipped:
                    out.append("- \(when) · \(b.displayTitle) · skipped\(b.skipReason.map { " (\($0.rawValue))" } ?? "")")
                default:
                    break
                }
            }
            out.append("")
        }

        for entry in entries {
            let title = entry.kind == .reflection ? "Reflection" : "Note"
            out.append("## \(title) · \(Fmt.time.string(from: entry.at))")
            if !entry.text.isEmpty {
                out.append(entry.text)
                out.append("")
            }
            for answer in entry.promptAnswers where !answer.answer.isEmpty {
                out.append("**\(answer.prompt)**")
                out.append(answer.answer)
                out.append("")
            }
            var context: [String] = []
            if let stress = entry.context.stress { context.append("Stress \(stress)") }
            if let battery = entry.context.bodyBattery { context.append("Body Battery \(battery)") }
            if entry.context.breaksToday > 0 { context.append("\(entry.context.breaksToday) breaks") }
            if let title = entry.context.lastMeetingTitle, let minutes = entry.context.lastMeetingMinutes {
                context.append("After \(title) (\(minutes) min)")
            }
            if let title = entry.context.nextMeetingTitle, let minutes = entry.context.nextMeetingMinutes {
                context.append("Before \(title) (\(minutes) min)")
            }
            if !context.isEmpty {
                out.append("_Context: \(context.joined(separator: " · "))_")
                out.append("")
            }
        }

        out.append("---")
        out.append("Exported from Dayline on \(Fmt.dayMonthYear.string(from: Date())).")
        return out.joined(separator: "\n")
    }
}
