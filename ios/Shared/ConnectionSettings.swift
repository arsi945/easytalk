import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// AI providers the user can connect with a personal key. Each request goes straight from the device to the provider.
public enum AIProvider: String, Codable, CaseIterable {
    /// `bedrock`: Claude in Amazon Bedrock (Messages API on bedrock-mantle) with a Bedrock API key.
    case openai, anthropic, bedrock, qwen, deepseek

    public var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Claude"
        case .bedrock: return "Bedrock"
        case .qwen: return "Qwen"
        case .deepseek: return "DeepSeek"
        }
    }
    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        // The region is part of the address; it must be one where Claude model access is enabled.
        case .bedrock: return "https://bedrock-mantle.us-east-1.api.aws/anthropic/v1"
        // Alibaba Model Studio hosts are per region/workspace; Virginia has a shared host.
        case .qwen: return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
        case .deepseek: return "https://api.deepseek.com"
        }
    }
    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-6-luna"
        case .anthropic: return "claude-opus-5-5"
        case .bedrock: return "anthropic.claude-opus-5-5"
        case .qwen: return "qwen3.7-plus"
        case .deepseek: return "deepseek-flash"
        }
    }
    /// Shown before the provider's own list is loaded (October 2026). The first one is the default.
    public var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-6-luna"]
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
        // Bedrock has no model list endpoint; Opus/Sonnet/Haiku 5.5 may need access granted in the AWS console.
        case .bedrock: return ["anthropic.claude-opus-5-5", "anthropic.claude-sonnet-5-5", "anthropic.claude-haiku-5-5",
                               "anthropic.claude-sonnet-5", "anthropic.claude-opus-4-8", "anthropic.claude-haiku-4-5"]
        case .qwen: return ["qwen3.7-plus", "qwen3.8-max", "qwen3.8-flash"]
        case .deepseek: return ["deepseek-flash", "deepseek-v4-pro"]
        }
    }
    /// Qwen (region and workspace) and Bedrock (AWS region) need a user-specific address.
    public var editableBaseURL: Bool { self == .qwen || self == .bedrock }
    /// The Messages API format of Anthropic (Claude and Bedrock) instead of chat completions.
    public var usesMessagesAPI: Bool { self == .anthropic || self == .bedrock }
    public var addressHint: String {
        switch self {
        case .bedrock: return "https://bedrock-mantle.<регион>.api.aws/anthropic/v1"
        default: return "https://…aliyuncs.com/compatible-mode/v1"
        }
    }
    /// The key is sent only to the provider's own hosts.
    func allows(host: String) -> Bool {
        switch self {
        case .openai: return host == "api.openai.com"
        case .anthropic: return host == "api.anthropic.com"
        case .bedrock: return host.hasPrefix("bedrock-mantle.") && host.hasSuffix(".api.aws")
        case .qwen: return host.hasSuffix(".aliyuncs.com")
        case .deepseek: return host == "api.deepseek.com"
        }
    }
    public var keyPlaceholder: String {
        switch self {
        case .openai: return "Ключ OpenAI: sk-…"
        case .anthropic: return "Ключ Claude API: sk-ant-…"
        case .bedrock: return "Ключ API Amazon Bedrock"
        case .qwen: return "Ключ Alibaba Model Studio"
        case .deepseek: return "Ключ DeepSeek: sk-…"
        }
    }
    /// Why a key probably will not work with this provider, before any request.
    public func keyWarning(_ key: String) -> String? {
        let key = ConnectionSettings.cleanKey(key)
        guard !key.isEmpty else { return nil }
        if key.contains("…") || key.contains("...") || key.contains("*") {
            return "В ключе есть «…» или «*» — это сокращённая версия из списка ключей. Нужна полная: её показывают один раз при создании ключа."
        }
        if self == .anthropic && !key.hasPrefix("sk-ant-") {
            return "Ключ Claude начинается с «sk-ant-». Этот — нет: похоже, это ключ другого сервиса."
        }
        if self == .bedrock && key.hasPrefix("sk-ant-") {
            return "Это ключ Anthropic (console.anthropic.com). Для Bedrock нужен ключ API из консоли AWS — или выбери «Claude»."
        }
        if self != .anthropic && key.hasPrefix("sk-ant-") { return "Это ключ Claude, а выбран \(title)." }
        return nil
    }
    public var keyHelp: String {
        switch self {
        case .openai: return "Ключ: platform.openai.com → API keys."
        case .anthropic: return "Ключ: console.anthropic.com → API Keys. Оплата отдельно от подписки Claude."
        case .bedrock: return "Ключ: консоль AWS → Amazon Bedrock → API keys. В адресе — регион, где включён доступ к моделям Claude (Model access)."
        case .qwen: return "Ключ и адрес своего региона: Alibaba Cloud Model Studio → API Keys. Ключ работает только в своём регионе."
        case .deepseek: return "Ключ: platform.deepseek.com → API keys."
        }
    }
}

