import CryptoKit
import Foundation
import LingobarDomain

public enum TranslationHashBuilder {
    public static let batchSeparator = "\n\n<<<LINGOBAR_BATCH_SEPARATOR>>>\n\n"

    public static func prepareTranslationText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+\n", with: "\n", options: .regularExpression)
    }

    public static func buildHashComponents(
        text: String,
        providerConfig: ProviderConfig,
        language: TranslationLanguageConfig,
        enableAIContentAware: Bool,
        articleContext: ArticleContext?,
        prompt: TranslationPrompt?
    ) -> [String] {
        var components = [
            prepareTranslationText(text),
            stableJSON(providerConfig),
            language.sourceCode,
            language.targetCode,
        ]

        if providerConfig.isLLMProvider, let prompt {
            components.append(prompt.systemPrompt)
            components.append(prompt.prompt)
            components.append(enableAIContentAware ? "enableAIContentAware=true" : "enableAIContentAware=false")
            if enableAIContentAware, let articleContext {
                if let title = articleContext.title {
                    components.append("title:\(title)")
                }
                if let textContent = articleContext.textContent {
                    components.append("content:\(String(textContent.prefix(1_000)))")
                }
            }
        }

        return components
    }

    public static func buildHash(_ components: [String]) -> String {
        sha256(components.joined(separator: "\u{001F}"))
    }

    public static func parseBatchResult(_ result: String) -> [String] {
        result
            .components(separatedBy: batchSeparator)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func stableJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        if #available(macOS 13.0, *) {
            encoder.outputFormatting = [.sortedKeys]
        } else {
            encoder.outputFormatting = []
        }
        let data = (try? encoder.encode(value)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
