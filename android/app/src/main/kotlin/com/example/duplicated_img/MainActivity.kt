package com.example.duplicated_img

import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.duplicated_img/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, _ -> }
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is null", null)
                    }
                }
                "scanMultipleFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths != null) {
                        MediaScannerConnection.scanFile(this, paths.toTypedArray(), null) { _, _ -> }
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Paths are null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
