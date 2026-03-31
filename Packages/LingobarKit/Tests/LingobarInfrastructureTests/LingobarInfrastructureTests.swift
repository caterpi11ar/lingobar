import Foundation
import XCTest
@testable import LingobarDomain
@testable import LingobarInfrastructure
import LingobarApplication

private actor MockHTTPClient: HTTPClient {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private var handlers: [Handler] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !handlers.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return try handlers.removeFirst()(request)
    }
}

private struct StaticPromptResolver: TranslationPromptResolving {
    let prompt: TranslationPrompt

    func resolve(targetLanguageName: String, input: String, options: TranslationPromptOptions) async throws -> TranslationPrompt {
        prompt
    }
}

private func response(status: Int = 200, url: URL, json: Any) throws -> (Data, HTTPURLResponse) {
    let data = try JSONSerialization.data(withJSONObject: json)
    return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

final class LingobarInfrastructureTests: XCTestCase {
    func testGoogleTranslateParsesResponse() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            XCTAssertEqual(request.url?.host, "translate.googleapis.com")
            return try response(url: request.url!, json: [[["你好", "hello", NSNull(), NSNull(), 1]], NSNull(), "en"])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )

        let value = try await executor.execute(
            request: TranslationRequest(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: "google-translate", name: "Google", provider: .googleTranslate),
                scheduleAt: .now,
                hash: "1"
            )
        )

        XCTAssertEqual(value, "你好")
    }

    func testMicrosoftTranslateRefreshesTokenAndTranslates() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            let data = Data("token-123".utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await client.enqueue { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), "token-123")
            return try response(url: request.url!, json: [["translations": [["text": "你好"]]]])
        }

        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: TranslationRequest(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: "microsoft-translate", name: "Microsoft", provider: .microsoftTranslate),
                scheduleAt: .now,
                hash: "2"
            )
        )
        XCTAssertEqual(value, "你好")
    }

    func testDeepLUsesFreeEndpointAndParsesResponse() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api-free.deepl.com/v2/translate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key key:fx")
            return try response(url: request.url!, json: ["translations": [["text": "你好"]]])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: TranslationRequest(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: "deepl", name: "DeepL", provider: .deepl, apiKey: "key:fx"),
                scheduleAt: .now,
                hash: "3"
            )
        )
        XCTAssertEqual(value, "你好")
    }

    func testDeepLXBuildsReadFrogStyleURL() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deeplx.org/abc/translate")
            return try response(url: request.url!, json: ["data": "你好"])
        }
        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "", prompt: ""))
        )
        let value = try await executor.execute(
            request: TranslationRequest(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: .init(id: "deeplx", name: "DeepLX", provider: .deeplx, apiKey: "abc", baseURL: "https://api.deeplx.org"),
                scheduleAt: .now,
                hash: "4"
            )
        )
        XCTAssertEqual(value, "你好")
    }

    func testOpenAICompatibleIncludesPromptAndProviderOptions() async throws {
        let client = MockHTTPClient()
        await client.enqueue { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gpt-4o-mini")
            XCTAssertEqual(payload["top_p"] as? Double, 0.8)
            let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
            XCTAssertEqual(messages[0]["content"], "system")
            XCTAssertEqual(messages[1]["content"], "user")
            return try response(url: request.url!, json: ["choices": [["message": ["content": "你好"]]]])
        }

        let executor = HTTPTranslationExecutor(
            httpClient: client,
            promptResolver: StaticPromptResolver(prompt: .init(systemPrompt: "system", prompt: "user"))
        )
        let provider = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            provider: .openAI,
            apiKey: "test-key",
            baseURL: "https://api.openai.com/v1",
            providerOptions: ["top_p": .number(0.8)],
            model: .init(model: "gpt-4o-mini")
        )

        let value = try await executor.execute(
            request: TranslationRequest(
                text: "hello",
                language: .init(sourceCode: "auto", targetCode: "zh"),
                providerConfig: provider,
                scheduleAt: .now,
                hash: "5"
            )
        )
        XCTAssertEqual(value, "你好")
    }

    func testSQLiteRepositoriesRoundTripAndDateFilter() async throws {
        let database = try AppDatabase()
        let cache = SQLiteTranslationCacheRepository(database: database)
        let stats = SQLiteStatisticsRepository(database: database)

        try await cache.save(.init(hash: "abc", translation: "你好"))
        let cached = try await cache.translation(for: "abc")
        XCTAssertEqual(cached?.translation, "你好")

        let now = Date()
        let old = now.addingTimeInterval(-10 * 24 * 60 * 60)
        try await stats.recordTranslation(.init(createdAt: old, sourceTextLength: 5, sourceLanguage: "en", targetLanguage: "zh", providerId: "g", latencyMs: 50, success: true, writeBackApplied: false))
        try await stats.recordTranslation(.init(createdAt: now, sourceTextLength: 10, sourceLanguage: nil, targetLanguage: "zh", providerId: "o", latencyMs: 100, success: true, writeBackApplied: true))

        let recent = try await stats.translations(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60))
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.providerId, "o")
    }
}
