package com.example.app.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.content.ContextCompat
import com.example.app.R
import com.example.app.data.ScanStore
import com.example.app.ui.WingmanViewModel

/**
 * A persistent floating bubble that lives on top of every app (including Discord
 * DMs). Tapping it arms a Wingman scan so the user can read the chat they are
 * currently looking at without leaving the app.
 *
 * Requires SYSTEM_ALERT_WINDOW, which the user grants in Settings › Special app
 * access › Display over other apps. Wingman asks for it the first time the
 * floating bubble is enabled.
 */
class FloatingScanService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var bubbleView: View
    private var bubbleParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "ACTION_SHOW_BUBBLE") {
            showBubble()
        } else if (intent?.action == "ACTION_HIDE_BUBBLE") {
            hideBubble()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        hideBubble()
        super.onDestroy()
    }

    private fun showBubble() {
        if (::bubbleView.isInitialized) return
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        bubbleView = LayoutInflater.from(this).inflate(R.layout.floating_bubble, null)
        val icon: ImageView = bubbleView.findViewById(R.id.floating_bubble_icon)

        // Draggable bubble.
        var initialX = 0f
        var initialY = 0f
        var initialTouchX = 0f
        var initialTouchY = 0f
        bubbleView.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = bubbleParams!!.x
                    initialY = bubbleParams!!.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    bubbleParams!!.x = (initialX + event.rawX - initialTouchX).toInt()
                    bubbleParams!!.y = (initialY + event.rawY - initialTouchY).toInt()
                    windowManager.updateViewLayout(bubbleView, bubbleParams!!)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // Short tap = arm a scan. Long drag = reposition.
                    val dx = Math.abs(event.rawX - initialTouchX)
                    val dy = Math.abs(event.rawY - initialTouchY)
                    if (dx < 12f && dy < 12f) {
                        armScanFromBubble()
                    }
                    true
                }
                else -> false
            }
        }

        // Icon tap also arms a scan.
        icon.setOnClickListener { armScanFromBubble() }

        bubbleParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 120
        }

        windowManager.addView(bubbleView, bubbleParams!!)
    }

    private fun hideBubble() {
        if (::bubbleView.isInitialized) {
            windowManager.removeView(bubbleView)
        }
    }

    /** Tells the UI layer to arm a scan, then brings Wingman to the front. */
    private fun armScanFromBubble() {
        ScanStore.arm()
        val intent = Intent(this, com.example.app.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("FLOATING_SCAN", true)
        }
        startActivity(intent)
    }

    companion object {
        fun isOverlayEnabled(context: Context): Boolean {
            return if (android.os.Build.VERSION.SDK_INT >= 23) {
                android.provider.Settings.canDrawOverlays(context)
            } else {
                true
            }
        }

        fun requestOverlayPermission(context: Context) {
            val intent = Intent(
                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }
}
