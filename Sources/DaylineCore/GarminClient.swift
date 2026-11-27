import Foundation

public struct GarminSync: Sendable {
    public var samples: [HealthSample]
    public var daily: [DailyHealth]
    public var tokens: String?
    public var fetchedAt: Date
    public var warnings: [String]
    public var lastDeviceSync: String?
}

public struct GarminLoginResult: Sendable {
    public var tokens: String
    public var displayName: String?
}

public enum GarminError: LocalizedError {
    case helperMissing(String)
    case dependencyMissing(String)
    case needsMFA(clientState: String)
    case login(String)
    case notSignedIn
    case process(String)

    public var errorDescription: String? {
        switch self {
        case .helperMissing(let path): return "Garmin helper not found at \(path). Reinstall the app."
        case .dependencyMissing(let detail): return "Garmin support is not set up yet. Run scripts/setup-garmin.sh. \(detail)"
        case .needsMFA: return "Garmin asked for a verification code."
        case .login(let message): return message
        case .notSignedIn: return "Not signed in to Garmin."
        case .process(let message): return message
        }
    }
}

/// Wraps the bundled Python helper. It is the only Garmin code in the app.
public struct GarminClient: Sendable {
    public var helperURL: URL
    public var pythonURL: URL

    public init(helperURL: URL, pythonURL: URL) {
        self.helperURL = helperURL
        self.pythonURL = pythonURL
    }

