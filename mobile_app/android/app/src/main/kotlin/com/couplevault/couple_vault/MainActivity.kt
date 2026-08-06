package com.couplevault.couple_vault

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not plain FlutterActivity) -- the local_auth
// plugin's biometric prompt needs a FragmentActivity host. See
// DECISIONS.md #27.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "couple_vault/icon_disguise"

    // A distinct push-notification sound so it's recognizable at a glance
    // without looking at the phone -- reuses the same chime already used
    // for in-app "message received" (res/raw/notify_sound.wav, copied
    // from assets/sounds/received.wav) so the sound the user already
    // associates with this app is exactly what plays for background
    // pushes too. Deliberately generic channel name/description ("বিজ্ঞপ্তি")
    // -- matches the app's icon-disguise design (project.md §6), doesn't
    // reveal what the app actually is if someone checks notification
    // settings. Must be created here (native code) since Android 8+ ties
    // sound to the channel itself, not to individual notifications, and
    // channel settings can't be changed once created -- only via
    // NotificationManager at app startup. See DECISIONS.md.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val soundUri = Uri.parse("android.resource://$packageName/${R.raw.notify_sound}")
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            "parsonal_default",
            "বিজ্ঞপ্তি",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "নতুন কার্যক্রমের বিজ্ঞপ্তি"
            setSound(soundUri, attributes)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots/screen recording app-wide, and prevent the real
        // content from ever reaching the OS recent-apps thumbnail (that
        // thumbnail is itself a screenshot, which FLAG_SECURE also blocks).
        // project.md §6.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        createNotificationChannel()
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
