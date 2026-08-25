import Foundation

// In-memory recording of one session's worth of sensor readings, plus the
// summary stat calculations used both by the live "Recording" screen and
// the final sync payload. No network calls happen here or anywhere during
// recording, per the "no live streaming, just local recording" requirement
// - see CoreTempAPI for the End & Sync upload.
final class RunSession: ObservableObject, Identifiable {
    let id = UUID()
    let startedAt: Date
    @Published private(set) var endedAt: Date?
    @Published private(set) var readings: [SensorReading] = []

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    func record(_ reading: SensorReading) {
        readings.append(reading)
    }

    func end() {
        endedAt = Date()
    }

    var elapsed: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var averageSkinTempC: Double? { average(readings.compactMap(\.skinTempC)) }
    var maxSkinTempC: Double? { readings.compactMap(\.skinTempC).max() }
    var averageCoreTempC: Double? { average(readings.compactMap(\.coreTempC)) }
    var maxCoreTempC: Double? { readings.compactMap(\.coreTempC).max() }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
