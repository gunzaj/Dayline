import Foundation

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.transport("No HTTP response")
        }
        return (data, http)
    }
}

public enum AIError: LocalizedError {
    case missingKey
    case badURL
    case transport(String)
    case http(Int, String)
    case decoding(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add an API key in Settings → AI."
        case .badURL: return "The base URL is not valid."
        case .transport(let message): return "Could not reach the provider: \(message)"
        case .http(let code, let body): return "Provider returned HTTP \(code). \(String(body.prefix(240)))"
        case .decoding(let message): return "Could not read the provider response: \(message)"
        case .empty: return "The provider returned an empty answer."
        }
    }
}

// MARK: - Keychain

public enum Keychain {
    public static let service = "io.github.gunzaj.dayline"

    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Update in place when the item exists, so a failed write never
        // leaves the Keychain without the previous value.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public static func has(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - Prompt

public struct InsightPeriod: Sendable {
    public var start: Date
    public var end: Date
    public var label: String
    public var question: String?

    public init(start: Date, end: Date, label: String, question: String? = nil) {
        self.start = start
        self.end = end
        self.label = label
        self.question = question
    }

    public static func week(containing date: Date) -> InsightPeriod {
        let monday = DayKey.monday(of: date)
        let friday = DayKey.adding(days: 4, to: monday)
        let week = Calendar.current.component(.weekOfYear, from: monday)
        return InsightPeriod(start: monday, end: friday, label: "Week \(week)")
    }

    public static func lastDays(_ days: Int, endingAt: Date = Date()) -> InsightPeriod {
        let end = DayKey.startOfDay(endingAt)
        let start = DayKey.adding(days: -(days - 1), to: end)
        return InsightPeriod(start: start, end: end, label: "Last \(days) days")
    }
}

public enum AIPrompt {

    public static func system() -> String {
        return """
        You are the analyst inside Dayline, a personal workday coach. You read a single remote worker's \
        day-level data: calendar load, breaks, standing time, Garmin stress and Body Battery, sleep, and \
        their own mood check-ins and journal. Find patterns the person would not notice themselves.

        Rules:
        - Be specific and concrete. Tie every observation to the days it comes from, using the date keys.
        - Never moralise, diagnose, or give medical advice. No productivity clichés.
        - 3 to 5 observations, then 1 to 2 suggestions. Each observation is 1-2 sentences.
        - If the data is too thin to support a claim, say so instead of inventing a pattern.
        - Plain language. No emojis, no headings, no markdown.
        - Answer with strict JSON only: {"observations": ["..."], "suggestions": ["..."], "days": ["2026-11-24", ...]}
        """
    }

    public static func dataset(state: AppState, period: InsightPeriod) -> String {
        let settings = state.settings
        var lines: [String] = []
        lines.append("Period: \(period.label), \(DayKey.make(period.start)) to \(DayKey.make(period.end)).")
        lines.append("Targets: standing \(settings.standingTargetMinutes) min, \(settings.breaksTarget) breaks, lunch \(settings.lunchTargetMinutes) min, breathing \(settings.breathingTarget).")
        lines.append("")

        var cursor = DayKey.startOfDay(period.start)
        let end = DayKey.startOfDay(period.end)
        while cursor <= end {
            let key = DayKey.make(cursor)
            let m = Summarizer.metrics(dayKey: key, state: state)
            if m.isWorkday || m.hasData {
                var parts: [String] = []
                parts.append("\(key) \(Fmt.weekdayShort.string(from: cursor))")
                if m.isOff { parts.append("day off") }
                parts.append("meetings \(String(format: "%.1f", m.meetingHours))h")
                parts.append("longest run \(Fmt.compactDuration(m.longestBackToBackMinutes))")
                parts.append("standing \(m.movedMinutes)m")
                parts.append("breaks \(m.breaksTaken)")
                if m.breaksSkipped > 0 { parts.append("skipped \(m.breaksSkipped)") }
                parts.append("lunch \(m.lunchMinutes)m")
                parts.append("longest seated \(m.longestSeatedMinutes)m")
                if let stress = m.stressAverage { parts.append("stress avg \(stress)") }
                if let start = m.bodyBatteryStart { parts.append("battery \(start)→\(m.bodyBatteryEnd.map(String.init) ?? "?")") }
                if let sleep = state.dailyHealth(key)?.sleepScore { parts.append("sleep score \(sleep)") }
                if let hrv = state.dailyHealth(key)?.hrvStatus { parts.append("hrv \(hrv)") }
                if let word = m.moodWord { parts.append("mood \(word) (energy \(m.energy ?? 0)/4, pleasantness \(m.mood ?? 0)/4)") }
                parts.append("goals \(m.goalsHit)/5")
                lines.append("- " + parts.joined(separator: ", "))

                if settings.ai.shareJournalText {
                    for entry in state.journal(on: key) {
                        var text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            if text.count > 700 { text = String(text.prefix(700)) + "…" }
                            lines.append("  journal \(Fmt.time.string(from: entry.at)) [\(entry.kind.rawValue)]: \(text.replacingOccurrences(of: "\n", with: " "))")
                        }
                        for answer in entry.promptAnswers where !answer.answer.isEmpty {
                            lines.append("  prompt '\(answer.prompt)': \(answer.answer.replacingOccurrences(of: "\n", with: " "))")
                        }
                    }
                }
                if settings.ai.shareCalendarTitles, let planEvents = state.planEvents(for: key) {
                    for e in planEvents where e.blocksTime {
                        lines.append("  meeting: \(e.title) \(Fmt.time.string(from: e.start))-\(Fmt.time.string(from: e.end))")
                    }
                }
            }
            cursor = DayKey.adding(days: 1, to: cursor)
        }

