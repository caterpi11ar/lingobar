import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public enum FeatureKey: String, Codable, CaseIterable, Sendable {
    case clipboardTranslate
}

public enum ProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case googleTranslate = "google-translate"
    case microsoftTranslate = "microsoft-translate"
    case deeplx
    case deepl
    case openAI = "openai"
    case deepSeek = "deepseek"
    case google
    case anthropic
    case xAI = "xai"
    case openAICompatible = "openai-compatible"
    case siliconflow
    case tensdaq
    case ai302
    case bedrock
    case groq
    case deepinfra
    case mistral
    case togetherAI = "togetherai"
    case cohere
    case fireworks
    case cerebras
    case replicate
    case perplexity
    case vercel
    case openrouter
    case ollama
    case volcengine
    case minimax
    case alibaba
    case moonshotAI = "moonshotai"
    case huggingFace = "huggingface"

    public var displayName: String {
        switch self {
        case .googleTranslate: return "Google Translate"
        case .microsoftTranslate: return "Microsoft Translate"
        case .deeplx: return "DeepLX"
        case .deepl: return "DeepL"
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .google: return "Google Gemini"
        case .anthropic: return "Anthropic"
        case .xAI: return "xAI"
        case .openAICompatible: return "OpenAI Compatible"
        case .siliconflow: return "SiliconFlow"
        case .tensdaq: return "Tensdaq"
        case .ai302: return "AI302"
        case .bedrock: return "AWS Bedrock"
        case .groq: return "Groq"
        case .deepinfra: return "DeepInfra"
        case .mistral: return "Mistral"
        case .togetherAI: return "Together AI"
        case .cohere: return "Cohere"
        case .fireworks: return "Fireworks"
        case .cerebras: return "Cerebras"
        case .replicate: return "Replicate"
        case .perplexity: return "Perplexity"
        case .vercel: return "Vercel AI"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .volcengine: return "Volcengine"
        case .minimax: return "MiniMax"
        case .alibaba: return "Alibaba DashScope"
        case .moonshotAI: return "Moonshot AI"
        case .huggingFace: return "Hugging Face"
        }
    }

    public var defaultBaseURL: String? {
        switch self {
        case .deeplx:
            return "https://api.deeplx.org"
        case .openAI:
            return "https://api.openai.com/v1"
        case .deepSeek:
            return "https://api.deepseek.com/v1"
        case .google:
            return "https://generativelanguage.googleapis.com"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .xAI:
            return "https://api.x.ai/v1"
        case .siliconflow:
            return "https://api.siliconflow.cn/v1"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .deepinfra:
            return "https://api.deepinfra.com/v1/openai"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .togetherAI:
            return "https://api.together.xyz/v1"
        case .cohere:
            return "https://api.cohere.com/v2"
        case .fireworks:
            return "https://api.fireworks.ai/inference/v1"
        case .cerebras:
            return "https://api.cerebras.ai/v1"
        case .perplexity:
            return "https://api.perplexity.ai"
        case .openrouter:
            return "https://openrouter.ai/api/v1"
        case .ollama:
            return "http://localhost:11434"
        case .alibaba:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .moonshotAI:
            return "https://api.moonshot.cn/v1"
        case .huggingFace:
            return "https://router.huggingface.co/v1"
        default:
            return nil
        }
    }

    public var defaultModelIdentifier: String? {
        switch self {
        case .openAI:
            return "gpt-4o-mini"
        case .deepSeek:
            return "deepseek-chat"
        case .google:
            return "gemini-2.0-flash"
        case .anthropic:
            return "claude-3-5-haiku-latest"
        case .xAI:
            return "grok-2-1212"
        case .openAICompatible:
            return "gpt-4o-mini"
        case .siliconflow:
            return "Qwen/Qwen2.5-7B-Instruct"
        case .tensdaq:
            return "gpt-4o-mini"
        case .ai302:
            return "gpt-4o-mini"
        case .bedrock:
            return "anthropic.claude-3-5-haiku-20241022-v1:0"
        case .groq:
            return "llama-3.1-8b-instant"
        case .deepinfra:
            return "meta-llama/Meta-Llama-3.1-8B-Instruct"
        case .mistral:
            return "mistral-small-latest"
        case .togetherAI:
            return "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"
        case .cohere:
            return "command-r"
        case .fireworks:
            return "accounts/fireworks/models/llama-v3p1-8b-instruct"
        case .cerebras:
            return "llama3.1-8b"
        case .replicate:
            return "meta/meta-llama-3-8b-instruct"
        case .perplexity:
            return "sonar"
        case .vercel:
            return "gpt-4o-mini"
        case .openrouter:
            return "openai/gpt-4o-mini"
        case .ollama:
            return "llama3.1:8b"
        case .volcengine:
            return "doubao-lite-4k"
        case .minimax:
            return "MiniMax-Text-01"
        case .alibaba:
            return "qwen-plus"
        case .moonshotAI:
            return "moonshot-v1-8k"
        case .huggingFace:
            return "openai/gpt-oss-20b"
        default:
            return nil
        }
    }

    public var presetModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo", "o1", "o1-mini", "o3-mini"]
        case .deepSeek:
            return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .google:
            return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .anthropic:
            return ["claude-sonnet-4-20250514", "claude-3-5-haiku-latest", "claude-3-5-sonnet-latest"]
        case .xAI:
            return ["grok-2-1212", "grok-2-latest", "grok-3-latest"]
        case .groq:
            return ["llama-3.1-8b-instant", "llama-3.1-70b-versatile", "mixtral-8x7b-32768"]
        case .mistral:
            return ["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest"]
        case .siliconflow:
            return ["Qwen/Qwen2.5-7B-Instruct", "Qwen/Qwen2.5-72B-Instruct", "deepseek-ai/DeepSeek-V3"]
        case .deepinfra:
            return ["meta-llama/Meta-Llama-3.1-8B-Instruct", "meta-llama/Meta-Llama-3.1-70B-Instruct"]
        case .togetherAI:
            return ["meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo", "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"]
        case .cohere:
            return ["command-r", "command-r-plus"]
        case .fireworks:
            return ["accounts/fireworks/models/llama-v3p1-8b-instruct", "accounts/fireworks/models/llama-v3p1-70b-instruct"]
        case .cerebras:
            return ["llama3.1-8b", "llama3.1-70b"]
        case .perplexity:
            return ["sonar", "sonar-pro", "sonar-reasoning"]
        case .openrouter:
            return ["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-3.5-sonnet"]
        case .ollama:
            return ["llama3.1:8b", "llama3.2:3b", "qwen2.5:7b", "gemma2:9b"]
        case .volcengine:
            return ["doubao-lite-4k", "doubao-pro-4k", "doubao-pro-32k"]
        case .minimax:
            return ["MiniMax-Text-01"]
        case .alibaba:
            return ["qwen-plus", "qwen-turbo", "qwen-max"]
        case .moonshotAI:
            return ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"]
        case .huggingFace:
            return ["openai/gpt-oss-20b"]
        case .openAICompatible:
            return ["gpt-4o-mini", "gpt-4o"]
        case .tensdaq:
            return ["gpt-4o-mini", "gpt-4o"]
        case .ai302:
            return ["gpt-4o-mini", "gpt-4o"]
        case .bedrock:
            return ["anthropic.claude-3-5-haiku-20241022-v1:0"]
        case .replicate:
            return ["meta/meta-llama-3-8b-instruct"]
        case .vercel:
            return ["gpt-4o-mini"]
        default:
            return []
        }
    }
}

