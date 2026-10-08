package id.adam.satsh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * Lets the agent look at the phone screen. The user grants it once through
 * Android's own "start recording/casting" dialog; a notification with a Stop
 * button stays up for as long as it's on.
 */
class ScreenCaptureService : Service() {
    companion object {
        const val CHANNEL = "satsh_screen"
        const val NOTIF_ID = 4343
        const val ACTION_STOP = "id.adam.satsh.SCREEN_STOP"

        @Volatile var instance: ScreenCaptureService? = null
        var onReady: ((Boolean, String?) -> Unit)? = null

        val running get() = instance?.display != null
    }

    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private val lock = Object()
    private var latest: Image? = null
    private var width = 0
    private var height = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val code = intent?.getIntExtra("code", 0) ?: 0
        @Suppress("DEPRECATION")
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) intent?.getParcelableExtra("data", Intent::class.java) else intent?.getParcelableExtra("data")
        try {
            val n = notification()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            else startForeground(NOTIF_ID, n)
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val p = mpm.getMediaProjection(code, data!!) ?: throw IllegalStateException("izin ditolak")
            projection = p
            p.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, null)

            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val dm = resources.displayMetrics
            var w: Int; var h: Int
            if (Build.VERSION.SDK_INT >= 30) {
                val b = wm.maximumWindowMetrics.bounds
                w = b.width(); h = b.height()
            } else {
                val m = DisplayMetrics()
                @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(m)
                w = m.widthPixels; h = m.heightPixels
            }
            // Half resolution is plenty for a model and much cheaper.
            width = (w / 2) and 1.inv(); height = (h / 2) and 1.inv()
            val t = HandlerThread("satsh-screen").apply { start() }
            thread = t
            val r = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3)
            r.setOnImageAvailableListener({ ir ->
                val img = try { ir.acquireLatestImage() } catch (_: Throwable) { null }
                if (img != null) synchronized(lock) {
                    latest?.close()
                    latest = img
                }
            }, Handler(t.looper))
            reader = r
            display = p.createVirtualDisplay("satsh-screen", width, height, dm.densityDpi / 2,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, null)
            instance = this
            onReady?.invoke(true, null); onReady = null
        } catch (e: Throwable) {
            onReady?.invoke(false, e.message ?: e.toString()); onReady = null
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Latest frame as a bitmap, or null if nothing arrived yet. */
    fun frame(): Bitmap? = synchronized(lock) {
        val img = latest ?: return null
        val plane = img.planes[0]
        val pixelStride = plane.pixelStride
        val rowPad = plane.rowStride - pixelStride * img.width
        val full = Bitmap.createBitmap(img.width + rowPad / pixelStride, img.height, Bitmap.Config.ARGB_8888)
        plane.buffer.rewind()
        full.copyPixelsFromBuffer(plane.buffer)
        if (rowPad == 0) full else Bitmap.createBitmap(full, 0, 0, img.width, img.height).also { full.recycle() }
    }

    private fun notification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Agent lihat layar", NotificationManager.IMPORTANCE_LOW))
        }
        val stop = PendingIntent.getService(this, 1, Intent(this, ScreenCaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return b.setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Agent satsh bisa lihat layar")
            .setContentText("Cuma ngambil gambar pas agent minta. Tap Stop buat matiin.")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    override fun onDestroy() {
        synchronized(lock) { latest?.close(); latest = null }
        try { display?.release() } catch (_: Throwable) {}
        try { reader?.close() } catch (_: Throwable) {}
        try { projection?.stop() } catch (_: Throwable) {}
        thread?.quitSafely()
        display = null; reader = null; projection = null
        if (instance === this) instance = null
        onReady?.invoke(false, "berhenti"); onReady = null
        super.onDestroy()
    }
}
