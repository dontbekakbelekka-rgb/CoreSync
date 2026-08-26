import Foundation
import CoreBluetooth

// Scans for, connects to, and streams readings from a greenTEG CORE sensor.
// Real hardware only - CoreBluetooth can't talk to a peripheral in the iOS
// Simulator, so Simulator builds use MockCoreSensorManager instead (see
// ActiveSensorManager in CoreSyncApp.swift). Both classes expose the exact
// same public surface so views work unmodified against either one.
final class CoreSensorManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: SensorConnectionState = .disconnected
    @Published private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published private(set) var currentSkinTempC: Double?
    @Published private(set) var currentCoreTempC: Double?
    @Published private(set) var batteryPercent: Int?

    // Called for every accepted reading while a session is recording -
    // RecordingView wires this to RunSession.record(_:).
    var onReading: ((SensorReading) -> Void)?

    private static let healthThermometerServiceUUID = CBUUID(string: "1809")
    private static let temperatureMeasurementCharacteristicUUID = CBUUID(string: "2A1C")
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    private static let coreBodyTemperatureServiceUUID = CBUUID(string: "00002100-5B1E-4347-B07C-97B514DAE121")
    // Per "CORE SENSOR - Core Body Temperature Service Specification" v2.2
    // (CoreBodyTemp/CoreBodyTemp on GitHub) - see CoreBodyTemperatureDecoder
    // for the payload format.
    private static let coreTemperatureCharacteristicUUID = CBUUID(string: "00002101-5B1E-4347-B07C-97B514DAE121")

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    // Keyed by peripheral identifier so re-discovery (duplicate adverts)
    // updates RSSI in place instead of growing the list.
    private var discovered: [UUID: (peripheral: CBPeripheral, rssi: Int)] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        discoveredPeripherals = []
        connectionState = .scanning
        central.scanForPeripherals(
            withServices: [Self.healthThermometerServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .disconnected }
    }

    func connect(to peripheral: DiscoveredPeripheral) {
        guard let entry = discovered[peripheral.id] else { return }
        stopScanning()
        connectionState = .connecting
        connectedPeripheral = entry.peripheral
        entry.peripheral.delegate = self
        central.connect(entry.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectionState = .disconnected
        currentSkinTempC = nil
        currentCoreTempC = nil
    }
}

extension CoreSensorManager: CBCentralManagerDelegate {
    // CBCentralManager's `state` is still .unknown right after init - it only
    // becomes .poweredOn once this delegate method fires, which happens
    // asynchronously behind the Bluetooth permission prompt. startScanning()
    // silently no-ops if called before that (see its guard below), so
    // ConnectView's onAppear call can easily lose the race against the
    // permission dialog and never actually start scanning - retrying here
    // once the state we were actually waiting for arrives is what makes that
    // race harmless instead of a silent dead end.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if connectionState != .connected && connectionState != .connecting {
                startScanning()
            }
        } else {
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        discovered[peripheral.identifier] = (peripheral, RSSI.intValue)
        discoveredPeripherals = discovered.values
            .map { DiscoveredPeripheral(id: $0.peripheral.identifier, name: $0.peripheral.name ?? "Unknown", rssi: $0.rssi) }
            .sorted { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        peripheral.discoverServices([
            Self.healthThermometerServiceUUID,
            Self.batteryServiceUUID,
            Self.coreBodyTemperatureServiceUUID,
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
    }
}

extension CoreSensorManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case Self.healthThermometerServiceUUID:
                peripheral.discoverCharacteristics([Self.temperatureMeasurementCharacteristicUUID], for: service)
            case Self.batteryServiceUUID:
                peripheral.discoverCharacteristics([Self.batteryLevelCharacteristicUUID], for: service)
            case Self.coreBodyTemperatureServiceUUID:
                peripheral.discoverCharacteristics([Self.coreTemperatureCharacteristicUUID], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            let uuid = characteristic.uuid
            if uuid == Self.temperatureMeasurementCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if uuid == Self.batteryLevelCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            } else if uuid == Self.coreTemperatureCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        let uuid = characteristic.uuid
        if uuid == Self.temperatureMeasurementCharacteristicUUID {
            guard let measurement = try? HealthThermometerDecoder.decode(data) else { return }
            currentSkinTempC = measurement.valueCelsius
            emitReading(recordedAt: measurement.timestamp ?? Date())
        } else if uuid == Self.batteryLevelCharacteristicUUID {
            batteryPercent = Int(data.first ?? 0)
        } else if uuid == Self.coreTemperatureCharacteristicUUID {
            guard let measurement = try? CoreBodyTemperatureDecoder.decode(data) else { return }
            currentCoreTempC = measurement.coreTempC
            emitReading(recordedAt: Date())
        }
    }

    // recordedAt prefers the sensor's own embedded timestamp (only the
    // standard Health Thermometer characteristic carries one - the
    // proprietary Core Body Temperature characteristic has no timestamp
    // field per its spec) over wall-clock "now", so a reading's recorded
    // time stays correct if the sensor ever replays buffered/delayed data
    // instead of a live sample.
    private func emitReading(recordedAt: Date) {
        let reading = SensorReading(
            recordedAt: recordedAt,
            skinTempC: currentSkinTempC,
            coreTempC: currentCoreTempC,
            batteryPct: batteryPercent
        )
        onReading?(reading)
    }
}
