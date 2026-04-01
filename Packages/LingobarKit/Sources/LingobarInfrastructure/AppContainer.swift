import Foundation
import LingobarApplication
import LingobarDomain

public final class AppContainer: @unchecked Sendable {
    public let settingsStore: any SettingsStore
    public let credentialsStore: any CredentialsStore
    public let cacheRepository: any TranslationCacheRepository
    public let statisticsRepository: any StatisticsRepository
    public let promptResolver: any TranslationPromptResolving
    public let executor: any TranslationExecuting
    public let clipboardMonitor: any ClipboardMonitoring
    public let clipboardWriter: any ClipboardWriting
    public let notifier: any UserNotifying
    public let runtimeStore: ClipboardTranslationRuntimeStore
    public let translationEngine: TranslationEngine
    public let coordinator: ClipboardTranslationCoordinator

    public init(
        settingsStore: any SettingsStore,
        credentialsStore: any CredentialsStore,
        cacheRepository: any TranslationCacheRepository,
        statisticsRepository: any StatisticsRepository,
        promptResolver: any TranslationPromptResolving,
        executor: any TranslationExecuting,
        clipboardMonitor: any ClipboardMonitoring,
        clipboardWriter: any ClipboardWriting,
        notifier: any UserNotifying,
        runtimeStore: ClipboardTranslationRuntimeStore,
        translationEngine: TranslationEngine,
        coordinator: ClipboardTranslationCoordinator
    ) {
        self.settingsStore = settingsStore
        self.credentialsStore = credentialsStore
        self.cacheRepository = cacheRepository
        self.statisticsRepository = statisticsRepository
        self.promptResolver = promptResolver
        self.executor = executor
        self.clipboardMonitor = clipboardMonitor
        self.clipboardWriter = clipboardWriter
        self.notifier = notifier
        self.runtimeStore = runtimeStore
        self.translationEngine = translationEngine
        self.coordinator = coordinator
    }

    public static func live() -> AppContainer {
        do {
            let defaults: UserDefaults = .standard

            let settingsStore = UserDefaultsSettingsStore(defaults: defaults)
            let credentialsStore: any CredentialsStore = KeychainCredentialsStore(service: "com.example.Lingobar")

            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("Lingobar", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = try AppDatabase(path: directory.appendingPathComponent("lingobar.sqlite").path)

            let cacheRepository = SQLiteTranslationCacheRepository(database: database)
            let statisticsRepository = SQLiteStatisticsRepository(database: database)
            let promptResolver = DefaultTranslationPromptResolver()
            let executor = HTTPTranslationExecutor(
                promptResolver: promptResolver,
                credentialsStore: credentialsStore
            )

            let tracker = ClipboardWriteTracker()
            let clipboardMonitor = PasteboardMonitor(
                tracker: tracker,
                pollingIntervalProvider: {
                    let settings = try? await settingsStore.load()
                    return settings?.pollingIntervalMs ?? 500
                }
            )
            let clipboardWriter = PasteboardWriter(tracker: tracker)
            let notifier: any UserNotifying = NoOpNotifier()
            let runtimeStore = ClipboardTranslationRuntimeStore()

            let translationEngine = TranslationEngine(
                executor: executor,
                promptResolver: promptResolver,
                cacheRepository: cacheRepository,
                statisticsRepository: statisticsRepository,
                requestQueueConfig: .init(),
                batchQueueConfig: .init()
            )
            let coordinator = ClipboardTranslationCoordinator(
                settingsStore: settingsStore,
                translationEngine: translationEngine,
                clipboardMonitor: clipboardMonitor,
                clipboardWriter: clipboardWriter,
                notifier: notifier,
                statisticsRepository: statisticsRepository,
                runtimeStore: runtimeStore
            )

            return AppContainer(
                settingsStore: settingsStore,
                credentialsStore: credentialsStore,
                cacheRepository: cacheRepository,
                statisticsRepository: statisticsRepository,
                promptResolver: promptResolver,
                executor: executor,
                clipboardMonitor: clipboardMonitor,
                clipboardWriter: clipboardWriter,
                notifier: notifier,
                runtimeStore: runtimeStore,
                translationEngine: translationEngine,
                coordinator: coordinator
            )
        } catch {
            fatalError("Failed to bootstrap AppContainer: \(error)")
        }
    }
}
