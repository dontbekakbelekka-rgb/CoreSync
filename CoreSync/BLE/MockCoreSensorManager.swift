import Foundation

// Simulator stand-in for CoreSensorManager - CoreBluetooth can't talk to
// real hardware in the iOS Simulator, so this fakes a nearby "CORE
// (Simulator)" peripheral and a stream of plausible skin-temperature
// readings for UI development and testing. Mirrors CoreSensorManager's
// public surface exactly (see ActiveSensorManager in CoreSyncApp.swift) so
// every view works unmodified against either type.
final class MockCoreSensorManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: SensorConnectionState = .disconnected
    @Published private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published private(set) var currentSkinTempC: Double?
    @Published private(set) var currentCoreTempC: Double?
    @Published private(set) var batteryPercent: Int?

    var onReading: ((SensorReading) -> Void)?

    private var readingTimer: Timer?
    private let mockPeripheralID = UUID()
    private let mockPeripheralName = "CORE (Simulator)"

    func startScanning() {
        connectionState = .scanning
        discoveredPeripherals = [DiscoveredPeripheral(id: mockPeripheralID, name: mockPeripheralName, rssi: -45)]
    }

    func stopScanning() {
        if connectionState == .scanning { connectionState = .disconnected }
    }

    func connect(to peripheral: DiscoveredPeripheral) {
        guard peripheral.id == mockPeripheralID else { return }
        connectionState = .connecting
        // Mimics real connect latency so ConnectView's connecting state is
        // actually exercised rather than skipped straight to connected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            self.batteryPercent = 87
            self.startMockReadings()
        }
    }

    func disconnect() {
        readingTimer?.invalidate()
        readingTimer = nil
        connectionState = .disconnected
        currentSkinTempC = nil
        currentCoreTempC = nil
    }

    private func startMockReadings() {
        readingTimer?.invalidate()
        readingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.emitMockReading()
        }
    }

    private func emitMockReading() {
        let wobble = Double.random(in: -0.15...0.15)
        let skin = 33.5 + wobble
        currentSkinTempC = skin
        let reading = SensorReading(recordedAt: Date(), skinTempC: skin, coreTempC: nil, batteryPct: batteryPercent)
        onReading?(reading)
    }
}
