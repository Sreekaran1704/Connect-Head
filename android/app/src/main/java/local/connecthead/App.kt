package local.connecthead

import android.Manifest
import android.app.Application
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import local.connecthead.bt.HeadphoneController
import local.connecthead.media.ListeningLog
import local.connecthead.media.NowPlaying
import local.connecthead.media.RemoteNowPlaying
import local.connecthead.ui.ConnectHeadApp
import local.connecthead.ui.ConnectHeadTheme

/** Holds the long-lived pieces so the link and the listening log outlive the activity. */
class ConnectHead : Application() {
    lateinit var controller: HeadphoneController
    lateinit var log: ListeningLog
    lateinit var nowPlaying: NowPlaying
    lateinit var remote: RemoteNowPlaying

    override fun onCreate() {
        super.onCreate()
        controller = HeadphoneController(this)
        log = ListeningLog(this)
        nowPlaying = NowPlaying(this, log) { controller.ui.value.deviceName }
        nowPlaying.start()
        remote = RemoteNowPlaying(this) { controller.headphonesAddress() }
        controller.mac = remote
        remote.onFound = { controller.macFound() }
        remote.start()
    }
}

class MainActivity : ComponentActivity() {
    private val app get() = application as ConnectHead

    private val askBluetooth = registerForActivityResult(ActivityResultContracts.RequestPermission()) { app.controller.connect() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { ConnectHeadTheme { ConnectHeadApp(app.controller, app.nowPlaying, app.remote, app.log) } }
        if (Build.VERSION.SDK_INT >= 31 && !app.controller.hasPermission()) askBluetooth.launch(Manifest.permission.BLUETOOTH_CONNECT)
        else app.controller.connect()
    }

    override fun onResume() {
        super.onResume()
        app.controller.foreground = true
        if (app.controller.ui.value.status != HeadphoneController.Status.CONNECTED || !app.controller.ui.value.loaded) app.controller.connect()
    }

    override fun onStop() {
        super.onStop()
        app.log.save()
        app.controller.foreground = false
        // The headphones allow one control link: hand it back to the Mac while the app isn't in use.
        if (app.controller.relaying) app.controller.stopRelay()
        else if (app.controller.ui.value.status == HeadphoneController.Status.CONNECTED) {
            app.controller.disconnect()
            app.remote.control("handback")
        }
    }
}
