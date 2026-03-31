import Foundation
import LingobarDomain

public final class TranslationEngine: Sendable {
    private let executor: any TranslationExecuting
    private let promptResolver: any TranslationPromptResolving
    private let cacheRepository: any TranslationCacheRepository
    private let statisticsRepository: any StatisticsRepository
    private let requestQueue: RequestQueue<String>
    private let batchRequestQueue: RequestQueue<[String]>
    private let batchQueue: BatchQueue<TranslationRequest, String>

    public init(
        executor: any TranslationExecuting,
        promptResolver: any TranslationPromptResolving,
        cacheRepository: any TranslationCacheRepository,
        statisticsRepository: any StatisticsRepository,
        requestQueueConfig: RequestQueueConfig,
        batchQueueConfig: BatchQueueConfig
    ) {
        self.executor = executor
        self.promptResolver = promptResolver
        self.cacheRepository = cacheRepository
        self.statisticsRepository = statisticsRepository
        self.requestQueue = RequestQueue(options: requestQueueConfig)
        self.batchRequestQueue = RequestQueue(options: requestQueueConfig)

        let requestQueue = self.requestQueue
        let batchRequestQueue = self.batchRequestQueue
        let executor = self.executor
        let statisticsRepository = self.statisticsRepository

        self.batchQueue = BatchQueue(
            options: BatchQueueOptions<TranslationRequest, String>(
                maxCharactersPerBatch: batchQueueConfig.maxCharactersPerBatch,
                maxItemsPerBatch: batchQueueConfig.maxItemsPerBatch,
                batchDelayMs: batchQueueConfig.batchDelayMs,
                maxRetries: batchQueueConfig.maxRetries,
                enableFallbackToIndividual: batchQueueConfig.enableFallbackToIndividual,
                getBatchKey: { request in
                    "\(request.language.sourceCode)-\(request.language.targetCode)-\(request.providerConfig.id)"
                },
                getCharacterCount: { $0.text.count },
                executeBatch: { requests in
                    let first = requests[0]
                    let combinedHash = TranslationHashBuilder.buildHash(requests.map(\.hash))
                    let earliest = requests.map(\.scheduleAt).min() ?? .now
                    let content = first.options.content
                    let batchRequest = TranslationRequest(
                        text: requests.map(\.text).joined(separator: TranslationHashBuilder.batchSeparator),
                        language: first.language,
                        providerConfig: first.providerConfig,
                        scheduleAt: earliest,
                        hash: combinedHash,
                        options: TranslationExecutionOptions(isBatch: true, content: content)
                    )

                    let model = first.providerConfig.model?.resolvedModelIdentifier ?? ""
                    let batchThunk: @Sendable () async throws -> [String] = {
                        try await statisticsRepository.recordBatchRequest(
                            BatchRequestRecord(
                                originalRequestCount: requests.count,
                                providerId: first.providerConfig.provider.rawValue,
                                model: model
                            )
                        )
                        let result = try await executor.execute(request: batchRequest)
                        return TranslationHashBuilder.parseBatchResult(result)
                    }

                    return try await batchRequestQueue.enqueue(batchThunk, scheduleAt: earliest, hash: combinedHash)
                },
                executeIndividual: { request in
                    let model = request.providerConfig.model?.resolvedModelIdentifier ?? ""
                    let thunk: @Sendable () async throws -> String = {
                        try await statisticsRepository.recordBatchRequest(
                            BatchRequestRecord(
                                originalRequestCount: 1,
                                providerId: request.providerConfig.provider.rawValue,
                                model: model
                            )
                        )
                        return try await executor.execute(request: request)
                    }
                    return try await requestQueue.enqueue(thunk, scheduleAt: request.scheduleAt, hash: request.hash)
                }
            )
        )
    }

    public func setQueueConfig(request: RequestQueueOptionsPatch) async {
        await requestQueue.setOptions(request)
        await batchRequestQueue.setOptions(request)
    }

    public func setBatchConfig(batch: BatchQueueOptionsPatch) async {
        await batchQueue.setOptions(batch)
    }

    public func translateTextCore(
        text: String,
        language: TranslationLanguageConfig,
        providerConfig: ProviderConfig,
        enableAIContentAware: Bool,
        extraHashTags: [String] = [],
        articleContext: ArticleContext? = nil
    ) async throws -> String {
        let preparedText = TranslationHashBuilder.prepareTranslationText(text)
        if preparedText.isEmpty {
            return ""
        }

        let prompt = try await promptForHash(
            text: preparedText,
            language: language,
            providerConfig: providerConfig,
            articleContext: articleContext
        )

        var hashComponents = TranslationHashBuilder.buildHashComponents(
            text: preparedText,
            providerConfig: providerConfig,
            language: language,
            enableAIContentAware: enableAIContentAware,
            articleContext: articleContext,
            prompt: prompt
        )
        hashComponents.append(contentsOf: extraHashTags)
        let hash = TranslationHashBuilder.buildHash(hashComponents)

        if let cached = try await cacheRepository.translation(for: hash) {
            return cached.translation
        }

        let request = TranslationRequest(
            text: preparedText,
            language: language,
            providerConfig: providerConfig,
            scheduleAt: .now,
            hash: hash,
            options: TranslationExecutionOptions(
                isBatch: false,
                content: articleContext,
                extraHashTags: extraHashTags
            )
        )

        let result: String
        if providerConfig.isLLMProvider {
            result = try await batchQueue.enqueue(request)
        } else {
            result = try await requestQueue.enqueue(
                { try await self.executor.execute(request: request) },
                scheduleAt: request.scheduleAt,
                hash: request.hash
            )
        }

        if !result.isEmpty {
            try await cacheRepository.save(TranslationCacheEntry(hash: hash, translation: result))
        }

        return result
    }

    private func promptForHash(
        text: String,
        language: TranslationLanguageConfig,
        providerConfig: ProviderConfig,
        articleContext: ArticleContext?
    ) async throws -> TranslationPrompt? {
        guard providerConfig.isLLMProvider else { return nil }
        let targetLanguage = Self.targetLanguageName(for: language.targetCode)
        return try await promptResolver.resolve(
            targetLanguageName: targetLanguage,
            input: text,
            options: TranslationPromptOptions(isBatch: true, content: articleContext)
        )
    }

    private static func targetLanguageName(for code: String) -> String {
        let mapping: [String: String] = [
            "en": "English",
            "zh": "Chinese",
            "ja": "Japanese",
            "ko": "Korean",
            "fr": "French",
            "de": "German",
            "es": "Spanish",
        ]
        return mapping[code] ?? code.uppercased()
    }
}
