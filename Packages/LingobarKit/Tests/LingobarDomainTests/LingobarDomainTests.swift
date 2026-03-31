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

    func testFeatureProviderAssignmentResolvesClipboardProvider() {
        var settings = AppSettings.default
        settings.featureProviders = FeatureProviderAssignments(clipboardTranslate: ProviderID.openAI.rawValue)

        let provider = settings.providerConfig(for: .clipboardTranslate)
        XCTAssertEqual(provider?.provider, .openAI)
        XCTAssertEqual(provider?.id, ProviderID.openAI.rawValue)
    }
}
