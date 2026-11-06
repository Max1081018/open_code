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
import android.widget.TextView
import com.example.app.R
import com.example.app.data.ScanStore

/**
 * A persistent floating bubble that lives on top of every app (including Discord
 * DMs). Tapping it toggles screen watching on/off. When watching, Wingman reads
 * the visible chat and suggests one reply. Tapping again stops watching.
 *
 * Requires SYSTEM_ALERT_WINDOW, granted in Settings › Special app access ›
 * Display over other apps. The app requests this automatically on launch.
 */
class FloatingScanService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var bubbleView: View
    private var bubbleParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "ACTION_SHOW_BUBBLE" -> showBubble()
            "ACTION_HIDE_BUBBLE" -> hideBubble()
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
        val stateText: TextView = bubbleView.findViewById(R.id.floating_bubble_state)

        updateBubbleVisuals(icon, stateText, watching = false)

        var initialX = 0f
        var initialY = 0f
        var initialTouchX = 0f
        var initialTouchY = 0f

        val toggleWatcher = {
            val currentlyArmed = ScanStore.armed.value
            if (currentlyArmed) {
                ScanStore.disarm()
                updateBubbleVisuals(icon, stateText, watching = false)
            } else {
                ScanStore.arm()
                updateBubbleVisuals(icon, stateText, watching = true)
            }
        }

        // Draggable bubble.
        bubbleView.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = bubbleParams!!.x.toFloat()
                    initialY = bubbleParams!!.y.toFloat()
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
                    val dx = Math.abs(event.rawX - initialTouchX)
                    val dy = Math.abs(event.rawY - initialTouchY)
                    if (dx < 12f && dy < 12f) {
                        toggleWatcher()
                    }
                    true
                }
                else -> false
            }
        }

        icon.setOnClickListener { toggleWatcher() }
        stateText.setOnClickListener { toggleWatcher() }

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

    /** Updates the bubble colour/state text based on whether screen watching is active. */
    private fun updateBubbleVisuals(icon: ImageView, stateText: TextView, watching: Boolean) {
        if (watching) {
            bubbleView.setBackgroundResource(R.drawable.floating_bubble_watching)
            stateText.text = "WATCHING"
            stateText.setTextColor(0xFFFFFFFF.toInt())
            icon.setColorFilter(0xFFFFFFFF.toInt())
        } else {
            bubbleView.setBackgroundResource(R.drawable.floating_bubble_idle)
            stateText.text = "SCAN"
            stateText.setTextColor(0xFFFFFFFF.toInt())
            icon.setColorFilter(0xFFFFFFFF.toInt())
        }
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
