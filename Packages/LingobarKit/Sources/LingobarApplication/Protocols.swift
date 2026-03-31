import Foundation
import LingobarDomain

public protocol SettingsStore: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

public protocol CredentialsStore: Sendable {
    func apiKey(for providerID: String) async throws -> String?
    func saveAPIKey(_ apiKey: String?, for providerID: String) async throws
}

public protocol TranslationCacheRepository: Sendable {
    func translation(for hash: String) async throws -> TranslationCacheEntry?
    func save(_ entry: TranslationCacheEntry) async throws
    func removeAll() async throws
}

public protocol StatisticsRepository: Sendable {
    func recordBatchRequest(_ record: BatchRequestRecord) async throws
    func recordTranslation(_ record: TranslationRecord) async throws
    func batchRequests(from start: Date, to end: Date) async throws -> [BatchRequestRecord]
    func translations(from start: Date, to end: Date) async throws -> [TranslationRecord]
}

public protocol TranslationPromptResolving: Sendable {
    func resolve(targetLanguageName: String, input: String, options: TranslationPromptOptions) async throws -> TranslationPrompt
}

public protocol TranslationExecuting: Sendable {
    func execute(request: TranslationRequest) async throws -> String
}

public protocol ClipboardMonitoring: Sendable {
    var snapshots: AsyncStream<ClipboardSnapshot> { get }
    func start() async
    func stop() async
}

public protocol ClipboardWriting: Sendable {
    func write(_ string: String) async throws
}

public protocol UserNotifying: Sendable {
    func notify(title: String, body: String) async
}
