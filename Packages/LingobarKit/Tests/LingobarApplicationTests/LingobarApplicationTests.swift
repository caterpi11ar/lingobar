import XCTest
@testable import LingobarApplication
@testable import LingobarDomain
import LingobarTestSupport

private actor CallCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private actor StringRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

final class LingobarApplicationTests: XCTestCase {
    func testRequestQueueDeduplicatesSameHash() async throws {
        let queue = RequestQueue<String>(
            options: RequestQueueConfig(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10)
        )
        let counter = CallCounter()

        let thunk: @Sendable () async throws -> String = {
            _ = await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return "ok"
        }

        async let first = queue.enqueue(thunk, scheduleAt: .now, hash: "same")
        async let second = queue.enqueue(thunk, scheduleAt: .now, hash: "same")

        let firstValue = try await first
        let secondValue = try await second
        XCTAssertEqual([firstValue, secondValue], ["ok", "ok"])
        let callCount = await counter.value
        XCTAssertEqual(callCount, 1)
    }

    func testRequestQueueRetriesAfterTimeout() async throws {
        let queue = RequestQueue<String>(
            options: RequestQueueConfig(rate: 50, capacity: 50, timeoutMs: 100, maxRetries: 1, baseRetryDelayMs: 10)
        )
        let counter = CallCounter()

        let value = try await queue.enqueue({
            let attempt = await counter.increment()
            if attempt == 1 {
                try await Task.sleep(for: .milliseconds(2_000))
                return "late"
            }
            return "recovered"
        }, scheduleAt: .now, hash: "retry")

        XCTAssertEqual(value, "recovered")
        let retryCount = await counter.value
        XCTAssertEqual(retryCount, 2)
    }

    func testBatchQueueFallsBackToIndividualAfterCountMismatch() async throws {
        let queue = BatchQueue<String, String>(
            options: BatchQueueOptions(
                maxCharactersPerBatch: 100,
                maxItemsPerBatch: 2,
                batchDelayMs: 10,
                maxRetries: 1,
                enableFallbackToIndividual: true,
                getBatchKey: { _ in "group" },
                getCharacterCount: { $0.count },
                executeBatch: { _ in ["only-one"] },
                executeIndividual: { $0.uppercased() }
            )
        )

        async let first = queue.enqueue("one")
        async let second = queue.enqueue("two")

        let firstValue = try await first
        let secondValue = try await second
        XCTAssertEqual([firstValue, secondValue], ["ONE", "TWO"])
    }

    func testTranslationEngineUsesCacheBeforeExecutor() async throws {
        let counter = CallCounter()
        let executor = FakeTranslationExecutor { request in
            _ = await counter.increment()
            return "tx:\(request.text)"
        }
        let engine = TranslationEngine(
            executor: executor,
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: InMemoryStatisticsRepository(),
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init()
        )
        let provider = ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)

        let first = try await engine.translateTextCore(
            text: "hello",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: provider,
            enableAIContentAware: false
        )
        let second = try await engine.translateTextCore(
            text: "hello",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: provider,
            enableAIContentAware: false
        )

