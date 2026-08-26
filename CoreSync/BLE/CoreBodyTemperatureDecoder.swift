import Foundation

enum CoreDataQuality: Int {
    case invalid = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4
    case notAvailable = 7
}

struct CoreBodyTemperatureMeasurement {
    let coreTempC: Double?
    let skinTempC: Double?
    let heartRateBPM: Int?
    let heatStrainIndex: Double?
    let dataQuality: CoreDataQuality?
}

enum CoreBodyTemperatureDecodeError: Error {
    case tooShort
}

// Decodes greenTEG's proprietary Core Body Temperature characteristic
// (00002101-5B1E-4347-B07C-97B514DAE121), per "CORE SENSOR - Core Body
// Temperature Service Specification" v2.2 (CoreBodyTemp/CoreBodyTemp on
// GitHub). Unlike the standard Health Thermometer characteristic this app
// also reads (see HealthThermometerDecoder), values here are plain
// little-endian fixed-point integers in 0.01 degree units, not IEEE-11073
// floats - a different, simpler wire format for a different service.
//
// Byte layout: Flags(1) + CoreBodyTemp(SINT16) + [SkinTemp(SINT16) if flag
// bit0] + [CoreReserved(SINT16) if bit1] + [QualityAndState(1) if bit2] +
// [HeartRate(1) if bit4] + [HeatStrainIndex(1) if bit5]. Each optional
// field's presence bit must be checked in this exact order since the
// payload is packed - an absent field simply isn't there, not zeroed.
enum CoreBodyTemperatureDecoder {
    private static let flagSkinTemperature: UInt8 = 1 << 0
    private static let flagCoreReserved: UInt8 = 1 << 1
    private static let flagQualityAndState: UInt8 = 1 << 2
    private static let flagFahrenheit: UInt8 = 1 << 3
    private static let flagHeartRate: UInt8 = 1 << 4
    private static let flagHeatStrainIndex: UInt8 = 1 << 5

    // Spec-defined sentinel for "Data not available" in the mandatory Core
    // Body Temperature field.
    private static let dataNotAvailable: Int16 = 0x7FFF

    static func decode(_ data: Data) throws -> CoreBodyTemperatureMeasurement {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { throw CoreBodyTemperatureDecodeError.tooShort }

        let flags = bytes[0]
        let isFahrenheit = (flags & flagFahrenheit) != 0
        var offset = 1

        let rawCoreTemp = try readSInt16LE(bytes, at: offset)
        offset += 2
        let coreTempC: Double? = rawCoreTemp == dataNotAvailable ? nil : celsius(fromRaw: rawCoreTemp, isFahrenheit: isFahrenheit)

        var skinTempC: Double?
        if flags & flagSkinTemperature != 0 {
            let raw = try readSInt16LE(bytes, at: offset)
            skinTempC = raw == dataNotAvailable ? nil : celsius(fromRaw: raw, isFahrenheit: isFahrenheit)
            offset += 2
        }

        if flags & flagCoreReserved != 0 {
            // Presence-flagged but its meaning is undefined by the spec -
            // consumed only to keep later optional fields at the right
            // offset, value itself is discarded.
            _ = try readSInt16LE(bytes, at: offset)
            offset += 2
        }

        var quality: CoreDataQuality?
        if flags & flagQualityAndState != 0 {
            guard bytes.count > offset else { throw CoreBodyTemperatureDecodeError.tooShort }
            quality = CoreDataQuality(rawValue: Int(bytes[offset] & 0x07))
            offset += 1
        }

        var heartRate: Int?
        if flags & flagHeartRate != 0 {
            guard bytes.count > offset else { throw CoreBodyTemperatureDecodeError.tooShort }
            heartRate = Int(bytes[offset])
            offset += 1
        }

        var heatStrainIndex: Double?
        if flags & flagHeatStrainIndex != 0 {
            guard bytes.count > offset else { throw CoreBodyTemperatureDecodeError.tooShort }
            heatStrainIndex = Double(bytes[offset]) / 10.0
            offset += 1
        }

        return CoreBodyTemperatureMeasurement(
            coreTempC: coreTempC,
            skinTempC: skinTempC,
            heartRateBPM: heartRate,
            heatStrainIndex: heatStrainIndex,
            dataQuality: quality
        )
    }

    private static func readSInt16LE(_ bytes: [UInt8], at offset: Int) throws -> Int16 {
        guard bytes.count >= offset + 2 else { throw CoreBodyTemperatureDecodeError.tooShort }
        let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        return Int16(bitPattern: raw)
    }

    private static func celsius(fromRaw raw: Int16, isFahrenheit: Bool) -> Double {
        let value = Double(raw) * 0.01
        return isFahrenheit ? (value - 32) * 5 / 9 : value
    }
}
