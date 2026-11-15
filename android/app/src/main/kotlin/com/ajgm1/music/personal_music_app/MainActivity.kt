package com.ajgm1.music.personal_music_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
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
                "canInstallPackages" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                                return@setMethodCallHandler
                            }

                            // En Android 8+ verificar si ya tiene el permiso de fuente confiable
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                val permIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(permIntent)
                            }

                            // Intentar primero instalación silenciosa / directa por sesión de PackageInstaller (Android 12+ USER_ACTION_NOT_REQUIRED)
                            val sessionInstalled = tryInstallWithPackageInstallerSession(file)
                            if (!sessionInstalled) {
                                // Respaldo directo con FileProvider
                                launchStandardApkInstaller(file)
                            }
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

    private fun tryInstallWithPackageInstallerSession(apkFile: File): Boolean {
        return try {
            val packageInstaller = applicationContext.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(applicationContext.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Permite actualizar automáticamente sin pedir confirmación cuando esta app es la instaladora
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }

            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            FileInputStream(apkFile).use { input ->
                session.openWrite("NovaMusic_Update", 0, apkFile.length()).use { output ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                    session.fsync(output)
                }
            }

            val callbackIntent = Intent(applicationContext, UpdateInstallReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(
                applicationContext,
                sessionId,
                callbackIntent,
                flags
            )
            session.commit(pendingIntent.intentSender)
            session.close()
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun launchStandardApkInstaller(file: File) {
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
