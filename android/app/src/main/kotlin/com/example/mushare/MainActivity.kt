package com.example.mushare

import android.content.Intent
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mushare/audio_output")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openOutputSettings" -> {
                        try {
                            // Android decide el encaminamiento de audio. Desde esta pantalla
                            // el usuario puede conectar/elegir su parlante Bluetooth.
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("OPEN_AUDIO_SETTINGS", error.message, null)
                        }
                    }
                    "openBluetoothSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("OPEN_BLUETOOTH_SETTINGS", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

    }
}
