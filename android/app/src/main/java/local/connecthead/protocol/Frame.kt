package local.connecthead.protocol

/**
 * Sony headphone wire framing (reverse-engineered by the Gadgetbridge project).
 *
 *   0x3e | type | seq | len (u32 BE) | payload | checksum | 0x3c
 *
 * Everything between header and trailer is escaped: 0x3c/0x3d/0x3e become 0x3d, (b & 0xef).
 * The checksum is the 8-bit sum of type, seq, len and payload.
 */
enum class MessageType(val code: Int) {
    ACK(0x01), COMMAND1(0x0c), COMMAND2(0x0e);

    companion object {
        fun of(code: Int) = entries.firstOrNull { it.code == code }
    }
}

data class Frame(val type: MessageType, val seq: Int, val payload: List<Int>) {

    fun encode(): ByteArray {
        val len = payload.size
        val body = mutableListOf(type.code, seq, len ushr 24 and 0xff, len ushr 16 and 0xff, len ushr 8 and 0xff, len and 0xff)
        body += payload
        body += checksum(body)
        val out = mutableListOf(HEADER)
        out += escaped(body)
        out += TRAILER
        return ByteArray(out.size) { out[it].toByte() }
    }

    companion object {
        const val HEADER = 0x3e
        const val TRAILER = 0x3c
        const val ESCAPE = 0x3d
        const val ESCAPE_MASK = 0xef

        /** Decodes one complete raw frame (header and trailer included). */
        fun decode(raw: List<Int>): Frame? {
            if (raw.size < 2 || raw.first() != HEADER || raw.last() != TRAILER) return null
            val body = unescaped(raw.subList(1, raw.size - 1))
            if (body.size < 7) return null
            if (checksum(body.dropLast(1)) != body.last()) return null
            val len = body[2] shl 24 or (body[3] shl 16) or (body[4] shl 8) or body[5]
            val type = MessageType.of(body[0]) ?: return null
            if (len != body.size - 7) return null
            return Frame(type, body[1], body.subList(6, 6 + len).toList())
        }

        fun checksum(bytes: List<Int>): Int = bytes.sum() and 0xff

        fun escaped(bytes: List<Int>): List<Int> = buildList {
            for (b in bytes) {
                if (b == HEADER || b == TRAILER || b == ESCAPE) { add(ESCAPE); add(b and ESCAPE_MASK) } else add(b)
            }
        }

        fun unescaped(bytes: List<Int>): List<Int> = buildList {
            var i = 0
            while (i < bytes.size) {
                if (bytes[i] == ESCAPE && i + 1 < bytes.size) {
                    add(bytes[i + 1] or (ESCAPE_MASK.inv() and 0xff))
                    i += 2
                } else {
                    add(bytes[i]); i++
                }
            }
        }
    }
}

/** Splits an RFCOMM byte stream into frames; data can arrive fragmented or batched. */
class FrameParser {
    private val buffer = ArrayList<Int>()

    fun feed(bytes: ByteArray, count: Int = bytes.size): List<Frame> {
        for (i in 0 until count) buffer += bytes[i].toInt() and 0xff
        val frames = mutableListOf<Frame>()
        while (true) {
            val start = buffer.indexOf(Frame.HEADER)
            if (start < 0) { buffer.clear(); break }
            val end = buffer.subList(start, buffer.size).indexOf(Frame.TRAILER).let { if (it < 0) -1 else it + start }
            if (end < 0) { repeat(start) { buffer.removeAt(0) }; break }
            Frame.decode(buffer.subList(start, end + 1))?.let { frames += it }
            buffer.subList(0, end + 1).clear()
        }
        return frames
    }
}
