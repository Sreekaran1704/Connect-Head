package local.connecthead.media

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Declared in the manifest so the user can grant notification access, which is what lets an
 * app read other apps' media sessions. It doesn't read or keep any notifications itself.
 */
class MediaListener : NotificationListenerService()

/**
 * What's playing on the phone, from the system's active media sessions (YouTube, Spotify,
 * YouTube Music, podcasts, anything with a media notification). Polls every 2 s, feeds the
 * listening log, and samples the media volume while it plays through the headphones.
 */
class NowPlaying(private val context: Context, private val log: ListeningLog, private val headphonesName: () -> String?) {
    data class Track(
        val packageName: String,
        val app: String,
        val title: String,
        val artist: String,
        val album: String,
        val playing: Boolean,
        val position: Long,
        val duration: Long,
        val art: Bitmap?,
    )

    private val _track = MutableStateFlow<Track?>(null)
    val track: StateFlow<Track?> = _track
    private val _hasAccess = MutableStateFlow(false)
    val hasAccess: StateFlow<Boolean> = _hasAccess

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var controller: MediaController? = null

    fun start() {
        scope.launch {
            while (isActive) {
                refresh()
                delay(2000)
            }
        }
    }

    fun accessGranted() = NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    private fun refresh() {
        _hasAccess.value = accessGranted()
        if (!_hasAccess.value) { _track.value = null; return }
        val sessions = try {
            context.getSystemService(MediaSessionManager::class.java)
                .getActiveSessions(ComponentName(context, MediaListener::class.java))
        } catch (_: SecurityException) { emptyList() }
        // Whatever is actually playing wins; otherwise the most recent session.
        val c = sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()
        controller = c
        val track = c?.let(::read)
        _track.value = track
        log.record(track, volumeOnHeadphones())
    }

    private fun read(c: MediaController): Track? {
        val m = c.metadata ?: return null
        val title = m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: return null
        val state = c.playbackState
        val playing = state?.state == PlaybackState.STATE_PLAYING
        // The session reports a position at a moment; extrapolate to now while playing.
        val position = state?.let {
            if (playing && it.lastPositionUpdateTime > 0)
                it.position + ((SystemClock.elapsedRealtime() - it.lastPositionUpdateTime) * it.playbackSpeed).toLong()
            else it.position
        } ?: 0
        val app = try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString()
        } catch (_: Exception) { c.packageName }
        return Track(
            packageName = c.packageName,
            app = app,
            title = title,
            artist = m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: "",
            album = m.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "",
            playing = playing,
            position = position.coerceAtLeast(0),
            duration = m.getLong(MediaMetadata.METADATA_KEY_DURATION),
            art = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART),
        )
    }

    /** Media volume 0…1, but only when audio is going to the (named) Bluetooth headphones. */
    private fun volumeOnHeadphones(): Double? {
        val audio = context.getSystemService(AudioManager::class.java)
        val name = headphonesName() ?: return null
        val onHeadphones = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP && it.productName.toString().contains(name, ignoreCase = true)
        }
        if (!onHeadphones) return null
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    fun playPause() {
        val c = controller ?: return
        if (c.playbackState?.state == PlaybackState.STATE_PLAYING) c.transportControls.pause() else c.transportControls.play()
        scope.launch { delay(300); refresh() }
    }

    fun next() { controller?.transportControls?.skipToNext(); scope.launch { delay(400); refresh() } }
    fun previous() { controller?.transportControls?.skipToPrevious(); scope.launch { delay(400); refresh() } }
}
