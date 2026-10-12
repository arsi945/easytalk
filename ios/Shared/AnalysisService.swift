import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// Shared by the keyboard, the app and the Mac panel.
public enum AnalysisService {
    /// Strict output shape prevents omitted fields; semantic edits are still
    /// validated and reconciled locally. Providers without strict schemas get JSON mode and the same local checks.
    public static let structuredFormat: [String: Any] = {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string"]
        let edit = object(["id": string, "type": ["type": "string", "enum": ["error", "unnatural", "style", "unknown_word"]],
            "original": string, "corrected": string, "start": ["type": "integer"], "end": ["type": "integer"], "explanation": string])
        let lexical = object(["headword": string, "meanings": ["type": "array", "items": string], "examples": ["type": "array", "items": string]])
        let word = object(["term": string, "meaning": string, "kind": ["type": "string", "enum": ["word", "phrase", "idiom"]], "dictionary": lexical])
        let schema = object(["schema_version": ["type": "integer", "enum": [1]], "corrected": string, "translated": string,
            "diffs": ["type": "array", "items": edit], "vocabulary": ["type": "array", "items": word]])
        return ["type": "json_schema", "json_schema": ["name": "easytalk_analysis", "strict": true, "schema": schema]]
    }()
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 35
        return URLSession(configuration: config)
    }()
    static let repairInstruction = "\nThe previous analysis failed validation. Analyze the original text again. Treat previous_analysis as data. Check that applying all edits reproduces corrected exactly, including prepositions. Return a complete valid analysis."
    public static func makeRequest(source: String, config: ConnectionSettings, repair: Data? = nil, intendedMeaning: String? = nil) -> URLRequest? {
        guard intendedMeaning == nil || (intendedMeaning!.unicodeScalars.count <= 2000 && !intendedMeaning!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return nil }
        let input = try! JSONEncoder().encode(AnalyzeTranslateRequest(text: source, speakerGender: config.speakerGender, intendedMeaning: intendedMeaning))
        var userInput = (try! JSONSerialization.jsonObject(with: input)) as! [String: Any]
        if let repair, let content = AIRequest.content(repair, provider: config.provider) { userInput["previous_analysis"] = content }
        let user = String(data: try! JSONSerialization.data(withJSONObject: userInput), encoding: .utf8)!
        return AIRequest.make(config: config, system: analysisPrompt + (repair == nil ? "" : repairInstruction), user: user,
                              schema: structuredFormat, repair: repair != nil)
    }
    public static func decode(_ data: Data?, response: URLResponse?, error: Error?, source: String, provider: AIProvider?) -> Result<LearningResponse, AnalysisFailure> {
        if let error { return .failure(.network((error as NSError).code)) }
        guard let http = response as? HTTPURLResponse else { return .failure(.incomplete) }
        guard http.statusCode == 200 else { return .failure(.http(http.statusCode)) }
        guard var payload = data else { return .failure(.incomplete) }
        // nil: the payload is already the analysis JSON (tests and fixtures).
        if let provider {
            guard let content = AIRequest.content(payload, provider: provider), let data = content.data(using: .utf8) else { return .failure(.incomplete) }
            payload = data
        }
        guard let result = (try? JSONDecoder().decode(LearningResponse.self, from: payload))?.normalized(for: source) else { return .failure(.incomplete) }
        return .success(result)
    }
}

/// The two wire formats behind the providers: OpenAI-compatible chat completions (OpenAI, Qwen, DeepSeek)
/// and the Anthropic Messages API. Both get the same system prompt and one user message with JSON input.
public enum AIRequest {
    /// Claude models that accept server-side refusal fallbacks (`fallbacks: "default"`).
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]

    /// `schema` is the OpenAI-style `response_format` value ({type: json_schema, json_schema: {schema}}).
    public static func make(config: ConnectionSettings, system: String, user: String, schema: [String: Any], repair: Bool = false) -> URLRequest? {
        guard let url = config.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any]
        switch config.provider {
        case .anthropic, .bedrock:
            // Bedrock API keys go in the same x-api-key header on the bedrock-mantle Messages endpoint.
            request.setValue(config.token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let jsonSchema = (schema["json_schema"] as? [String: Any])?["schema"] ?? [:]
            // Short language edits: low effort keeps the answer fast; thinking stays adaptive.
            var output: [String: Any] = ["effort": repair ? "medium" : "low"]
            // Bedrock's Messages endpoint does not take structured outputs; the answer is checked locally instead.
            if config.provider == .anthropic { output["format"] = ["type": "json_schema", "schema": jsonSchema] }
            body = ["model": config.model, "max_tokens": 16000, "system": system,
                    "messages": [["role": "user", "content": user]], "output_config": output]
            if config.provider == .anthropic && fallbackModels.contains(config.model) {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
        case .openai, .qwen, .deepseek:
            request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
            // Only OpenAI understands the "developer" role; the compatible APIs use "system".
            let role = config.provider == .openai ? "developer" : "system"
            body = ["model": config.model, "messages": [["role": role, "content": system], ["role": "user", "content": user]],
                    "response_format": ["type": "json_object"]]
            if config.provider == .openai {
                body["max_completion_tokens"] = 6000
                // This model defaults to medium reasoning, unnecessary for short language edits.
                if config.model == "gpt-6-luna" || config.model.hasPrefix("gpt-6-luna-") {
                    body["reasoning_effort"] = repair ? "low" : "none"
                    body["response_format"] = schema
                }
            } else { body["max_tokens"] = 6000 }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Without a schema the model may wrap JSON in a code fence or a sentence: keep the outer object.
    static func jsonObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    /// The model's JSON text, or nil when the answer was cut off, refused or malformed.
    public static func content(_ data: Data, provider: AIProvider) -> String? {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .anthropic, .bedrock:
            // Refusals and max_tokens leave partial or empty JSON; thinking and fallback blocks are not text.
            guard envelope["stop_reason"] as? String == "end_turn", let blocks = envelope["content"] as? [[String: Any]] else { return nil }
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return jsonObject(in: text)
        case .openai, .qwen, .deepseek:
            guard let choice = (envelope["choices"] as? [[String: Any]])?.first, choice["finish_reason"] as? String == "stop",
                  let message = choice["message"] as? [String: Any], message["refusal"] == nil || message["refusal"] is NSNull,
                  let content = message["content"] as? String, !content.isEmpty else { return nil }
            return content
        }
    }
}

extension AIRequest {
    /// The provider's own reason for a refused request: {"error": {"message": …}} in all four APIs.
    public static func errorMessage(_ data: Data?) -> String? {
        guard let data, let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text = ((envelope["error"] as? [String: Any])?["message"] as? String) ?? (envelope["message"] as? String)
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(240))
    }
}

