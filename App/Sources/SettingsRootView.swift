import SwiftUI
import LingobarDomain

struct SettingsRootView: View {
    @ObservedObject var model: LingobarAppModel

    var body: some View {
        NavigationStack {
            List {
                Section("通用") {
                    Picker("主题", selection: $model.settings.theme) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(themeLabel(for: mode)).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("settings.theme")

                    Picker("监听频率", selection: $model.settings.pollingIntervalMs) {
                        Text("300 ms").tag(UInt64(300))
                        Text("500 ms").tag(UInt64(500))
                        Text("1000 ms").tag(UInt64(1000))
                    }
                    .accessibilityIdentifier("settings.polling")

                    Picker("防抖延迟", selection: $model.settings.translate.batchQueueConfig.batchDelayMs) {
                        Text("100 ms").tag(UInt64(100))
                        Text("150 ms").tag(UInt64(150))
                        Text("350 ms").tag(UInt64(350))
                        Text("600 ms").tag(UInt64(600))
                    }
                    .accessibilityIdentifier("settings.debounce")

                    Toggle("自动翻译", isOn: $model.settings.autoTranslateEnabled)
                        .accessibilityIdentifier("settings.autoTranslate")
                    Toggle("自动回写剪贴板", isOn: $model.settings.autoWriteBackEnabled)
                        .accessibilityIdentifier("settings.autoWriteBack")
                    Toggle("记录统计", isOn: $model.settings.statsEnabled)
                        .accessibilityIdentifier("settings.statsEnabled")
                }

                Section("翻译服务") {
                    Picker("服务商", selection: $model.settings.featureProviders.clipboardTranslate) {
                        ForEach(model.settings.providersConfig.filter(\.enabled), id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .accessibilityIdentifier("settings.provider")
                    .onChange(of: model.settings.featureProviders.clipboardTranslate) { _, _ in
                        model.onProviderChanged()
                    }

                    if let provider = model.currentProvider(), !provider.isNonAPIProvider {
                        TextField(
                            "Base URL",
                            text: Binding(
                                get: { model.providerBaseURL },
                                set: { model.providerBaseURL = $0 }
                            ),
                            prompt: Text(provider.provider.defaultBaseURL ?? "https://")
                        )
                        .accessibilityIdentifier("settings.baseURL")
                    }

                    if model.currentProvider()?.requiresAPIKey == true {
                        SecureField("API Key", text: $model.providerAPIKey)
                            .accessibilityIdentifier("settings.apiKey")
                    }

                    if let provider = model.currentProvider(), provider.isLLMProvider {
                        let presets = provider.provider.presetModels

                        Picker("模型", selection: Binding(
                            get: { model.providerSelectedModel },
                            set: { model.providerSelectedModel = $0 }
                        )) {
                            ForEach(presets, id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                            Divider()
                            Text("自定义").tag(LingobarAppModel.customModelSentinel)
                        }
                        .accessibilityIdentifier("settings.model")

                        if model.providerSelectedModel == LingobarAppModel.customModelSentinel {
                            TextField(
                                "自定义模型 ID",
                                text: Binding(
                                    get: { model.providerCustomModel },
                                    set: { model.providerCustomModel = $0 }
                                )
                            )
                            .accessibilityIdentifier("settings.customModel")
                        }
                    }
                }

                Section("统计") {
                    Picker("时间范围", selection: $model.selectedStatsRange) {
                        ForEach(StatsRange.allCases, id: \.self) { range in
                            Text(statsRangeLabel(for: range)).tag(range)
                        }
                    }
                    .accessibilityIdentifier("stats.range")
                    .onChange(of: model.selectedStatsRange) { _, _ in
                        Task { await model.refreshStats() }
                    }

                    HStack {
                        Text("翻译次数")
                        Spacer()
                        Text("\(model.statsSummary.totalTranslations)")
                            .accessibilityIdentifier("stats.totalTranslations")
                    }
                    HStack {
                        Text("字符数")
                        Spacer()
                        Text("\(model.statsSummary.totalCharacters)")
                            .accessibilityIdentifier("stats.totalCharacters")
                    }
                    HStack {
                        Text("成功率")
                        Spacer()
                        Text(String(format: "%.0f%%", model.statsSummary.successRate * 100))
                            .accessibilityIdentifier("stats.successRate")
                    }
                }

                Section("状态") {
                    Text(model.lastTranslationPreview)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.status")
                }

                Section {
                    Button("保存") {
                        Task { await model.saveSettings() }
                    }
                    .accessibilityIdentifier("settings.save")

                    Button("重新加载") {
                        Task { await model.reload() }
                    }
                    .accessibilityIdentifier("settings.reload")
                }
            }
            .navigationTitle("Lingobar 设置")
        }
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(model.preferredColorScheme)
        .onChange(of: model.settings) { _, _ in
            model.scheduleAutosave()
        }
        .onChange(of: model.providerAPIKey) { _, _ in
            model.scheduleAutosave()
        }
    }

    private func themeLabel(for mode: ThemeMode) -> String {
        switch mode {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    private func statsRangeLabel(for range: StatsRange) -> String {
        switch range {
        case .day:
            return "今日"
        case .week:
            return "近 7 天"
        case .month:
            return "近 30 天"
        case .year:
            return "近 1 年"
        }
    }
}
