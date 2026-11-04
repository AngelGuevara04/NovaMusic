package com.ajgm1.music.personal_music_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
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
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "com.ajgm1.music.channel.audio.v5"
            val channelName = "Reproductor Nova Music"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            try {
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v2")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v3")
                notificationManager.deleteNotificationChannel("com.ajgm1.music.channel.audio.v4")
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