public struct ConnectionSettings: Codable {
    public var provider: AIProvider
    /// Without the trailing method path, e.g. https://api.openai.com/v1.
    public var baseURL: String
    public var token: String
    public var model: String
    public var speakerGender: SpeakerGender

    public init(provider: AIProvider, apiKey: String, model: String? = nil, baseURL: String? = nil, speakerGender: SpeakerGender = .unspecified) {
        self.provider = provider; token = Self.cleanKey(apiKey)
        self.model = model ?? provider.defaultModel
        self.baseURL = provider.editableBaseURL ? (baseURL ?? provider.defaultBaseURL) : provider.defaultBaseURL
        self.speakerGender = speakerGender
    }
    public init(apiKey: String, model: String = AIProvider.openai.defaultModel, speakerGender: SpeakerGender = .unspecified) {
        self.init(provider: .openai, apiKey: apiKey, model: model, speakerGender: speakerGender)
    }

    /// Keys never contain spaces, line breaks or invisible characters; copying from notes or chats often adds them.
    public static func cleanKey(_ key: String) -> String {
        String(String.UnicodeScalarView(key.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && !$0.properties.isDefaultIgnorableCodePoint
        }))
    }
    /// A masked summary to check a key without showing it: «sk-ant-ap…AbCd · 108 символов».
    public static func keySummary(_ key: String) -> String {
        let key = cleanKey(key)
        guard key.count >= 16 else { return "Ключ: \(key.count) символов" }
        return "Ключ: \(key.prefix(9))…\(key.suffix(4)) · \(key.count) символов"
    }

    enum CodingKeys: String, CodingKey {
        case provider, token, model
        case baseURL = "base_url"
        case speakerGender = "speaker_gender"
        // Saved before providers: {"mode": "openai" | "server", "endpoint": …}.
        case mode, endpoint
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) {
            self.provider = provider
            baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? provider.defaultBaseURL
        } else if try c.decodeIfPresent(String.self, forKey: .mode) == "openai" {
            provider = .openai; baseURL = AIProvider.openai.defaultBaseURL
        } else {
            // The own-server mode was removed; such settings are entered again.
            throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "Unsupported connection mode")
        }
        token = try c.decode(String.self, forKey: .token)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        speakerGender = try c.decodeIfPresent(SpeakerGender.self, forKey: .speakerGender) ?? .unspecified
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider); try c.encode(baseURL, forKey: .baseURL)
        try c.encode(token, forKey: .token); try c.encode(model, forKey: .model)
        try c.encode(speakerGender, forKey: .speakerGender)
    }

    /// The provider's model list, checked like `url`.
    public var modelsURL: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Bedrock has no model list endpoint.
        guard provider != .bedrock, !token.isEmpty, var components = URLComponents(string: base + "/models"), components.scheme == "https",
              let host = components.host?.lowercased(), provider.allows(host: host),
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else { return nil }
        // Anthropic pages by 20 by default.
        if provider == .anthropic { components.queryItems = [URLQueryItem(name: "limit", value: "100")] }
        return components.url
    }

    /// The request URL, or nil when anything would send the key somewhere unexpected.
    public var url: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = provider.usesMessagesAPI ? "/messages" : "/chat/completions"
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: base + path), url.scheme == "https", let host = url.host?.lowercased(), provider.allows(host: host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

/// The models a key can use, from the provider's own list (GET …/models) — so the user picks instead of typing.
public enum ModelCatalog {
    public static func request(config: ConnectionSettings) -> URLRequest? {
        guard let url = config.modelsURL else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        if config.provider == .anthropic {
            request.setValue(config.token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Text models only, in a useful order: Anthropic lists newest first; others are sorted by name.
    public static func parse(_ data: Data, provider: AIProvider) -> [String] {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = envelope["data"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        let ids = items.compactMap { $0["id"] as? String }.filter { usable($0, provider: provider) && seen.insert($0).inserted }
        return provider == .anthropic ? ids : ids.sorted()
    }

    static func usable(_ id: String, provider: AIProvider) -> Bool {
        let model = id.lowercased()
        switch provider {
        case .anthropic: return model.hasPrefix("claude-")
        case .bedrock: return model.hasPrefix("anthropic.claude")
        case .deepseek: return model.hasPrefix("deepseek")
        case .qwen:
            return model.hasPrefix("qwen") && !["embedding", "tts", "asr", "image", "audio", "realtime"].contains { model.contains($0) }
        case .openai:
            let excluded = ["embedding", "tts", "whisper", "dall-e", "image", "moderation", "audio", "realtime", "transcribe", "search", "davinci", "babbage", "computer-use"]
            return (model.hasPrefix("gpt-") || model.hasPrefix("o")) && !excluded.contains { model.contains($0) }
        }
    }
}
