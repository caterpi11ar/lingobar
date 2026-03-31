import Foundation
import LingobarDomain

public actor ClipboardTranslationCoordinator {
    private let settingsStore: any SettingsStore
    private let translationEngine: TranslationEngine
    private let clipboardMonitor: any ClipboardMonitoring
    private let clipboardWriter: any ClipboardWriting
    private let notifier: any UserNotifying
    private let statisticsRepository: any StatisticsRepository
    private let runtimeStore: ClipboardTranslationRuntimeStore

    private var workerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var pendingSnapshot: ClipboardSnapshot?
    private var lastProcessedChangeCount: Int?

    public init(
        settingsStore: any SettingsStore,
        translationEngine: TranslationEngine,
        clipboardMonitor: any ClipboardMonitoring,
        clipboardWriter: any ClipboardWriting,
        notifier: any UserNotifying,
        statisticsRepository: any StatisticsRepository,
        runtimeStore: ClipboardTranslationRuntimeStore = ClipboardTranslationRuntimeStore()
    ) {
        self.settingsStore = settingsStore
        self.translationEngine = translationEngine
        self.clipboardMonitor = clipboardMonitor
        self.clipboardWriter = clipboardWriter
        self.notifier = notifier
        self.statisticsRepository = statisticsRepository
        self.runtimeStore = runtimeStore
    }

    public func start() async {
        guard workerTask == nil else { return }
        await clipboardMonitor.start()
        await runtimeStore.publish(.idle())
        let snapshots = clipboardMonitor.snapshots
        workerTask = Task {
            for await snapshot in snapshots {
                await self.handle(snapshot)
            }
        }
    }

    public func stop() async {
        workerTask?.cancel()
        workerTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        processingTask?.cancel()
        processingTask = nil
        pendingSnapshot = nil
        await clipboardMonitor.stop()
    }

    private func handle(_ snapshot: ClipboardSnapshot) async {
        guard snapshot.changeCount != lastProcessedChangeCount else { return }
        lastProcessedChangeCount = snapshot.changeCount
        guard snapshot.origin == .external else { return }
        guard let string = snapshot.string else { return }

        let preparedText = TranslationHashBuilder.prepareTranslationText(string)
        guard !preparedText.isEmpty else { return }

        do {
            let settings = try await settingsStore.load()
            guard settings.autoTranslateEnabled else { return }
            guard let providerConfig = settings.providerConfig(for: .clipboardTranslate) else {
                await runtimeStore.publish(
                    .idle(message: "请先配置翻译服务")
                )
                return
            }

            debounceTask?.cancel()
            pendingSnapshot = ClipboardSnapshot(
                changeCount: snapshot.changeCount,
                string: preparedText,
                origin: .external
            )
            let debounceMs = max(100, settings.translate.batchQueueConfig.batchDelayMs)
            await runtimeStore.publish(
                ClipboardTranslationRuntimeState(
                    phase: .debouncing,
                    message: "等待剪贴板内容稳定",
                    sourcePreview: preparedText,
                    providerName: providerConfig.name
                )
            )

            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(debounceMs))
                guard !Task.isCancelled else { return }
                await self.schedulePendingProcessing()
            }
        } catch {
            await runtimeStore.publish(
                ClipboardTranslationRuntimeState(
                    phase: .failed,
                    message: error.localizedDescription,
                    sourcePreview: preparedText
                )
            )
        }
    }

    private func schedulePendingProcessing() async {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil

        guard processingTask == nil else {
            pendingSnapshot = snapshot
            return
        }

        processingTask = Task {
            await self.process(snapshot)
            await self.finishProcessing()
        }
    }

    private func finishProcessing() async {
        processingTask = nil
        if pendingSnapshot != nil {
            await schedulePendingProcessing()
        }
    }

    private func process(_ snapshot: ClipboardSnapshot) async {
        guard let string = snapshot.string else { return }

        do {
            let settings = try await settingsStore.load()
            guard settings.autoTranslateEnabled else {
                await runtimeStore.publish(.idle(message: "自动翻译已关闭"))
                return
            }

            guard let providerConfig = settings.providerConfig(for: .clipboardTranslate) else {
                await runtimeStore.publish(.idle(message: "请先配置翻译服务"))
                return
            }

            let effectiveLanguage = Self.resolvedLanguageConfig(for: string, fallback: settings.language)

            await runtimeStore.publish(
                ClipboardTranslationRuntimeState(
                    phase: .translating,
                    message: "正在使用 \(providerConfig.name) 翻译",
                    sourcePreview: string,
                    providerName: providerConfig.name
                )
            )

            let startedAt = Date()
            let translatedText = try await translationEngine.translateTextCore(
                text: string,
                language: effectiveLanguage,
                providerConfig: providerConfig,
                enableAIContentAware: settings.translate.enableAIContentAware
            )

            guard !translatedText.isEmpty else {
                await runtimeStore.publish(
                    ClipboardTranslationRuntimeState(
                        phase: .failed,
                        message: "翻译结果为空",
                        sourcePreview: string,
                        providerName: providerConfig.name
                    )
                )
                return
            }

            if settings.autoWriteBackEnabled {
                try await clipboardWriter.write(translatedText)
            }

            await runtimeStore.publish(
                ClipboardTranslationRuntimeState(
                    phase: .succeeded,
                    message: settings.autoWriteBackEnabled ? "翻译完成，已回写到剪贴板" : "翻译完成，已显示在菜单栏",
                    sourcePreview: string,
                    translatedPreview: translatedText,
                    providerName: providerConfig.name,
                    writeBackApplied: settings.autoWriteBackEnabled
                )
            )

            if settings.notificationsEnabled {
                await notifier.notify(
                    title: "翻译完成",
                    body: String(translatedText.prefix(140))
                )
            }

            if settings.statsEnabled {
                let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                try await statisticsRepository.recordTranslation(
                    TranslationRecord(
                        sourceTextLength: string.count,
                        sourceLanguage: effectiveLanguage.sourceCode == "auto" ? nil : effectiveLanguage.sourceCode,
                        targetLanguage: effectiveLanguage.targetCode,
                        providerId: providerConfig.provider.rawValue,
                        latencyMs: latencyMs,
                        success: true,
                        writeBackApplied: settings.autoWriteBackEnabled
                    )
                )
            }
        } catch {
            do {
                let settings = try await settingsStore.load()
                await runtimeStore.publish(
                    ClipboardTranslationRuntimeState(
                        phase: .failed,
                        message: error.localizedDescription,
                        sourcePreview: string,
                        providerName: settings.providerConfig(for: .clipboardTranslate)?.name
                    )
                )
                if settings.notificationsEnabled {
                    await notifier.notify(title: "翻译失败", body: error.localizedDescription)
                }
                if let providerConfig = settings.providerConfig(for: .clipboardTranslate), settings.statsEnabled {
                    let effectiveLanguage = Self.resolvedLanguageConfig(for: string, fallback: settings.language)
                    try await statisticsRepository.recordTranslation(
                        TranslationRecord(
                            sourceTextLength: string.count,
                            sourceLanguage: effectiveLanguage.sourceCode == "auto" ? nil : effectiveLanguage.sourceCode,
                            targetLanguage: effectiveLanguage.targetCode,
                            providerId: providerConfig.provider.rawValue,
                            latencyMs: 0,
                            success: false,
                            writeBackApplied: false
                        )
                    )
                }
            } catch {
                await runtimeStore.publish(
                    ClipboardTranslationRuntimeState(
                        phase: .failed,
                        message: error.localizedDescription,
                        sourcePreview: string
                    )
                )
                // Ignore secondary persistence errors.
            }
        }
    }

    private static func resolvedLanguageConfig(for text: String, fallback: TranslationLanguageConfig) -> TranslationLanguageConfig {
        switch detectPrimaryLanguage(in: text) {
        case .chinese:
            return TranslationLanguageConfig(sourceCode: "zh", targetCode: "en", level: fallback.level)
        case .english:
            return TranslationLanguageConfig(sourceCode: "en", targetCode: "zh", level: fallback.level)
        case .unknown:
            return fallback
        }
    }

    private static func detectPrimaryLanguage(in text: String) -> DetectedLanguage {
        let scalars = text.unicodeScalars
        let hanCount = scalars.filter(Self.isHanScalar).count
        let latinCount = scalars.filter(Self.isEnglishLetterScalar).count

        if hanCount > 0, hanCount >= latinCount {
            return .chinese
        }

        if latinCount > 0 {
            return .english
        }

        return .unknown
    }

    private static func isHanScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2A6DF,
             0x2A700 ... 0x2B73F,
             0x2B740 ... 0x2B81F,
             0x2B820 ... 0x2CEAF,
             0x2CEB0 ... 0x2EBEF,
             0x30000 ... 0x3134F:
            return true
        default:
            return false
        }
    }

    private static func isEnglishLetterScalar(_ scalar: UnicodeScalar) -> Bool {
        (65 ... 90).contains(scalar.value) || (97 ... 122).contains(scalar.value)
    }
}

private enum DetectedLanguage {
    case chinese
    case english
    case unknown
}
