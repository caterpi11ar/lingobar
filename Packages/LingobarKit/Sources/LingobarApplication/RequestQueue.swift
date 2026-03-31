import Foundation
import LingobarDomain

public enum RequestQueueError: Error, Equatable, Sendable {
    case timedOut
}

public struct RequestQueueOptionsPatch: Sendable {
    public var rate: Double?
    public var capacity: Double?
    public var timeoutMs: UInt64?
    public var maxRetries: Int?
    public var baseRetryDelayMs: UInt64?

    public init(
        rate: Double? = nil,
        capacity: Double? = nil,
        timeoutMs: UInt64? = nil,
        maxRetries: Int? = nil,
        baseRetryDelayMs: UInt64? = nil
    ) {
        self.rate = rate
        self.capacity = capacity
        self.timeoutMs = timeoutMs
        self.maxRetries = maxRetries
        self.baseRetryDelayMs = baseRetryDelayMs
    }
}

final class PendingRequestRecord<Output: Sendable>: @unchecked Sendable {
    let id = UUID()
    let hash: String
    let thunk: @Sendable () async throws -> Output
    let createdAt: Date
    var scheduleAt: Date
    var retryCount: Int
    let promise = SharedPromise<Output>()

    init(hash: String, scheduleAt: Date, thunk: @escaping @Sendable () async throws -> Output) {
        self.hash = hash
        self.scheduleAt = scheduleAt
        self.thunk = thunk
        self.createdAt = .now
        self.retryCount = 0
    }
}

public actor RequestQueue<Output: Sendable> {
    private var options: RequestQueueConfig
    private var waitingByHash: [String: PendingRequestRecord<Output>] = [:]
    private var executingByHash: [String: PendingRequestRecord<Output>] = [:]
    private var waitingOrder: [PendingRequestRecord<Output>] = []
    private var processingLoop: Task<Void, Never>?
    private var bucketTokens: Double
    private var lastRefillAt: Date

    public init(options: RequestQueueConfig) {
        self.options = options
        self.bucketTokens = options.capacity
        self.lastRefillAt = .now
    }

    public func enqueue(
        _ thunk: @escaping @Sendable () async throws -> Output,
        scheduleAt: Date,
        hash: String
    ) async throws -> Output {
        if let duplicate = waitingByHash[hash] ?? executingByHash[hash] {
            return try await duplicate.promise.wait()
        }

        let record = PendingRequestRecord(hash: hash, scheduleAt: scheduleAt, thunk: thunk)
        waitingByHash[hash] = record
        waitingOrder.append(record)
        waitingOrder.sort { $0.scheduleAt < $1.scheduleAt }
        ensureProcessingLoop()
        return try await record.promise.wait()
    }

    public func setOptions(_ patch: RequestQueueOptionsPatch) {
        if let rate = patch.rate { options.rate = rate }
        if let capacity = patch.capacity {
            options.capacity = capacity
            bucketTokens = min(bucketTokens, capacity)
        }
        if let timeoutMs = patch.timeoutMs { options.timeoutMs = timeoutMs }
        if let maxRetries = patch.maxRetries { options.maxRetries = maxRetries }
        if let baseRetryDelayMs = patch.baseRetryDelayMs { options.baseRetryDelayMs = baseRetryDelayMs }
        ensureProcessingLoop()
    }

    private func ensureProcessingLoop() {
        guard processingLoop == nil else { return }
        processingLoop = Task { await processLoop() }
    }

    private func processLoop() async {
        while !Task.isCancelled {
            refillTokens()

            var scheduledWork = false
            while bucketTokens >= 1, let nextTask = nextReadyTask() {
                waitingByHash.removeValue(forKey: nextTask.hash)
                waitingOrder.removeAll(where: { $0.id == nextTask.id })
                executingByHash[nextTask.hash] = nextTask
                bucketTokens -= 1
                scheduledWork = true
                Task { await self.execute(nextTask) }
            }

            if waitingOrder.isEmpty {
                processingLoop = nil
                return
            }

            if scheduledWork {
                continue
            }

            let delayMs = max(1, nextDelayMs())
            do {
                try await Task.sleep(for: .milliseconds(delayMs))
            } catch {
                processingLoop = nil
                return
            }
        }

        processingLoop = nil
    }

    private func nextReadyTask() -> PendingRequestRecord<Output>? {
        waitingOrder.first(where: { $0.scheduleAt <= .now })
    }

    private func nextDelayMs() -> Int {
        guard let nextTask = waitingOrder.min(by: { $0.scheduleAt < $1.scheduleAt }) else {
            return 50
        }

        let now = Date()
        let scheduledDelay = max(0, Int(nextTask.scheduleAt.timeIntervalSince(now) * 1000))
        let tokenDelay: Int
        if bucketTokens >= 1 || options.rate <= 0 {
            tokenDelay = 0
        } else {
            tokenDelay = Int(ceil(((1 - bucketTokens) / options.rate) * 1000))
        }
        return max(scheduledDelay, tokenDelay)
    }

    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillAt)
        let refillAmount = elapsed * options.rate
        bucketTokens = min(options.capacity, bucketTokens + refillAmount)
        lastRefillAt = now
    }

    private func execute(_ record: PendingRequestRecord<Output>) async {
        defer {
            executingByHash.removeValue(forKey: record.hash)
            ensureProcessingLoop()
        }

        do {
            let result = try await withTimeout(milliseconds: options.timeoutMs, operation: record.thunk)
            await record.promise.resolve(.success(result))
        } catch {
            if record.retryCount < options.maxRetries {
                record.retryCount += 1
                let backoff = backoffDelayMs(for: record.retryCount)
                record.scheduleAt = Date().addingTimeInterval(Double(backoff) / 1000)
                waitingByHash[record.hash] = record
                waitingOrder.append(record)
                waitingOrder.sort { $0.scheduleAt < $1.scheduleAt }
            } else {
                await record.promise.resolve(.failure(error))
            }
        }
    }

    private func backoffDelayMs(for retryCount: Int) -> UInt64 {
        let base = Double(options.baseRetryDelayMs)
        let delay = base * pow(2, Double(max(retryCount - 1, 0)))
        let jitter = Double.random(in: 0...(delay * 0.1))
        return UInt64(delay + jitter)
    }

    private func withTimeout<T: Sendable>(
        milliseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(milliseconds))
                throw RequestQueueError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
