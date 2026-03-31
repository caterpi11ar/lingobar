import Foundation
import LingobarDomain

public enum ClipboardTranslationRuntimePhase: String, Equatable, Sendable {
    case idle
    case debouncing
    case translating
    case succeeded
    case failed

    public var isLoading: Bool {
        switch self {
        case .debouncing, .translating:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }
}

public struct ClipboardTranslationRuntimeState: Equatable, Sendable {
    public var phase: ClipboardTranslationRuntimePhase
    public var message: String
    public var sourcePreview: String?
    public var translatedPreview: String?
    public var providerName: String?
    public var writeBackApplied: Bool

    public init(
        phase: ClipboardTranslationRuntimePhase,
        message: String,
        sourcePreview: String? = nil,
        translatedPreview: String? = nil,
        providerName: String? = nil,
        writeBackApplied: Bool = false
    ) {
        self.phase = phase
        self.message = message
        self.sourcePreview = sourcePreview
        self.translatedPreview = translatedPreview
        self.providerName = providerName
        self.writeBackApplied = writeBackApplied
    }

    public static func idle(message: String = "正在监听剪贴板") -> ClipboardTranslationRuntimeState {
        ClipboardTranslationRuntimeState(
            phase: .idle,
            message: message
        )
    }
}

public actor ClipboardTranslationRuntimeStore {
    private var state: ClipboardTranslationRuntimeState
    private let stream: AsyncStream<ClipboardTranslationRuntimeState>
    private let continuation: AsyncStream<ClipboardTranslationRuntimeState>.Continuation

    public nonisolated var updates: AsyncStream<ClipboardTranslationRuntimeState> {
        stream
    }

    public init(initialState: ClipboardTranslationRuntimeState = .idle()) {
        state = initialState

        var continuation: AsyncStream<ClipboardTranslationRuntimeState>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func currentState() -> ClipboardTranslationRuntimeState {
        state
    }

    public func publish(_ nextState: ClipboardTranslationRuntimeState) {
        state = nextState
        continuation.yield(nextState)
    }
}
