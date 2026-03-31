import Foundation
import LingobarApplication
import LingobarDomain
import LingobarInfrastructure
import LingobarTestSupport

private struct VerificationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private actor MockHTTPClient: HTTPClient {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private var handlers: [Handler] = []

    func enqueue(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !handlers.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return try handlers.removeFirst()(request)
    }
}

private struct StaticPromptResolver: TranslationPromptResolving {
    let prompt: TranslationPrompt

    func resolve(targetLanguageName: String, input: String, options: TranslationPromptOptions) async throws -> TranslationPrompt {
        prompt
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw VerificationFailure(message: message)
    }
}

private func requireEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw VerificationFailure(message: "\(message) | lhs=\(lhs) rhs=\(rhs)")
    }
}

private func jsonResponse(url: URL, payload: Any, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    let data = try JSONSerialization.data(withJSONObject: payload)
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
        throw VerificationFailure(message: "Failed to create HTTPURLResponse")
    }
    return (data, response)
}

@main
enum LingobarVerification {
    static func main() async {
        do {
            try await runAll()
            print("Lingobar verification passed.")
        } catch {
            fputs("Lingobar verification failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runAll() async throws {
        try await verifyProviderTypes()
        try await verifyRequestQueue()
        try await verifyBatchQueue()
        try await verifyTranslationEngine()
        try await verifyClipboardWorkflow()
        try await verifyProviderContracts()
        try await verifySQLiteRepositories()
    }

    private static func verifyProviderTypes() async throws {
        try requireEqual(ProviderConfig.defaults.count, ProviderID.allCases.count, "Provider defaults should cover all provider ids")
        try require(!ProviderConfig(id: "g", name: "Google", provider: .googleTranslate).requiresAPIKey, "Google translate should not need API key")
        try require(ProviderConfig(id: "d", name: "DeepL", provider: .deepl).requiresAPIKey, "DeepL should need API key")
        try require(!ProviderConfig(id: "o", name: "Ollama", provider: .ollama).requiresAPIKey, "Ollama should not require API key")
    }

    private static func verifyRequestQueue() async throws {
        let dedupeQueue = RequestQueue<String>(
            options: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10)
        )
        let dedupeCounter = Counter()
        let thunk: @Sendable () async throws -> String = {
            _ = await dedupeCounter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return "ok"
        }

        async let first = dedupeQueue.enqueue(thunk, scheduleAt: .now, hash: "same")
        async let second = dedupeQueue.enqueue(thunk, scheduleAt: .now, hash: "same")
        try requireEqual(try await first, "ok", "First dedupe result mismatch")
        try requireEqual(try await second, "ok", "Second dedupe result mismatch")
        try requireEqual(await dedupeCounter.value, 1, "Dedupe queue should execute once")

        let retryQueue = RequestQueue<String>(
            options: .init(rate: 50, capacity: 50, timeoutMs: 50, maxRetries: 1, baseRetryDelayMs: 10)
        )
        let retryCounter = Counter()
        let recovered = try await retryQueue.enqueue({
            let attempt = await retryCounter.increment()
            if attempt == 1 {
                try await Task.sleep(for: .milliseconds(100))
                return "slow"
            }
            return "recovered"
        }, scheduleAt: .now, hash: "retry")
        try requireEqual(recovered, "recovered", "Retry queue should recover on second attempt")
        try requireEqual(await retryCounter.value, 2, "Retry queue should attempt twice")
    }

    private static func verifyBatchQueue() async throws {
        let queue = BatchQueue<String, String>(
            options: .init(
                maxCharactersPerBatch: 100,
                maxItemsPerBatch: 2,
                batchDelayMs: 10,
                maxRetries: 1,
                enableFallbackToIndividual: true,
                getBatchKey: { _ in "group" },
                getCharacterCount: { $0.count },
                executeBatch: { _ in ["single"] },
                executeIndividual: { $0.uppercased() }
            )
        )

        async let first = queue.enqueue("one")
        async let second = queue.enqueue("two")
        try requireEqual(try await first, "ONE", "Fallback individual result mismatch for first item")
        try requireEqual(try await second, "TWO", "Fallback individual result mismatch for second item")
    }

    private static func verifyTranslationEngine() async throws {
        let cacheCounter = Counter()
        let cacheStats = InMemoryStatisticsRepository()
        let cacheEngine = TranslationEngine(
            executor: FakeTranslationExecutor { request in
                _ = await cacheCounter.increment()
                return "tx:\(request.text)"
            },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: cacheStats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init()
        )
        let googleProvider = ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)
        let first = try await cacheEngine.translateTextCore(
            text: "hello",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: googleProvider,
            enableAIContentAware: false
        )
        let second = try await cacheEngine.translateTextCore(
            text: "hello",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: googleProvider,
            enableAIContentAware: false
        )
        try requireEqual(first, "tx:hello", "Cache engine first translation mismatch")
        try requireEqual(second, "tx:hello", "Cache engine second translation mismatch")
        try requireEqual(await cacheCounter.value, 1, "Cache should prevent duplicate execution")

        let batchStats = InMemoryStatisticsRepository()
        let batchEngine = TranslationEngine(
            executor: FakeTranslationExecutor { request in
                if request.options.isBatch {
                    return request.text
                        .components(separatedBy: TranslationHashBuilder.batchSeparator)
                        .map { "tx:\($0)" }
                        .joined(separator: TranslationHashBuilder.batchSeparator)
                }
                return "tx:\(request.text)"
            },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: batchStats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init(maxCharactersPerBatch: 1_000, maxItemsPerBatch: 10, batchDelayMs: 20, maxRetries: 1, enableFallbackToIndividual: true)
        )
        let llmProvider = ProviderConfig(
            id: ProviderID.openAI.rawValue,
            name: "OpenAI",
            provider: .openAI,
            apiKey: "test-key",
            model: .init(model: "gpt-4o-mini")
        )

        async let batchOne = batchEngine.translateTextCore(
            text: "one",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: llmProvider,
            enableAIContentAware: false
        )
        async let batchTwo = batchEngine.translateTextCore(
            text: "two",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: llmProvider,
            enableAIContentAware: false
        )
        try requireEqual(try await batchOne, "tx:one", "Batch engine first result mismatch")
        try requireEqual(try await batchTwo, "tx:two", "Batch engine second result mismatch")
        let batchRecords = try await batchStats.batchRequests(from: .distantPast, to: .distantFuture)
        try requireEqual(batchRecords.count, 1, "Batch stats should contain one record")
        try requireEqual(batchRecords.first?.originalRequestCount, 2, "Batch request should record both items")
    }