    public static func locate(storeDirectory: URL) -> GarminClient? {
        let fm = FileManager.default
        let venv = storeDirectory
            .appendingPathComponent("Garmin", isDirectory: true)
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("garmin/garmin_helper.py"),
            Bundle.main.resourceURL?.appendingPathComponent("garmin_helper.py"),
        ].compactMap { $0 }
        guard let helper = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return nil }
        let python: URL
        if fm.isExecutableFile(atPath: venv.path) {
            python = venv
        } else if fm.isExecutableFile(atPath: "/opt/homebrew/bin/python3.13") {
            python = URL(fileURLWithPath: "/opt/homebrew/bin/python3.13")
        } else if fm.isExecutableFile(atPath: "/usr/local/bin/python3.13") {
            python = URL(fileURLWithPath: "/usr/local/bin/python3.13")
        } else {
            python = URL(fileURLWithPath: "/usr/bin/python3")
        }
        return GarminClient(helperURL: helper, pythonURL: python)
    }

    /// Earlier builds left a token file on disk. Tokens live only in the
    /// Keychain now, so remove it wherever it is found.
    public static func removeLegacyTokenStore(storeDirectory: URL) {
        let legacy = storeDirectory.appendingPathComponent("Garmin/tokenstore", isDirectory: true)
        try? FileManager.default.removeItem(at: legacy)
    }

    public func status() async throws -> [String: Any] {
        try await run(command: "status", payload: [:])
    }

    public func login(email: String, password: String, mfa: String? = nil,
                      clientState: String? = nil) async throws -> GarminLoginResult {
        var payload: [String: Any] = ["email": email]
        if let mfa, let clientState {
            // Finishing an MFA login needs the code and the pending state, not the password.
            payload["mfa"] = mfa
            payload["clientState"] = clientState
        } else {
            payload["password"] = password
        }
        let result = try await run(command: "login", payload: payload)
        if let need = result["needMFA"] as? Bool, need,
           let state = result["clientState"] as? String {
            throw GarminError.needsMFA(clientState: state)
        }
        if let code = result["errorCode"] as? String, code == "dependency_missing" {
            throw GarminError.dependencyMissing(result["detail"] as? String ?? "")
        }
        guard let tokens = result["tokens"] as? String, !tokens.isEmpty else {
            throw GarminError.login(result["error"] as? String ?? "Garmin login failed.")
        }
        return GarminLoginResult(tokens: tokens, displayName: result["displayName"] as? String)
    }

    public func sync(tokens: String, daysBack: Int = 0) async throws -> GarminSync {
        let result = try await run(command: "sync", payload: ["tokens": tokens],
                                   extraArgs: ["--days", String(max(0, daysBack))],
                                   timeout: 180 + TimeInterval(max(0, daysBack)) * 30)
        if let code = result["errorCode"] as? String, code == "dependency_missing" {
            throw GarminError.dependencyMissing(result["detail"] as? String ?? "")
        }
        if let ok = result["ok"] as? Bool, !ok {
            if (result["errorCode"] as? String) == "no_tokens" { throw GarminError.notSignedIn }
            throw GarminError.login(result["error"] as? String ?? "Garmin sync failed.")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        func parseDate(_ raw: Any?) -> Date? {
            guard let string = raw as? String else { return nil }
            return iso.date(from: string) ?? isoNoFraction.date(from: string)
        }

        var samples: [HealthSample] = []
        if let rawSamples = result["samples"] as? [[String: Any]] {
            for row in rawSamples {
                guard let at = parseDate(row["at"]) else { continue }
                samples.append(HealthSample(at: at,
                                            stress: row["stress"] as? Int,
                                            bodyBattery: row["bodyBattery"] as? Int,
                                            steps: row["steps"] as? Int,
                                            heartRate: row["heartRate"] as? Int))
            }
        }
        var daily: [DailyHealth] = []
        if let rawDaily = result["daily"] as? [[String: Any]] {
            for row in rawDaily {
                guard let key = row["dayKey"] as? String else { continue }
                daily.append(DailyHealth(dayKey: key,
                                         sleepScore: row["sleepScore"] as? Int,
                                         sleepMinutes: row["sleepMinutes"] as? Int,
                                         hrvStatus: row["hrvStatus"] as? String,
                                         bodyBatteryWake: row["bodyBatteryWake"] as? Int,
                                         restingHeartRate: row["restingHeartRate"] as? Int,
                                         stressAverage: row["stressAverage"] as? Int,
                                         bodyBatteryEnd: row["bodyBatteryEnd"] as? Int))
            }
        }
        return GarminSync(samples: samples, daily: daily,
                          tokens: result["tokens"] as? String,
                          fetchedAt: parseDate(result["fetchedAt"]) ?? Date(),
                          warnings: (result["warnings"] as? [String]) ?? [],
                          lastDeviceSync: result["lastDeviceSync"] as? String)
    }

    // MARK: Process

    /// Collects one pipe on its own thread so a full stderr can never stall stdout.
    private final class PipeReader: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let done = DispatchSemaphore(value: 0)

        init(_ handle: FileHandle) {
            DispatchQueue.global(qos: .utility).async { [self] in
                let read = handle.readDataToEndOfFile()
                lock.lock(); data = read; lock.unlock()
                done.signal()
            }
        }

        func text() -> String {
            done.wait()
            lock.lock(); defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// The helper gets a minimal environment rather than everything the app has.
    private static func helperEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "PATH", "LANG", "LC_ALL", "TMPDIR", "SSL_CERT_FILE",
                    "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "no_proxy"] {
            if let value = inherited[key] { env[key] = value }
        }
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return env
    }

    private func run(command: String, payload: [String: Any],
                     extraArgs: [String] = [], timeout: TimeInterval = 120) async throws -> [String: Any] {
        let helper = helperURL
        let python = pythonURL
        guard FileManager.default.fileExists(atPath: helper.path) else {
            throw GarminError.helperMissing(helper.path)
        }
        let inputData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = python
                process.arguments = [helper.path, command] + extraArgs
                process.environment = GarminClient.helperEnvironment()

                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GarminError.process("Could not start Python: \(error.localizedDescription)"))
                    return
                }

                let out = PipeReader(stdout.fileHandleForReading)
                let err = PipeReader(stderr.fileHandleForReading)

                // A hung helper must not leave Garmin "busy" forever.
                let timedOut = Flag()
                let watchdog = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.set()
                        process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

                try? stdin.fileHandleForWriting.write(contentsOf: inputData)
                try? stdin.fileHandleForWriting.close()

                process.waitUntilExit()
                watchdog.cancel()
                let outText = out.text()
                let errText = err.text()

                if timedOut.isSet {
                    continuation.resume(throwing: GarminError.process("Garmin did not answer within \(Int(timeout)) s. Try again later."))
                    return
                }

                for line in outText.split(separator: "\n").reversed() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("{"),
                          let data = trimmed.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    continuation.resume(returning: object)
                    return
                }
                let hint = errText.isEmpty ? "exit \(process.terminationStatus)" : String(errText.suffix(400))
                continuation.resume(throwing: GarminError.process("Garmin helper gave no JSON (\(hint))"))
            }
        }
    }
}
