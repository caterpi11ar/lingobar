import XCTest
@testable import LingobarDomain

final class LingobarDomainTests: XCTestCase {
    func testProviderCategoryAndAPIKeyRules() {
        XCTAssertEqual(ProviderConfig.defaults.count, ProviderID.allCases.count)

        let googleTranslate = ProviderConfig(id: "g", name: "Google", provider: .googleTranslate)
        XCTAssertEqual(googleTranslate.category, .nonAPI)
        XCTAssertFalse(googleTranslate.requiresAPIKey)

        let deepL = ProviderConfig(id: "d", name: "DeepL", provider: .deepl)
        XCTAssertEqual(deepL.category, .pureAPI)
        XCTAssertTrue(deepL.requiresAPIKey)

        let openAI = ProviderConfig(id: "o", name: "OpenAI", provider: .openAI)
        XCTAssertEqual(openAI.category, .llm)
        XCTAssertTrue(openAI.requiresAPIKey)

        let ollama = ProviderConfig(id: "l", name: "Ollama", provider: .ollama)
        XCTAssertEqual(ollama.category, .llm)
        XCTAssertFalse(ollama.requiresAPIKey)
    }

    func testLLMProvidersHaveNonEmptyPresetModelsContainingDefault() {
        let llmProviders = ProviderID.allCases.filter { provider in
            let config = ProviderConfig(id: provider.rawValue, name: provider.displayName, provider: provider)
            return config.isLLMProvider
        }

        XCTAssertFalse(llmProviders.isEmpty)

        for provider in llmProviders {
            let presets = provider.presetModels
            XCTAssertFalse(presets.isEmpty, "\(provider.displayName) should have preset models")

            if let defaultModel = provider.defaultModelIdentifier {
                XCTAssertTrue(
                    presets.contains(defaultModel),
                    "\(provider.displayName) presetModels should contain defaultModelIdentifier '\(defaultModel)'"
                )
            }
        }
    }

    func testNonLLMProvidersHaveEmptyPresetModels() {
        let nonLLMProviders: [ProviderID] = [.googleTranslate, .microsoftTranslate, .deeplx, .deepl]
        for provider in nonLLMProviders {
            XCTAssertTrue(provider.presetModels.isEmpty, "\(provider.displayName) should have no preset models")
        }
    }

    func testProviderModelConfigResolvesCustomModel() {
        let preset = ProviderModelConfig(model: "gpt-4o-mini")
        XCTAssertEqual(preset.resolvedModelIdentifier, "gpt-4o-mini")

        let custom = ProviderModelConfig(model: "gpt-4o-mini", isCustomModel: true, customModel: "ft:gpt-4o:my-org::abc")
        XCTAssertEqual(custom.resolvedModelIdentifier, "ft:gpt-4o:my-org::abc")

        let customEmpty = ProviderModelConfig(model: "gpt-4o-mini", isCustomModel: true, customModel: "")
        XCTAssertEqual(customEmpty.resolvedModelIdentifier, "gpt-4o-mini")
    }

    func testFeatureProviderAssignmentResolvesClipboardProvider() {
        var settings = AppSettings.default
        settings.featureProviders = FeatureProviderAssignments(clipboardTranslate: ProviderID.openAI.rawValue)

        let provider = settings.providerConfig(for: .clipboardTranslate)
        XCTAssertEqual(provider?.provider, .openAI)
        XCTAssertEqual(provider?.id, ProviderID.openAI.rawValue)
    }
}