    private static func verifyClipboardWorkflow() async throws {
        let settings = AppSettings(
            autoTranslateEnabled: true,
            autoWriteBackEnabled: true,
            notificationsEnabled: true,
            statsEnabled: true,
            featureProviders: .init(clipboardTranslate: ProviderID.googleTranslate.rawValue),
            providersConfig: [.init(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)]
        )
        let settingsStore = InMemorySettingsStore(settings: settings)
        let stats = InMemoryStatisticsRepository()
        let engine = TranslationEngine(
            executor: FakeTranslationExecutor { _ in "你好" },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: stats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init()
        )
        let monitor = FakeClipboardMonitor()
        let writer = FakeClipboardWriter()
        let notifier = RecordingNotifier()
        let coordinator = ClipboardTranslationCoordinator(
            settingsStore: settingsStore,
            translationEngine: engine,
            clipboardMonitor: monitor,
            clipboardWriter: writer,
            notifier: notifier,
            statisticsRepository: stats
        )

        await coordinator.start()
        monitor.emit(.init(changeCount: 1, string: "hello", origin: .external))
        monitor.emit(.init(changeCount: 2, string: "你好", origin: .selfWritten))
        monitor.emit(.init(changeCount: 2, string: "你好", origin: .external))
        try await Task.sleep(for: .milliseconds(200))
        await coordinator.stop()

        try requireEqual(await writer.writes, ["你好"], "Clipboard writer should record one translated write")
        try requireEqual((await notifier.messages).count, 1, "Notifier should emit once")
        let records = try await stats.translations(from: .distantPast, to: .distantFuture)
        try requireEqual(records.count, 1, "Clipboard workflow should record one translation")
        try require(records.first?.success == true, "Clipboard translation record should be successful")
    }

    private static func verifyProviderContracts() async throws {
        try await verifyGoogleContract()
        try await verifyMicrosoftContract()
        try await verifyDeepLContract()
        try await verifyDeepLXContract()
        try await verifyOpenAICompatibleContract()
    }

