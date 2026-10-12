import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

public enum StudyAction: String { case rephrase, dictionary }
public enum StudyActionResult { case variants([PhraseVariant]), dictionary(LexicalEntry) }
public enum StudyActionService {
    public static func format(_ action: StudyAction) -> [String: Any] {
        let string: [String: Any] = ["type": "string"]
        func object(_ p: [String: Any]) -> [String: Any] { ["type": "object", "properties": p, "required": p.keys.sorted(), "additionalProperties": false] }
        let profile = object(["headword": string, "meanings": ["type": "array", "items": string], "examples": ["type": "array", "items": string]])
        let variant = object(["label": string, "text": string, "explanation": string])
        let schema = object(["schema_version": ["type": "integer", "enum": [1]], action == .rephrase ? "variants" : "entry": action == .rephrase ? ["type": "array", "items": variant] : profile])
        return ["type": "json_schema", "json_schema": ["name": "easytalk_" + action.rawValue, "strict": true, "schema": schema]]
    }
    public static func makeRequest(_ action: StudyAction, source: String, config: ConnectionSettings) -> URLRequest? {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.unicodeScalars.count <= 2000 else { return nil }
        let input: [String: Any] = ["op": action.rawValue, "schema_version": 1, "text": source, "native_language": "ru", "target_language": "en"]
        let user = String(data: try! JSONSerialization.data(withJSONObject: input), encoding: .utf8)!
        return AIRequest.make(config: config, system: studyActionsPrompt, user: user, schema: format(action))
    }
    /// `provider` nil: the payload is already the action JSON (tests and fixtures).
    public static func decode(_ action: StudyAction, source: String, data: Data?, response: URLResponse?, error: Error?, provider: AIProvider?) -> Result<StudyActionResult, AnalysisFailure> {
        if let error { return .failure(.network((error as NSError).code)) }
        guard let response = response as? HTTPURLResponse else { return .failure(.incomplete) }
        guard response.statusCode == 200 else { return .failure(.http(response.statusCode)) }
        guard var payload = data else { return .failure(.incomplete) }
        if let provider {
            guard let content = AIRequest.content(payload, provider: provider), let data = content.data(using: .utf8) else { return .failure(.incomplete) }
            payload = data
        }
        if action == .rephrase, let variants = (try? JSONDecoder().decode(RephraseResponse.self, from: payload))?.validated(for: source) { return .success(.variants(variants)) }
        struct DictionaryResponse: Decodable { let schema_version: Int; let entry: LexicalEntry }
        if action == .dictionary, let object = try? JSONDecoder().decode(DictionaryResponse.self, from: payload), object.schema_version == 1, let entry = object.entry.validated { return .success(.dictionary(entry)) }
        return .failure(.incomplete)
    }
}
public final class StudyActionOperation {
    private var task: URLSessionDataTask?, deadline: Timer?
    private var finished = false
    private var completion: ((Result<StudyActionResult, AnalysisFailure>) -> Void)?
    public init(_ action: StudyAction, source: String, config: ConnectionSettings, session: URLSession = AnalysisService.session, completion: @escaping (Result<StudyActionResult, AnalysisFailure>) -> Void) {
        self.completion = completion
        guard let request = StudyActionService.makeRequest(action, source: source, config: config) else { DispatchQueue.main.async { [weak self] in self?.finish(.failure(.incomplete)) }; return }
        deadline = Timer(timeInterval: 30, repeats: false) { [weak self] _ in self?.finish(.failure(.network(URLError.timedOut.rawValue))) }
        RunLoop.main.add(deadline!, forMode: .common)
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(StudyActionService.decode(action, source: source, data: data, response: response, error: error, provider: config.provider)) }
        }; task?.resume()
    }
    private func finish(_ result: Result<StudyActionResult, AnalysisFailure>) {
        guard !finished else { return }; finished = true; task?.cancel(); task = nil; deadline?.invalidate(); deadline = nil
        let callback = completion; completion = nil; callback?(result)
    }
    public func cancel() { finished = true; completion = nil; task?.cancel(); task = nil; deadline?.invalidate(); deadline = nil }
    deinit { task?.cancel(); deadline?.invalidate() }
}
