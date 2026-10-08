package id.adam.satsh

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.webkit.CookieManager
import android.provider.Settings
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        const val REQ_SCREEN = 7101
        const val REQ_VOICE = 7102
        const val AGENT_CHANNEL = "satsh_agent"
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var screenResult: MethodChannel.Result? = null
    private var voiceResult: MethodChannel.Result? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var channel: MethodChannel? = null
    /** Package-name keywords the agent may never operate (banks, e-wallets…). */
    @Volatile private var blockList: List<String> = emptyList()

    private fun blocked(pkg: String) = pkg.isNotEmpty() && blockList.any { pkg.lowercase().contains(it) }

    private fun ctl(result: MethodChannel.Result): AgentControlService? {
        val s = AgentControlService.instance
        if (s == null) result.error("off", "Kontrol HP belum nyala (Aksesibilitas)", null)
        return s
    }

    /** Refuses when the app in front (or the target) is on the block list. */
    private fun guard(s: AgentControlService, result: MethodChannel.Result, n: Int = 0): Boolean {
        val pkgs = mutableListOf(s.activePackage())
        if (n > 0) try { pkgs += s.packageOf(n) } catch (_: Throwable) {}
        val b = pkgs.firstOrNull { blocked(it) }
        if (b != null) { result.error("blocked", b, null); return false }
        s.showPill()
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "satsh/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                "deviceDiag" -> bg(result) { DeviceDiag.collect(applicationContext) }
                "deviceLogs" -> bg(result) { DeviceDiag.logs(applicationContext, call.argument<String>("what") ?: "crash") }
                "vibrate" -> {
                    val ms = (call.argument<Int>("ms") ?: 400).toLong()
                    val v = if (Build.VERSION.SDK_INT >= 31) (getSystemService(android.os.VibratorManager::class.java)).defaultVibrator
                            else @Suppress("DEPRECATION") (getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator)
                    if (Build.VERSION.SDK_INT >= 26) v.vibrate(android.os.VibrationEffect.createOneShot(ms, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
                    else @Suppress("DEPRECATION") v.vibrate(ms)
                    result.success(v.hasVibrator())
                }

                // ------------------------------------------------ agent browser
                "webshot" -> {
                    val id = (call.argument<Number>("id") ?: -1).toLong()
                    val maxW = call.argument<Int>("maxW") ?: 900
                    val q = call.argument<Int>("q") ?: 70
                    @Suppress("DEPRECATION")
                    val wv = WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, id)
                    if (wv == null) {
                        result.error("nowebview", "WebView ga ketemu", null); return@setMethodCallHandler
                    }
                    val w = wv.width
                    val h = wv.height
                    if (w <= 0 || h <= 0 || !wv.isAttachedToWindow) {
                        result.error("hidden", "Browser lagi ga tampil di layar", null); return@setMethodCallHandler
                    }
                    try {
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        val c = Canvas(bmp)
                        c.drawColor(Color.WHITE)
                        wv.draw(c)
                        bg(result) { encode(bmp, maxW, q) + mapOf("vw" to w, "vh" to h) }
                    } catch (e: Throwable) {
                        result.error("draw", e.toString(), null)
                    }
                }
                "cookies" -> result.success(CookieManager.getInstance().getCookie(call.argument<String>("url") ?: "") ?: "")

                // ------------------------------------------------------ images
                "jpeg" -> {
                    val path = call.argument<String>("path")
                    val data = call.argument<ByteArray>("bytes")
                    val maxW = call.argument<Int>("maxW") ?: 1280
                    val q = call.argument<Int>("q") ?: 75
                    bg(result) {
                        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        if (path != null) BitmapFactory.decodeFile(path, opts) else BitmapFactory.decodeByteArray(data, 0, data!!.size, opts)
                        var sample = 1
                        while (opts.outWidth / (sample * 2) >= maxW && opts.outHeight / (sample * 2) >= maxW / 2) sample *= 2
                        val o2 = BitmapFactory.Options().apply { inSampleSize = sample }
                        val bmp = (if (path != null) BitmapFactory.decodeFile(path, o2) else BitmapFactory.decodeByteArray(data, 0, data!!.size, o2))
                            ?: throw IllegalArgumentException("bukan gambar / format ga didukung")
                        encode(bmp, maxW, q)
                    }
                }

                // ------------------------------------------------- phone screen
                "screenStatus" -> result.success(ScreenCaptureService.running)
                "screenStart" -> {
                    if (ScreenCaptureService.running) { result.success(true); return@setMethodCallHandler }
                    if (screenResult != null) { result.error("busy", "Lagi nunggu izin", null); return@setMethodCallHandler }
                    screenResult = result
                    val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    @Suppress("DEPRECATION")
                    startActivityForResult(mpm.createScreenCaptureIntent(), REQ_SCREEN)
                }
                "screenShot" -> {
                    val svc = ScreenCaptureService.instance
                    if (svc == null) { result.error("off", "Lihat layar belum nyala", null); return@setMethodCallHandler }
                    val maxW = call.argument<Int>("maxW") ?: 720
                    val q = call.argument<Int>("q") ?: 70
                    bg(result) {
                        var bmp: Bitmap? = null
                        for (i in 0 until 20) { bmp = svc.frame(); if (bmp != null) break; Thread.sleep(100) }
                        encode(bmp ?: throw IllegalStateException("belum ada gambar dari layar"), maxW, q)
                    }
                }
                "screenStop" -> {
                    startService(Intent(this, ScreenCaptureService::class.java).setAction(ScreenCaptureService.ACTION_STOP))
                    result.success(true)
                }

                // ------------------------------------------------------- voice
                "listen" -> {
                    if (voiceResult != null) { result.error("busy", "Lagi dengerin", null); return@setMethodCallHandler }
                    val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, call.argument<String>("lang") ?: "id-ID")
                        .putExtra(RecognizerIntent.EXTRA_PROMPT, "Ngomong ke agent…")
                    try {
                        voiceResult = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(i, REQ_VOICE)
                    } catch (e: ActivityNotFoundException) {
                        voiceResult = null
                        result.error("nostt", "HP ini ga punya pengenal suara (install Google app)", null)
                    }
                }
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    speak(text)
                    result.success(true)
                }
                "stopSpeak" -> { tts?.stop(); result.success(true) }

                // ------------------------------------------------ notification
                "notify" -> {
                    notifyAgent(call.argument<String>("title") ?: "satsh", call.argument<String>("body") ?: "", call.argument<Int>("id") ?: 1)
                    result.success(true)
                }

                // ---------------------------------------------- control other apps
                "controlConfig" -> {
                    blockList = (call.argument<List<String>>("block") ?: emptyList()).map { it.lowercase().trim() }.filter { it.isNotEmpty() }
                    AgentControlService.onUserStop = { main.post { channel?.invokeMethod("controlStopped", null) } }
                    result.success(true)
                }
                "controlStatus" -> result.success(AgentControlService.instance != null)
                "controlSettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "appSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "controlTree" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    bg(result) {
                        val t = s.tree()
                        if (blocked(t.optString("pkg"))) t.put("blocked", true).put("els", org.json.JSONArray()).put("texts", org.json.JSONArray())
                        t.toString()
                    }
                }
                "controlMarks" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    if (call.argument<Boolean>("show") == true) s.showMarks() else s.removeMarks()
                    result.success(true)
                }
                "controlClick" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    val n = call.argument<Int>("n") ?: 0
                    if (!guard(s, result, n)) return@setMethodCallHandler
                    try { s.click(n, call.argument<Boolean>("long") == true) { ok -> result.success(ok) } }
                    catch (e: Throwable) { result.error("err", e.message, null) }
                }
                "controlTap" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    if (!guard(s, result)) return@setMethodCallHandler
                    val x = (call.argument<Number>("x") ?: 0).toFloat()
                    val y = (call.argument<Number>("y") ?: 0).toFloat()
                    s.tap(x, y, if (call.argument<Boolean>("long") == true) 700 else 60) { ok -> result.success(ok) }
                }
                "controlSwipe" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    if (!guard(s, result)) return@setMethodCallHandler
                    fun f(k: String) = (call.argument<Number>(k) ?: 0).toFloat()
                    s.swipe(f("x1"), f("y1"), f("x2"), f("y2"), (call.argument<Number>("ms") ?: 350).toLong()) { ok -> result.success(ok) }
                }
                "controlType" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    val n = call.argument<Int>("n") ?: 0
                    if (!guard(s, result, n)) return@setMethodCallHandler
                    try {
                        var r = s.type(n, call.argument<String>("text") ?: "", call.argument<Boolean>("append") == true)
                        if (r == "ok" && call.argument<Boolean>("enter") == true && !s.enter()) r = "ok-noenter"
                        result.success(r)
                    } catch (e: Throwable) { result.error("err", e.message, null) }
                }
                "controlScroll" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    val n = call.argument<Int>("n") ?: 0
                    if (!guard(s, result, n)) return@setMethodCallHandler
                    try { result.success(s.scroll(n, call.argument<Boolean>("forward") != false)) }
                    catch (e: Throwable) { result.error("err", e.message, null) }
                }
                "controlKey" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    s.showPill() // back/home always allowed: they're the way out
                    try { result.success(s.key(call.argument<String>("k") ?: "")) }
                    catch (e: Throwable) { result.error("err", e.message, null) }
                }
                "controlScreenSize" -> {
                    val s = ctl(result) ?: return@setMethodCallHandler
                    val (w, h) = s.screenSize()
                    result.success(mapOf("w" to w, "h" to h))
                }
                "listApps" -> bg(result) {
                    val pm = packageManager
                    val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    @Suppress("DEPRECATION")
                    pm.queryIntentActivities(i, 0).map {
                        mapOf("label" to it.loadLabel(pm).toString(), "pkg" to it.activityInfo.packageName)
                    }.distinctBy { it["pkg"] }.sortedBy { it["label"]?.lowercase() }
                }
                "openApp" -> {
                    val pkg = call.argument<String>("pkg") ?: ""
                    if (blocked(pkg)) { result.error("blocked", pkg, null); return@setMethodCallHandler }
                    val li = packageManager.getLaunchIntentForPackage(pkg)
                    if (li == null) { result.error("noapp", "App $pkg ga ketemu", null); return@setMethodCallHandler }
                    startActivity(li.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    AgentControlService.instance?.showPill()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun bg(result: MethodChannel.Result, f: () -> Any) {
        io.execute {
            try {
                val r = f()
                main.post { result.success(r) }
            } catch (e: Throwable) {
                main.post { result.error("err", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun speak(text: String) {
        if (text.isBlank()) return
        val go = {
            tts?.speak(text.take(3900), TextToSpeech.QUEUE_FLUSH, null, "satsh")
            Unit
        }
        if (tts != null && ttsReady) { go(); return }
        tts = TextToSpeech(this) { st ->
            ttsReady = st == TextToSpeech.SUCCESS
            if (ttsReady) {
                val id = Locale("id", "ID")
                if (tts?.isLanguageAvailable(id) ?: -1 >= TextToSpeech.LANG_AVAILABLE) tts?.language = id
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) { main.post { channel?.invokeMethod("speaking", true) } }
                    override fun onDone(utteranceId: String?) { main.post { channel?.invokeMethod("speaking", false) } }
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) { main.post { channel?.invokeMethod("speaking", false) } }
                })
                go()
            }
        }
    }

    private fun notifyAgent(title: String, body: String, id: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(AGENT_CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(AGENT_CHANNEL, "Agent", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Kabar dari agent: tugas selesai, butuh izin, dll"
            })
        }
        val open = PendingIntent.getActivity(this, 10, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("openAgent", true), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(this, AGENT_CHANNEL) else android.app.Notification.Builder(this)
        val n = b.setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try { nm.notify(5000 + id, n) } catch (_: SecurityException) {}
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQ_SCREEN -> {
                val r = screenResult; screenResult = null
                if (resultCode != Activity.RESULT_OK || data == null) {
                    r?.error("denied", "User ga ngizinin lihat layar", null)
                } else {
                    ScreenCaptureService.onReady = { ok, err -> main.post { if (ok) r?.success(true) else r?.error("fail", err, null) } }
                    val i = Intent(this, ScreenCaptureService::class.java).putExtra("code", resultCode).putExtra("data", data)
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                }
            }
            REQ_VOICE -> {
                val r = voiceResult; voiceResult = null
                val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
                r?.success(if (resultCode == Activity.RESULT_OK) text else null)
            }
            else -> @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        tts?.shutdown()
        super.onDestroy()
    }

    private fun encode(src: Bitmap, maxW: Int, q: Int): Map<String, Any> {
        val bmp = if (src.width > maxW) {
            Bitmap.createScaledBitmap(src, maxW, (src.height.toLong() * maxW / src.width).toInt().coerceAtLeast(1), true)
        } else src
        val bos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, q, bos)
        val r = mapOf("bytes" to bos.toByteArray(), "w" to bmp.width, "h" to bmp.height)
        if (bmp !== src) bmp.recycle()
        src.recycle()
        return r
    }
}