public enum ProviderCategory: String, Codable, CaseIterable, Sendable {
    case nonAPI
    case pureAPI
    case llm
}

public enum TranslationLevel: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
}

public enum TranslationMode: String, Codable, CaseIterable, Sendable {
    case bilingual
    case translationOnly
}

public enum TranslationRange: String, Codable, CaseIterable, Sendable {
    case main
    case all
}

public enum StartupMode: String, Codable, CaseIterable, Sendable {
    case disabled
    case enabled
}

public enum StatsRange: String, Codable, CaseIterable, Sendable {
    case day
    case week
    case month
    case year
}

public enum SourceLanguageMode: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct ProviderModelConfig: Codable, Equatable, Sendable {
    public var model: String
    public var isCustomModel: Bool
    public var customModel: String?

    public init(model: String, isCustomModel: Bool = false, customModel: String? = nil) {
        self.model = model
        self.isCustomModel = isCustomModel
        self.customModel = customModel
    }

    public var resolvedModelIdentifier: String {
        if isCustomModel, let customModel, !customModel.isEmpty {
            return customModel
        }
        return model
    }
}

public struct ProviderConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var provider: ProviderID
    public var apiKey: String?
    public var baseURL: String?
    public var temperature: Double?
    public var providerOptions: [String: JSONValue]
    public var connectionOptions: [String: JSONValue]
    public var model: ProviderModelConfig?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        provider: ProviderID,
        apiKey: String? = nil,
        baseURL: String? = nil,
        temperature: Double? = nil,
        providerOptions: [String: JSONValue] = [:],
        connectionOptions: [String: JSONValue] = [:],
        model: ProviderModelConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.temperature = temperature
        self.providerOptions = providerOptions
        self.connectionOptions = connectionOptions
        self.model = model
    }

    public var category: ProviderCategory {
        switch provider {
        case .googleTranslate, .microsoftTranslate:
            return .nonAPI
        case .deeplx, .deepl:
            return .pureAPI
        default:
            return .llm
        }
    }

    public var isNonAPIProvider: Bool { category == .nonAPI }
    public var isPureAPIProvider: Bool { category == .pureAPI }
    public var isLLMProvider: Bool { category == .llm }
    public var requiresAPIKey: Bool { !isNonAPIProvider && provider != .deeplx && provider != .ollama }

    public static var defaults: [ProviderConfig] {
        ProviderID.allCases.map { provider in
            ProviderConfig(
                id: provider.rawValue,
                name: provider.displayName,
                enabled: provider == .googleTranslate || provider == .microsoftTranslate || provider == .deeplx || provider == .deepl || provider == .openAI,
                provider: provider,
                baseURL: provider.defaultBaseURL,
                model: provider.defaultModelIdentifier.map { ProviderModelConfig(model: $0) }
            )
        }
    }
}

