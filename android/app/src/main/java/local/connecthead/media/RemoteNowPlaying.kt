package local.connecthead.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * What a Mac running Connect Head is playing, read over the local network. The Mac advertises
 * `_connecthead._tcp` with Bonjour and answers only requests that carry the headphones'
 * Bluetooth address, which this phone knows because it's paired with the same headphones.
 */
class RemoteNowPlaying(context: Context, private val headphonesAddress: () -> String?) {
    data class Track(
        val device: String, val service: String, val title: String, val artist: String, val album: String,
        val playing: Boolean, val position: Double, val duration: Double, val controllable: Boolean, val art: Bitmap?,
    )

    private val nsd = context.getSystemService(NsdManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _track = MutableStateFlow<Track?>(null)
    val track: StateFlow<Track?> = _track

    @Volatile private var endpoint: String? = null
    /** True once a Mac running Connect Head has been found on the network. */
    val available get() = endpoint != null
    /** Called (on a background thread) when a Mac is found. */
    var onFound: () -> Unit = {}
    private var artKey: String? = null
    private var art: Bitmap? = null

    fun start() {
        nsd.discoverServices("_connecthead._tcp", NsdManager.PROTOCOL_DNS_SD, object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) = resolve(info)
            override fun onServiceLost(info: NsdServiceInfo) { endpoint = null; _track.value = null }
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) { Log.w(TAG, "discovery failed: $code") }
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        })
        scope.launch {
            while (isActive) {
                poll()
                delay(2000)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(info: NsdServiceInfo) {
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(resolved: NsdServiceInfo) {
                val host = resolved.host?.hostAddress ?: return
                endpoint = if (host.contains(':')) "http://[$host]:${resolved.port}" else "http://$host:${resolved.port}"
                Log.i(TAG, "found ${resolved.serviceName} at $endpoint")
                onFound()
            }
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) { Log.w(TAG, "resolve failed: $code") }
        })
    }

    /** The headphones' state as the Mac reads it, or null if unreachable. Blocking: call off the main thread. */
    fun headphones(): JSONObject? = request("/headphones")?.let { try { JSONObject(it) } catch (_: Exception) { null } }

    /** Relays a raw request to the headphones through the Mac. Blocking. */
    fun send(type: Int, payload: List<Int>): Boolean =
        request("/send?type=%02x&p=%s".format(type, payload.joinToString("") { "%02x".format(it) }), "POST") != null

    private fun request(path: String, method: String = "GET"): String? {
        val base = endpoint ?: return null
        val key = headphonesAddress() ?: return null
        return try {
            val c = URL(base + path).openConnection() as HttpURLConnection
            c.requestMethod = method
            c.connectTimeout = 1500; c.readTimeout = 2000
            c.setRequestProperty("X-Headphones", key)
            if (c.responseCode != 200) null else c.inputStream.bufferedReader().readText()
        } catch (e: Exception) { null }
    }

    private fun poll() {
        val body = request("/now-playing") ?: run { _track.value = null; return }
        val t = try { JSONObject(body).optJSONObject("track") } catch (_: Exception) { null }
        if (t == null) { _track.value = null; return }
        val key = t.optString("service") + "|" + t.optString("title")
        if (key != artKey) {
            artKey = key
            art = t.optString("artwork").takeIf { it.isNotEmpty() }?.let {
                val bytes = Base64.decode(it, Base64.DEFAULT); BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        }
        _track.value = Track(
            device = t.optString("device", "Mac"), service = t.optString("service"), title = t.optString("title"),
            artist = t.optString("artist"), album = t.optString("album"), playing = t.optBoolean("playing"),
            position = t.optDouble("position", 0.0), duration = t.optDouble("duration", 0.0),
            controllable = t.optBoolean("controllable"), art = art,
        )
    }

    fun control(action: String) {
        scope.launch { request("/control?action=$action", "POST"); delay(400); poll() }
    }

    companion object { private const val TAG = "ConnectHead" }
}
