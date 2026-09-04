//
//  SMCClient.swift
//  Awake
//

import Foundation
import IOKit

public nonisolated struct SMCParamStruct {
    public var b0: UInt64 = 0
    public var b1: UInt64 = 0
    public var b2: UInt64 = 0
    public var b3: UInt64 = 0
    public var b4: UInt64 = 0
    public var b5: UInt64 = 0
    public var b6: UInt64 = 0
    public var b7: UInt64 = 0
    public var b8: UInt64 = 0
    public var b9: UInt64 = 0

    public init() {}
}

public nonisolated extension SMCParamStruct {
    var key: UInt32 {
        get {
            withUnsafeBytes(of: self) { $0.load(fromByteOffset: 0, as: UInt32.self) }
        }
        set {
            withUnsafeMutableBytes(of: &self) { $0.storeBytes(of: newValue, toByteOffset: 0, as: UInt32.self) }
        }
    }

    var keyInfoDataSize: UInt32 {
        get {
            withUnsafeBytes(of: self) { $0.load(fromByteOffset: 28, as: UInt32.self) }
        }
        set {
            withUnsafeMutableBytes(of: &self) { $0.storeBytes(of: newValue, toByteOffset: 28, as: UInt32.self) }
        }
    }

    var keyInfoDataType: UInt32 {
        get {
            withUnsafeBytes(of: self) { $0.load(fromByteOffset: 32, as: UInt32.self) }
        }
        set {
            withUnsafeMutableBytes(of: &self) { $0.storeBytes(of: newValue, toByteOffset: 32, as: UInt32.self) }
        }
    }

    var keyInfoDataAttributes: UInt8 {
        get { withUnsafeBytes(of: self) { $0[36] } }
        set { withUnsafeMutableBytes(of: &self) { $0[36] = newValue } }
    }

    var result: UInt8 {
        get { withUnsafeBytes(of: self) { $0[40] } }
        set { withUnsafeMutableBytes(of: &self) { $0[40] = newValue } }
    }

    var status: UInt8 {
        get { withUnsafeBytes(of: self) { $0[41] } }
        set { withUnsafeMutableBytes(of: &self) { $0[41] = newValue } }
    }

    var data8: UInt8 {
        get { withUnsafeBytes(of: self) { $0[42] } }
        set { withUnsafeMutableBytes(of: &self) { $0[42] = newValue } }
    }

    var data32: UInt32 {
        get {
            withUnsafeBytes(of: self) { $0.load(fromByteOffset: 44, as: UInt32.self) }
        }
        set {
            withUnsafeMutableBytes(of: &self) { $0.storeBytes(of: newValue, toByteOffset: 44, as: UInt32.self) }
        }
    }

    func getBytes() -> [UInt8] {
        withUnsafeBytes(of: self) { ptr in
            Array(ptr[48..<80])
        }
    }

    mutating func setBytes(_ bytes: [UInt8]) {
        withUnsafeMutableBytes(of: &self) { ptr in
            for i in 0..<32 {
                ptr[48 + i] = i < bytes.count ? bytes[i] : 0
            }
        }
    }
}

