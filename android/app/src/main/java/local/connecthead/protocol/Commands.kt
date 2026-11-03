package local.connecthead.protocol

/** A single command sent to the headphones. Payload byte 0 is the payload type. */
data class Request(val type: MessageType, val payload: List<Int>) {
    constructor(payload: List<Int>) : this(MessageType.COMMAND1, payload)
}

// ---- Setting value types ----

enum class NoiseMode(val label: String) {
    NOISE_CANCELLING("Noise Cancelling"), AMBIENT("Ambient Sound"), OFF("Off")
}

enum class EqPreset(val code: Int, val label: String) {
    OFF(0x00, "Off"), BRIGHT(0x10, "Bright"), EXCITED(0x11, "Excited"), MELLOW(0x12, "Mellow"),
    RELAXED(0x13, "Relaxed"), VOCAL(0x14, "Vocal"), TREBLE_BOOST(0x15, "Treble Boost"),
    BASS_BOOST(0x16, "Bass Boost"), SPEECH(0x17, "Speech"), MANUAL(0xa0, "Manual"),
    CUSTOM1(0xa1, "Custom 1"), CUSTOM2(0xa2, "Custom 2");

    companion object { fun of(code: Int) = entries.firstOrNull { it.code == code } }
}

enum class AutoPowerOff(val a: Int, val b: Int, val label: String) {
    OFF(0x11, 0x00, "Never"), AFTER_5_MIN(0x00, 0x00, "After 5 minutes"), AFTER_30_MIN(0x01, 0x01, "After 30 minutes"),
    AFTER_1_HOUR(0x02, 0x02, "After 1 hour"), AFTER_3_HOURS(0x03, 0x03, "After 3 hours"), WHEN_TAKEN_OFF(0x10, 0x00, "When taken off");

    companion object { fun of(a: Int, b: Int) = entries.firstOrNull { it.a == a && it.b == b } }
}

/** What the NC/AMBIENT button cycles through. */
enum class NcButtonMode(val code: Int, val label: String) {
    NC_AMBIENT_OFF(0x01, "NC → Ambient → Off"), NC_AMBIENT(0x02, "NC ↔ Ambient"),
    NC_OFF(0x03, "NC ↔ Off"), AMBIENT_OFF(0x04, "Ambient ↔ Off");

    companion object { fun of(code: Int) = entries.firstOrNull { it.code == code } }
}

enum class VoiceAssistant(val code: Int, val label: String) {
    OFF(0xff, "Off"), DEVICE(0x30, "Phone assistant"), GOOGLE(0x31, "Google Assistant"), ALEXA(0x32, "Amazon Alexa");

    companion object { fun of(code: Int) = entries.firstOrNull { it.code == code } }
}

enum class AudioCodec(val code: Int, val label: String) {
    UNKNOWN(0x00, "Unknown"), SBC(0x01, "SBC"), AAC(0x02, "AAC"), LDAC(0x10, "LDAC"), APTX(0x20, "aptX"), APTX_HD(0x21, "aptX HD");

    companion object { fun of(code: Int) = entries.firstOrNull { it.code == code } ?: UNKNOWN }
}

/** A phone/computer the headphones are paired with (from the multipoint device list). */
data class SourceDevice(val address: String, val name: String, val slot: Int, val classOfDevice: Int) {
    /** 0 = not connected, otherwise the connection slot (1, 2) the headphones assigned it. */
    val connected get() = slot != 0
    val isPhone get() = (classOfDevice shr 8) and 0x1f == 0x02
}

/**
 * Everything we know about the headphones. `null` means the device hasn't reported it (yet),
 * and the UI hides that control.
 */
data class HeadphoneState(
    val firmware: String? = null,
    val codec: AudioCodec? = null,
    val battery: Int? = null,
    val charging: Boolean = false,
    val noiseMode: NoiseMode? = null,
    val focusOnVoice: Boolean = false,
    val ambientLevel: Int = 10,
    val ncButtonMode: NcButtonMode? = null,
    val eqPreset: EqPreset? = null,
    val clearBass: Int = 0,
    val eqBands: List<Int> = listOf(0, 0, 0, 0, 0),
    /** The ULT WEAR puts an extra 0x01 after the preset in EQ messages, and expects it back. */
    val eqHasExtraByte: Boolean = false,
    val autoPowerOff: AutoPowerOff? = null,
    val pauseWhenTakenOff: Boolean? = null,
    val voiceGuidance: Boolean? = null,
    val voiceGuidanceVolume: Int? = null,
    val voiceAssistant: VoiceAssistant? = null,
    val dseeUpsampling: Boolean? = null,
    val preferSoundQuality: Boolean? = null,
    val multipoint: Boolean? = null,
    val captureVoiceDuringCall: Boolean? = null,
    val devices: List<SourceDevice>? = null,
    /** Address of the device currently allowed to play audio. */
    val playbackDevice: String? = null,
)

// ---- Requests (Sony protocol v2, as used by the WH-ULT900N) ----

