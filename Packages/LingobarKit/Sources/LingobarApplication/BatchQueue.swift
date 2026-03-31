import Foundation
import LingobarDomain

public struct BatchQueueOptions<Input: Sendable, Output: Sendable>: Sendable {
    public var maxCharactersPerBatch: Int
    public var maxItemsPerBatch: Int
    public var batchDelayMs: UInt64
    public var maxRetries: Int
    public var enableFallbackToIndividual: Bool
    public var getBatchKey: @Sendable (Input) -> String
    public var getCharacterCount: @Sendable (Input) -> Int
    public var executeBatch: @Sendable ([Input]) async throws -> [Output]
    public var executeIndividual: (@Sendable (Input) async throws -> Output)?
    public var onError: (@Sendable (Error, BatchExecutionContext) -> Void)?

    public init(
        maxCharactersPerBatch: Int,
        maxItemsPerBatch: Int,
        batchDelayMs: UInt64,
        maxRetries: Int,
        enableFallbackToIndividual: Bool,
        getBatchKey: @escaping @Sendable (Input) -> String,
        getCharacterCount: @escaping @Sendable (Input) -> Int,
        executeBatch: @escaping @Sendable ([Input]) async throws -> [Output],
        executeIndividual: (@Sendable (Input) async throws -> Output)? = nil,
        onError: (@Sendable (Error, BatchExecutionContext) -> Void)? = nil
    ) {
        self.maxCharactersPerBatch = maxCharactersPerBatch
        self.maxItemsPerBatch = maxItemsPerBatch
        self.batchDelayMs = batchDelayMs
        self.maxRetries = maxRetries
        self.enableFallbackToIndividual = enableFallbackToIndividual
        self.getBatchKey = getBatchKey
        self.getCharacterCount = getCharacterCount
        self.executeBatch = executeBatch
        self.executeIndividual = executeIndividual
        self.onError = onError
    }
}

public struct BatchQueueOptionsPatch: Sendable {
    public var maxCharactersPerBatch: Int?
    public var maxItemsPerBatch: Int?

    public init(maxCharactersPerBatch: Int? = nil, maxItemsPerBatch: Int? = nil) {
        self.maxCharactersPerBatch = maxCharactersPerBatch
        self.maxItemsPerBatch = maxItemsPerBatch
    }
}

public struct BatchExecutionContext: Sendable, Equatable {
    public var batchKey: String
    public var retryCount: Int
    public var isFallback: Bool

    public init(batchKey: String, retryCount: Int, isFallback: Bool) {
        self.batchKey = batchKey
        self.retryCount = retryCount
        self.isFallback = isFallback
    }
}

public struct BatchCountMismatchError: Error, Equatable, Sendable {
    public var expected: Int
    public var actual: Int
    public var payloadDescription: String

    public init(expected: Int, actual: Int, payloadDescription: String) {
        self.expected = expected
        self.actual = actual
        self.payloadDescription = payloadDescription
    }
}

final class PendingBatchTask<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    let data: Input
    let promise = SharedPromise<Output>()

    init(data: Input) {
        self.data = data
    }
}

final class PendingBatch<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    let id = UUID()
    let batchKey: String
    let createdAt: Date
    var tasks: [PendingBatchTask<Input, Output>]
    var totalCharacters: Int

    init(batchKey: String, task: PendingBatchTask<Input, Output>, characters: Int) {
        self.batchKey = batchKey
        self.createdAt = .now
        self.tasks = [task]
        self.totalCharacters = characters
    }
}

