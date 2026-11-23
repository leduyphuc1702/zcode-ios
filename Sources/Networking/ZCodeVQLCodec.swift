import Foundation

/// Represents any value encoded/decoded by ZCode Server's binary VQL serializer (`server-core.js`).
public enum VQLValue: Equatable {
    case undefined
    case string(String)
    case buffer(Data)
    case vsBuffer(Data)
    case array([VQLValue])
    case objectJSON(String)
    case int32(Int32)

    public static func bool(_ value: Bool) -> VQLValue {
        .objectJSON(value ? "true" : "false")
    }

    public static func fromJSONObject(_ dict: [String: Any]) -> VQLValue {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return .objectJSON("{}")
        }
        return .objectJSON(str)
    }

    public func decodeJSONDictionary() -> [String: Any]? {
        guard case .objectJSON(let json) = self,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    public func decodeJSONValue() -> Any? {
        switch self {
        case .undefined:
            return nil
        case .string(let s):
            return s
        case .int32(let i):
            return Int(i)
        case .buffer(let b), .vsBuffer(let b):
            return b
        case .array(let items):
            return items.map { $0.decodeJSONValue() ?? NSNull() }
        case .objectJSON(let json):
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }
}

/// Exact byte-level implementation of ZCode v3.16.3 `SocketProtocol` (13-byte BE) + `VQL` codec + IEEE CRC32.
public enum ZCodeVQLCodec {

    // MARK: - 7-bit Unsigned LEB128 (`writeInt32VQL` / `readIntVQL`)

    public static func writeUInt32VQL(_ value: UInt32, into data: inout Data) {
        var v = value
        while true {
            let byte = UInt8(v & 0x7F)
            v >>= 7
            if v == 0 {
                data.append(byte)
                break
            } else {
                data.append(byte | 0x80)
            }
        }
    }

    public static func readUInt32VQL(from data: Data, offset: inout Int) throws -> UInt32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while true {
            guard offset < data.count else {
                throw VQLCodecError.truncatedBuffer
            }
            let next = data[offset]
            offset += 1
            result |= UInt32(next & 0x7F) << shift
            if (next & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 35 {
                throw VQLCodecError.invalidVarint
            }
        }
    }

    // MARK: - Value Serialization (`DataType` tags 0..6)

    public static func encode(_ value: VQLValue, into data: inout Data) {
        switch value {
        case .undefined:
            data.append(0)
        case .string(let s):
            data.append(1)
            let utf8 = Data(s.utf8)
            writeUInt32VQL(UInt32(utf8.count), into: &data)
            data.append(utf8)
        case .buffer(let buf):
            data.append(2)
            writeUInt32VQL(UInt32(buf.count), into: &data)
            data.append(buf)
        case .vsBuffer(let buf):
            data.append(3)
            writeUInt32VQL(UInt32(buf.count), into: &data)
            data.append(buf)
        case .array(let items):
            data.append(4)
            writeUInt32VQL(UInt32(items.count), into: &data)
            for item in items {
                encode(item, into: &data)
            }
        case .objectJSON(let json):
            data.append(5)
            let utf8 = Data(json.utf8)
            writeUInt32VQL(UInt32(utf8.count), into: &data)
            data.append(utf8)
        case .int32(let i):
            data.append(6)
            writeUInt32VQL(UInt32(bitPattern: i), into: &data)
        }
    }

    public static func decode(from data: Data, offset: inout Int) throws -> VQLValue {
        guard offset < data.count else {
            throw VQLCodecError.truncatedBuffer
        }
        let tag = data[offset]
        offset += 1

        switch tag {
        case 0:
            return .undefined
        case 1:
            let len = Int(try readUInt32VQL(from: data, offset: &offset))
            guard offset + len <= data.count else { throw VQLCodecError.truncatedBuffer }
            let slice = data.subdata(in: offset..<(offset + len))
            offset += len
            return .string(String(decoding: slice, as: UTF8.self))
        case 2:
            let len = Int(try readUInt32VQL(from: data, offset: &offset))
            guard offset + len <= data.count else { throw VQLCodecError.truncatedBuffer }
            let slice = data.subdata(in: offset..<(offset + len))
            offset += len
            return .buffer(slice)
        case 3:
            let len = Int(try readUInt32VQL(from: data, offset: &offset))
            guard offset + len <= data.count else { throw VQLCodecError.truncatedBuffer }
            let slice = data.subdata(in: offset..<(offset + len))
            offset += len
            return .vsBuffer(slice)
        case 4:
            let count = Int(try readUInt32VQL(from: data, offset: &offset))
            var arr: [VQLValue] = []
            arr.reserveCapacity(min(count, 1024))
            for _ in 0..<count {
                arr.append(try decode(from: data, offset: &offset))
            }
            return .array(arr)
        case 5:
            let len = Int(try readUInt32VQL(from: data, offset: &offset))
            guard offset + len <= data.count else { throw VQLCodecError.truncatedBuffer }
            let slice = data.subdata(in: offset..<(offset + len))
            offset += len
            return .objectJSON(String(decoding: slice, as: UTF8.self))
        case 6:
            let raw = try readUInt32VQL(from: data, offset: &offset)
            return .int32(Int32(bitPattern: raw))
        default:
            throw VQLCodecError.unknownTag(tag)
        }
    }

    // MARK: - SocketProtocol 13-byte Big-Endian Frame

    public static func wrapSocketFrame(payload: Data, type: UInt8 = 1, id: UInt32 = 0, ack: UInt32 = 0) -> Data {
        var frame = Data(capacity: 13 + payload.count)
        frame.append(type)
        appendUInt32BE(id, into: &frame)
        appendUInt32BE(ack, into: &frame)
        appendUInt32BE(UInt32(payload.count), into: &frame)
        frame.append(payload)
        return frame
    }

    public static func unwrapSocketFrame(_ frame: Data) throws -> (type: UInt8, id: UInt32, ack: UInt32, payload: Data) {
        guard frame.count >= 13 else {
            throw VQLCodecError.invalidFrameHeader
        }
        let type = frame[0]
        let id = readUInt32BE(frame, at: 1)
        let ack = readUInt32BE(frame, at: 5)
        let length = Int(readUInt32BE(frame, at: 9))
        guard frame.count >= 13 + length else {
            throw VQLCodecError.truncatedBuffer
        }
        let payload = frame.subdata(in: 13..<(13 + length))
        return (type, id, ack, payload)
    }

    public static func buildRawRPCRequestPayload(id: Int32, channel: String, method: String, args: [VQLValue]) -> Data {
        var rpcPayload = Data()
        let header: VQLValue = .array([
            .int32(100),
            .int32(id),
            .string(channel),
            .string(method)
        ])
        encode(header, into: &rpcPayload)
        encode(.array(args), into: &rpcPayload)
        return rpcPayload
    }

    public static func buildRawRPCEventListenPayload(id: Int32, channel: String, event: String, arg: VQLValue = .undefined) -> Data {
        var rpcPayload = Data()
        let header: VQLValue = .array([
            .int32(102),
            .int32(id),
            .string(channel),
            .string(event)
        ])
        encode(header, into: &rpcPayload)
        encode(arg, into: &rpcPayload)
        return rpcPayload
    }

    public static func buildRPCRequestFrame(id: Int32, channel: String, method: String, args: [VQLValue]) -> Data {
        wrapSocketFrame(payload: buildRawRPCRequestPayload(id: id, channel: channel, method: method, args: args))
    }

    public static func buildRPCEventListenFrame(id: Int32, channel: String, event: String, arg: VQLValue = .undefined) -> Data {
        wrapSocketFrame(payload: buildRawRPCEventListenPayload(id: id, channel: channel, event: event, arg: arg))
    }

    // MARK: - IEEE 802.3 CRC32 (for Cloud Relay V2 `rpc-frame` checksum)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func crc32Hex(_ data: Data) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[idx] ^ (crc >> 8)
        }
        return String(format: "%08x", crc ^ 0xFFFFFFFF)
    }

    private static func appendUInt32BE(_ v: UInt32, into data: inout Data) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }
}

public enum VQLCodecError: Error, LocalizedError {
    case truncatedBuffer
    case invalidVarint
    case unknownTag(UInt8)
    case invalidFrameHeader

    public var errorDescription: String? {
        switch self {
        case .truncatedBuffer: return "Truncated binary VQL frame"
        case .invalidVarint: return "Malformed VQL 7-bit integer"
        case .unknownTag(let t): return "Unsupported VQL tag \(t)"
        case .invalidFrameHeader: return "SocketProtocol frame shorter than 13 bytes"
        }
    }
}
