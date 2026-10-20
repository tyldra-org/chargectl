import Foundation
import IOKit

nonisolated enum SMCError: Error, Equatable, CustomStringConvertible {
    case serviceUnavailable
    case openFailed(kern_return_t)
    case callFailed(String, kern_return_t)
    case keyUnavailable(String)
    case rejected(String, UInt8)
    case wrongSize(String, expected: Int, actual: Int)

    var description: String {
        switch self {
        case .serviceUnavailable: "AppleSMC is not available"
        case .openFailed(let code): "could not open AppleSMC (\(String(format: "0x%08x", code)))"
        case .callFailed(let key, let code): "SMC call for \(key) failed (\(String(format: "0x%08x", code)))"
        case .keyUnavailable(let key): "SMC key \(key) is not available"
        case .rejected(let key, let result): "SMC rejected \(key) (result \(result))"
        case .wrongSize(let key, let expected, let actual):
            "SMC key \(key) holds \(expected) bytes, not \(actual)"
        }
    }
}

/// A raw SMC value. Apple silicon stores integers and floats little-endian.
nonisolated struct SMCValue: Equatable, Sendable {
    let key: String
    let type: String
    let bytes: [UInt8]

    var float: Float? {
        guard type == "flt ", bytes.count == 4 else { return nil }
        return Float(bitPattern: Self.littleEndian(bytes))
    }

    var integer: Int? {
        switch (type, bytes.count) {
        case ("ui8 ", 1), ("hex_", 1), ("flag", 1): Int(bytes[0])
        case ("si8 ", 1): Int(Int8(bitPattern: bytes[0]))
        case ("ui16", 2): Int(Self.littleEndian(bytes))
        case ("si16", 2): Int(Int16(bitPattern: UInt16(Self.littleEndian(bytes))))
        case ("ui32", 4): Int(Self.littleEndian(bytes))
        case ("si32", 4): Int(Int32(bitPattern: Self.littleEndian(bytes)))
        default: nil
        }
    }

    private static func littleEndian(_ bytes: [UInt8]) -> UInt32 {
        bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }
}

/// Connection to the AppleSMC user client. Reading works for any user; writing needs root.
final class SMC {
    private static let selector: UInt32 = 2
    private enum Command {
        static let read: UInt8 = 5
        static let write: UInt8 = 6
        static let keyInfo: UInt8 = 9
    }

    private let connection: io_connect_t

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.serviceUnavailable }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw SMCError.openFailed(result) }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func read(_ key: String) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = Self.code(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.read
        let output = try call(input, key: key)
        let size = Int(info.dataSize)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return SMCValue(key: key, type: Self.string(info.dataType), bytes: bytes)
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard Int(info.dataSize) == bytes.count else {
            throw SMCError.wrongSize(key, expected: Int(info.dataSize), actual: bytes.count)
        }
        var input = SMCParamStruct()
        input.key = Self.code(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.write
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        _ = try call(input, key: key)
    }

    /// False for keys that are missing and for keys the firmware refuses to describe.
    func hasKey(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    private func keyInfo(_ key: String) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = Self.code(key)
        input.data8 = Command.keyInfo
        let output = try call(input, key: key)
        guard output.keyInfo.dataSize > 0 else { throw SMCError.keyUnavailable(key) }
        return output.keyInfo
    }

    private func call(_ input: SMCParamStruct, key: String) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.selector, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        guard result == KERN_SUCCESS else { throw SMCError.callFailed(key, result) }
        switch output.result {
        case 0: return output
        case 0x84: throw SMCError.keyUnavailable(key)
        default: throw SMCError.rejected(key, output.result)
        }
    }

    private static func code(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