public struct RequestQueueConfig: Codable, Equatable, Sendable {
    public var rate: Double
    public var capacity: Double
    public var timeoutMs: UInt64
    public var maxRetries: Int
    public var baseRetryDelayMs: UInt64

    public init(
        rate: Double = 2,
        capacity: Double = 4,
        timeoutMs: UInt64 = 20_000,
        maxRetries: Int = 2,
        baseRetryDelayMs: UInt64 = 1_000
    ) {
        self.rate = rate
        self.capacity = capacity
        self.timeoutMs = timeoutMs
        self.maxRetries = maxRetries
        self.baseRetryDelayMs = baseRetryDelayMs
    }
}

public struct BatchQueueConfig: Codable, Equatable, Sendable {
    public var maxCharactersPerBatch: Int
    public var maxItemsPerBatch: Int
    public var batchDelayMs: UInt64
    public var maxRetries: Int
    public var enableFallbackToIndividual: Bool

    public init(
        maxCharactersPerBatch: Int = 4_000,
        maxItemsPerBatch: Int = 8,
        batchDelayMs: UInt64 = 100,
        maxRetries: Int = 3,
        enableFallbackToIndividual: Bool = true
    ) {
        self.maxCharactersPerBatch = maxCharactersPerBatch
        self.maxItemsPerBatch = maxItemsPerBatch
        self.batchDelayMs = batchDelayMs
        self.maxRetries = maxRetries
        self.enableFallbackToIndividual = enableFallbackToIndividual
    }
}

public struct SupportedLanguage: Sendable {
    public let code: String
    public let displayName: String

    public static let all: [SupportedLanguage] = [
        .init(code: "zh", displayName: "中文"),
        .init(code: "en", displayName: "English"),
        .init(code: "ja", displayName: "日本語"),
        .init(code: "ko", displayName: "한국어"),
        .init(code: "fr", displayName: "Français"),
        .init(code: "de", displayName: "Deutsch"),
        .init(code: "es", displayName: "Español"),
        .init(code: "it", displayName: "Italiano"),
        .init(code: "pt", displayName: "Português"),
        .init(code: "ru", displayName: "Русский"),
    ]

