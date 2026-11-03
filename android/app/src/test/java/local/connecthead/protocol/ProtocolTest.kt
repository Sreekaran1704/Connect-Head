package local.connecthead.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class ProtocolTest {
    private fun bytes(hex: String) = hex.split(" ").map { it.toInt(16) }

    @Test fun frameRoundTripsWithEscapes() {
        // Payload containing all three reserved bytes.
        val frame = Frame(MessageType.COMMAND1, 1, listOf(0x3c, 0x3d, 0x3e, 0x10))
        val encoded = frame.encode()
        val parsed = FrameParser().feed(encoded)
        assertEquals(listOf(frame), parsed)
    }

    @Test fun parserHandlesFragmentsAndBatches() {
        val a = Frame(MessageType.ACK, 0, emptyList()).encode()
        val b = Frame(MessageType.COMMAND1, 1, listOf(0x23, 0x00, 0x39, 0x00)).encode()
        val parser = FrameParser()
        val all = a + b
        val first = parser.feed(all.copyOfRange(0, 5))
        val rest = parser.feed(all.copyOfRange(5, all.size))
        assertEquals(2, first.size + rest.size)
    }

    @Test fun parsesUltWearEqWithExtraByte() {
        val s = HeadphoneState().apply(MessageType.COMMAND1, bytes("57 00 a0 01 06 11 0d 0b 08 0c 0f"))
        assertNotNull(s)
        assertEquals(EqPreset.MANUAL, s!!.eqPreset)
        assertEquals(true, s.eqHasExtraByte)
        assertEquals(7, s.clearBass)
        assertEquals(listOf(3, 1, -2, 2, 5), s.eqBands)
        // And the write mirrors it.
        assertEquals(bytes("58 00 a0 01 06 11 0d 0b 08 0c 0f"),
            Commands.eqBands(7, listOf(3, 1, -2, 2, 5), extraByte = true).payload)
    }

    @Test fun parsesBatteryAndAmbient() {
        var s = HeadphoneState().apply(MessageType.COMMAND1, bytes("23 00 39 01"))!!
        assertEquals(57, s.battery); assertEquals(true, s.charging)
        s = s.apply(MessageType.COMMAND1, bytes("67 17 01 01 01 01 0c"))!!
        assertEquals(NoiseMode.AMBIENT, s.noiseMode); assertEquals(12, s.ambientLevel)
    }

    @Test fun parsesDeviceListPlayingSlot() {
        val addr = "7C:F0:E5:B3:44:B8".map { it.code }
        val name = "Nord".map { it.code }
        val payload = listOf(0x37, 0x02, 0x01) + addr + listOf(0x02, 0x7a, 0x42, 0x0c, name.size) + name + listOf(0x02)
        val s = HeadphoneState().apply(MessageType.COMMAND2, payload)!!
        assertEquals("Nord", s.devices!!.single().name)
        assertEquals(true, s.devices!!.single().isPhone)
        assertEquals("7C:F0:E5:B3:44:B8", s.playbackDevice)
    }
}
