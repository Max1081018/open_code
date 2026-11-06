package com.example.app.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.app.data.CapturedText
import com.example.app.data.ScanNotifier
import com.example.app.data.ScanStore
import com.example.app.data.ScreenTranscript

/**
 * Reads the text of whatever chat is on screen, but only while the user has
 * armed a scan from inside Wingman.
 *
 * The service never stores anything by itself, never uploads anything and turns
 * itself off again as soon as one chat has been captured. Its only job is to hand
 * the visible text to [ScanStore] for the review step.
 */
class WingmanAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var attempts = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        ScanStore.setConnected(true)
        ScanStore.captureHandler = { handler.post { captureNow() } }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!ScanStore.armed.value) return

        val source = event?.packageName?.toString().orEmpty()
        if (ignored(source)) return
        attempts = 0
        schedule(450)
    }

    override fun onInterrupt() {
        pending?.let(handler::removeCallbacks)
        pending = null
    }

    override fun onUnbind(intent: Intent?): Boolean {
        cleanup()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    private fun cleanup() {
        ScanStore.setConnected(false)
        pending?.let(handler::removeCallbacks)
        pending = null
    }

    private fun schedule(delayMs: Long) {
        pending?.let(handler::removeCallbacks)
        val runnable = Runnable { captureNow() }
        pending = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun captureNow() {
        pending = null
        if (!ScanStore.armed.value) return

        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString().orEmpty()
        if (ignored(pkg)) return

        val nodes = ArrayList<CapturedText>(128)
        walk(root, nodes, 0)

        val metrics = resources.displayMetrics
        val snapshot = ScreenTranscript.snapshot(
            nodes = nodes,
            width = metrics.widthPixels,
            height = metrics.heightPixels,
            appLabel = labelFor(pkg),
            packageName = pkg
        )

        val meaningful = snapshot.lines.size >= 2 ||
            snapshot.lines.sumOf { it.text.length } >= 24

        if (!meaningful) {
            // Chat apps load in stages. Try again shortly while the user is still
            // on the same screen, then stop rather than polling forever.
            attempts++
            if (attempts <= 5 && ScanStore.armed.value) schedule(800)
            return
        }

        attempts = 0
        ScanStore.publish(snapshot)
        ScanNotifier.captured(this)
    }

    private fun walk(node: AccessibilityNodeInfo?, out: MutableList<CapturedText>, depth: Int) {
        if (node == null || depth > 40 || out.size >= 1_200) return

        val text = node.text?.toString()?.trim().orEmpty()
            .ifBlank { node.contentDescription?.toString()?.trim().orEmpty() }

        if (text.isNotEmpty() && text.length <= 1_000) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            if (!bounds.isEmpty) {
                out.add(
                    CapturedText(
                        text = text,
                        left = bounds.left,
                        top = bounds.top,
                        right = bounds.right,
                        bottom = bounds.bottom
                    )
                )
            }
        }

        for (index in 0 until node.childCount) {
            walk(node.getChild(index), out, depth + 1)
        }
    }

    private fun labelFor(pkg: String): String = runCatching {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    }.getOrDefault(pkg)

    private fun ignored(pkg: String): Boolean = pkg.isEmpty() || pkg == packageName ||
        pkg == "com.android.systemui" ||
        pkg == "com.android.settings" ||
        pkg.startsWith("com.google.android.inputmethod")
}
