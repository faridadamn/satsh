package id.adam.satsh

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lets the satsh agent read and operate other apps: list what's on screen,
 * tap, type, swipe, press back/home. The user turns it on in Android's
 * Accessibility settings and can kill it any time with the floating STOP pill.
 */
class AgentControlService : AccessibilityService() {
    companion object {
        @Volatile var instance: AgentControlService? = null
        /** Called when the user hits STOP on the floating pill. */
        var onUserStop: (() -> Unit)? = null
        const val MAX_ELEMENTS = 150
    }

    private val main = Handler(Looper.getMainLooper())
    private var nodes: List<AccessibilityNodeInfo> = emptyList()
    private var marks: View? = null
    private var pill: View? = null
    private val hidePill = Runnable { removePill() }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        removeMarks(); removePill()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private val wm get() = getSystemService(Context.WINDOW_SERVICE) as WindowManager

    fun screenSize(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= 30) {
            val b = wm.maximumWindowMetrics.bounds
            return b.width() to b.height()
        }
        val m = DisplayMetrics()
        @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(m)
        return m.widthPixels to m.heightPixels
    }

    // ------------------------------------------------------------- reading
    /** What's on screen: numbered actionable elements + loose text. */
    fun tree(): JSONObject {
        val roots = mutableListOf<Pair<AccessibilityNodeInfo, String>>()
        try {
            for (w in windows) {
                if (w.type == AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY) continue
                if (w.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) continue
                val r = w.root ?: continue
                if (r.packageName?.toString() == packageName && w.type == AccessibilityWindowInfo.TYPE_APPLICATION && !w.isActive) continue
                roots += r to (when (w.type) {
                    AccessibilityWindowInfo.TYPE_SYSTEM -> "sistem"
                    AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER -> "pembatas"
                    else -> if (w.isActive) "aktif" else "lain"
                })
            }
        } catch (_: Throwable) {}
        if (roots.isEmpty()) rootInActiveWindow?.let { roots += it to "aktif" }

        val els = JSONArray()
        val texts = JSONArray()
        val kept = mutableListOf<AccessibilityNodeInfo>()
        var textLen = 0
        var pkg = ""
        val (sw, sh) = screenSize()
        val screen = Rect(0, 0, sw, sh)
        for ((root, kind) in roots) {
            if (kind == "aktif" && pkg.isEmpty()) pkg = root.packageName?.toString() ?: ""
            val stack = ArrayDeque<AccessibilityNodeInfo>()
            stack.addLast(root)
            while (stack.isNotEmpty()) {
                val n = stack.removeLast()
                for (i in n.childCount - 1 downTo 0) n.getChild(i)?.let { stack.addLast(it) }
                if (!n.isVisibleToUser) continue
                val r = Rect(); n.getBoundsInScreen(r)
                if (!r.intersect(screen) || r.width() < 2 || r.height() < 2) continue
                val text = (n.text ?: "").toString().trim()
                val desc = (n.contentDescription ?: "").toString().trim()
                val hint = if (Build.VERSION.SDK_INT >= 26) (n.hintText ?: "").toString().trim() else ""
                val label = listOf(text, desc, hint).firstOrNull { it.isNotEmpty() } ?: ""
                val act = n.isClickable || n.isLongClickable || n.isEditable || n.isCheckable || n.isScrollable
                if (act && kept.size < MAX_ELEMENTS) {
                    val cls = (n.className ?: "").toString().substringAfterLast('.')
                    // unlabeled clickable wrappers: borrow text from children
                    val shown = if (label.isEmpty()) childText(n) else label
                    kept += n
                    els.put(JSONObject().apply {
                        put("n", kept.size)
                        put("cls", cls)
                        put("t", if (n.isPassword) "(password)" else shown.take(80))
                        put("x", r.centerX()); put("y", r.centerY())
                        put("b", JSONArray(listOf(r.left, r.top, r.right, r.bottom)))
                        if (n.isEditable) put("edit", true)
                        if (n.isPassword) put("pw", true)
                        if (n.isScrollable) put("scroll", true)
                        if (n.isCheckable) put("checked", n.isChecked)
                        if (!n.isEnabled) put("off", true)
                        if (n.isFocused) put("focus", true)
                        if (kind != "aktif") put("win", kind)
                    })
                } else if (label.isNotEmpty() && !n.isPassword && textLen < 6000 && n.childCount == 0) {
                    texts.put(label.take(200)); textLen += label.length
                }
            }
        }
        nodes = kept
        return JSONObject().apply {
            put("pkg", pkg); put("els", els); put("texts", texts)
            put("sw", sw); put("sh", sh)
        }
    }

    private fun childText(n: AccessibilityNodeInfo, depth: Int = 0): String {
        if (depth > 3) return ""
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            val t = (c.text ?: c.contentDescription ?: "").toString().trim()
            if (t.isNotEmpty()) return t
            val d = childText(c, depth + 1)
            if (d.isNotEmpty()) return d
        }
        return ""
    }

    private fun node(n: Int): AccessibilityNodeInfo {
        val x = nodes.getOrNull(n - 1) ?: throw IllegalArgumentException("Elemen [$n] ga ada. Baca layar lagi (phone_ui).")
        if (!x.refresh()) throw IllegalStateException("Elemen [$n] udah hilang dari layar. Baca layar lagi (phone_ui).")
        return x
    }

    fun packageOf(n: Int): String = node(n).packageName?.toString() ?: ""
    fun activePackage(): String = rootInActiveWindow?.packageName?.toString() ?: ""

    // ------------------------------------------------------------- actions
    fun click(n: Int, long: Boolean, done: (Boolean) -> Unit) {
        val x = node(n)
        val action = if (long) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK
        var p: AccessibilityNodeInfo? = x
        while (p != null) {
            if ((if (long) p.isLongClickable else p.isClickable) && p.performAction(action)) { done(true); return }
            p = p.parent
        }
        val r = Rect(); x.getBoundsInScreen(r)
        tap(r.exactCenterX(), r.exactCenterY(), if (long) 700 else 60, done)
    }

    fun tap(x: Float, y: Float, ms: Long, done: (Boolean) -> Unit) {
        val path = Path().apply { moveTo(x, y) }
        gesture(GestureDescription.StrokeDescription(path, 0, ms.coerceAtLeast(1)), done)
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, ms: Long, done: (Boolean) -> Unit) {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        gesture(GestureDescription.StrokeDescription(path, 0, ms.coerceIn(50, 3000)), done)
    }

    private fun gesture(s: GestureDescription.StrokeDescription, done: (Boolean) -> Unit) {
        val ok = dispatchGesture(GestureDescription.Builder().addStroke(s).build(), object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) = done(true)
            override fun onCancelled(g: GestureDescription?) = done(false)
        }, main)
        if (!ok) done(false)
    }

    /** n = 0 → whatever field has focus. */
    fun type(n: Int, text: String, append: Boolean): String {
        val x = if (n == 0) findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: throw IllegalStateException("Ga ada kolom yang fokus. Tap kolomnya dulu.") else node(n)
        if (x.isPassword) return "blocked"
        if (!x.isEditable) return "noedit"
        val cur = if (append) (x.text ?: "").toString() else ""
        val b = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, cur + text) }
        x.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        return if (x.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, b)) "ok" else "fail"
    }

    /** Press the keyboard's action (search/send/next/done) on the focused field. */
    fun enter(): Boolean {
        val f = findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        if (Build.VERSION.SDK_INT >= 30) {
            return f.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        }
        return false
    }

    fun scroll(n: Int, forward: Boolean): Boolean =
        node(n).performAction(if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)

    fun key(k: String): Boolean = performGlobalAction(when (k) {
        "back" -> GLOBAL_ACTION_BACK
        "home" -> GLOBAL_ACTION_HOME
        "recents" -> GLOBAL_ACTION_RECENTS
        "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
        "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
        else -> throw IllegalArgumentException("Tombol ga dikenal: $k")
    })

    // ------------------------------------------------------------- overlays
    private fun overlayParams(touch: Boolean, full: Boolean) = WindowManager.LayoutParams(
        if (full) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
        if (full) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or (if (touch) 0 else WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE),
        PixelFormat.TRANSLUCENT
    ).apply {
        if (Build.VERSION.SDK_INT >= 28) layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
    }

    /** Numbered boxes over the last tree() result, for a marked screenshot. */
    fun showMarks() {
        removeMarks()
        val boxes = nodes.mapIndexedNotNull { i, n ->
            val r = Rect(); n.getBoundsInScreen(r); if (r.isEmpty) null else r to (i + 1)
        }
        val v = MarksView(this, boxes)
        wm.addView(v, overlayParams(touch = false, full = true))
        marks = v
    }

    fun removeMarks() {
        marks?.let { try { wm.removeView(it) } catch (_: Throwable) {} }
        marks = null
    }

    /** Floating "agent is driving — tap to STOP" pill. Auto-hides after 20s idle. */
    @SuppressLint("SetTextI18n", "ClickableViewAccessibility")
    fun showPill() {
        main.removeCallbacks(hidePill)
        if (pill == null) {
            val t = TextView(this).apply {
                text = "🤖 Agent lagi ngontrol HP · STOP"
                setTextColor(Color.WHITE)
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(36, 18, 36, 18)
                background = android.graphics.drawable.GradientDrawable().apply {
                    cornerRadius = 60f
                    setColor(Color.parseColor("#E6E5484D"))
                }
                setOnClickListener {
                    removePill()
                    onUserStop?.invoke()
                }
            }
            val p = overlayParams(touch = true, full = false).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = 140
            }
            try { wm.addView(t, p); pill = t } catch (_: Throwable) {}
        }
        main.postDelayed(hidePill, 20000)
    }

    fun removePill() {
        main.removeCallbacks(hidePill)
        pill?.let { try { wm.removeView(it) } catch (_: Throwable) {} }
        pill = null
    }

    private class MarksView(ctx: Context, val boxes: List<Pair<Rect, Int>>) : View(ctx) {
        private val stroke = Paint().apply { style = Paint.Style.STROKE; strokeWidth = 4f; color = Color.parseColor("#7C5CFF"); isAntiAlias = true }
        private val tagBg = Paint().apply { color = Color.parseColor("#7C5CFF"); isAntiAlias = true }
        private val tagText = Paint().apply { color = Color.WHITE; textSize = 30f; typeface = Typeface.MONOSPACE; isFakeBoldText = true; isAntiAlias = true }
        private val loc = IntArray(2)
        override fun onDraw(c: Canvas) {
            getLocationOnScreen(loc)
            for ((r, n) in boxes) {
                val rr = RectF(r).apply { offset(-loc[0].toFloat(), -loc[1].toFloat()) }
                c.drawRoundRect(rr, 6f, 6f, stroke)
                val label = n.toString()
                val w = tagText.measureText(label) + 12
                val top = (rr.top - 34).coerceAtLeast(0f)
                c.drawRoundRect(RectF(rr.left, top, rr.left + w, top + 34), 6f, 6f, tagBg)
                c.drawText(label, rr.left + 6, top + 27, tagText)
            }
        }
        override fun onTouchEvent(event: MotionEvent?) = false
    }
}
