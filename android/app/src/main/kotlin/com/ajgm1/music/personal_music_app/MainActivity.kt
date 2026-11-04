package com.ajgm1.music.personal_music_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.ajgm1.music/equalizer"
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initEqualizer" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    try {
                        equalizer?.release()
                        bassBoost?.release()

                        equalizer = Equalizer(0, sessionId).apply { enabled = true }
                        bassBoost = BassBoost(0, sessionId).apply { enabled = true }

                        val bands = equalizer?.numberOfBands?.toInt() ?: 0
                        val minLevel = equalizer?.bandLevelRange?.get(0)?.toInt() ?: -1500
                        val maxLevel = equalizer?.bandLevelRange?.get(1)?.toInt() ?: 1500
                        
                        val centerFreqs = mutableListOf<Int>()
                        for (i in 0 until bands) {
                            centerFreqs.add(equalizer?.getCenterFreq(i.toShort()) ?: 0)
                        }

                        val data = mapOf(
                            "bands" to bands,
                            "minLevel" to minLevel,
                            "maxLevel" to maxLevel,
                            "centerFreqs" to centerFreqs,
                            "bassBoostSupported" to (bassBoost?.strengthSupported ?: false)
                        )
                        result.success(data)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.localizedMessage, null)
                    }
                }
                "setBandLevel" -> {
                    val band = call.argument<Int>("band")?.toShort() ?: 0
                    val level = call.argument<Int>("level")?.toShort() ?: 0
                    try {
                        equalizer?.setBandLevel(band, level)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SET_BAND_ERROR", e.localizedMessage, null)
                    }
                }
                "setBassBoost" -> {
                    val strength = call.argument<Int>("strength")?.toShort() ?: 0
                    try {
                        bassBoost?.setStrength(strength)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SET_BASS_ERROR", e.localizedMessage, null)
                    }
                }
                "release" -> {
                    try {
                        equalizer?.release()
                        bassBoost?.release()
                        equalizer = null
                        bassBoost = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RELEASE_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ajgm1.music/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_ARG", "filePath is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "com.ajgm1.music.channel.audio.v6"
            val channelName = "Reproductor Nova Music"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            try {
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v2")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v3")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v4")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v5")
            } catch (e: Exception) {
                // Ignore
            }

            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Controles de reproducción multimedia"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
}
