import Foundation
import CloudKit
import CryptoKit

struct CloudArchiveGeneration: Codable, Equatable {
    var generation: String
    var count: Int
    var byteCount: Int
    var sha256: String
    var committedAt: Double
}

struct CloudArchiveManifest: Codable {
    var chunkVersion = 1
    var deviceID: String
    var current: CloudArchiveGeneration
    var previous: CloudArchiveGeneration?
}

private struct CloudArchiveChunk: Codable {
    var chunkVersion = 1
    var deviceID: String
    var generation: String
    var index: Int
    var count: Int
    var payload: String
}

/// Chunks are immutable; the small workspace manifest is committed last with a
/// change-tag check. A partial upload can never become a readable workspace.
@MainActor
enum CloudArchiveTransport {
    static let chunkType = "StickeyWorkspaceChunk"
    static let chunkSize = 360_000

    static func manifest(in record: CKRecord) -> CloudArchiveManifest? {
        guard let string = record["archive"] as? String else { return nil }
        return try? JSONDecoder().decode(CloudArchiveManifest.self, from: Data(string.utf8))
    }

    static func read(_ record: CKRecord, database: CKDatabase) async throws -> (data: Data, usedPrevious: Bool) {
        guard let string = record["archive"] as? String else { throw CloudArchiveError.incomplete }
        guard let manifest = manifest(in: record) else { return (Data(string.utf8), false) } // Legacy whole archive.
        guard manifest.chunkVersion == 1 else { throw CloudArchiveError.unsupported }
        do { return (try await read(manifest.current, deviceID: manifest.deviceID, database: database), false) }
        catch {
            guard let previous = manifest.previous else { throw error }
            return (try await read(previous, deviceID: manifest.deviceID, database: database), true)
        }
    }

    private static func read(_ generation: CloudArchiveGeneration, deviceID: String, database: CKDatabase) async throws -> Data {
        guard generation.count > 0, generation.count <= 300,
              generation.byteCount > 0, generation.byteCount <= 100_000_000 else { throw CloudArchiveError.incomplete }
        let ids = chunkIDs(generation, deviceID: deviceID)
        var chunks: [CKRecord] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let records = try await database.records(for: batch, desiredKeys: ["archive"])
            for id in batch {
                guard let result = records[id] else { throw CloudArchiveError.incomplete }
                chunks.append(try result.get())
            }
        }
        return try verifiedData(chunks, generation: generation, deviceID: deviceID)
    }

    static func verifiedData(_ chunks: [CKRecord], generation: CloudArchiveGeneration, deviceID: String) throws -> Data {
        guard chunks.count == generation.count, generation.byteCount <= 100_000_000 else { throw CloudArchiveError.incomplete }
        var data = Data()
        for (index, record) in chunks.enumerated() {
            guard let string = record["archive"] as? String,
                  let chunk = try? JSONDecoder().decode(CloudArchiveChunk.self, from: Data(string.utf8)),
                  chunk.chunkVersion == 1, chunk.deviceID == deviceID, chunk.generation == generation.generation,
                  chunk.index == index, chunk.count == generation.count,
                  let bytes = Data(base64Encoded: chunk.payload), bytes.count <= chunkSize else { throw CloudArchiveError.incomplete }
            data.append(bytes)
        }
        guard data.count == generation.byteCount, digest(data) == generation.sha256 else { throw CloudArchiveError.incomplete }
        return data
    }

    static func generation(for data: Data) throws -> CloudArchiveGeneration {
        guard !data.isEmpty, data.count <= 100_000_000 else { throw CloudArchiveError.tooLarge }
        return CloudArchiveGeneration(generation: UUID().uuidString,
                                      count: max(1, (data.count + chunkSize - 1) / chunkSize),
                                      byteCount: data.count, sha256: digest(data),
                                      committedAt: Date().timeIntervalSince1970 * 1_000)
    }

    static func chunkRecord(_ data: Data, generation: CloudArchiveGeneration, deviceID: String, index: Int) throws -> CKRecord {
        let bytes = data.subdata(in: (index * chunkSize)..<min((index + 1) * chunkSize, data.count))
        let envelope = CloudArchiveChunk(deviceID: deviceID, generation: generation.generation,
                                         index: index, count: generation.count, payload: bytes.base64EncodedString())
        let record = CKRecord(recordType: chunkType, recordID: chunkIDs(generation, deviceID: deviceID)[index])
        record["archive"] = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self) as CKRecordValue
        return record
    }

    static func write(_ data: Data, to record: CKRecord, deviceID: String, database: CKDatabase,
                      retainPrevious: Bool, isActive: () -> Bool) async throws -> CKRecord {
        let previous = manifest(in: record)
        let generation = try generation(for: data)
        let ids = chunkIDs(generation, deviceID: deviceID)
        for start in stride(from: 0, to: ids.count, by: 30) {
            guard isActive() else { throw CancellationError() }
            var chunks: [CKRecord] = []
            for index in start..<min(start + 30, ids.count) {
                chunks.append(try chunkRecord(data, generation: generation, deviceID: deviceID, index: index))
            }
            let response = try await database.modifyRecords(saving: chunks, deleting: [],
                                                            savePolicy: .ifServerRecordUnchanged, atomically: false)
            for (_, result) in response.saveResults { _ = try result.get() }
        }
        guard isActive() else { throw CancellationError() }
        let next = CloudArchiveManifest(deviceID: deviceID, current: generation,
                                        previous: retainPrevious ? previous?.current : nil)
        record["archive"] = String(decoding: try JSONEncoder().encode(next), as: UTF8.self) as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        let result = try await database.modifyRecords(saving: [record], deleting: [],
                                                       savePolicy: .ifServerRecordUnchanged, atomically: false)
        guard let saved = result.saveResults[record.recordID] else { throw CloudArchiveError.incomplete }
        let committed = try saved.get()
        // Once commit succeeds, remove generations no longer referenced. A lock
        // also removes the previous plaintext generation instead of retaining it.
        if let previous, isActive() {
            var obsolete = previous.previous.map { chunkIDs($0, deviceID: previous.deviceID) } ?? []
            if !retainPrevious { obsolete += chunkIDs(previous.current, deviceID: previous.deviceID) }
            for start in stride(from: 0, to: obsolete.count, by: 100) {
                guard isActive() else { break }
                _ = try? await database.modifyRecords(saving: [], deleting: Array(obsolete[start..<min(start + 100, obsolete.count)]),
                                                       savePolicy: .ifServerRecordUnchanged, atomically: false)
            }
        }
        return committed
    }

    private static func chunkIDs(_ generation: CloudArchiveGeneration, deviceID: String) -> [CKRecord.ID] {
        (0..<generation.count).map { CKRecord.ID(recordName: "device-\(deviceID)-\(generation.generation)-\($0)") }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

private enum CloudArchiveError: LocalizedError {
    case incomplete, unsupported, tooLarge
    var errorDescription: String? {
        switch self {
        case .incomplete: return "An iCloud upload is incomplete or damaged. Local notes are safe; sync will retry."
        case .unsupported: return "This iCloud workspace requires a newer version of StickeyNote."
        case .tooLarge: return "This archive exceeds the 100 MB safety limit. Export a backup before reducing attachment or history data."
        }
    }
}