    public static let autoDetect = SupportedLanguage(code: "auto", displayName: "自动检测")

    public static let sourceOptions: [SupportedLanguage] = [autoDetect] + all
}

public struct TranslationLanguageConfig: Codable, Equatable, Sendable {
    public var sourceCode: String
    public var targetCode: String
    public var level: TranslationLevel

    public init(sourceCode: String = "auto", targetCode: String = "zh", level: TranslationLevel = .intermediate) {
        self.sourceCode = sourceCode
        self.targetCode = targetCode
        self.level = level
    }
}

public struct ClipboardTranslateSettings: Codable, Equatable, Sendable {
    public var providerId: String
    public var mode: TranslationMode
    public var range: TranslationRange
    public var enableAIContentAware: Bool
    public var requestQueueConfig: RequestQueueConfig
    public var batchQueueConfig: BatchQueueConfig

    public init(
        providerId: String = ProviderID.googleTranslate.rawValue,
        mode: TranslationMode = .translationOnly,
        range: TranslationRange = .main,
        enableAIContentAware: Bool = false,
        requestQueueConfig: RequestQueueConfig = .init(),
        batchQueueConfig: BatchQueueConfig = .init()
    ) {
        self.providerId = providerId
        self.mode = mode
        self.range = range
        self.enableAIContentAware = enableAIContentAware
        self.requestQueueConfig = requestQueueConfig
        self.batchQueueConfig = batchQueueConfig
    }
}

public struct FeatureProviderAssignments: Codable, Equatable, Sendable {
    public var clipboardTranslate: String

    public init(clipboardTranslate: String = ProviderID.googleTranslate.rawValue) {
        self.clipboardTranslate = clipboardTranslate
    }

    public func providerID(for featureKey: FeatureKey) -> String {
        switch featureKey {
        case .clipboardTranslate:
            return clipboardTranslate
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: ThemeMode
    public var pollingIntervalMs: UInt64
    public var autoTranslateEnabled: Bool
    public var autoWriteBackEnabled: Bool
    public var notificationsEnabled: Bool
    public var statsEnabled: Bool
    public var startupMode: StartupMode
    public var sourceLanguageMode: SourceLanguageMode
    public var language: TranslationLanguageConfig
    public var featureProviders: FeatureProviderAssignments
    public var translate: ClipboardTranslateSettings
    public var providersConfig: [ProviderConfig]

    public init(
        theme: ThemeMode = .system,
        pollingIntervalMs: UInt64 = 500,
        autoTranslateEnabled: Bool = true,
        autoWriteBackEnabled: Bool = false,
        notificationsEnabled: Bool = false,
        statsEnabled: Bool = true,
        startupMode: StartupMode = .disabled,
        sourceLanguageMode: SourceLanguageMode = .auto,
        language: TranslationLanguageConfig = .init(),
        featureProviders: FeatureProviderAssignments = .init(),
        translate: ClipboardTranslateSettings = .init(),
        providersConfig: [ProviderConfig] = ProviderConfig.defaults
    ) {
        self.theme = theme
        self.pollingIntervalMs = pollingIntervalMs
        self.autoTranslateEnabled = autoTranslateEnabled
        self.autoWriteBackEnabled = autoWriteBackEnabled
        self.notificationsEnabled = notificationsEnabled
        self.statsEnabled = statsEnabled
        self.startupMode = startupMode
        self.sourceLanguageMode = sourceLanguageMode
        self.language = language
        self.featureProviders = featureProviders
        self.translate = translate
        self.providersConfig = providersConfig
    }

    public static let `default` = AppSettings()

    public func providerConfig(for featureKey: FeatureKey) -> ProviderConfig? {
        let providerId = featureProviders.providerID(for: featureKey)
        return providersConfig.first(where: { $0.id == providerId })
    }
}

public struct ArticleContext: Codable, Equatable, Sendable {
    public var title: String?
    public var textContent: String?
    public var summary: String?

    public init(title: String? = nil, textContent: String? = nil, summary: String? = nil) {
        self.title = title
        self.textContent = textContent
        self.summary = summary
    }
}

public struct TranslationPrompt: Equatable, Sendable {
    public var systemPrompt: String
    public var prompt: String

    public init(systemPrompt: String, prompt: String) {
        self.systemPrompt = systemPrompt
        self.prompt = prompt
    }
}

public struct TranslationPromptOptions: Equatable, Sendable {
    public var isBatch: Bool
    public var content: ArticleContext?

    public init(isBatch: Bool = false, content: ArticleContext? = nil) {
        self.isBatch = isBatch
        self.content = content
    }
}

public struct TranslationExecutionOptions: Equatable, Sendable {
    public var isBatch: Bool
    public var forceBackgroundFetch: Bool
    public var content: ArticleContext?
    public var extraHashTags: [String]

    public init(
        isBatch: Bool = false,
        forceBackgroundFetch: Bool = false,
        content: ArticleContext? = nil,
        extraHashTags: [String] = []
    ) {
        self.isBatch = isBatch
        self.forceBackgroundFetch = forceBackgroundFetch
        self.content = content
        self.extraHashTags = extraHashTags
    }
}

public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var language: TranslationLanguageConfig
    public var providerConfig: ProviderConfig
    public var scheduleAt: Date
    public var hash: String
    public var options: TranslationExecutionOptions

    public init(
        text: String,
        language: TranslationLanguageConfig,
        providerConfig: ProviderConfig,
        scheduleAt: Date,
        hash: String,
        options: TranslationExecutionOptions = .init()
    ) {
        self.text = text
        self.language = language
        self.providerConfig = providerConfig
        self.scheduleAt = scheduleAt
        self.hash = hash
        self.options = options
    }
}

public struct TranslationCacheEntry: Equatable, Sendable {
    public var hash: String
    public var translation: String
    public var createdAt: Date

