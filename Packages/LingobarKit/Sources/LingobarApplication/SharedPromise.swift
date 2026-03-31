import Foundation

actor SharedPromise<Output: Sendable> {
    private var continuations: [CheckedContinuation<Output, Error>] = []
    private var result: Result<Output, Error>?

    func wait() async throws -> Output {
        if let result {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resolve(_ result: Result<Output, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let pendingContinuations = continuations
        continuations.removeAll()

        for continuation in pendingContinuations {
            switch result {
            case .success(let output):
                continuation.resume(returning: output)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
