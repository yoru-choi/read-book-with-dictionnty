package com.example.read_book_with_dictionnty

import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Launched when the user long-presses the home button and ReadBook is set as
 * the default digital-assistant app (Settings → Apps → Default apps →
 * Digital assistant app).
 *
 * Receives ACTION_ASSIST, extracts the system-provided screenshot, saves it
 * to the app cache, then starts Flutter on the "/assist" route.
 * A MethodChannel "com.readbook/assist" lets the Flutter side fetch the path
 * and close this Activity.
 */
class AssistActivity : FlutterActivity() {

    private var screenshotPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Save the screenshot BEFORE super.onCreate() so that getInitialRoute()
        // can be overridden once the FlutterEngine initialises.
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(
                "android.intent.extra.ASSIST_SCREENSHOT",
                Bitmap::class.java
            )
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("android.intent.extra.ASSIST_SCREENSHOT")
        }

        if (bitmap != null) {
            try {
                val file = File(cacheDir, "assist_screenshot.png")
                FileOutputStream(file).use { fos ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 90, fos)
                }
                screenshotPath = file.absolutePath
            } catch (_: Exception) {
                // Screenshot save failed — OcrOverlayScreen will show an error message.
            }
        }

        super.onCreate(savedInstanceState)
    }

    /** Always start Flutter on the /assist route. */
    override fun getInitialRoute(): String = "/assist"

    /** Expose screenshot path and close command to Flutter via MethodChannel. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.readbook/assist"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenshotPath" -> result.success(screenshotPath)
                "close" -> {
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        // Clean up temp file when the Activity is destroyed.
        screenshotPath?.let { File(it).delete() }
        super.onDestroy()
    }
}
