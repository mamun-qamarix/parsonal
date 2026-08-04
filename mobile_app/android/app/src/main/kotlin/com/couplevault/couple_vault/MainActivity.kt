package com.couplevault.couple_vault

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "couple_vault/icon_disguise"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots/screen recording app-wide, and prevent the real
        // content from ever reaching the OS recent-apps thumbnail (that
        // thumbnail is itself a screenshot, which FLAG_SECURE also blocks).
        // project.md §6.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    // Component name suffixes for the launcher entry points declared in
    // AndroidManifest.xml. Exactly one is enabled at any time.
    private val components = mapOf(
        "real" to ".MainActivity",
        "notes" to ".AliasNotes",
        "calculator" to ".AliasCalculator",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIdentity" -> {
                    val key = call.argument<String>("identity") ?: "real"
                    setIdentity(key)
                    result.success(true)
                }
                "getIdentity" -> result.success(getCurrentIdentity())
                else -> result.notImplemented()
            }
        }
    }

    private fun setIdentity(key: String) {
        val target = components[key] ?: return
        val pm = packageManager
        for ((k, suffix) in components) {
            val state = if (k == key) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(
                ComponentName(packageName, packageName + suffix),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    private fun getCurrentIdentity(): String {
        val pm = packageManager
        for ((k, suffix) in components) {
            val state = pm.getComponentEnabledSetting(ComponentName(packageName, packageName + suffix))
            val isEnabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && k == "real")
            if (isEnabled) return k
        }
        return "real"
    }
}
