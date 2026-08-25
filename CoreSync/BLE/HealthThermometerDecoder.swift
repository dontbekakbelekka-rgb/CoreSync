import Foundation

enum TemperatureUnit: Equatable {
    case celsius
    case fahrenheit
}

struct TemperatureMeasurement {
    let valueCelsius: Double
    let timestamp: Date?
    let unit: TemperatureUnit
}

enum HealthThermometerDecodeError: Error, Equatable {
    case tooShort
    case specialFloatValue
}

// Decodes the Bluetooth SIG Health Thermometer Service's "Temperature
// Measurement" characteristic (0x2A1C) - the standard, well-documented BLE
// profile the CORE sensor uses for skin temperature (see
// CoreSensorManager). Byte layout per the GATT spec:
//   [0]       flags: bit0 = unit (0 Celsius, 1 Fahrenheit),
//             bit1 = timestamp present, bit2 = temperature type present
//   [1...4]   IEEE-11073 32-bit FLOAT (not a plain IEEE-754 float - a signed
//             24-bit mantissa + signed 8-bit exponent, see below)
//   [5...11]  optional 7-byte date/time, present only if flags bit1 is set
//   [12]      optional temperature-type enum, present only if bit2 is set
//             (not needed here - the CORE sensor's skin probe is the only
//             source this app reads from)
enum HealthThermometerDecoder {
    private static let flagUnitFahrenheit: UInt8 = 0x01
    private static let flagTimestampPresent: UInt8 = 0x02

    static func decode(_ data: Data) throws -> TemperatureMeasurement {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { throw HealthThermometerDecodeError.tooShort }

        let flags = bytes[0]
        let unit: TemperatureUnit = (flags & flagUnitFahrenheit) != 0 ? .fahrenheit : .celsius
        let rawValue = try decodeIEEE11073Float(bytes: Array(bytes[1...4]))

        var timestamp: Date?
        if (flags & flagTimestampPresent) != 0 {
            let start = 5
            guard bytes.count >= start + 7 else { throw HealthThermometerDecodeError.tooShort }
            timestamp = decodeDateTime(bytes: Array(bytes[start..<(start + 7)]))
        }

        let celsius = unit == .fahrenheit ? (rawValue - 32) * 5 / 9 : rawValue
        return TemperatureMeasurement(valueCelsius: celsius, timestamp: timestamp, unit: unit)
    }

    // IEEE-11073 32-bit FLOAT: 4 bytes, little-endian. The low 3 bytes are a
    // signed 24-bit mantissa, the high byte is a signed 8-bit exponent.
    // value = mantissa * 10^exponent. A handful of raw 24-bit mantissa
    // patterns are reserved sentinels (NaN / +INFINITY / -INFINITY / "not at
    // this resolution") rather than real values - checked against the raw
    // unsigned pattern *before* sign-extension, since that's how the spec
    // defines them.
    private static func decodeIEEE11073Float(bytes: [UInt8]) throws -> Double {
        precondition(bytes.count == 4)
        let exponent = Int8(bitPattern: bytes[3])
        let raw24 = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16)

        switch raw24 {
        case 0x007FFFFF, 0x00800000, 0x00800001, 0x00800002:
            throw HealthThermometerDecodeError.specialFloatValue
        default:
            break
        }

        var mantissa = Int32(bitPattern: raw24)
        if raw24 & 0x00800000 != 0 {
            mantissa |= Int32(bitPattern: 0xFF000000) // sign-extend 24 -> 32 bits
        }

        return Double(mantissa) * pow(10.0, Double(exponent))
    }

    private static func decodeDateTime(bytes: [UInt8]) -> Date? {
        precondition(bytes.count == 7)
        let year = Int(bytes[0]) | (Int(bytes[1]) << 8)
        let month = Int(bytes[2])
        let day = Int(bytes[3])
        guard year > 0, month > 0, day > 0 else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = Int(bytes[4])
        components.minute = Int(bytes[5])
        components.second = Int(bytes[6])
        components.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