        XCTAssertEqual(first, "tx:hello")
        XCTAssertEqual(second, "tx:hello")
        let cacheHitCount = await counter.value
        XCTAssertEqual(cacheHitCount, 1)
    }

    func testTranslationEngineBatchesLLMRequestsAndRecordsStats() async throws {
        let stats = InMemoryStatisticsRepository()
        let executor = FakeTranslationExecutor { request in
            if request.options.isBatch {
                return request.text
                    .components(separatedBy: TranslationHashBuilder.batchSeparator)
                    .map { "tx:\($0)" }
                    .joined(separator: TranslationHashBuilder.batchSeparator)
            }
            return "tx:\(request.text)"
        }
        let engine = TranslationEngine(
            executor: executor,
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: stats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init(maxCharactersPerBatch: 1_000, maxItemsPerBatch: 10, batchDelayMs: 20, maxRetries: 1, enableFallbackToIndividual: true)
        )
        let provider = ProviderConfig(
            id: ProviderID.openAI.rawValue,
            name: "OpenAI",
            provider: .openAI,
            apiKey: "test-key",
            model: .init(model: "gpt-4o-mini")
        )

        async let first = engine.translateTextCore(
            text: "one",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: provider,
            enableAIContentAware: false
        )
        async let second = engine.translateTextCore(
            text: "two",
            language: .init(sourceCode: "auto", targetCode: "zh"),
            providerConfig: provider,
            enableAIContentAware: false
        )

        let firstValue = try await first
        let secondValue = try await second
        XCTAssertEqual([firstValue, secondValue], ["tx:one", "tx:two"])

        let records = try await stats.batchRequests(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.originalRequestCount, 2)
    }

    func testClipboardCoordinatorHandlesExternalClipboardAndIgnoresSelfWritten() async throws {
        let settings = AppSettings(
            autoTranslateEnabled: true,
            autoWriteBackEnabled: true,
            notificationsEnabled: true,
            statsEnabled: true,
            featureProviders: .init(clipboardTranslate: ProviderID.googleTranslate.rawValue),
            providersConfig: [ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)]
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
        let runtimeStore = ClipboardTranslationRuntimeStore()
        let coordinator = ClipboardTranslationCoordinator(
            settingsStore: settingsStore,
            translationEngine: engine,
            clipboardMonitor: monitor,
            clipboardWriter: writer,
            notifier: notifier,
            statisticsRepository: stats,
            runtimeStore: runtimeStore
        )

        await coordinator.start()
        monitor.emit(.init(changeCount: 1, string: "hello", origin: .external))
        monitor.emit(.init(changeCount: 2, string: "你好", origin: .selfWritten))
        monitor.emit(.init(changeCount: 2, string: "你好", origin: .external))
        try await Task.sleep(for: .milliseconds(200))
        await coordinator.stop()

        let writes = await writer.writes
        let notifications = await notifier.messages
        XCTAssertEqual(writes, ["你好"])
        XCTAssertEqual(notifications.count, 1)

        let translations = try await stats.translations(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(translations.count, 1)
        XCTAssertEqual(translations.first?.success, true)
    }

    func testClipboardCoordinatorDebouncesRapidUpdatesAndPublishesSuccessState() async throws {
        let recordedTexts = StringRecorder()
        let settings = AppSettings(
            autoTranslateEnabled: true,
            autoWriteBackEnabled: false,
            notificationsEnabled: false,
            statsEnabled: true,
            featureProviders: .init(clipboardTranslate: ProviderID.googleTranslate.rawValue),
            translate: .init(batchQueueConfig: .init(batchDelayMs: 120)),
            providersConfig: [ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)]
        )
        let settingsStore = InMemorySettingsStore(settings: settings)
        let stats = InMemoryStatisticsRepository()
        let engine = TranslationEngine(
            executor: FakeTranslationExecutor { request in
                await recordedTexts.append(request.text)
                return "tx:\(request.text)"
            },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: stats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init()
        )
        let monitor = FakeClipboardMonitor()
        let writer = FakeClipboardWriter()
        let notifier = RecordingNotifier()
        let runtimeStore = ClipboardTranslationRuntimeStore()
        let coordinator = ClipboardTranslationCoordinator(
            settingsStore: settingsStore,
            translationEngine: engine,
            clipboardMonitor: monitor,
            clipboardWriter: writer,
            notifier: notifier,
            statisticsRepository: stats,
            runtimeStore: runtimeStore
        )

        await coordinator.start()
        monitor.emit(.init(changeCount: 1, string: "first", origin: .external))
        try await Task.sleep(for: .milliseconds(40))
        monitor.emit(.init(changeCount: 2, string: "second", origin: .external))
        try await Task.sleep(for: .milliseconds(260))
        await coordinator.stop()

        let executedTexts = await recordedTexts.values
        let writes = await writer.writes
        XCTAssertEqual(executedTexts, ["second"])
        XCTAssertEqual(writes, [])

        let state = await runtimeStore.currentState()
        XCTAssertEqual(state.phase, .succeeded)
        XCTAssertEqual(state.sourcePreview, "second")
        XCTAssertEqual(state.translatedPreview, "tx:second")

        let translations = try await stats.translations(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(translations.count, 1)
        XCTAssertEqual(translations.first?.sourceTextLength, "second".count)
    }

    func testClipboardCoordinatorTranslatesEnglishToChineseAndChineseToEnglish() async throws {
        let capturedLanguages = StringRecorder()
        let settings = AppSettings(
            autoTranslateEnabled: true,
            autoWriteBackEnabled: false,
            notificationsEnabled: false,
            statsEnabled: true,
            language: .init(sourceCode: "auto", targetCode: "ja"),
            featureProviders: .init(clipboardTranslate: ProviderID.googleTranslate.rawValue),
            providersConfig: [ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)]
        )
        let settingsStore = InMemorySettingsStore(settings: settings)
        let stats = InMemoryStatisticsRepository()
        let engine = TranslationEngine(
            executor: FakeTranslationExecutor { request in
                await capturedLanguages.append("\(request.language.sourceCode)->\(request.language.targetCode)")
                return "tx:\(request.text)"
            },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: stats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init(batchDelayMs: 60)
        )
        let monitor = FakeClipboardMonitor()
        let testCoordinator = ClipboardTranslationCoordinator(
            settingsStore: settingsStore,
            translationEngine: engine,
            clipboardMonitor: monitor,
            clipboardWriter: FakeClipboardWriter(),
            notifier: RecordingNotifier(),
            statisticsRepository: stats,
            runtimeStore: ClipboardTranslationRuntimeStore()
        )

        await testCoordinator.start()
        monitor.emit(.init(changeCount: 1, string: "hello world", origin: .external))
        try await Task.sleep(for: .milliseconds(180))
        monitor.emit(.init(changeCount: 2, string: "你好世界", origin: .external))
        try await Task.sleep(for: .milliseconds(180))
        await testCoordinator.stop()

        let languages = await capturedLanguages.values
        XCTAssertEqual(languages, ["en->zh", "zh->en"])

        let translations = try await stats.translations(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(translations.map(\.targetLanguage), ["zh", "en"])
        XCTAssertEqual(translations.map(\.sourceLanguage), ["en", "zh"])
    }

    func testClipboardCoordinatorAppliesUpdatedAutoWriteBackSettingWithoutRestart() async throws {
        let provider = ProviderConfig(id: ProviderID.googleTranslate.rawValue, name: "Google", provider: .googleTranslate)
        let initialSettings = AppSettings(
            autoTranslateEnabled: true,
            autoWriteBackEnabled: false,
            notificationsEnabled: false,
            statsEnabled: true,
            featureProviders: .init(clipboardTranslate: ProviderID.googleTranslate.rawValue),
            translate: .init(batchQueueConfig: .init(batchDelayMs: 60)),
            providersConfig: [provider]
        )
        let settingsStore = InMemorySettingsStore(settings: initialSettings)
        let stats = InMemoryStatisticsRepository()
        let engine = TranslationEngine(
            executor: FakeTranslationExecutor { request in
                "tx:\(request.text)"
            },
            promptResolver: TestPromptResolver(),
            cacheRepository: InMemoryTranslationCacheRepository(),
            statisticsRepository: stats,
            requestQueueConfig: .init(rate: 50, capacity: 50, timeoutMs: 1_000, maxRetries: 0, baseRetryDelayMs: 10),
            batchQueueConfig: .init(batchDelayMs: 60)
        )
        let monitor = FakeClipboardMonitor()
        let writer = FakeClipboardWriter()
        let coordinator = ClipboardTranslationCoordinator(
            settingsStore: settingsStore,
            translationEngine: engine,
            clipboardMonitor: monitor,
            clipboardWriter: writer,
            notifier: RecordingNotifier(),
            statisticsRepository: stats,
            runtimeStore: ClipboardTranslationRuntimeStore()
        )

        await coordinator.start()
        monitor.emit(.init(changeCount: 1, string: "first", origin: .external))
        try await Task.sleep(for: .milliseconds(200))
        let initialWrites = await writer.writes
        XCTAssertEqual(initialWrites, [])

        var updatedSettings = initialSettings
        updatedSettings.autoWriteBackEnabled = true
        try await settingsStore.save(updatedSettings)

        monitor.emit(.init(changeCount: 2, string: "second", origin: .external))
        try await Task.sleep(for: .milliseconds(200))
        await coordinator.stop()

        let writes = await writer.writes
        XCTAssertEqual(writes, ["tx:second"])
    }

    func testStatisticsCalculatorAggregatesDayWeekMonthYearRecords() {
        let now = Date()
        let records = [
            TranslationRecord(createdAt: now, sourceTextLength: 10, sourceLanguage: "en", targetLanguage: "zh", providerId: "p1", latencyMs: 100, success: true, writeBackApplied: true),
            TranslationRecord(createdAt: now.addingTimeInterval(-3_600), sourceTextLength: 20, sourceLanguage: nil, targetLanguage: "zh", providerId: "p1", latencyMs: 300, success: false, writeBackApplied: false),
        ]

        let summary = StatisticsCalculator.summary(from: records)
        XCTAssertEqual(summary.totalTranslations, 2)
        XCTAssertEqual(summary.totalCharacters, 30)
        XCTAssertEqual(summary.averageLatencyMs, 200, accuracy: 0.001)
        XCTAssertEqual(summary.successRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.providerBreakdown["p1"], 2)
        XCTAssertEqual(summary.languagePairBreakdown["en->zh"], 1)
        XCTAssertEqual(summary.languagePairBreakdown["auto->zh"], 1)
    }
}