    private static func verifyGoogleContract() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            try requireEqual(request.url?.host, "translate.googleapis.com", "Google translate host mismatch")
            return try jsonResponse(url: request.url!, payload: [[["你好", "hello", NSNull(), NSNull(), 1]], NSNull(), "en"])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: .init(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate),
                scheduleAt: .now,
                hash: "g"
            )
        )
        try requireEqual(value, "你好", "Google translate response mismatch")
    }

    private static func verifyMicrosoftContract() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            let data = Data("token-123".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        await client.enqueue { request in
            try requireEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123", "Microsoft authorization header mismatch")
            try requireEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), "token-123", "Microsoft subscription header mismatch")
            return try jsonResponse(url: request.url!, payload: [["translations": [["text": "你好"]]]])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: .init(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: ProviderID.microsoftTranslate.rawValue, name: "Microsoft", provider: .microsoftTranslate),
                scheduleAt: .now,
                hash: "m"
            )
        )
        try requireEqual(value, "你好", "Microsoft translate response mismatch")
    }

    private static func verifyDeepLContract() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            try requireEqual(request.url?.absoluteString, "https://api-free.deepl.com/v2/translate", "DeepL free endpoint mismatch")
            try requireEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key key:fx", "DeepL auth header mismatch")
            return try jsonResponse(url: request.url!, payload: ["translations": [["text": "你好"]]])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: .init(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: ProviderID.deepl.rawValue, name: "DeepL", provider: .deepl, apiKey: "key:fx"),
                scheduleAt: .now,
                hash: "d"
            )
        )
        try requireEqual(value, "你好", "DeepL response mismatch")
    }

    private static func verifyDeepLXContract() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            try requireEqual(request.url?.absoluteString, "https://api.deeplx.org/abc/translate", "DeepLX URL mismatch")
            return try jsonResponse(url: request.url!, payload: ["data": "你好"])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: .init(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: ProviderID.deeplx.rawValue, name: "DeepLX", provider: .deeplx, apiKey: "abc", baseURL: "https://api.deeplx.org"),
                scheduleAt: .now,
                hash: "dx"
            )
        )
        try requireEqual(value, "你好", "DeepLX response mismatch")
    }

    private static func verifyOpenAICompatibleContract() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            try requireEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key", "OpenAI auth header mismatch")
            guard let body = request.httpBody,
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw VerificationFailure(message: "Missing OpenAI request body")
            }
            try requireEqual(payload["model"] as? String, "gpt-4o-mini", "OpenAI model mismatch")
            try requireEqual(payload["top_p"] as? Double, 0.8, "OpenAI provider option mismatch")
            return try jsonResponse(url: request.url!, payload: ["choices": [["message": ["content": "你好"]]]])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "system", prompt: "user"))
        )
        let provider = ProviderConfig(
            id: ProviderID.openAI.rawValue,
            name: "OpenAI",
            provider: .openAI,
            apiKey: "test-key",
            baseURL: "https://api.openai.com/v1",
            providerOptions: ["top_p": .number(0.8)],
            model: .init(model: "gpt-4o-mini")
        )
        let value = try await executor.execute(
            request: .init(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: provider,
                scheduleAt: .now,
                hash: "o"
            )
        )
        try requireEqual(value, "你好", "OpenAI-compatible response mismatch")
    }

    private static func verifySQLiteRepositories() async throws {
        let database = try AppDatabase()
        let cache = SQLiteTranslationCacheRepository(database: database)
        let stats = SQLiteStatisticsRepository(database: database)

        try await cache.save(.init(hash: "abc", translation: "你好"))
        let cached = try await cache.translation(for: "abc")
        try requireEqual(cached?.translation, "你好", "SQLite cache roundtrip mismatch")

        let now = Date()
        let old = now.addingTimeInterval(-10 * 24 * 60 * 60)
        try await stats.recordTranslation(.init(createdAt: old, sourceTextLength: 5, sourceLanguage: "en", targetLanguage: "zh", providerId: "g", latencyMs: 50, success: true, writeBackApplied: false))
        try await stats.recordTranslation(.init(createdAt: now, sourceTextLength: 10, sourceLanguage: nil, targetLanguage: "zh", providerId: "o", latencyMs: 100, success: true, writeBackApplied: true))

        let recent = try await stats.translations(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60))
        try requireEqual(recent.count, 1, "SQLite translation filter should only return recent record")
        try requireEqual(recent.first?.providerId, "o", "SQLite recent provider id mismatch")
    }
}
