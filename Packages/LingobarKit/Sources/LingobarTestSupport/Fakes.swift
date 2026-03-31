import Foundation
import LingobarApplication
import LingobarDomain

public actor InMemorySettingsStore: SettingsStore {
    private var settings: AppSettings

    public init(settings: AppSettings = .default) {
        self.settings = settings
    }

    public func load() async throws -> AppSettings {
        settings
    }

    public func save(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

public actor InMemoryCredentialsStore: CredentialsStore {
    private var apiKeys: [String: String]

    public init(apiKeys: [String: String] = [:]) {
        self.apiKeys = apiKeys
    }

    public func apiKey(for providerID: String) async throws -> String? {
        apiKeys[providerID]
    }

    public func saveAPIKey(_ apiKey: String?, for providerID: String) async throws {
        apiKeys[providerID] = apiKey
    }
}

public actor InMemoryTranslationCacheRepository: TranslationCacheRepository {
    private var storage: [String: TranslationCacheEntry]

    public init(storage: [String: TranslationCacheEntry] = [:]) {
        self.storage = storage
    }

    public func translation(for hash: String) async throws -> TranslationCacheEntry? {
        storage[hash]
    }

    public func save(_ entry: TranslationCacheEntry) async throws {
        storage[entry.hash] = entry
    }

    public func removeAll() async throws {
        storage.removeAll()
    }
}

public actor InMemoryStatisticsRepository: StatisticsRepository {
    private var batchStorage: [BatchRequestRecord]
    private var translationStorage: [TranslationRecord]

    public init(
        batchStorage: [BatchRequestRecord] = [],
        translationStorage: [TranslationRecord] = []
    ) {
        self.batchStorage = batchStorage
        self.translationStorage = translationStorage
    }

    public func recordBatchRequest(_ record: BatchRequestRecord) async throws {
        batchStorage.append(record)
    }

    public func recordTranslation(_ record: TranslationRecord) async throws {
        translationStorage.append(record)
    }

    public func batchRequests(from start: Date, to end: Date) async throws -> [BatchRequestRecord] {
        batchStorage.filter { $0.createdAt >= start && $0.createdAt <= end }
    }

    public func translations(from start: Date, to end: Date) async throws -> [TranslationRecord] {
        translationStorage.filter { $0.createdAt >= start && $0.createdAt <= end }
    }
}

public struct TestPromptResolver: TranslationPromptResolving {
    public var makePrompt: @Sendable (String, String, TranslationPromptOptions) -> TranslationPrompt

    public init(
        makePrompt: @escaping @Sendable (String, String, TranslationPromptOptions) -> TranslationPrompt = { targetLanguage, input, _ in
            TranslationPrompt(
                systemPrompt: "Translate to \(targetLanguage)",
                prompt: input
            )
        }
    ) {
        self.makePrompt = makePrompt
    }

    public func resolve(targetLanguageName: String, input: String, options: TranslationPromptOptions) async throws -> TranslationPrompt {
        makePrompt(targetLanguageName, input, options)
    }
}

public struct FakeTranslationExecutor: TranslationExecuting {
    public var handler: @Sendable (TranslationRequest) async throws -> String

    public init(handler: @escaping @Sendable (TranslationRequest) async throws -> String) {
        self.handler = handler
    }

    public func execute(request: TranslationRequest) async throws -> String {
        try await handler(request)
    }
}

public final class FakeClipboardMonitor: ClipboardMonitoring, @unchecked Sendable {
    private let stream: AsyncStream<ClipboardSnapshot>
    private let continuation: AsyncStream<ClipboardSnapshot>.Continuation

    public var snapshots: AsyncStream<ClipboardSnapshot> { stream }

    public init() {
        var continuation: AsyncStream<ClipboardSnapshot>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() async {}
    public func stop() async {}

    public func emit(_ snapshot: ClipboardSnapshot) {
        continuation.yield(snapshot)
    }
}

public actor FakeClipboardWriter: ClipboardWriting {
    public private(set) var writes: [String] = []

    public init() {}

    public func write(_ string: String) async throws {
        writes.append(string)
    }
}

public actor RecordingNotifier: UserNotifying {
    public private(set) var messages: [(title: String, body: String)] = []

    public init() {}

    public func notify(title: String, body: String) async {
        messages.append((title: title, body: body))
    }
}
