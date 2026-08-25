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

    // Pending the real characteristic UUID from greenTEG's "CORE BLE
    // Implementation Notes" PDF (email info@greenteg.com - see README). The
    // proprietary Core Body Temperature Service itself
    // (coreBodyTemperatureServiceUUID below) is documented in greenTEG's
    // public Wear OS reference app, but not which characteristic under it
    // carries the computed core-temp value, or its byte format. Once known,
    // set this and it gets subscribed to exactly like temperature
    // measurement below - everything else in the app already handles a nil
    // core temp gracefully, so this is meant to be a one-line swap.
    var coreTemperatureCharacteristicUUID: CBUUID?

    private static let healthThermometerServiceUUID = CBUUID(string: "1809")
    private static let temperatureMeasurementCharacteristicUUID = CBUUID(string: "2A1C")
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    private static let coreBodyTemperatureServiceUUID = CBUUID(string: "00002100-5B1E-4347-B07C-97B514DAE121")

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
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
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
                // Service is present on real hardware, but there's nothing to
                // subscribe to until coreTemperatureCharacteristicUUID is set
                // (see the property doc comment above).
                if let coreUUID = coreTemperatureCharacteristicUUID {
                    peripheral.discoverCharacteristics([coreUUID], for: service)
                }
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
            } else if coreTemperatureCharacteristicUUID != nil, uuid == coreTemperatureCharacteristicUUID {
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
            emitReading()
        } else if uuid == Self.batteryLevelCharacteristicUUID {
            batteryPercent = Int(data.first ?? 0)
        } else if coreTemperatureCharacteristicUUID != nil, uuid == coreTemperatureCharacteristicUUID {
            // TODO: decode once greenTEG's Implementation Notes give us the
            // byte format for this characteristic - currentCoreTempC stays
            // nil until then.
        }
    }

    private func emitReading() {
        let reading = SensorReading(
            recordedAt: Date(),
            skinTempC: currentSkinTempC,
            coreTempC: currentCoreTempC,
            batteryPct: batteryPercent
        )
        onReading?(reading)
    }
}
