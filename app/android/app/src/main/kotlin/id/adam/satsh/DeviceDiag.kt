package id.adam.satsh

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.File

/**
 * Device health for the agent ("diagnosa_hp"): real battery capacity estimate, true specs from the
 * system (not the box), root hints. Everything here works without root; logcat / dumpsys need the
 * one-time `adb shell pm grant id.adam.satsh android.permission.READ_LOGS` (and DUMP).
 */
object DeviceDiag {

    fun collect(ctx: Context): Map<String, Any?> = mapOf(
        "battery" to safe { battery(ctx) },
        "device" to safe { device() },
        "soc" to safe { soc() },
        "memory" to safe { memory(ctx) },
        "storage" to safe { storage() },
        "display" to safe { display(ctx) },
        "cameras" to safe { cameras(ctx) },
        "sensors" to safe { sensors(ctx) },
        "security" to safe { security(ctx) },
        "thermal" to safe { thermal(ctx) },
        "uptimeH" to SystemClock.elapsedRealtime() / 3_600_000.0,
        "perms" to mapOf(
            "readLogs" to granted(ctx, "android.permission.READ_LOGS"),
            "dump" to granted(ctx, "android.permission.DUMP"),
        ),
    )

    private fun <T> safe(f: () -> T): Any? = try { f() } catch (t: Throwable) { mapOf("error" to (t.message ?: t.javaClass.simpleName)) }

