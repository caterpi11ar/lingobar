import Foundation
import SwiftUI
import LingobarApplication
import LingobarDomain
import LingobarInfrastructure

@MainActor
final class LingobarAppModel: ObservableObject {
    let container: AppContainer

    @Published var lastTranslationPreview: String = "准备就绪"
    @Published var translationRuntimeState: ClipboardTranslationRuntimeState = .idle()
    @Published var settings: AppSettings = .default
    @Published var selectedStatsRange: StatsRange = .day
    @Published var statsSummary: StatsSummary = .init()
    @Published var providerAPIKey: String = ""
    private var runtimeUpdatesTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var lastPersistedSettings: AppSettings?
    private var lastPersistedProviderAPIKey: String = ""

    init(container: AppContainer) {
        self.container = container
    }

    static func bootstrap() -> LingobarAppModel {
        let model = LingobarAppModel(container: .live())
        Task {
            await model.initialize()
        }
        return model
    }

    func initialize() async {
        bindRuntimeState()
        translationRuntimeState = await container.runtimeStore.currentState()
        await startCoordinator()
        await reload()
    }

    func reload() async {
        do {
            let loadedSettings = try await container.settingsStore.load()
            settings = loadedSettings
            if let provider = loadedSettings.providerConfig(for: .clipboardTranslate) {
                providerAPIKey = try await container.credentialsStore.apiKey(for: provider.id) ?? provider.apiKey ?? ""
                lastTranslationPreview = "当前翻译服务：\(provider.name)"
            } else {
                providerAPIKey = ""
                lastTranslationPreview = "尚未配置翻译服务"
            }
            lastPersistedSettings = loadedSettings
            lastPersistedProviderAPIKey = providerAPIKey
            await applyRuntimeSettings(from: loadedSettings)
            await refreshStats()
        } catch {
            lastTranslationPreview = "加载设置失败：\(error.localizedDescription)"
        }
    }

    func saveSettings() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        await persistCurrentSettings(userInitiated: true)
    }

    func scheduleAutosave() {
        guard hasPendingSettingsChanges else { return }
        autosaveTask?.cancel()
        let settingsSnapshot = settings
        let providerAPIKeySnapshot = providerAPIKey
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.persistCurrentSettings(
                userInitiated: false,
                settingsSnapshot: settingsSnapshot,
                providerAPIKeySnapshot: providerAPIKeySnapshot
            )
        }
    }

    func refreshStats() async {
        let now = Date()
        let start: Date
        switch selectedStatsRange {
        case .day:
            start = now.addingTimeInterval(-24 * 60 * 60)
        case .week:
            start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month:
            start = now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .year:
            start = now.addingTimeInterval(-365 * 24 * 60 * 60)
        }

        do {
            let records = try await container.statisticsRepository.translations(from: start, to: now)
            statsSummary = StatisticsCalculator.summary(from: records)
        } catch {
            statsSummary = .init()
            lastTranslationPreview = "统计加载失败：\(error.localizedDescription)"
        }
    }

    func currentProvider() -> ProviderConfig? {
        settings.providerConfig(for: .clipboardTranslate)
    }

    var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var menuBarSymbolName: String {
        switch translationRuntimeState.phase {
        case .idle:
            return "globe"
        case .debouncing:
            return "timer"
        case .translating:
            return "arrow.triangle.2.circlepath"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var menuBarTitle: String {
        menuBarCompactText
    }

    var menuBarCompactText: String {
        switch translationRuntimeState.phase {
        case .idle:
            return "Lingobar"
        case .debouncing:
            return "等待中"
        case .translating:
            return "翻译中"
        case .succeeded:
            if let translated = menuBarTranslatedPreview, !translated.isEmpty {
                return compactMenuBarPreview(translated)
            }
            return "已完成"
        case .failed:
            return "失败"
        }
    }

    var menuBarTooltip: String {
        switch translationRuntimeState.phase {
        case .succeeded:
            if let translated = menuBarTranslatedPreview, !translated.isEmpty {
                return translated
            }
        case .translating, .debouncing:
            if let source = menuBarSourcePreview, !source.isEmpty {
                return source
            }
        case .idle, .failed:
            break
        }
        return translationRuntimeState.message
    }

    var menuBarSourcePreview: String? {
        previewText(translationRuntimeState.sourcePreview)
    }

    var menuBarTranslatedPreview: String? {
        previewText(translationRuntimeState.translatedPreview)
    }

    private func startCoordinator() async {
        await container.coordinator.start()
    }

    private var hasPendingSettingsChanges: Bool {
        settings != lastPersistedSettings || providerAPIKey != lastPersistedProviderAPIKey
    }

    private func persistCurrentSettings(
        userInitiated: Bool,
        settingsSnapshot: AppSettings? = nil,
        providerAPIKeySnapshot: String? = nil
    ) async {
        let settingsToSave = settingsSnapshot ?? settings
        let apiKeyToSave = providerAPIKeySnapshot ?? providerAPIKey

        do {
            try await container.settingsStore.save(settingsToSave)
            if let provider = settingsToSave.providerConfig(for: .clipboardTranslate) {
                try await container.credentialsStore.saveAPIKey(apiKeyToSave, for: provider.id)
            }
            lastPersistedSettings = settingsToSave
            lastPersistedProviderAPIKey = apiKeyToSave
            await applyRuntimeSettings(from: settingsToSave)
            await refreshStats()

            if userInitiated {
                if let provider = settingsToSave.providerConfig(for: .clipboardTranslate) {
                    lastTranslationPreview = "已保存 \(provider.name) 设置"
                } else {
                    lastTranslationPreview = "设置已保存"
                }
            }
        } catch {
            lastTranslationPreview = "保存失败：\(error.localizedDescription)"
        }
    }

    private func applyRuntimeSettings(from settings: AppSettings) async {
        await container.translationEngine.setQueueConfig(
            request: .init(
                rate: settings.translate.requestQueueConfig.rate,
                capacity: settings.translate.requestQueueConfig.capacity,
                timeoutMs: settings.translate.requestQueueConfig.timeoutMs,
                maxRetries: settings.translate.requestQueueConfig.maxRetries,
                baseRetryDelayMs: settings.translate.requestQueueConfig.baseRetryDelayMs
            )
        )
        await container.translationEngine.setBatchConfig(
            batch: .init(
                maxCharactersPerBatch: settings.translate.batchQueueConfig.maxCharactersPerBatch,
                maxItemsPerBatch: settings.translate.batchQueueConfig.maxItemsPerBatch
            )
        )
    }

    private func bindRuntimeState() {
        guard runtimeUpdatesTask == nil else { return }
        let updates = container.runtimeStore.updates
        runtimeUpdatesTask = Task { [weak self] in
            for await state in updates {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.translationRuntimeState = state
                }
            }
        }
    }

    private func previewText(_ text: String?) -> String? {
        guard let text else { return nil }
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactMenuBarPreview(_ text: String) -> String {
        let normalized = previewText(text) ?? text
        guard !normalized.isEmpty else { return "已完成" }

        let maxDisplayUnits = 18
        var usedUnits = 0
        var output = ""

        for character in normalized {
            let unitCost = character.unicodeScalars.allSatisfy(\.isASCII) ? 1 : 2
            if usedUnits + unitCost > maxDisplayUnits {
                return output + "…"
            }
            output.append(character)
            usedUnits += unitCost
        }

        return output
    }
}
