import XCTest
@testable import CoreSync

final class HealthThermometerDecoderTests: XCTestCase {
    // flags=0x00 (Celsius, no timestamp), mantissa=366 (0x00016E, LE ->
    // 6E 01 00), exponent=-1 (0xFF) => 366 * 10^-1 = 36.6°C.
    func testDecodesSimpleCelsiusValue() throws {
        let bytes: [UInt8] = [0x00, 0x6E, 0x01, 0x00, 0xFF]
        let measurement = try HealthThermometerDecoder.decode(Data(bytes))
        XCTAssertEqual(measurement.valueCelsius, 36.6, accuracy: 0.0001)
        XCTAssertEqual(measurement.unit, .celsius)
        XCTAssertNil(measurement.timestamp)
    }

    // mantissa=20, exponent=0 => 20.0 exactly, exercising the exponent=0 path.
    func testDecodesWholeNumberValue() throws {
        let bytes: [UInt8] = [0x00, 0x14, 0x00, 0x00, 0x00]
        let measurement = try HealthThermometerDecoder.decode(Data(bytes))
        XCTAssertEqual(measurement.valueCelsius, 20.0, accuracy: 0.0001)
    }

    // flags=0x01 (Fahrenheit): mantissa=986, exponent=-1 => 98.6°F, which
    // should convert to 37.0°C.
    func testConvertsFahrenheitToCelsius() throws {
        let bytes: [UInt8] = [0x01, 0xDA, 0x03, 0x00, 0xFF] // 986 = 0x03DA
        let measurement = try HealthThermometerDecoder.decode(Data(bytes))
        XCTAssertEqual(measurement.unit, .fahrenheit)
        XCTAssertEqual(measurement.valueCelsius, 37.0, accuracy: 0.01)
    }

    // flags=0x02 (timestamp present) appends a 7-byte date/time: year 2024
    // (0x07E8, LE -> E8 07), month=1, day=15, hour=8, minute=30, second=0.
    func testDecodesOptionalTimestamp() throws {
        let bytes: [UInt8] = [
            0x02, 0x6E, 0x01, 0x00, 0xFF,
            0xE8, 0x07, 0x01, 0x0F, 0x08, 0x1E, 0x00,
        ]
        let measurement = try HealthThermometerDecoder.decode(Data(bytes))
        XCTAssertEqual(measurement.valueCelsius, 36.6, accuracy: 0.0001)

        let calendar = Calendar(identifier: .gregorian)
        let timestamp = try XCTUnwrap(measurement.timestamp)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: timestamp)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 30)
    }

    // A negative mantissa exercises the 24-bit sign-extension path: -50,
    // exponent=-1 => -5.0 (a below-freezing reading, unrealistic for a body
    // sensor but valid per the wire format and worth covering).
    func testDecodesNegativeMantissa() throws {
        let bytes: [UInt8] = [0x00, 0xCE, 0xFF, 0xFF, 0xFF] // -50 as a 24-bit two's-complement LE value
        let measurement = try HealthThermometerDecoder.decode(Data(bytes))
        XCTAssertEqual(measurement.valueCelsius, -5.0, accuracy: 0.0001)
    }

    func testThrowsOnTooShortPayload() {
        let bytes: [UInt8] = [0x00, 0x6E, 0x01]
        XCTAssertThrowsError(try HealthThermometerDecoder.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? HealthThermometerDecodeError, .tooShort)
        }
    }

    // Raw mantissa 0x007FFFFF is the reserved IEEE-11073 "NaN" sentinel, not
    // a real reading.
    func testThrowsOnReservedNaNSentinel() {
        let bytes: [UInt8] = [0x00, 0xFF, 0xFF, 0x7F, 0x00]
        XCTAssertThrowsError(try HealthThermometerDecoder.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? HealthThermometerDecodeError, .specialFloatValue)
        }
    }
}