object Commands {
    val initialize = Request(listOf(0x00, 0x00))

    val battery = Request(listOf(0x22, 0x00))
    val codec = Request(listOf(0x12, 0x02))

    // Multipoint device management lives in the second command family ("peripheral" commands,
    // as named by mos9527/SonyHeadphonesClient's libmdr). Inquired type 0x02 = with class of device.
    val deviceList = Request(MessageType.COMMAND2, listOf(0x36, 0x02))

    /** Queried right after the init handshake. */
    val initialQueries = listOf(
        Request(listOf(0x04, 0x02)),         // firmware version
        codec,
        battery,
        Request(listOf(0x66, 0x17)),         // ambient sound control
        Request(listOf(0xfa, 0x03)),         // NC/AMB button mode
        Request(listOf(0x56, 0x00)),         // equalizer
        Request(listOf(0x26, 0x05)),         // auto power off
        Request(listOf(0x26, 0x01)),         // pause when taken off
        Request(listOf(0xe6, 0x01)),         // DSEE upsampling
        Request(listOf(0xe6, 0x02)),         // connection quality (LDAC)
        Request(listOf(0xf6, 0x04)),         // voice assistant
        Request(listOf(0xd6, 0xd1)),         // multipoint
        Request(listOf(0xd6, 0xd3)),         // capture voice during call
        Request(MessageType.COMMAND2, listOf(0x46, 0x01)), // voice guidance on/off
        Request(MessageType.COMMAND2, listOf(0x46, 0x20)), // voice guidance volume
        deviceList,
    )

    fun ambientSound(mode: NoiseMode, focusOnVoice: Boolean, level: Int) = Request(listOf(
        0x68, 0x17, 0x01,
        if (mode == NoiseMode.OFF) 0x00 else 0x01,
        if (mode == NoiseMode.AMBIENT) 0x01 else 0x00,
        if (focusOnVoice) 0x01 else 0x00,
        level.coerceIn(0, 255),
    ))

    fun ncButtonMode(mode: NcButtonMode) = Request(listOf(0xfc, 0x03, 0x01, 0x00, 0x01, 0x00, mode.code))

    fun eqPreset(preset: EqPreset, extraByte: Boolean) =
        Request(listOf(0x58, 0x00, preset.code) + (if (extraByte) listOf(0x01) else emptyList()) + 0x00)

    fun eqBands(clearBass: Int, bands: List<Int>, extraByte: Boolean) =
        Request(listOf(0x58, 0x00, 0xa0) + (if (extraByte) listOf(0x01) else emptyList()) + 0x06 +
            (listOf(clearBass) + bands).map { (it + 10).coerceIn(0, 255) })

    fun autoPowerOff(v: AutoPowerOff) = Request(listOf(0x28, 0x05, v.a, v.b))

    // Many v2 toggles use 0x00 for "on" and 0x01 for "off".
    fun pauseWhenTakenOff(on: Boolean) = Request(listOf(0xf8, 0x01, if (on) 0x00 else 0x01))
    fun dseeUpsampling(on: Boolean) = Request(listOf(0xe8, 0x01, if (on) 0x01 else 0x00))
    fun preferSoundQuality(on: Boolean) = Request(listOf(0xe8, 0x02, if (on) 0x00 else 0x01))
    fun captureVoiceDuringCall(on: Boolean) = Request(listOf(0xd8, 0xd3, 0x00, if (on) 0x00 else 0x01))
    fun voiceGuidance(on: Boolean) = Request(MessageType.COMMAND2, listOf(0x48, 0x01, if (on) 0x00 else 0x01))
    fun voiceGuidanceVolume(v: Int) = Request(MessageType.COMMAND2, listOf(0x48, 0x20, v.coerceIn(-128, 127) and 0xff, 0x00))
    fun voiceAssistant(va: VoiceAssistant) = Request(listOf(0xf8, 0x04, va.code))

    /** Multipoint is toggled via the 0xd1 touch-sensor slot and then committed. */
    fun multipoint(on: Boolean) = listOf(
        Request(listOf(0xd8, 0xd1, 0x00, if (on) 0x00 else 0x01)),
        Request(listOf(0x98, 0x00, 0x06, 0x01)),
    )

    val powerOff = Request(listOf(0x24, 0x03, 0x01))

    private fun ascii(s: String) = s.toByteArray(Charsets.UTF_8).map { it.toInt() and 0xff }
    fun connectDevice(address: String) = Request(MessageType.COMMAND2, listOf(0x3c, 0x02, 0x01) + ascii(address))
    fun disconnectDevice(address: String) = Request(MessageType.COMMAND2, listOf(0x3c, 0x02, 0x00) + ascii(address))
    /** Hands the audio "playback right" to another connected device. */
    fun playFrom(address: String) = Request(MessageType.COMMAND2, listOf(0x3c, 0x01) + ascii(address))
}

// ---- Responses ----

