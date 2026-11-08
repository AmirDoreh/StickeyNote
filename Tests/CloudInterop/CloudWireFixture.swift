import Foundation
import CloudKit

private struct WireChunk: Codable { var recordName: String; var archive: String }
private struct WireFixture: Codable {
    var manifest: CloudArchiveManifest
    var chunks: [WireChunk]
    var archive: String
}

@main
struct CloudWireFixture {
    @MainActor
    static func main() throws {
        let fixture = try JSONDecoder().decode(WireFixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let records = fixture.chunks.map { item in
            let record = CKRecord(recordType: CloudArchiveTransport.chunkType, recordID: CKRecord.ID(recordName: item.recordName))
            record["archive"] = item.archive as CKRecordValue
            return record
        }
        let data = try CloudArchiveTransport.verifiedData(records, generation: fixture.manifest.current,
                                                         deviceID: fixture.manifest.deviceID)
        precondition(data == Data(fixture.archive.utf8), "Swift did not reproduce the browser's exact UTF-8 bytes")
        let generation = try CloudArchiveTransport.generation(for: data)
        let device = "swift-fixture"
        let chunks = try (0..<generation.count).map { index in
            let record = try CloudArchiveTransport.chunkRecord(data, generation: generation, deviceID: device, index: index)
            return WireChunk(recordName: record.recordID.recordName, archive: record["archive"] as! String)
        }
        let output = WireFixture(manifest: CloudArchiveManifest(deviceID: device, current: generation),
                                 chunks: chunks, archive: fixture.archive)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("Swift decoded JavaScript archive and produced \(chunks.count) verified native chunks.")
    }
}