        if let question = period.question, !question.isEmpty {
            lines.append("")
            lines.append("The person asks: \(question)")
            lines.append("Answer that question first in the observations, then add any other clear pattern.")
        }
        return lines.joined(separator: "\n")
    }

    public static func userMessage(state: AppState, period: InsightPeriod) -> String {
        return """
        Here is my data.

        \(dataset(state: state, period: period))

        Return the JSON object described in the system prompt.
        """
    }
}

// MARK: - Client

public final class AIClient {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func apiKey(for provider: AIProvider) -> String? {
        Keychain.get(provider.keychainAccount)
    }

    public func testConnection(settings: AISettings, apiKey: String) async throws -> String {
        let request = try Self.buildRequest(settings: settings, apiKey: apiKey,
                                            system: "You are a connection test.",
                                            user: "Reply with exactly: OK")
        let (data, http) = try await transport.send(request)
        try Self.checkHTTP(http, data: data)
        let text = try Self.extractText(provider: settings.provider, data: data)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func insights(state: AppState, period: InsightPeriod) async throws -> Insight {
        let settings = state.settings.ai
        let key = apiKey(for: settings.provider) ?? ""
        // A custom endpoint (a local model server) may not need a key.
        guard !key.isEmpty || settings.provider == .custom else {
            throw AIError.missingKey
        }
        let request = try Self.buildRequest(settings: settings, apiKey: key,
                                            system: AIPrompt.system(),
                                            user: AIPrompt.userMessage(state: state, period: period))
        let (data, http) = try await transport.send(request)
        try Self.checkHTTP(http, data: data)
        let text = try Self.extractText(provider: settings.provider, data: data)
        return try Self.parseInsight(text, period: period, settings: settings)
    }

    // MARK: Request building (public for checks)

    public static func endpoint(for settings: AISettings) -> URL? {
        switch settings.provider {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")
        case .custom:
            var raw = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return nil }
            if raw.hasSuffix("/") { raw.removeLast() }
            if raw.hasSuffix("/chat/completions") { return URL(string: raw) }
            return URL(string: raw + "/chat/completions")
        }
    }

    public static func buildRequest(settings: AISettings, apiKey: String,
                                    system: String, user: String) throws -> URLRequest {
        guard let url = endpoint(for: settings) else { throw AIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any]
        switch settings.provider {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            payload = [
                "model": settings.effectiveModel,
                "max_tokens": 1400,
                "temperature": 0.4,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        case .openai, .custom:
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            payload = [
                "model": settings.effectiveModel,
                "temperature": 0.4,
                "max_tokens": 1400,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    public static func checkHTTP(_ http: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    public static func extractText(provider: AIProvider, data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decoding("not JSON")
        }
        if provider == .anthropic {
            if let content = root["content"] as? [[String: Any]] {
                let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
        } else {
            if let choices = root["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            throw AIError.transport(message)
        }
        throw AIError.decoding("no text in response")
    }

    public static func parseInsight(_ text: String, period: InsightPeriod,
                                    settings: AISettings) throws -> Insight {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            throw AIError.decoding("expected a JSON object")
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decoding("invalid JSON")
        }
        let observations = (root["observations"] as? [String]) ?? []
        let suggestions = (root["suggestions"] as? [String]) ?? []
        let days = (root["days"] as? [String]) ?? []
        guard !observations.isEmpty else { throw AIError.empty }
        return Insight(periodStart: period.start, periodEnd: period.end,
                       periodLabel: period.label,
                       provider: settings.provider.shortTitle,
                       model: settings.effectiveModel,
                       observations: observations,
                       suggestions: suggestions,
                       basedOnDays: days,
                       question: period.question)
    }
}
