package local.connecthead.media

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar
import java.util.UUID

/**
 * Local history of what was played and how loud, for the Listening screen. Time accumulates
 * into a session per track while it plays; media volume is kept in per-minute buckets while
 * playing through the headphones. Stored as JSON in the app's private files, kept 120 days.
 */
class ListeningLog(context: Context) {
    data class Session(val id: String, val title: String, val artist: String, val app: String, val start: Long, val seconds: Double) {
        val end get() = start + (seconds * 1000).toLong()
    }

    /** One minute of listening; `level` is the time-weighted average media volume (0…1). */
    data class VolumeMinute(val minute: Long, val level: Double, val seconds: Double)

    private val file = File(context.filesDir, "listening.json")
    private val _sessions = MutableStateFlow<List<Session>>(emptyList())
    val sessions: StateFlow<List<Session>> = _sessions
    private val _volume = MutableStateFlow<List<VolumeMinute>>(emptyList())
    val volume: StateFlow<List<VolumeMinute>> = _volume

    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pendingSave: Job? = null
    private var lastTick: Long? = null

    init { load() }

    fun record(track: NowPlaying.Track?, volume: Double?, now: Long = System.currentTimeMillis()) {
        val last = lastTick
        lastTick = now
        if (track == null || !track.playing || last == null) return
        val dt = ((now - last) / 1000.0).coerceAtMost(10.0)   // cap gaps (sleep, stalls)
        if (dt <= 0) return

        val list = _sessions.value.toMutableList()
        val current = list.lastOrNull()
        if (current != null && current.title == track.title && current.artist == track.artist &&
            current.app == track.app && now - current.end < 90_000) {
            list[list.size - 1] = current.copy(seconds = current.seconds + dt)
        } else {
            list += Session(UUID.randomUUID().toString(), track.title, track.artist, track.app, now - (dt * 1000).toLong(), dt)
        }
        _sessions.value = list

        if (volume != null) {
            val minute = now / 60_000 * 60_000
            val v = _volume.value.toMutableList()
            val lastMinute = v.lastOrNull()
            if (lastMinute?.minute == minute) {
                v[v.size - 1] = lastMinute.copy(
                    level = (lastMinute.level * lastMinute.seconds + volume * dt) / (lastMinute.seconds + dt),
                    seconds = lastMinute.seconds + dt)
            } else v += VolumeMinute(minute, volume, dt)
            _volume.value = v
        }
        scheduleSave()
    }

    fun clear() {
        _sessions.value = emptyList()
        _volume.value = emptyList()
        save()
    }

    private fun scheduleSave() {
        if (pendingSave?.isActive == true) return
        pendingSave = io.launch { delay(15_000); save() }
    }

    fun save() {
        val json = JSONObject()
            .put("sessions", JSONArray().apply {
                _sessions.value.forEach {
                    put(JSONObject().put("id", it.id).put("title", it.title).put("artist", it.artist)
                        .put("app", it.app).put("start", it.start).put("seconds", it.seconds))
                }
            })
            .put("volume", JSONArray().apply {
                _volume.value.forEach { put(JSONObject().put("minute", it.minute).put("level", it.level).put("seconds", it.seconds)) }
            })
        try { file.writeText(json.toString()) } catch (_: Exception) {}
    }

    private fun load() {
        val json = try { JSONObject(file.readText()) } catch (_: Exception) { return }
        val cutoff = System.currentTimeMillis() - 120L * 86_400_000
        val s = json.optJSONArray("sessions") ?: JSONArray()
        _sessions.value = (0 until s.length()).map { s.getJSONObject(it) }.map {
            Session(it.getString("id"), it.getString("title"), it.getString("artist"), it.getString("app"),
                it.getLong("start"), it.getDouble("seconds"))
        }.filter { it.start > cutoff }
        val v = json.optJSONArray("volume") ?: JSONArray()
        _volume.value = (0 until v.length()).map { v.getJSONObject(it) }.map {
            VolumeMinute(it.getLong("minute"), it.getDouble("level"), it.getDouble("seconds"))
        }.filter { it.minute > cutoff }
    }
}

/** Aggregates for the Listening screen, over the last `days` days. */
class ListeningStats(sessions: List<ListeningLog.Session>, volume: List<ListeningLog.VolumeMinute>, val days: Int) {
    data class Row(val name: String, val detail: String, val seconds: Double)

    val totalSeconds: Double
    val perDay: List<Pair<Long, Double>>          // day start → seconds
    val perHour: List<Double>
    val topArtists: List<Row>
    val topTracks: List<Row>
    val apps: List<Row>
    val perDayVolume: List<Double?>
    val averageVolume: Double?
    val loudSeconds: Double

    init {
        val cal = Calendar.getInstance()
        fun startOfDay(t: Long): Long {
            cal.timeInMillis = t
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }
        val today = startOfDay(System.currentTimeMillis())
        val dayList = (days - 1 downTo 0).map { back ->
            cal.timeInMillis = today; cal.add(Calendar.DAY_OF_YEAR, -back); cal.timeInMillis
        }
        val start = dayList.first()
        val recent = sessions.filter { it.end > start }
        val loud = volume.filter { it.minute >= start }

        totalSeconds = recent.sumOf { it.seconds }
        val byDay = recent.groupBy { startOfDay(it.start) }.mapValues { (_, g) -> g.sumOf { it.seconds } }
        perDay = dayList.map { it to (byDay[it] ?: 0.0) }
        perHour = DoubleArray(24).also { h ->
            recent.forEach { s -> cal.timeInMillis = s.start; h[cal.get(Calendar.HOUR_OF_DAY)] += s.seconds }
        }.toList()

        fun ranked(key: (ListeningLog.Session) -> String, detail: (List<ListeningLog.Session>) -> String) =
            recent.groupBy(key).map { (name, g) -> Row(name, detail(g), g.sumOf { it.seconds }) }.sortedByDescending { it.seconds }
        topArtists = ranked({ it.artist.ifEmpty { it.app } }) { g -> g.map { it.title }.toSet().size.let { if (it == 1) "1 track" else "$it tracks" } }
        topTracks = ranked({ it.title }) { g -> g.first().artist.ifEmpty { g.first().app } }
        apps = ranked({ it.app }) { "" }

        val volumeByDay = loud.groupBy { startOfDay(it.minute) }
        perDayVolume = dayList.map { d ->
            volumeByDay[d]?.let { g -> val secs = g.sumOf { it.seconds }; if (secs > 0) g.sumOf { it.level * it.seconds } / secs else null }
        }
        val volumeSeconds = loud.sumOf { it.seconds }
        averageVolume = if (volumeSeconds > 0) loud.sumOf { it.level * it.seconds } / volumeSeconds else null
        loudSeconds = loud.filter { it.level > 0.75 }.sumOf { it.seconds }
    }
}

fun durationText(seconds: Double): String {
    val m = Math.round(seconds / 60).toInt()
    return when {
        m < 1 -> if (seconds > 0) "<1m" else "0m"
        m < 60 -> "${m}m"
        m % 60 == 0 -> "${m / 60}h"
        else -> "${m / 60}h ${m % 60}m"
    }
}
