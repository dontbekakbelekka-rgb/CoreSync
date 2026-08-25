import Foundation

enum SensorConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
}

struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

// One recorded sample. coreTempC stays nil until the proprietary
// characteristic UUID from greenTEG's BLE Implementation Notes is wired up
// (see CoreSensorManager.coreTemperatureCharacteristicUUID) - every screen
// in the app is built to display that absence gracefully rather than a fake
// number.
struct SensorReading {
    let recordedAt: Date
    let skinTempC: Double?
    let coreTempC: Double?
    let batteryPct: Int?
}
