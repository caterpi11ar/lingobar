import AppKit
import Foundation
import LingobarApplication
import LingobarDomain

public actor ClipboardWriteTracker {
    private var selfWrittenChangeCounts: Set<Int> = []

    func mark(changeCount: Int) {
        selfWrittenChangeCounts.insert(changeCount)
    }

    func consume(changeCount: Int) -> Bool {
        selfWrittenChangeCounts.remove(changeCount) != nil
    }
}

public final class PasteboardMonitor: ClipboardMonitoring, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let tracker: ClipboardWriteTracker
    private let pollingIntervalProvider: @Sendable () async -> UInt64
    private let stream: AsyncStream<ClipboardSnapshot>
    private let continuation: AsyncStream<ClipboardSnapshot>.Continuation
    private var task: Task<Void, Never>?

    public var snapshots: AsyncStream<ClipboardSnapshot> { stream }

    init(
        pasteboard: NSPasteboard = .general,
        tracker: ClipboardWriteTracker,
        pollingIntervalProvider: @escaping @Sendable () async -> UInt64
    ) {
        self.pasteboard = pasteboard
        self.tracker = tracker
        self.pollingIntervalProvider = pollingIntervalProvider

        var continuation: AsyncStream<ClipboardSnapshot>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() async {
        guard task == nil else { return }
        let pasteboard = self.pasteboard
        let tracker = self.tracker
        let continuation = self.continuation
        let pollingIntervalProvider = self.pollingIntervalProvider

        task = Task {
            var lastSeenChangeCount = pasteboard.changeCount
            while !Task.isCancelled {
                let currentChangeCount = pasteboard.changeCount
                if currentChangeCount != lastSeenChangeCount {
                    lastSeenChangeCount = currentChangeCount
                    let string = pasteboard.string(forType: .string)
                    let origin: ClipboardChangeOrigin = await tracker.consume(changeCount: currentChangeCount) ? .selfWritten : .external
                    continuation.yield(
                        ClipboardSnapshot(
                            changeCount: currentChangeCount,
                            string: string,
                            origin: origin
                        )
                    )
                }

                let delay = max(50, await pollingIntervalProvider())
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
    }
}

public final class PasteboardWriter: ClipboardWriting, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let tracker: ClipboardWriteTracker

    init(
        pasteboard: NSPasteboard = .general,
        tracker: ClipboardWriteTracker
    ) {
        self.pasteboard = pasteboard
        self.tracker = tracker
    }

    public func write(_ string: String) async throws {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        await tracker.mark(changeCount: pasteboard.changeCount)
    }
}