public nonisolated final class SMCClient: @unchecked Sendable {
    public static let shared = SMCClient()

    private enum Selector: UInt8 {
        case open = 0
        case close = 1
        case call = 2
        case readKey = 5
        case writeKey = 6
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private let callLock = NSLock()

    private init() {
        _ = openConnection()
    }

    deinit {
        closeConnection()
    }

    public func openConnection() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 { return true }

        // Apple Silicon uses AppleSMCKeysEndpoint, Intel uses AppleSMC
        var service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        }
        guard service != 0 else {
            NSLog("[SMCClient] AppleSMC service not found in IORegistry")
            return false
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess, conn != 0 else {
            NSLog("[SMCClient] IOServiceOpen failed: 0x%08x", result)
            return false
        }

        self.connection = conn
        return true
    }

    public func closeConnection() {
        callLock.lock()
        defer { callLock.unlock() }
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: - Low Level Call
    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        callLock.lock()
        defer { callLock.unlock() }

        if connection == 0 {
            if !openConnection() {
                return kIOReturnNotOpen
            }
        }

        let inputSize = MemoryLayout<SMCParamStruct>.size
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            inputSize,
            &output,
            &outputSize
        )

        return result
    }

    // MARK: - Key Info
    public func getKeyInfo(key: String) -> (size: UInt32, type: UInt32)? {
        guard key.utf8.count == 4 else { return nil }
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCharCode(from: key)
        input.data8 = Selector.getKeyInfo.rawValue

        let result = callSMC(input: &input, output: &output)
        guard result == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        return (output.keyInfoDataSize, output.keyInfoDataType)
    }

    // MARK: - Read Key
    public func readBytes(key: String) -> [UInt8]? {
        guard let info = getKeyInfo(key: key) else { return nil }

        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCharCode(from: key)
        input.keyInfoDataSize = info.size
        input.data8 = Selector.readKey.rawValue

        let result = callSMC(input: &input, output: &output)
        guard result == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        return Array(output.getBytes().prefix(Int(info.size)))
    }

    public func readFloat(key: String) -> Float? {
        guard let bytes = readBytes(key: key), let info = getKeyInfo(key: key) else { return nil }

        let typeStr = fourCharCodeToString(info.type)
        if typeStr == "flt " && bytes.count >= 4 {
            var val: Float = 0
            memcpy(&val, bytes, 4)
            return val
        } else if typeStr == "fpe2" && bytes.count >= 2 {
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Float(raw >> 2)
        } else if typeStr == "sp78" && bytes.count >= 2 {
            let intPart = Float(Int8(bitPattern: bytes[0]))
            let fractPart = Float(bytes[1]) / 256.0
            return intPart + fractPart
        } else if typeStr.hasPrefix("ui") && !bytes.isEmpty {
            var raw: UInt32 = 0
            for b in bytes {
                raw = (raw << 8) | UInt32(b)
            }
            return Float(raw)
        }

        return nil
    }

    public func readInt(key: String) -> Int? {
        guard let bytes = readBytes(key: key) else { return nil }
        var result: Int = 0
        for b in bytes {
            result = (result << 8) | Int(b)
        }
        return result
    }

    // MARK: - Write Key
    public func writeBytes(key: String, bytes: [UInt8]) -> Bool {
        guard let info = getKeyInfo(key: key) else {
            NSLog("[SMCClient] Failed to get key info for write on key: %@", key)
            return false
        }

        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCharCode(from: key)
        input.data8 = Selector.writeKey.rawValue
        input.keyInfoDataSize = info.size
        input.keyInfoDataType = info.type
        input.setBytes(bytes)

        let result = callSMC(input: &input, output: &output)
        if result != kIOReturnSuccess || output.result != 0 {
            NSLog("[SMCClient] Write to key %@ failed with result: 0x%08x, smcResult: %d", key, result, output.result)
            return false
        }

        NSLog("[SMCClient] Successfully wrote to SMC key %@", key)
        return true
    }

    public func writeFloat(key: String, value: Float) -> Bool {
        guard let info = getKeyInfo(key: key) else { return false }
        let typeStr = fourCharCodeToString(info.type)

        if typeStr == "flt " {
            var v = value
            var bytes = [UInt8](repeating: 0, count: 4)
            memcpy(&bytes, &v, 4)
            return writeBytes(key: key, bytes: bytes)
        } else if typeStr == "fpe2" {
            let raw = UInt16(value * 4.0)
            let bytes = [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
            return writeBytes(key: key, bytes: bytes)
        } else if typeStr == "ui8" {
            return writeBytes(key: key, bytes: [UInt8(value)])
        } else if typeStr == "ui16" {
            let raw = UInt16(value)
            let bytes = [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
            return writeBytes(key: key, bytes: bytes)
        }

        return false
    }

    // MARK: - Fan Operations
    public func getFanCount() -> Int {
        return readInt(key: "FNum") ?? 0
    }

    public func getFanCurrentRPM(fanIndex: Int) -> Int? {
        let key = "F\(fanIndex)Ac"
        if let val = readFloat(key: key) {
            return Int(val)
        }
        return nil
    }

    public func getFanMaxRPM(fanIndex: Int) -> Int? {
        let key = "F\(fanIndex)Mx"
        if let val = readFloat(key: key) {
            return Int(val)
        }
        return 6000
    }

    public func getFanMinRPM(fanIndex: Int) -> Int? {
        let key = "F\(fanIndex)Mn"
        if let val = readFloat(key: key) {
            return Int(val)
        }
        return 1200
    }

    public func setFanManualMode(fanIndex: Int, manual: Bool) -> Bool {
        let modeKey = "F\(fanIndex)Md"
        return writeBytes(key: modeKey, bytes: [manual ? 1 : 0])
    }

    public func setFanTargetRPM(fanIndex: Int, rpm: Float) -> Bool {
        let targetKey = "F\(fanIndex)Tg"
        return writeFloat(key: targetKey, value: rpm)
    }

    public func setAllFansMax() -> Bool {
        setAllFans(targetFraction: 1.0)
    }

    public func setAllFansAggressive() -> Bool {
        setAllFans(targetFraction: 0.75)
    }

    public func areAnyFansInManualMode() -> Bool {
        let count = getFanCount()
        guard count > 0 else { return false }
        return (0..<count).contains { (readInt(key: "F\($0)Md") ?? 0) != 0 }
    }

    private func setAllFans(targetFraction: Float) -> Bool {
        let count = getFanCount()
        var ok = true
        let targetFans = count > 0 ? count : 2

        for i in 0..<targetFans {
            let maxRPM = Float(getFanMaxRPM(fanIndex: i) ?? 6000) * targetFraction
            let mOk = setFanManualMode(fanIndex: i, manual: true)
            let sOk = setFanTargetRPM(fanIndex: i, rpm: maxRPM)
            if !mOk || !sOk {
                ok = false
            }
        }
        return ok
    }

    public func setAllFansAuto() -> Bool {
        let count = getFanCount()
        var ok = true
        let targetFans = count > 0 ? count : 2

        for i in 0..<targetFans {
            let mOk = setFanManualMode(fanIndex: i, manual: false)
            if !mOk {
                ok = false
            }
        }
        return ok
    }

    // MARK: - Helpers
    private func fourCharCode(from string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    private func fourCharCodeToString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
