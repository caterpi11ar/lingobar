import Foundation
import GRDB
import LingobarApplication
import LingobarDomain

public final class AppDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    public init() throws {
        dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create_translation_cache") { db in
            try db.create(table: "translation_cache", ifNotExists: true) { table in
                table.column("hash", .text).primaryKey()
                table.column("translation", .text).notNull()
                table.column("created_at", .double).notNull()
            }
        }
        migrator.registerMigration("create_batch_requests") { db in
            try db.create(table: "batch_requests", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("created_at", .double).notNull()
                table.column("original_request_count", .integer).notNull()
                table.column("provider_id", .text).notNull()
                table.column("model", .text).notNull()
            }
        }
        migrator.registerMigration("create_translation_records") { db in
            try db.create(table: "translation_records", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("created_at", .double).notNull()
                table.column("source_text_length", .integer).notNull()
                table.column("source_language", .text)
                table.column("target_language", .text).notNull()
                table.column("provider_id", .text).notNull()
                table.column("latency_ms", .integer).notNull()
                table.column("success", .boolean).notNull()
                table.column("write_back_applied", .boolean).notNull()
            }
        }
        return migrator
    }
}

public struct SQLiteTranslationCacheRepository: TranslationCacheRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func translation(for hash: String) async throws -> TranslationCacheEntry? {
        try await database.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT hash, translation, created_at FROM translation_cache WHERE hash = ?",
                arguments: [hash]
            ) else {
                return nil
            }

            let hash: String = row["hash"]
            let translation: String = row["translation"]
            let createdAt: Double = row["created_at"]

            return TranslationCacheEntry(
                hash: hash,
                translation: translation,
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        }
    }

    public func save(_ entry: TranslationCacheEntry) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO translation_cache (hash, translation, created_at) VALUES (?, ?, ?)",
                arguments: [entry.hash, entry.translation, entry.createdAt.timeIntervalSince1970]
            )
        }
    }

    public func removeAll() async throws {
        try await database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM translation_cache")
        }
    }
}

public struct SQLiteStatisticsRepository: StatisticsRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func recordBatchRequest(_ record: BatchRequestRecord) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO batch_requests (id, created_at, original_request_count, provider_id, model) VALUES (?, ?, ?, ?, ?)",
                arguments: [record.id.uuidString, record.createdAt.timeIntervalSince1970, record.originalRequestCount, record.providerId, record.model]
            )
        }
    }

    public func recordTranslation(_ record: TranslationRecord) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO translation_records (id, created_at, source_text_length, source_language, target_language, provider_id, latency_ms, success, write_back_applied) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    record.id.uuidString,
                    record.createdAt.timeIntervalSince1970,
                    record.sourceTextLength,
                    record.sourceLanguage,
                    record.targetLanguage,
                    record.providerId,
                    record.latencyMs,
                    record.success,
                    record.writeBackApplied,
                ]
            )
        }
    }

    public func batchRequests(from start: Date, to end: Date) async throws -> [BatchRequestRecord] {
        try await database.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, created_at, original_request_count, provider_id, model FROM batch_requests WHERE created_at >= ? AND created_at <= ? ORDER BY created_at ASC",
                arguments: [start.timeIntervalSince1970, end.timeIntervalSince1970]
            )
            return rows.map { row in
                let id: String = row["id"]
                let createdAt: Double = row["created_at"]
                let originalRequestCount: Int = row["original_request_count"]
                let providerId: String = row["provider_id"]
                let model: String = row["model"]

                return BatchRequestRecord(
                    id: UUID(uuidString: id) ?? UUID(),
                    createdAt: Date(timeIntervalSince1970: createdAt),
                    originalRequestCount: originalRequestCount,
                    providerId: providerId,
                    model: model
                )
            }
        }
    }

    public func translations(from start: Date, to end: Date) async throws -> [TranslationRecord] {
        try await database.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, created_at, source_text_length, source_language, target_language, provider_id, latency_ms, success, write_back_applied FROM translation_records WHERE created_at >= ? AND created_at <= ? ORDER BY created_at ASC",
                arguments: [start.timeIntervalSince1970, end.timeIntervalSince1970]
            )
            return rows.map { row in
                let id: String = row["id"]
                let createdAt: Double = row["created_at"]
                let sourceTextLength: Int = row["source_text_length"]
                let sourceLanguage: String? = row["source_language"]
                let targetLanguage: String = row["target_language"]
                let providerId: String = row["provider_id"]
                let latencyMs: Int = row["latency_ms"]
                let success: Bool = row["success"]
                let writeBackApplied: Bool = row["write_back_applied"]

                return TranslationRecord(
                    id: UUID(uuidString: id) ?? UUID(),
                    createdAt: Date(timeIntervalSince1970: createdAt),
                    sourceTextLength: sourceTextLength,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    providerId: providerId,
                    latencyMs: latencyMs,
                    success: success,
                    writeBackApplied: writeBackApplied
                )
            }
        }
    }
}