    private fun granted(ctx: Context, p: String) = ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    // ------------------------------------------------------------------ battery
    private fun battery(ctx: Context): Map<String, Any?> {
        val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val i = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) level * 100.0 / scale else bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).toDouble()
        val counterUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER) // µAh now (some phones report mAh)
        val nowUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        var counterMah: Double? = null
        if (counterUah > 0 && counterUah != Int.MIN_VALUE) counterMah = if (counterUah > 100_000) counterUah / 1000.0 else counterUah.toDouble()
        val fullEst = if (counterMah != null && pct >= 15) counterMah / (pct / 100.0) else null
        val design = designCapacity(ctx)
        val cycles = if (Build.VERSION.SDK_INT >= 34) i?.getIntExtra("android.os.extra.CYCLE_COUNT", -1)?.takeIf { it >= 0 } else null
        val health = when (i?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0)) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
            BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over_voltage"
            BatteryManager.BATTERY_HEALTH_COLD -> "cold"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
            else -> "unknown"
        }
        val plugged = when (i?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"; BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"; else -> "none"
        }
        return mapOf(
            "percent" to pct,
            "chargeNowMah" to counterMah,
            "fullEstimateMah" to fullEst,
            "designMah" to design,
            "healthPct" to if (fullEst != null && design != null && design > 0) fullEst * 100 / design else null,
            "cycles" to cycles,
            "health" to health,
            "tempC" to (i?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)?.takeIf { it != Int.MIN_VALUE }?.div(10.0)),
            "voltageMv" to i?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it > 0 },
            "currentMa" to if (nowUa != 0 && nowUa != Int.MIN_VALUE) nowUa / 1000.0 else null,
            "plugged" to plugged,
            "technology" to i?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            "sysfs" to sysfsBattery(),
        )
    }

    /** Design capacity in mAh: hidden PowerProfile (works on most phones), else sysfs. */
    private fun designCapacity(ctx: Context): Double? {
        try {
            val c = Class.forName("com.android.internal.os.PowerProfile")
            val p = c.getConstructor(Context::class.java).newInstance(ctx)
            val v = c.getMethod("getBatteryCapacity").invoke(p) as Double
            if (v > 500) return v
        } catch (_: Throwable) {}
        val s = sysfsBattery()
        return (s["charge_full_design"] as? Long)?.let { if (it > 100_000) it / 1000.0 else it.toDouble() }?.takeIf { it > 500 }
    }

    /** Fuel-gauge files when SELinux lets us read them (often blocked on new phones — fine). */
    private fun sysfsBattery(): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        for (n in listOf("charge_full", "charge_full_design", "cycle_count")) {
            for (dir in listOf("/sys/class/power_supply/battery", "/sys/class/power_supply/bms")) {
                try {
                    val v = File("$dir/$n").readText().trim().toLongOrNull()
                    if (v != null && v > 0) { out[n] = v; break }
                } catch (_: Throwable) {}
            }
        }
        return out
    }

    // ------------------------------------------------------------------ specs
    private fun device() = mapOf(
        "brand" to Build.BRAND, "manufacturer" to Build.MANUFACTURER, "model" to Build.MODEL, "device" to Build.DEVICE,
        "product" to Build.PRODUCT, "android" to Build.VERSION.RELEASE, "sdk" to Build.VERSION.SDK_INT,
        "securityPatch" to Build.VERSION.SECURITY_PATCH, "fingerprint" to Build.FINGERPRINT, "buildType" to Build.TYPE,
        "tags" to Build.TAGS, "bootloader" to Build.BOOTLOADER, "hardware" to Build.HARDWARE,
    )

    private fun soc(): Map<String, Any?> {
        val cores = Runtime.getRuntime().availableProcessors()
        val maxKhz = (0 until cores).mapNotNull {
            try { File("/sys/devices/system/cpu/cpu$it/cpufreq/cpuinfo_max_freq").readText().trim().toLong() } catch (_: Throwable) { null }
        }
        return mapOf(
            "model" to (if (Build.VERSION.SDK_INT >= 31) "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}" else Build.HARDWARE),
            "cores" to cores,
            "maxGhz" to maxKhz.maxOrNull()?.div(1_000_000.0),
            "clusters" to maxKhz.groupingBy { it }.eachCount().map { (k, n) -> "${n}x${"%.2f".format(k / 1_000_000.0)}GHz" },
            "abis" to Build.SUPPORTED_ABIS.toList(),
        )
    }

    private fun memory(ctx: Context): Map<String, Any?> {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return mapOf("totalGb" to mi.totalMem / 1e9, "availGb" to mi.availMem / 1e9, "lowRam" to am.isLowRamDevice)
    }

    private fun storage(): Map<String, Any?> {
        val s = StatFs(Environment.getDataDirectory().path)
        return mapOf("totalGb" to s.totalBytes / 1e9, "freeGb" to s.availableBytes / 1e9)
    }

    @Suppress("DEPRECATION")
    private fun display(ctx: Context): Map<String, Any?> {
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val d = wm.defaultDisplay
        val m = DisplayMetrics().also { d.getRealMetrics(it) }
        val rates = d.supportedModes.map { it.refreshRate.toInt() }.distinct().sorted()
        val inch = Math.sqrt(Math.pow(m.widthPixels / m.xdpi.toDouble(), 2.0) + Math.pow(m.heightPixels / m.ydpi.toDouble(), 2.0))
        return mapOf(
            "px" to "${m.widthPixels}x${m.heightPixels}", "dpi" to m.densityDpi, "inchApprox" to inch,
            "refreshHz" to rates, "hdr" to (if (Build.VERSION.SDK_INT >= 26) d.isHdr else null),
        )
    }

    private fun cameras(ctx: Context): List<Map<String, Any?>> {
        val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        return cm.cameraIdList.map { id ->
            val c = cm.getCameraCharacteristics(id)
            val size = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
            mapOf(
                "id" to id,
                "facing" to when (c.get(CameraCharacteristics.LENS_FACING)) { CameraCharacteristics.LENS_FACING_FRONT -> "depan"; CameraCharacteristics.LENS_FACING_BACK -> "belakang"; else -> "lain" },
                "mp" to size?.let { it.width * it.height / 1e6 },
                "flash" to c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE),
                "focalMm" to c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.toList(),
            )
        }
    }

    private fun sensors(ctx: Context): Map<String, Any?> {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val pm = ctx.packageManager
        fun has(t: Int) = sm.getDefaultSensor(t) != null
        return mapOf(
            "accelerometer" to has(Sensor.TYPE_ACCELEROMETER), "gyroscope" to has(Sensor.TYPE_GYROSCOPE),
            "compass" to has(Sensor.TYPE_MAGNETIC_FIELD), "proximity" to has(Sensor.TYPE_PROXIMITY),
            "light" to has(Sensor.TYPE_LIGHT), "barometer" to has(Sensor.TYPE_PRESSURE), "stepCounter" to has(Sensor.TYPE_STEP_COUNTER),
            "fingerprint" to pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT), "nfc" to pm.hasSystemFeature(PackageManager.FEATURE_NFC),
            "ir" to pm.hasSystemFeature(PackageManager.FEATURE_CONSUMER_IR), "gps" to pm.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS),
            "telephony" to pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY),
            "count" to sm.getSensorList(Sensor.TYPE_ALL).size,
        )
    }

    private fun security(ctx: Context): Map<String, Any?> {
        val suPaths = listOf("/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/app/Superuser.apk", "/data/adb/magisk", "/data/adb/ksu", "/system/bin/magisk")
        val rootApps = listOf("com.topjohnwu.magisk", "eu.chainfire.supersu", "me.weishu.kernelsu", "com.koushikdutta.superuser")
        val pm = ctx.packageManager
        val apps = rootApps.filter { try { pm.getPackageInfo(it, 0); true } catch (_: Throwable) { false } }
        return mapOf(
            "suFound" to suPaths.filter { File(it).exists() },
            "rootApps" to apps,
            "testKeys" to (Build.TAGS?.contains("test-keys") == true),
            "debuggable" to (Build.TYPE == "userdebug" || Build.TYPE == "eng"),
            "verifiedBoot" to sysprop("ro.boot.verifiedbootstate"),
            "bootloaderLocked" to sysprop("ro.boot.flash.locked"),
        )
    }

    private fun sysprop(k: String): String? = try {
        val c = Class.forName("android.os.SystemProperties")
        (c.getMethod("get", String::class.java).invoke(null, k) as String).ifEmpty { null }
    } catch (_: Throwable) { null }

    private fun thermal(ctx: Context): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 29) return mapOf("status" to null)
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val s = when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "normal"; PowerManager.THERMAL_STATUS_LIGHT -> "hangat"
            PowerManager.THERMAL_STATUS_MODERATE -> "panas"; PowerManager.THERMAL_STATUS_SEVERE -> "panas banget"
            else -> "kritis"
        }
        return mapOf("status" to s)
    }

    // ------------------------------------------------------------------ logs (adb-granted only)
    /** [what]: "crash" (recent crashes / ANR / reboots in logcat), "battery" (dumpsys battery), "batterystats" (summary). */
    fun logs(ctx: Context, what: String): String {
        return when (what) {
            "battery", "batterystats" -> {
                if (!granted(ctx, "android.permission.DUMP")) return NEED_GRANT
                run(if (what == "battery") listOf("dumpsys", "battery") else listOf("dumpsys", "batterystats", "--checkin"), 60_000)
            }
            else -> {
                if (!granted(ctx, "android.permission.READ_LOGS")) return NEED_GRANT
                run(listOf("logcat", "-d", "-t", "4000", "-b", "main,system,crash", "*:W"), 120_000)
                    .lines().filter { l -> KEYS.any { l.contains(it, ignoreCase = true) } }.takeLast(150).joinToString("\n")
                    .ifEmpty { "(ga ada crash / ANR / reboot di log terakhir)" }
            }
        }
    }

    private val KEYS = listOf("FATAL", "ANR in", "crash", "thermal", "shutdown", "reboot", "watchdog", "kernel panic", "battery", "OutOfMemory", "lowmemorykiller")
    const val NEED_GRANT = "NEED_GRANT: log sistem dikunci Android. Sekali aja dari laptop (USB debugging nyala): " +
        "adb shell pm grant id.adam.satsh android.permission.READ_LOGS && adb shell pm grant id.adam.satsh android.permission.DUMP " +
        "— lalu buka ulang satsh."

    private fun run(cmd: List<String>, maxChars: Int): String {
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().use { it.readText() }
        p.waitFor()
        return if (out.length > maxChars) out.takeLast(maxChars) else out
    }
}
