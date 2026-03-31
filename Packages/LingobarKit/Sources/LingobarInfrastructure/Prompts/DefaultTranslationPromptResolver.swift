import Foundation
import LingobarApplication
import LingobarDomain

public struct DefaultTranslationPromptResolver: TranslationPromptResolving {
    public init() {}

    public func resolve(targetLanguageName: String, input: String, options: TranslationPromptOptions) async throws -> TranslationPrompt {
        var systemPrompt = "You are a precise translation engine. Translate the user's text into \(targetLanguageName). Return only the translation."
        if options.isBatch {
            systemPrompt += " The input may contain multiple segments separated by <<<LINGOBAR_BATCH_SEPARATOR>>>. Preserve the same separator count and order in the output."
        }

        var prompt = input
        if let content = options.content {
            var contextLines: [String] = []
            if let title = content.title, !title.isEmpty {
                contextLines.append("Title: \(title)")
            }
            if let summary = content.summary, !summary.isEmpty {
                contextLines.append("Summary: \(summary)")
            }
            if let textContent = content.textContent, !textContent.isEmpty {
                contextLines.append("Context: \(String(textContent.prefix(1000)))")
            }
            if !contextLines.isEmpty {
                prompt = contextLines.joined(separator: "\n") + "\n\nText:\n" + input
            }
        }

        return TranslationPrompt(systemPrompt: systemPrompt, prompt: prompt)
    }
}
