import XCTest
@testable import CoreSync

final class CoreBodyTemperatureDecoderTests: XCTestCase {
    // flags=0x00 (Celsius, no optional fields), core temp raw=3700 (0x0E74 LE) => 37.00°C.
    func testDecodesCoreTempOnly() throws {
        let bytes: [UInt8] = [0x00, 0x74, 0x0E]
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertEqual(m.coreTempC ?? -1, 37.0, accuracy: 0.001)
        XCTAssertNil(m.skinTempC)
        XCTAssertNil(m.heartRateBPM)
        XCTAssertNil(m.heatStrainIndex)
        XCTAssertNil(m.dataQuality)
    }

    // flags=0x01 (skin temp valid): core temp 3700 (0x0E74), skin temp 3250 (0x0CB2) => 32.50°C.
    func testDecodesSkinTempWhenPresent() throws {
        let bytes: [UInt8] = [0x01, 0x74, 0x0E, 0xB2, 0x0C]
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertEqual(m.coreTempC ?? -1, 37.0, accuracy: 0.001)
        XCTAssertEqual(m.skinTempC ?? -1, 32.5, accuracy: 0.001)
    }

    // Core Body Temperature field's spec-defined sentinel (0x7FFF) means
    // "Data not available" - must decode to nil, not a bogus 327.67°C.
    func testCoreTempSentinelDecodesToNil() throws {
        let bytes: [UInt8] = [0x00, 0xFF, 0x7F]
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertNil(m.coreTempC)
    }

    // flags=0x14 (quality bit2 + heart rate bit4): core temp 3700, quality
    // byte 0x03 (Good), heart rate byte 150 (0x96) - exercises reading two
    // single-byte optional fields in sequence at the right offsets.
    func testDecodesQualityAndHeartRate() throws {
        let bytes: [UInt8] = [0x14, 0x74, 0x0E, 0x03, 0x96]
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertEqual(m.coreTempC ?? -1, 37.0, accuracy: 0.001)
        XCTAssertEqual(m.dataQuality, .good)
        XCTAssertEqual(m.heartRateBPM, 150)
    }

    // flags=0x20 (heat strain index bit5): HSI byte 87 => 8.7 (units of 0.1).
    func testDecodesHeatStrainIndex() throws {
        let bytes: [UInt8] = [0x20, 0x74, 0x0E, 0x57]
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertEqual(m.heatStrainIndex ?? -1, 8.7, accuracy: 0.001)
    }

    // flags=0x08 (Fahrenheit unit bit3): core temp raw 9860 (98.60°F) should
    // convert to 37.0°C.
    func testConvertsFahrenheitToCelsius() throws {
        let bytes: [UInt8] = [0x08, 0x84, 0x26] // 9860 = 0x2684
        let m = try CoreBodyTemperatureDecoder.decode(Data(bytes))
        XCTAssertEqual(m.coreTempC ?? -1, 37.0, accuracy: 0.01)
    }

    func testThrowsOnTooShortPayload() {
        let bytes: [UInt8] = [0x00, 0x74]
        XCTAssertThrowsError(try CoreBodyTemperatureDecoder.decode(Data(bytes)))
    }
}