/** Applies a reply or notification. Returns the updated state, or null if it wasn't understood. */
fun HeadphoneState.apply(type: MessageType, p: List<Int>): HeadphoneState? {
    val kind = p.firstOrNull() ?: return null

    if (type == MessageType.COMMAND2) {
        if (kind == 0x37 || kind == 0x39) return applyDeviceList(p)
        if ((kind != 0x47 && kind != 0x49) || p.size < 3) return null
        return when (p[1]) {
            0x01 -> copy(voiceGuidance = p[2] == 0x00)
            0x20 -> copy(voiceGuidanceVolume = p[2].toByte().toInt())
            else -> null
        }
    }

    return when (kind) {
        0x05 -> {
            if (p.size < 3 || p[1] != 0x02) return null
            val len = p[2]
            if (p.size < 3 + len) return null
            copy(firmware = String(ByteArray(len) { p[3 + it].toByte() }, Charsets.US_ASCII))
        }
        0x13, 0x15 -> if (p.size == 3 && p[1] == 0x02) copy(codec = AudioCodec.of(p[2])) else null
        0x23, 0x25 -> if (p.size >= 4 && p[1] == 0x00) copy(battery = p[2], charging = p[3] == 0x01) else null
        0x27, 0x29 -> when {
            p.size == 4 && p[1] == 0x05 -> copy(autoPowerOff = AutoPowerOff.of(p[2], p[3]))
            p.size == 3 && p[1] == 0x01 -> copy(pauseWhenTakenOff = p[2] == 0x00)
            else -> null
        }
        0x57, 0x59 -> {
            // 57 00 <preset> [01 on the ULT WEAR] 06 <clear bass> <5 bands>: the values are always last.
            if (p.size < 10 || p[p.size - 7] != 0x06) return null
            val values = p.takeLast(6).map { it - 10 }
            copy(eqPreset = EqPreset.of(p[2]), eqHasExtraByte = p.size == 11, clearBass = values[0], eqBands = values.drop(1))
        }
        0x67, 0x69 -> applyAmbient(p)
        0xd7, 0xd9 -> {
            if (p.size != 4) return null
            val on = p[3] == 0x00
            when (p[1]) {
                0xd1 -> copy(multipoint = on)
                0xd3 -> copy(captureVoiceDuringCall = on)
                else -> null
            }
        }
        0xe7, 0xe9 -> {
            if (p.size != 3) return null
            when (p[1]) {
                0x01 -> copy(dseeUpsampling = p[2] == 0x01)
                0x02 -> copy(preferSoundQuality = p[2] == 0x00)
                else -> null
            }
        }
        0xf7, 0xf9 -> {
            if (p.size < 3) return null
            when (p[1]) {
                0x01 -> copy(pauseWhenTakenOff = p[2] == 0x00)
                0x04 -> copy(voiceAssistant = VoiceAssistant.of(p[2]))
                else -> null
            }
        }
        0xfb, 0xfd -> if (p.size == 7 && p[1] == 0x03) copy(ncButtonMode = NcButtonMode.of(p[6])) else null
        else -> null
    }
}

/**
 * 37/39 02 <count> { <17-byte address> <slot> <class of device, 3 BE> <len> <name> }… <playing slot>
 * The trailing byte is the connection slot of the device that has the audio, not a list index.
 */
private fun HeadphoneState.applyDeviceList(p: List<Int>): HeadphoneState? {
    if (p.size < 3 || p[1] != 0x02) return null
    val list = mutableListOf<SourceDevice>()
    var i = 3
    repeat(p[2]) {
        if (i + 22 > p.size) return null
        val address = String(ByteArray(17) { p[i + it].toByte() }, Charsets.UTF_8)
        val slot = p[i + 17]
        val cod = p[i + 18] shl 16 or (p[i + 19] shl 8) or p[i + 20]
        val nameLength = p[i + 21]
        i += 22
        if (i + nameLength > p.size) return null
        val name = String(ByteArray(nameLength) { p[i + it].toByte() }, Charsets.UTF_8)
        i += nameLength
        list += SourceDevice(address, name, slot, cod)
    }
    val playingSlot = if (i < p.size) p[i] else 0
    return copy(devices = list, playbackDevice = if (playingSlot == 0) null else list.firstOrNull { it.slot == playingSlot }?.address)
}

private fun HeadphoneState.applyAmbient(p: List<Int>): HeadphoneState? {
    if (p.size !in 6..8 || p[1] !in listOf(0x15, 0x17, 0x22)) return null
    val hasWindMode = p[1] == 0x17 && p.size > 7
    val mode = when {
        p[3] == 0x00 -> NoiseMode.OFF
        p[1] == 0x22 -> NoiseMode.AMBIENT
        hasWindMode && p[5] != 0x02 -> NoiseMode.NOISE_CANCELLING // wind noise reduction; treat as NC
        else -> if (p[4] == 0x01) NoiseMode.AMBIENT else NoiseMode.NOISE_CANCELLING
    }
    return copy(noiseMode = mode, focusOnVoice = p[p.size - 2] == 0x01, ambientLevel = p[p.size - 1])
}
