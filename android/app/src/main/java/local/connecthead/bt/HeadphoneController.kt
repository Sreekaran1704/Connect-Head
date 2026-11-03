package local.connecthead.bt

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import local.connecthead.protocol.Commands
import local.connecthead.protocol.EqPreset
import local.connecthead.protocol.Frame
import local.connecthead.protocol.FrameParser
import local.connecthead.protocol.HeadphoneState
import local.connecthead.protocol.MessageType
import local.connecthead.protocol.NoiseMode
import local.connecthead.protocol.Request
import local.connecthead.protocol.SourceDevice
import local.connecthead.protocol.VoiceAssistant
import local.connecthead.protocol.apply
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

/**
 * Owns the RFCOMM link to the headphones, runs the one-request-at-a-time ACK queue, and
 * publishes state. Mirrors the Mac app's controller: replies to the initial queries collect
 * off-screen and are published in one go, so the UI appears complete instead of filling in.
 */
class HeadphoneController(private val context: Context) {
    /** ELSEWHERE: the headphones are on but another device (the Mac app) holds their one control link. */
    enum class Status { CONNECTING, CONNECTED, DISCONNECTED, ELSEWHERE, NO_DEVICE, NO_PERMISSION, FAILED }

    data class Ui(
        val status: Status = Status.CONNECTING,
        val deviceName: String? = null,
        val deviceAddress: String? = null,
        val state: HeadphoneState = HeadphoneState(),
        val loaded: Boolean = false,
        val message: String? = null,
    ) {
        val ready get() = status == Status.CONNECTED && loaded
    }

    private val _ui = MutableStateFlow(Ui())
    val ui: StateFlow<Ui> = _ui

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Connect Head on the Mac. The headphones allow one control link, so when the Mac holds it
     * this app reads the state from the Mac and relays its commands through it (both apps keep
     * working); it only takes the link itself when the Mac isn't reachable.
     */
    var mac: local.connecthead.media.RemoteNowPlaying? = null
    /** Set by the activity: only take over or relay while the app is on screen. */
    @Volatile var foreground = false
    private var relay: Job? = null
    @Volatile private var lastLocalChange = 0L
    val relaying get() = relay?.isActive == true
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val prefs = context.getSharedPreferences("connecthead", Context.MODE_PRIVATE)

    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private val writeLock = Any()
    private var link: Job? = null
    private var queue = Channel<Request>(Channel.UNLIMITED)
    private var ack: CompletableDeferred<Unit>? = null
    private var initReply: CompletableDeferred<Unit>? = null
    @Volatile private var seq = 0
    @Volatile private var closingOnPurpose = false
    private var a2dp: android.bluetooth.BluetoothA2dp? = null
    @Volatile private var loading = HeadphoneState()

