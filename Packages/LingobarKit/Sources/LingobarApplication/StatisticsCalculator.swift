import Foundation
import LingobarDomain

public enum StatisticsCalculator {
    public static func summary(from records: [TranslationRecord]) -> StatsSummary {
        guard !records.isEmpty else { return StatsSummary() }

        let totalTranslations = records.count
        let totalCharacters = records.reduce(0) { $0 + $1.sourceTextLength }
        let averageLatencyMs = Double(records.reduce(0) { $0 + $1.latencyMs }) / Double(totalTranslations)
        let successCount = records.filter(\.success).count
        let successRate = Double(successCount) / Double(totalTranslations)

        let providerBreakdown = records.reduce(into: [String: Int]()) { partialResult, record in
            partialResult[record.providerId, default: 0] += 1
        }

        let languagePairBreakdown = records.reduce(into: [String: Int]()) { partialResult, record in
            let pair = "\(record.sourceLanguage ?? "auto")->\(record.targetLanguage)"
            partialResult[pair, default: 0] += 1
        }

        return StatsSummary(
            totalTranslations: totalTranslations,
            totalCharacters: totalCharacters,
            averageLatencyMs: averageLatencyMs,
            successRate: successRate,
            providerBreakdown: providerBreakdown,
            languagePairBreakdown: languagePairBreakdown
        )
    }
}
