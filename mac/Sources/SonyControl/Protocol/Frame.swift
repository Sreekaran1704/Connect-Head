import Foundation

/// Sony headphone wire framing (reverse-engineered by the Gadgetbridge project).
///
///   0x3e | type | seq | len (u32 BE) | payload | checksum | 0x3c
///
/// Everything between header and trailer is escaped: 0x3c/0x3d/0x3e become 0x3d, (b & 0xef).
/// The checksum is the 8-bit sum of type, seq, len and payload.
enum MessageType: UInt8 {
    case ack = 0x01
    case command1 = 0x0c
    case command2 = 0x0e
}

struct Frame: Equatable {
    static let header: UInt8 = 0x3e
    static let trailer: UInt8 = 0x3c
    static let escape: UInt8 = 0x3d
    static let escapeMask: UInt8 = 0xef

    let type: MessageType
    let seq: UInt8
    let payload: [UInt8]

    func encode() -> [UInt8] {
        let len = UInt32(payload.count)
        var body: [UInt8] = [type.rawValue, seq,
                             UInt8(len >> 24 & 0xff), UInt8(len >> 16 & 0xff),
                             UInt8(len >> 8 & 0xff), UInt8(len & 0xff)]
        body += payload
        body.append(Frame.checksum(body))
        return [Frame.header] + Frame.escaped(body) + [Frame.trailer]
    }

    /// Decodes one complete raw frame (header and trailer included).
    static func decode(_ raw: [UInt8]) -> Frame? {
        guard raw.count >= 2, raw.first == header, raw.last == trailer else { return nil }
        let body = unescaped(Array(raw[1..<(raw.count - 1)]))
        guard body.count >= 7 else { return nil }
        guard checksum(body.dropLast()) == body.last else { return nil }
        let len = Int(body[2]) << 24 | Int(body[3]) << 16 | Int(body[4]) << 8 | Int(body[5])
        guard len == body.count - 7, let type = MessageType(rawValue: body[0]) else { return nil }
        return Frame(type: type, seq: body[1], payload: Array(body[6..<(6 + len)]))
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    static func escaped(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        for b in bytes {
            if b == header || b == trailer || b == escape {
                out += [escape, b & escapeMask]
            } else {
                out.append(b)
            }
        }
        return out
    }

    static func unescaped(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == escape, i + 1 < bytes.count {
                out.append(bytes[i + 1] | ~escapeMask)
                i += 2
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return out
    }
}

/// Splits an RFCOMM byte stream into raw frames; data can arrive fragmented or batched.
struct FrameParser {
    private var buffer: [UInt8] = []

    mutating func feed(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while let start = buffer.firstIndex(of: Frame.header) {
            guard let end = buffer[start...].firstIndex(of: Frame.trailer) else {
                buffer.removeFirst(start)
                return frames
            }
            if let frame = Frame.decode(Array(buffer[start...end])) {
                frames.append(frame)
            }
            buffer.removeFirst(end + 1)
        }
        buffer.removeAll()
        return frames
    }
}
