import Foundation

// A session's data in the shape it needs to survive a failed sync - written
// to Documents/pending-sessions/<uuid>.json whenever the End & Sync upload
// fails (no signal, server error, etc.) rather than losing the recording.
// Kept separate from RunSession (the in-memory, actively-recording model)
// since this is the durable, at-rest shape the "Retry Sync" flow reads back.
struct PendingSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let readings: [PendingReading]
    let notes: String?

    struct PendingReading: Codable {
        let recordedAt: Date
        let skinTempC: Double?
        let coreTempC: Double?
        let batteryPct: Int?
    }

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, readings: [PendingReading], notes: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.readings = readings
        self.notes = notes
    }
}

enum PendingSessionStore {
    private static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("pending-sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ session: PendingSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [PendingSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(PendingSession.self, from: data)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    static func remove(_ session: PendingSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