public actor BatchQueue<Input: Sendable, Output: Sendable> {
    private var options: BatchQueueOptions<Input, Output>
    private var pendingBatches: [String: PendingBatch<Input, Output>] = [:]
    private var processingLoop: Task<Void, Never>?

    public init(options: BatchQueueOptions<Input, Output>) {
        self.options = options
    }

    public func enqueue(_ data: Input) async throws -> Output {
        let task = PendingBatchTask<Input, Output>(data: data)
        let batchKey = options.getBatchKey(data)
        addTask(task, batchKey: batchKey)
        ensureProcessingLoop()
        return try await task.promise.wait()
    }

    public func setOptions(_ patch: BatchQueueOptionsPatch) {
        if let maxCharacters = patch.maxCharactersPerBatch {
            options.maxCharactersPerBatch = maxCharacters
        }
        if let maxItems = patch.maxItemsPerBatch {
            options.maxItemsPerBatch = maxItems
        }
        ensureProcessingLoop()
    }

    private func addTask(_ task: PendingBatchTask<Input, Output>, batchKey: String) {
        let characters = options.getCharacterCount(task.data)
        if let existing = pendingBatches[batchKey] {
            let canFitCharacters = existing.totalCharacters + characters <= options.maxCharactersPerBatch
            let canFitItems = existing.tasks.count + 1 <= options.maxItemsPerBatch
            if canFitCharacters && canFitItems {
                existing.tasks.append(task)
                existing.totalCharacters += characters
                if shouldFlush(existing) {
                    flush(batchKey: batchKey)
                }
            } else {
                flush(batchKey: batchKey)
                pendingBatches[batchKey] = PendingBatch(batchKey: batchKey, task: task, characters: characters)
            }
        } else {
            pendingBatches[batchKey] = PendingBatch(batchKey: batchKey, task: task, characters: characters)
        }
    }

    private func shouldFlush(_ batch: PendingBatch<Input, Output>) -> Bool {
        batch.tasks.count >= options.maxItemsPerBatch || batch.totalCharacters >= options.maxCharactersPerBatch
    }

    private func ensureProcessingLoop() {
        guard processingLoop == nil else { return }
        processingLoop = Task { await processLoop() }
    }

    private func processLoop() async {
        while !Task.isCancelled {
            let now = Date()
            let flushKeys = pendingBatches.values
                .filter { shouldFlush($0) || now.timeIntervalSince($0.createdAt) * 1000 >= Double(options.batchDelayMs) }
                .map(\.batchKey)

            flushKeys.forEach { flush(batchKey: $0) }

            if pendingBatches.isEmpty {
                processingLoop = nil
                return
            }

            let nextDelay = max(1, Int(options.batchDelayMs))
            do {
                try await Task.sleep(for: .milliseconds(nextDelay))
            } catch {
                processingLoop = nil
                return
            }
        }

        processingLoop = nil
    }

    private func flush(batchKey: String) {
        guard let batch = pendingBatches.removeValue(forKey: batchKey) else { return }
        Task { await self.execute(batch: batch, retryCount: 0) }
    }

    private func execute(batch: PendingBatch<Input, Output>, retryCount: Int) async {
        let onError = options.onError
        let enableFallbackToIndividual = options.enableFallbackToIndividual
        let executeIndividual = options.executeIndividual
        let maxRetries = options.maxRetries
        do {
            let results = try await options.executeBatch(batch.tasks.map(\.data))
            if results.count != batch.tasks.count {
                throw BatchCountMismatchError(
                    expected: batch.tasks.count,
                    actual: results.count,
                    payloadDescription: "\(results)"
                )
            }

            for (task, output) in zip(batch.tasks, results) {
                await task.promise.resolve(.success(output))
            }
        } catch {
            onError?(error, BatchExecutionContext(batchKey: batch.batchKey, retryCount: retryCount, isFallback: false))
            if retryCount < maxRetries, error is BatchCountMismatchError {
                let delay = min(UInt64(1_000 * Int(pow(2, Double(retryCount)))), 8_000)
                do {
                    try await Task.sleep(for: .milliseconds(delay))
                } catch {
                    for task in batch.tasks {
                        await task.promise.resolve(.failure(error))
                    }
                    return
                }
                await execute(batch: batch, retryCount: retryCount + 1)
                return
            }

            if enableFallbackToIndividual, let executeIndividual {
                await withTaskGroup(of: Void.self) { group in
                    for task in batch.tasks {
                        group.addTask {
                            do {
                                let output = try await executeIndividual(task.data)
                                await task.promise.resolve(.success(output))
                            } catch {
                                onError?(error, BatchExecutionContext(batchKey: batch.batchKey, retryCount: retryCount, isFallback: true))
                                await task.promise.resolve(.failure(error))
                            }
                        }
                    }
                }
                return
            }

            for task in batch.tasks {
                await task.promise.resolve(.failure(error))
            }
        }
    }
}