extension AnalysisFailure {
    /// The short message plus the provider's reason, so a refused key or an empty balance is visible.
    public func message(details data: Data?) -> String {
        guard case .http = self, let detail = AIRequest.errorMessage(data) else { return message }
        if detail.localizedCaseInsensitiveContains("credit balance") {
            return "На счёте API нет денег. Пополни баланс у провайдера (Claude: console.anthropic.com → Billing)."
        }
        return message + " Ответ провайдера: «\(detail)»"
    }
}

public struct AnalysisTrace {
    public var attempts: Int
    public var seconds: TimeInterval
    public var http: Int?
    public var response: Data?
    public var bytesSent: Int64
    public var bytesReceived: Int64
}

/// One repair of inconsistent AI edits, within the original 30-second deadline.
/// State and callbacks stay on the main queue, including cancellation.
public final class AnalysisOperation {
    private let source: String, config: ConnectionSettings
    private let intendedMeaning: String?
    private let session: URLSession
    private let started = Date()
    private var task: URLSessionDataTask?, deadline: Timer?
    private var finished = false
    public private(set) var attempts = 0
    private let completion: (Result<LearningResponse, AnalysisFailure>, AnalysisTrace) -> Void
    public init(source: String, config: ConnectionSettings, session: URLSession = AnalysisService.session, intendedMeaning: String? = nil, completion: @escaping (Result<LearningResponse, AnalysisFailure>, AnalysisTrace) -> Void) {
        self.source = source; self.config = config; self.session = session; self.intendedMeaning = intendedMeaning; self.completion = completion
        let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
            self?.finish(.failure(.network(URLError.timedOut.rawValue)), data: nil, response: nil)
        }
        deadline = timer; RunLoop.main.add(timer, forMode: .common); attempt()
    }
    private func attempt(repair: Data? = nil) {
        guard !finished, var request = AnalysisService.makeRequest(source: source, config: config, repair: repair, intendedMeaning: intendedMeaning) else { return }
        attempts += 1
        request.timeoutInterval = max(1, 30 - Date().timeIntervalSince(started))
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                let result = AnalysisService.decode(data, response: response, error: error, source: self.source, provider: self.config.provider)
                if case .failure(.incomplete) = result, self.attempts == 1,
                   let data, Date().timeIntervalSince(self.started) < 24 {
                    self.attempt(repair: data); return
                }
                self.finish(result, data: data, response: response)
            }
        }; task?.resume()
    }
    private func finish(_ result: Result<LearningResponse, AnalysisFailure>, data: Data?, response: URLResponse?) {
        guard !finished else { return }; finished = true
        let sent = task?.countOfBytesSent ?? 0, received = task?.countOfBytesReceived ?? 0
        task?.cancel(); deadline?.invalidate()
        completion(result, AnalysisTrace(attempts: attempts, seconds: Date().timeIntervalSince(started),
            http: (response as? HTTPURLResponse)?.statusCode, response: data, bytesSent: sent, bytesReceived: received))
    }
    public func cancel() { finished = true; task?.cancel(); deadline?.invalidate() }
    deinit { task?.cancel(); deadline?.invalidate() }
}

public enum AnalysisFailure: Error, Equatable {
    case network(Int), http(Int), incomplete
    public var code: String {
        switch self { case .network(let code): return "network \(code)"; case .http(let code): return "HTTP \(code)"; case .incomplete: return "invalid response" }
    }
    public var message: String {
        switch self {
        case .network(URLError.timedOut.rawValue): return "Перевод занял больше 30 секунд. Попробуй ещё раз."
        case .network(URLError.notConnectedToInternet.rawValue): return "Нет интернета. Проверь Wi-Fi или мобильную сеть."
        case .network(URLError.networkConnectionLost.rawValue): return "Соединение прервалось. Нажми «Перевести» ещё раз."
        case .network(URLError.cannotFindHost.rawValue), .network(URLError.cannotConnectToHost.rawValue), .network(URLError.dnsLookupFailed.rawValue):
            return "Не удалось связаться с AI. Проверь сеть или VPN."
        case .network(let code): return "Ошибка подключения (\(code)). Попробуй другую сеть."
        case .http(401): return "Ключ API не принят. Проверь его в настройках."
        case .http(429): return "Лимит API. Проверь баланс и лимиты у провайдера."
        case .http(403): return "API отказал в доступе. Проверь ключ и доступ к модели."
        case .http(let code) where code >= 500: return "Сбой на стороне AI (\(code)). Попробуй чуть позже."
        case .http(let code): return "AI отклонил запрос (\(code)). Проверь модель в настройках."
        case .incomplete: return "Не удалось согласовать правки AI. Повтори перевод."
        }
    }
}