    public init(hash: String, translation: String, createdAt: Date = .now) {
        self.hash = hash
        self.translation = translation
        self.createdAt = createdAt
    }
}

public struct BatchRequestRecord: Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var originalRequestCount: Int
    public var providerId: String
    public var model: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        originalRequestCount: Int,
        providerId: String,
        model: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.originalRequestCount = originalRequestCount
        self.providerId = providerId
        self.model = model
    }
}

public struct TranslationRecord: Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var sourceTextLength: Int
    public var sourceLanguage: String?
    public var targetLanguage: String
    public var providerId: String
    public var latencyMs: Int
    public var success: Bool
    public var writeBackApplied: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourceTextLength: Int,
        sourceLanguage: String?,
        targetLanguage: String,
        providerId: String,
        latencyMs: Int,
        success: Bool,
        writeBackApplied: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceTextLength = sourceTextLength
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.providerId = providerId
        self.latencyMs = latencyMs
        self.success = success
        self.writeBackApplied = writeBackApplied
    }
}

public struct StatsSummary: Equatable, Sendable {
    public var totalTranslations: Int
    public var totalCharacters: Int
    public var averageLatencyMs: Double
    public var successRate: Double
    public var providerBreakdown: [String: Int]
    public var languagePairBreakdown: [String: Int]

    public init(
        totalTranslations: Int = 0,
        totalCharacters: Int = 0,
        averageLatencyMs: Double = 0,
        successRate: Double = 0,
        providerBreakdown: [String: Int] = [:],
        languagePairBreakdown: [String: Int] = [:]
    ) {
        self.totalTranslations = totalTranslations
        self.totalCharacters = totalCharacters
        self.averageLatencyMs = averageLatencyMs
        self.successRate = successRate
        self.providerBreakdown = providerBreakdown
        self.languagePairBreakdown = languagePairBreakdown
    }
}

public enum ClipboardChangeOrigin: Equatable, Sendable {
    case external
    case selfWritten
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public var changeCount: Int
    public var string: String?
    public var origin: ClipboardChangeOrigin

    public init(changeCount: Int, string: String?, origin: ClipboardChangeOrigin = .external) {
        self.changeCount = changeCount
        self.string = string
        self.origin = origin
    }
}
