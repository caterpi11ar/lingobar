import Foundation
import LingobarApplication
import LingobarDomain

public enum TranslationExecutorError: LocalizedError {
    case unsupportedProvider(String)
    case invalidResponse(String)
    case missingAPIKey(String)
    case invalidTargetLanguage(String)
    case httpFailure(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported provider: \(provider)"
        case .invalidResponse(let message):
            return message
        case .missingAPIKey(let provider):
            return "Missing API key for provider: \(provider)"
        case .invalidTargetLanguage(let code):
            return "Invalid target language code: \(code)"
        case .httpFailure(let status, let message):
            return "HTTP \(status): \(message)"
        }
    }
}

public final class HTTPTranslationExecutor: TranslationExecuting, @unchecked Sendable {
    private let httpClient: any HTTPClient
    private let promptResolver: any TranslationPromptResolving
    private let credentialsStore: (any CredentialsStore)?

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        promptResolver: any TranslationPromptResolving,
        credentialsStore: (any CredentialsStore)? = nil
    ) {
        self.httpClient = httpClient
        self.promptResolver = promptResolver
        self.credentialsStore = credentialsStore
    }

    public func execute(request: TranslationRequest) async throws -> String {
        let preparedText = TranslationHashBuilder.prepareTranslationText(request.text)
        if preparedText.isEmpty {
            return ""
        }

        let providerConfig = try await hydratedProviderConfig(for: request.providerConfig)
        switch providerConfig.category {
        case .nonAPI:
            return try await executeNonAPI(text: preparedText, language: request.language, providerConfig: providerConfig)
        case .pureAPI:
            return try await executePureAPI(text: preparedText, language: request.language, providerConfig: providerConfig)
        case .llm:
            return try await executeLLM(text: preparedText, language: request.language, providerConfig: providerConfig, options: request.options)
        }
    }

    private func hydratedProviderConfig(for providerConfig: ProviderConfig) async throws -> ProviderConfig {
        guard (providerConfig.apiKey == nil || providerConfig.apiKey?.isEmpty == true), let credentialsStore else {
            return providerConfig
        }
        var hydrated = providerConfig
        hydrated.apiKey = try await credentialsStore.apiKey(for: providerConfig.id)
        return hydrated
    }

    private func executeNonAPI(text: String, language: TranslationLanguageConfig, providerConfig: ProviderConfig) async throws -> String {
        let sourceLanguage = normalizeSourceLanguage(language.sourceCode)
        let targetLanguage = try normalizeTargetLanguage(language.targetCode)

        switch providerConfig.provider {
        case .googleTranslate:
            return try await googleTranslate(text: text, from: sourceLanguage, to: targetLanguage)
        case .microsoftTranslate:
            return try await microsoftTranslate(text: text, from: sourceLanguage, to: targetLanguage)
        default:
            throw TranslationExecutorError.unsupportedProvider(providerConfig.provider.rawValue)
        }
    }

    private func executePureAPI(text: String, language: TranslationLanguageConfig, providerConfig: ProviderConfig) async throws -> String {
        let sourceLanguage = normalizeSourceLanguage(language.sourceCode)
        let targetLanguage = try normalizeTargetLanguage(language.targetCode)

        switch providerConfig.provider {
        case .deeplx:
            return try await deepLXTranslate(text: text, from: sourceLanguage, to: targetLanguage, providerConfig: providerConfig)
        case .deepl:
            return try await deepLTranslate(texts: [text], from: sourceLanguage, to: targetLanguage, providerConfig: providerConfig).first ?? ""
        default:
            throw TranslationExecutorError.unsupportedProvider(providerConfig.provider.rawValue)
        }
    }

    private func executeLLM(
        text: String,
        language: TranslationLanguageConfig,
        providerConfig: ProviderConfig,
        options: TranslationExecutionOptions
    ) async throws -> String {
        let model = providerConfig.model?.resolvedModelIdentifier ?? providerConfig.provider.defaultModelIdentifier ?? ""
        let targetLanguageName = languageName(for: language.targetCode)
        let prompt = try await promptResolver.resolve(
            targetLanguageName: targetLanguageName,
            input: text,
            options: TranslationPromptOptions(isBatch: options.isBatch, content: options.content)
        )

        switch providerConfig.provider {
        case .google:
            return try await geminiTranslate(model: model, prompt: prompt, providerConfig: providerConfig)
        case .anthropic:
            return try await anthropicTranslate(model: model, prompt: prompt, providerConfig: providerConfig)
        case .cohere:
            return try await cohereTranslate(model: model, prompt: prompt, providerConfig: providerConfig)
        case .ollama:
            return try await ollamaTranslate(model: model, prompt: prompt, providerConfig: providerConfig)
        case .bedrock, .replicate, .vercel:
            throw TranslationExecutorError.unsupportedProvider(providerConfig.provider.rawValue)
        default:
            return try await openAICompatibleTranslate(model: model, prompt: prompt, providerConfig: providerConfig)
        }
    }

    private func googleTranslate(text: String, from: String, to: String) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from),
            URLQueryItem(name: "tl", value: to),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "strip", value: "1"),
            URLQueryItem(name: "nonced", value: "1"),
            URLQueryItem(name: "q", value: text),
        ]
        let data = try await sendValidated(URLRequest(url: components.url!))
        let payload = try jsonObject(from: data)
        guard let array = payload as? [Any], let chunks = array.first as? [Any] else {
            throw TranslationExecutorError.invalidResponse("Unexpected Google Translate response")
        }
        let translated = chunks.compactMap { chunk -> String? in
            guard let item = chunk as? [Any], let text = item.first as? String else { return nil }
            return text
        }.joined()
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func microsoftTranslate(text: String, from: String, to: String) async throws -> String {
        let tokenData = try await sendValidated(URLRequest(url: URL(string: "https://edge.microsoft.com/translate/auth")!))
        let token = String(decoding: tokenData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(string: "https://api-edge.cognitive.microsofttranslator.com/translate")!
        components.queryItems = [
            URLQueryItem(name: "from", value: from == "auto" ? "" : from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "includeSentenceLength", value: "true"),
            URLQueryItem(name: "textType", value: "html"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard
            let array = payload as? [[String: Any]],
            let translations = array.first?["translations"] as? [[String: Any]],
            let translated = translations.first?["text"] as? String
        else {
            throw TranslationExecutorError.invalidResponse("Unexpected Microsoft Translate response")
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deepLTranslate(texts: [String], from: String, to: String, providerConfig: ProviderConfig) async throws -> [String] {
        let apiKey = try requiredAPIKey(for: providerConfig)
        let baseURL = apiKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        let source = from == "auto" ? nil : formatDeepLLanguage(from, direction: .source)
        let target = formatDeepLLanguage(to, direction: .target)
        var body: [String: Any] = ["text": texts, "target_lang": target]
        if let source {
            body["source_lang"] = source
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/v2/translate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard let object = payload as? [String: Any], let translations = object["translations"] as? [[String: Any]] else {
            throw TranslationExecutorError.invalidResponse("Unexpected DeepL response")
        }
        guard translations.count == texts.count else {
            throw TranslationExecutorError.invalidResponse("DeepL response count mismatch")
        }
        return try translations.map {
            guard let text = $0["text"] as? String else {
                throw TranslationExecutorError.invalidResponse("Unexpected DeepL translation payload")
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func deepLXTranslate(text: String, from: String, to: String, providerConfig: ProviderConfig) async throws -> String {
        let baseURL = providerConfig.baseURL ?? ProviderID.deeplx.defaultBaseURL ?? "https://api.deeplx.org"
        let url = try buildDeepLXURL(baseURL: baseURL, apiKey: providerConfig.apiKey)
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "source_lang": formatDeepLXLanguage(from),
            "target_lang": formatDeepLXLanguage(to),
        ])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard let object = payload as? [String: Any], let translated = object["data"] as? String else {
            throw TranslationExecutorError.invalidResponse("Unexpected DeepLX response")
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openAICompatibleTranslate(model: String, prompt: TranslationPrompt, providerConfig: ProviderConfig) async throws -> String {
        let apiKey = try requiredAPIKey(for: providerConfig)
        guard let baseURL = providerConfig.baseURL ?? providerConfig.provider.defaultBaseURL else {
            throw TranslationExecutorError.invalidResponse("Missing baseURL for \(providerConfig.provider.rawValue)")
        }
        let endpoint = appendPath("chat/completions", to: baseURL)
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (header, value) in customHeaders(for: providerConfig) {
            request.setValue(value, forHTTPHeaderField: header)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt.systemPrompt],
                ["role": "user", "content": prompt.prompt],
            ],
        ]
        if let temperature = providerConfig.temperature {
            body["temperature"] = temperature
        }
        body.merge(providerOptionsDictionary(from: providerConfig.providerOptions), uniquingKeysWith: { _, new in new })
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard
            let object = payload as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw TranslationExecutorError.invalidResponse("Unexpected chat completion response")
        }

        if let content = message["content"] as? String {
            return stripThinkTags(content).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let contentArray = message["content"] as? [[String: Any]] {
            let text = contentArray.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return stripThinkTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranslationExecutorError.invalidResponse("Unsupported message content format")
    }

    private func geminiTranslate(model: String, prompt: TranslationPrompt, providerConfig: ProviderConfig) async throws -> String {
        let apiKey = try requiredAPIKey(for: providerConfig)
        let baseURL = providerConfig.baseURL ?? ProviderID.google.defaultBaseURL ?? "https://generativelanguage.googleapis.com"
        let endpoint = appendPath("v1beta/models/\(model):generateContent", to: baseURL)
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": prompt.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt.prompt]]]],
        ])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard
            let object = payload as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw TranslationExecutorError.invalidResponse("Unexpected Gemini response")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return stripThinkTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func anthropicTranslate(model: String, prompt: TranslationPrompt, providerConfig: ProviderConfig) async throws -> String {
        let apiKey = try requiredAPIKey(for: providerConfig)
        let baseURL = providerConfig.baseURL ?? ProviderID.anthropic.defaultBaseURL ?? "https://api.anthropic.com/v1"
        let endpoint = appendPath("messages", to: baseURL)
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("true", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 4096,
            "system": prompt.systemPrompt,
            "messages": [["role": "user", "content": prompt.prompt]],
        ])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard let object = payload as? [String: Any], let content = object["content"] as? [[String: Any]] else {
            throw TranslationExecutorError.invalidResponse("Unexpected Anthropic response")
        }
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return stripThinkTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cohereTranslate(model: String, prompt: TranslationPrompt, providerConfig: ProviderConfig) async throws -> String {
        let apiKey = try requiredAPIKey(for: providerConfig)
        let baseURL = providerConfig.baseURL ?? ProviderID.cohere.defaultBaseURL ?? "https://api.cohere.com/v2"
        let endpoint = appendPath("chat", to: baseURL)
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "preamble": prompt.systemPrompt,
            "messages": [["role": "user", "content": prompt.prompt]],
        ])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard let object = payload as? [String: Any] else {
            throw TranslationExecutorError.invalidResponse("Unexpected Cohere response")
        }
        if let text = object["text"] as? String {
            return stripThinkTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let message = object["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return stripThinkTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranslationExecutorError.invalidResponse("Unexpected Cohere payload")
    }

    private func ollamaTranslate(model: String, prompt: TranslationPrompt, providerConfig: ProviderConfig) async throws -> String {
        let baseURL = providerConfig.baseURL ?? ProviderID.ollama.defaultBaseURL ?? "http://localhost:11434"
        let endpoint = appendPath("api/chat", to: baseURL)
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": prompt.systemPrompt],
                ["role": "user", "content": prompt.prompt],
            ],
        ])

        let data = try await sendValidated(request)
        let payload = try jsonObject(from: data)
        guard
            let object = payload as? [String: Any],
            let message = object["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TranslationExecutorError.invalidResponse("Unexpected Ollama response")
        }
        return stripThinkTags(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendValidated(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await httpClient.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw TranslationExecutorError.httpFailure(status: response.statusCode, message: message)
        }
        return data
    }

    private func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private func requiredAPIKey(for providerConfig: ProviderConfig) throws -> String {
        guard let apiKey = providerConfig.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw TranslationExecutorError.missingAPIKey(providerConfig.provider.rawValue)
        }
        return apiKey
    }

    private func normalizeSourceLanguage(_ code: String) -> String {
        code == "auto" ? "auto" : code.lowercased()
    }

    private func normalizeTargetLanguage(_ code: String) throws -> String {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            throw TranslationExecutorError.invalidTargetLanguage(code)
        }
        return cleaned
    }

    private func languageName(for code: String) -> String {
        let mapping: [String: String] = [
            "en": "English",
            "zh": "Chinese",
            "ja": "Japanese",
            "ko": "Korean",
            "fr": "French",
            "de": "German",
            "es": "Spanish",
            "it": "Italian",
            "pt": "Portuguese",
            "ru": "Russian",
        ]
        return mapping[code.lowercased()] ?? code.uppercased()
    }

    private func formatDeepLLanguage(_ language: String, direction: DeepLDirection) -> String {
        let uppercased = language.uppercased()
        if uppercased == "ZH" {
            return direction == .target ? "ZH-HANS" : "ZH"
        }
        if uppercased == "ZH-TW" {
            return direction == .target ? "ZH-HANT" : "ZH"
        }
        return uppercased
    }

    private func formatDeepLXLanguage(_ language: String) -> String {
        if language == "auto" {
            return "auto"
        }
        if language.uppercased() == "ZH-TW" {
            return "ZH-HANT"
        }
        return language.uppercased()
    }

    private func buildDeepLXURL(baseURL: String, apiKey: String?) throws -> String {
        let cleanBaseURL = baseURL.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        if cleanBaseURL.contains("{{apiKey}}") {
            guard let apiKey, !apiKey.isEmpty else {
                throw TranslationExecutorError.missingAPIKey(ProviderID.deeplx.rawValue)
            }
            return cleanBaseURL.replacingOccurrences(of: "{{apiKey}}", with: apiKey)
        }
        if cleanBaseURL == "https://api.deeplx.org" {
            if let apiKey, !apiKey.isEmpty {
                return "https://api.deeplx.org/\(apiKey)/translate"
            }
            return "\(cleanBaseURL)/translate"
        }
        if cleanBaseURL.hasSuffix("/translate") {
            return cleanBaseURL
        }
        if let apiKey, !apiKey.isEmpty {
            return "\(cleanBaseURL)/\(apiKey)/translate"
        }
        return "\(cleanBaseURL)/translate"
    }

    private func appendPath(_ path: String, to baseURL: String) -> String {
        let cleanBase = baseURL.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        let cleanPath = path.replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
        return "\(cleanBase)/\(cleanPath)"
    }

    private func providerOptionsDictionary(from options: [String: JSONValue]) -> [String: Any] {
        options.reduce(into: [String: Any]()) { result, element in
            result[element.key] = decodeJSONValue(element.value)
        }
    }

    private func decodeJSONValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .array(let values): return values.map(decodeJSONValue)
        case .object(let object):
            return object.reduce(into: [String: Any]()) { result, element in
                result[element.key] = decodeJSONValue(element.value)
            }
        case .null:
            return NSNull()
        }
    }

    private func customHeaders(for providerConfig: ProviderConfig) -> [String: String] {
        providerConfig.provider == .anthropic
            ? ["anthropic-dangerous-direct-browser-access": "true"]
            : [:]
    }

    private func stripThinkTags(_ text: String) -> String {
        guard let range = text.range(of: #"</think>([\s\S]*)"#, options: .regularExpression) else {
            return text
        }
        return String(text[range]).replacingOccurrences(of: "</think>", with: "")
    }
}

private enum DeepLDirection {
    case source
    case target
}
