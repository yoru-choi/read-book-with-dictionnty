package com.example.read_book_with_dictionnty

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles android.intent.action.PROCESS_TEXT.
 * Appears as "ReadBook에 저장" in the text-selection context menu of every app.
 *
 * Passes the selected text to Flutter via MethodChannel "com.readbook/process_text",
 * then starts Flutter on the "/process-text" route.
 */
class ProcessTextActivity : FlutterActivity() {

    private var selectedText: String? = null

    // Make the Flutter surface transparent so the calling app shows behind the popup.
    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        selectedText = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        } else {
            null
        }
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.transparent)
    }

    override fun getInitialRoute(): String = "/process-text"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.readbook/process_text"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSelectedText" -> result.success(selectedText)
                "close" -> {
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