    init {
        // Kept to tell "headphones off" from "another device took the controls" when the link drops.
        try {
            adapter?.getProfileProxy(context, object : android.bluetooth.BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: android.bluetooth.BluetoothProfile) { a2dp = proxy as android.bluetooth.BluetoothA2dp }
                override fun onServiceDisconnected(profile: Int) { a2dp = null }
            }, android.bluetooth.BluetoothProfile.A2DP)
        } catch (_: SecurityException) {}
        // Reconnect when the headphones come back (turned on, back in range).
        val filter = IntentFilter(BluetoothDevice.ACTION_ACL_CONNECTED)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                val device = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                              else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)) ?: return
                if (socket == null && device.address == preferredDevice()?.address) {
                    scope.launch { delay(2000); connect() }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else context.registerReceiver(receiver, filter)
    }

    fun hasPermission() = Build.VERSION.SDK_INT < 31 ||
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun pairedDevices(): List<BluetoothDevice> =
        if (hasPermission()) adapter?.bondedDevices?.sortedBy { it.name ?: "" } ?: emptyList() else emptyList()

    @SuppressLint("MissingPermission")
    private fun preferredDevice(): BluetoothDevice? {
        val paired = pairedDevices()
        prefs.getString("device", null)?.let { saved -> paired.firstOrNull { it.address == saved }?.let { return it } }
        return paired.firstOrNull { d -> listOf("ULT", "WH-", "WF-", "SONY").any { (d.name ?: "").uppercase().contains(it) } }
    }

    /** The headphones' Bluetooth address: also the key the Mac asks for before it shares anything. */
    fun headphonesAddress(): String? = _ui.value.deviceAddress ?: preferredDevice()?.address

    fun select(device: BluetoothDevice) {
        prefs.edit().putString("device", device.address).apply()
        disconnect()
        connect()
    }

    // ---- Connection ----

    @SuppressLint("MissingPermission")
    fun connect() {
        if (link?.isActive == true || relaying || waiting?.isActive == true) return
        if (mac?.available == true) { startRelay(fallBackToDirect = true); return }
        // Just opened: give the network a moment to find the Mac before taking the link from it.
        waiting = scope.launch {
            val until = System.currentTimeMillis() + 2500
            while (mac?.available != true && System.currentTimeMillis() < until) delay(100)
            if (link?.isActive == true || relaying) return@launch
            if (mac?.available == true) startRelay(fallBackToDirect = true) else connectSocket()
        }
    }
    private var waiting: Job? = null

    @SuppressLint("MissingPermission")
    private fun connectSocket() {
        if (!hasPermission()) { _ui.update { it.copy(status = Status.NO_PERMISSION) }; return }
        val device = preferredDevice() ?: run { _ui.update { it.copy(status = Status.NO_DEVICE) }; return }
        // Falling back from the relay: keep showing the current state rather than a connecting screen.
        if (!_ui.value.ready) _ui.update { it.copy(status = Status.CONNECTING, deviceName = device.name, deviceAddress = device.address, loaded = false, message = null) }

        link = scope.launch {
            val s = openSocket(device) ?: run {
                _ui.update { it.copy(status = Status.FAILED, message = "Headphones not reachable. Turn them on and try again.") }
                return@launch
            }
            socket = s
            output = s.outputStream
            queue = Channel(Channel.UNLIMITED)
            seq = 0
            loading = HeadphoneState()
            _ui.update { it.copy(status = Status.CONNECTED) }

            val reader = launch { readLoop(s) }
            if (!handshake()) {
                _ui.update { it.copy(status = Status.FAILED, message = "Headphones didn't answer. Close the Sony app and retry.") }
                closeSocket()
                return@launch
            }
            launch { sendLoop() }
            Commands.initialQueries.forEach { queue.send(it) }
            // Publish once the initial replies are in (or after a timeout if one never answers).
            launch {
                withTimeoutOrNull(6000) { while (!queue.isEmpty || ack != null) delay(50) }
                delay(300)
                finishLoading()
            }
            launch {
                while (isActive) {
                    delay(60_000)
                    queue.send(Commands.battery); queue.send(Commands.codec)
                }
            }
            reader.join()
        }
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(device: BluetoothDevice): BluetoothSocket? {
        // Discovery slows RFCOMM down, but cancelling it needs the scan permission on Android 12+.
        try { adapter?.cancelDiscovery() } catch (_: SecurityException) {}
        // The first attempt right after the headphones connect often times out; try v2 twice.
        for (uuid in listOf(SERVICE_UUIDS[0]) + SERVICE_UUIDS) {
            try {
                val s = device.createRfcommSocketToServiceRecord(uuid)
                s.connect()
                Log.i(TAG, "connected via $uuid")
                return s
            } catch (e: IOException) {
                Log.w(TAG, "RFCOMM $uuid failed: ${e.message}")
            } catch (e: SecurityException) {
                Log.w(TAG, "RFCOMM $uuid not permitted: ${e.message}")
            }
        }
        return null
    }

    /** The headphones sometimes ignore the first init, so retry a few times. */
    private suspend fun handshake(): Boolean {
        repeat(4) {
            val reply = CompletableDeferred<Unit>()
            initReply = reply
            write(Frame(MessageType.COMMAND1, seq, Commands.initialize.payload))
            if (withTimeoutOrNull(1500) { reply.await() } != null) return true
        }
        return false
    }

    private suspend fun sendLoop() {
        for (request in queue) {
            val waiter = CompletableDeferred<Unit>()
            ack = waiter
            Log.d(TAG, "→ ${request.type} ${hex(request.payload)}")
            write(Frame(request.type, seq, request.payload))
            if (withTimeoutOrNull(2000) { waiter.await() } == null) Log.w(TAG, "ACK timeout, moving on")
            ack = null
        }
    }

    private fun readLoop(s: BluetoothSocket) {
        val parser = FrameParser()
        val buffer = ByteArray(1024)
        try {
            val input = s.inputStream
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                parser.feed(buffer, n).forEach(::handle)
            }
        } catch (e: IOException) {
            Log.i(TAG, "link closed: ${e.message}")
        }
        closeSocket()
        val elsewhere = !closingOnPurpose && headphonesStillOn()
        closingOnPurpose = false
        if (relaying) return   // handed over to the Mac; the relay owns the screen now
        _ui.update { it.copy(status = if (elsewhere) Status.ELSEWHERE else Status.DISCONNECTED, loaded = false) }
    }

    @SuppressLint("MissingPermission")
    private fun headphonesStillOn(): Boolean = try {
        val d = preferredDevice()
        d != null && a2dp?.getConnectionState(d) == android.bluetooth.BluetoothProfile.STATE_CONNECTED
    } catch (_: SecurityException) { false }

    private fun handle(frame: Frame) {
        when (frame.type) {
            MessageType.ACK -> {
                seq = frame.seq
                ack?.complete(Unit)
            }
            MessageType.COMMAND1, MessageType.COMMAND2 -> {
                write(Frame(MessageType.ACK, (1 - frame.seq) and 0xff, emptyList()))
                val p = frame.payload
                Log.d(TAG, "← ${frame.type} ${hex(p)}")
                when {
                    frame.type == MessageType.COMMAND1 && p.firstOrNull() == 0x01 && initReply?.isCompleted == false ->
                        initReply?.complete(Unit)
                    frame.type == MessageType.COMMAND2 && p.firstOrNull() == 0x3d ->
                        queue.trySend(Commands.deviceList)   // a device (dis)connected: refresh the list
                    _ui.value.loaded -> _ui.value.state.apply(frame.type, p)?.let { s -> _ui.update { it.copy(state = s) } }
                    else -> loading.apply(frame.type, p)?.let { loading = it }
                }
            }
        }
    }

    private fun finishLoading() {
        if (_ui.value.loaded || socket == null) return
        _ui.update { it.copy(state = loading, loaded = true) }
    }

    private fun write(frame: Frame) {
        synchronized(writeLock) {
            try { output?.write(frame.encode()); output?.flush() } catch (e: IOException) { Log.w(TAG, "write failed: ${e.message}") }
        }
    }

    private fun closeSocket() {
        try { socket?.close() } catch (_: IOException) {}
        socket = null
        output = null
        queue.close()
    }

    fun disconnect() {
        closingOnPurpose = true
        link?.cancel()
        closeSocket()
        _ui.update { it.copy(status = Status.DISCONNECTED, loaded = false) }
    }

    // ---- Relay through the Mac ----

    /** The Mac appeared on the network: if we hold the link ourselves, hand it over and relay. */
    fun macFound() {
        if (!foreground || relaying) return
        if (socket != null) {
            // Hand over quietly: the screen keeps showing the current state until the relay takes over.
            closingOnPurpose = true
            link?.cancel()
            closeSocket()
            mac?.control("handback")
        }
        startRelay(fallBackToDirect = true)
    }

    private fun startRelay(fallBackToDirect: Boolean) {
        val m = mac ?: return
        relay = scope.launch {
            var misses = 0
            var askedBack = false
            while (isActive) {
                val json = m.headphones()
                when {
                    json?.optBoolean("connected") == true -> {
                        misses = 0; askedBack = true
                        val name = json.optString("deviceName")
                        val remoteState = json.optJSONObject("state")?.let(::parseState)
                        _ui.update { u ->
                            // Keep our optimistic change for a moment so the poll doesn't flicker it back.
                            val state = if (System.currentTimeMillis() - lastLocalChange < 1500) u.state else (remoteState ?: u.state)
                            u.copy(status = Status.CONNECTED, loaded = true, deviceName = name.ifEmpty { u.deviceName }, state = state,
                                   deviceAddress = u.deviceAddress ?: preferredDevice()?.address,
                                   message = "via ${json.optString("host", "your Mac")}")
                        }
                    }
                    else -> {
                        // Reachable but without the link: it gave it up to us earlier, so ask for it back
                        // and wait while it reconnects (that takes a few seconds). Unreachable: fall back sooner.
                        if (json != null && !askedBack && socket == null) { askedBack = true; m.control("handback") }
                        if (++misses >= (if (json != null) 12 else 4)) {
                            relay = null
                            if (fallBackToDirect && foreground) connectDirect()
                            else _ui.update { it.copy(status = Status.DISCONNECTED, loaded = false) }
                            return@launch
                        }
                    }
                }
                delay(1000)
            }
        }
    }

    fun stopRelay() {
        relay?.cancel(); relay = null
    }

    private fun connectDirect() { if (link?.isActive != true) { relay = null; connectSocket() } }

    private fun parseState(j: org.json.JSONObject): HeadphoneState {
        fun bool(k: String) = if (j.has(k) && !j.isNull(k)) j.getBoolean(k) else null
        fun int(k: String) = if (j.has(k) && !j.isNull(k)) j.getInt(k) else null
        val bands = j.optJSONArray("eqBands")?.let { a -> (0 until a.length()).map { a.getInt(it) } } ?: listOf(0, 0, 0, 0, 0)
        val devices = j.optJSONArray("devices")?.let { a ->
            (0 until a.length()).map { a.getJSONObject(it) }.map {
                SourceDevice(it.getString("address"), it.getString("name"), it.getInt("slot"), it.getInt("cod"))
            }
        }
        return HeadphoneState(
            firmware = j.optString("firmware").ifEmpty { null },
            codec = int("codec")?.let { local.connecthead.protocol.AudioCodec.of(it) },
            battery = int("battery"), charging = j.optBoolean("charging"),
            noiseMode = j.optString("noiseMode").takeIf { it.isNotEmpty() }?.let { runCatching { NoiseMode.valueOf(it) }.getOrNull() },
            focusOnVoice = j.optBoolean("focusOnVoice"), ambientLevel = j.optInt("ambientLevel", 10),
            ncButtonMode = int("ncButtonMode")?.let { local.connecthead.protocol.NcButtonMode.of(it) },
            eqPreset = int("eqPreset")?.let { EqPreset.of(it) }, clearBass = j.optInt("clearBass"), eqBands = bands,
            eqHasExtraByte = j.optBoolean("eqHasExtraByte"),
            pauseWhenTakenOff = bool("pauseWhenTakenOff"), voiceGuidance = bool("voiceGuidance"),
            voiceGuidanceVolume = int("voiceGuidanceVolume"), voiceAssistant = int("voiceAssistant")?.let { VoiceAssistant.of(it) },
            dseeUpsampling = bool("dseeUpsampling"), preferSoundQuality = bool("preferSoundQuality"),
            multipoint = bool("multipoint"), captureVoiceDuringCall = bool("captureVoiceDuringCall"),
            devices = devices, playbackDevice = j.optString("playbackDevice").ifEmpty { null },
        )
    }

    // ---- Actions (optimistic: update state, then send) ----

    private fun send(vararg requests: Request) {
        val m = mac
        if (relaying && m != null) scope.launch { requests.forEach { m.send(it.type.code, it.payload) } }
        else requests.forEach { queue.trySend(it) }
    }

    private fun mutate(f: (HeadphoneState) -> HeadphoneState) {
        lastLocalChange = System.currentTimeMillis()
        _ui.update { it.copy(state = f(it.state)) }
    }

    fun setNoiseMode(mode: NoiseMode) {
        mutate { it.copy(noiseMode = mode) }
        val s = _ui.value.state
        send(Commands.ambientSound(mode, s.focusOnVoice, s.ambientLevel))
    }

    fun setAmbientLevel(level: Int) {
        mutate { it.copy(ambientLevel = level) }
        val s = _ui.value.state
        send(Commands.ambientSound(NoiseMode.AMBIENT, s.focusOnVoice, level))
    }

    fun setFocusOnVoice(on: Boolean) {
        mutate { it.copy(focusOnVoice = on) }
        val s = _ui.value.state
        send(Commands.ambientSound(s.noiseMode ?: NoiseMode.AMBIENT, on, s.ambientLevel))
    }

    fun setEqPreset(preset: EqPreset) {
        mutate { it.copy(eqPreset = preset) }
        send(Commands.eqPreset(preset, _ui.value.state.eqHasExtraByte), Request(listOf(0x56, 0x00)))
    }

    /** Band index 0 is Clear Bass, 1…5 are 400 Hz … 16 kHz. */
    fun setEqBand(index: Int, value: Int) {
        mutate { s ->
            if (index == 0) s.copy(clearBass = value, eqPreset = EqPreset.MANUAL)
            else s.copy(eqBands = s.eqBands.toMutableList().also { it[index - 1] = value }, eqPreset = EqPreset.MANUAL)
        }
        val s = _ui.value.state
        send(Commands.eqBands(s.clearBass, s.eqBands, s.eqHasExtraByte))
    }

    fun resetEq() {
        mutate { it.copy(clearBass = 0, eqBands = listOf(0, 0, 0, 0, 0), eqPreset = EqPreset.MANUAL) }
        send(Commands.eqBands(0, listOf(0, 0, 0, 0, 0), _ui.value.state.eqHasExtraByte))
    }

    fun setDsee(on: Boolean) { mutate { it.copy(dseeUpsampling = on) }; send(Commands.dseeUpsampling(on)) }
    fun setPreferSoundQuality(on: Boolean) { mutate { it.copy(preferSoundQuality = on) }; send(Commands.preferSoundQuality(on)) }
    fun setMultipoint(on: Boolean) { mutate { it.copy(multipoint = on) }; send(*Commands.multipoint(on).toTypedArray()) }
    fun setCaptureVoice(on: Boolean) { mutate { it.copy(captureVoiceDuringCall = on) }; send(Commands.captureVoiceDuringCall(on)) }
    fun setPauseWhenTakenOff(on: Boolean) { mutate { it.copy(pauseWhenTakenOff = on) }; send(Commands.pauseWhenTakenOff(on)) }
    fun setVoiceGuidance(on: Boolean) { mutate { it.copy(voiceGuidance = on) }; send(Commands.voiceGuidance(on)) }
    fun setVoiceGuidanceVolume(v: Int) { mutate { it.copy(voiceGuidanceVolume = v) }; send(Commands.voiceGuidanceVolume(v)) }
    fun setVoiceAssistant(va: VoiceAssistant) { mutate { it.copy(voiceAssistant = va) }; send(Commands.voiceAssistant(va)) }

    fun playFrom(d: SourceDevice) { mutate { it.copy(playbackDevice = d.address) }; send(Commands.playFrom(d.address)) }
    fun connectDevice(d: SourceDevice) = send(Commands.connectDevice(d.address))
    fun disconnectDevice(d: SourceDevice) = send(Commands.disconnectDevice(d.address))
    fun refreshDevices() = send(Commands.deviceList)
    fun powerOff() = send(Commands.powerOff)

    companion object {
        private const val TAG = "ConnectHead"
        private fun hex(p: List<Int>) = p.joinToString(" ") { "%02x".format(it) }
        private val SERVICE_UUIDS = listOf(
            UUID.fromString("956C7B26-D49A-4BA8-B03F-B17D393CB6E2"), // protocol v2
            UUID.fromString("96CC203E-5068-46AD-B32D-E316F5E069BA"), // protocol v1
        )
    }
}
