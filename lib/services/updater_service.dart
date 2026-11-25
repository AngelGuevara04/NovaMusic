import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReleaseInfo {
  final String tagName;
  final String title;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSize;

  ReleaseInfo({
    required this.tagName,
    required this.title,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSize,
  });
}

class UpdaterService {
  static const String currentVersion = '1.0.0+44';
  static const String repoOwner = 'AngelGuevara04';
  static const String repoName = 'NovaMusic';
  static const MethodChannel _channel = MethodChannel('com.ajgm1.music/updater');
  static bool _checkedThisSession = false;

  /// Revisa automáticamente al abrir la app por primera vez en el día si hay una nueva versión
  /// y muestra un cuadro de actualización de 1 solo toque muy fácil de usar.
  static Future<void> checkAndShowDailyUpdateDialog(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final release = await checkForUpdate();
      if (release == null) {
        await prefs.setString('last_daily_update_check_date', todayStr);
        return;
      }

      // Si el usuario ya pospuso ESTA misma versión hoy, no volver a insistir hasta mañana
      // (pero si salió una versión nueva distinta hoy mismo, sí mostrarla de inmediato)
      final dismissedKey = '${release.tagName}_$todayStr';
      if (prefs.getString('dismissed_update_tag_date') == dismissedKey) {
        return;
      }

      await prefs.setString('last_daily_update_check_date', todayStr);

      if (!context.mounted) return;
      await showUpdateDialog(context, release, todayStr: todayStr);
    } catch (e) {
      debugPrint('Error en revisión diaria de actualización: $e');
    }
  }

  static Future<void> showUpdateDialog(
    BuildContext context,
    ReleaseInfo release, {
    String? todayStr,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AutoUpdateDialog(release: release, todayStr: todayStr),
    );
  }

  /// Checks GitHub Releases API for the latest version.
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'NovaMusic-App',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String? ?? '';
        final title = data['name'] as String? ?? tagName;
        final body = data['body'] as String? ?? '';
        final assets = (data['assets'] as List<dynamic>?) ?? [];

        String? downloadUrl;
        int size = 0;
        for (var asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (kIsWeb) {
            if (name.endsWith('.zip') && name.contains('novamusic')) {
              downloadUrl = asset['browser_download_url'] as String?;
              size = (asset['size'] as num?)?.toInt() ?? 0;
              break;
            }
          } else {
            if (name.endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String?;
              size = (asset['size'] as num?)?.toInt() ?? 0;
              break;
            }
          }
        }

        if (downloadUrl != null) {
          final cleanTag = tagName.replaceAll('v', '').trim();
          final cleanCurrent = currentVersion.replaceAll('v', '').trim();

          if (_isNewerVersion(cleanTag, cleanCurrent)) {
            return ReleaseInfo(
              tagName: tagName,
              title: title,
              releaseNotes: body,
              apkDownloadUrl: downloadUrl,
              apkSize: size,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking update: $e');
    }
    return null;
  }

  static bool _isNewerVersion(String remote, String current) {
    try {
      int remoteBuild = _extractBuildNumber(remote);
      int currentBuild = _extractBuildNumber(current);
      if (remoteBuild != currentBuild) {
        return remoteBuild > currentBuild;
      }
      return remote != current;
    } catch (_) {
      return remote != current;
    }
  }

  static int _extractBuildNumber(String version) {
    if (version.contains('+')) {
      final parts = version.split('+');
      return int.tryParse(parts.last) ?? 0;
    }
    return 0;
  }

  static Future<File?> downloadApk(
    String downloadUrl, {
    required Function(double progress, String status) onProgress,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'NovaMusic-App';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP error ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/NovaMusic_update.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int downloadedBytes = 0;

      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0) {
          final progress = downloadedBytes / contentLength;
          final mbDownloaded = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, '$mbDownloaded MB / $mbTotal MB (${(progress * 100).toInt()}%)');
        } else {
          final mbDownloaded = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(-1.0, '$mbDownloaded MB descargados...');
        }
      }

      await sink.flush();
      await sink.close();
      return apkFile;
    } catch (e) {
      debugPrint('Error downloading APK: $e');
      return null;
    }
  }

  static Future<bool> canInstallPackages() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('canInstallPackages');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> installApk(File apkFile) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'filePath': apkFile.path,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error invoking installApk: $e');
      return false;
    }
  }

  /// Actualiza automáticamente la versión de escritorio en PC (Windows) descargando el ZIP de GitHub y reiniciando NovaMusic.exe
  static Future<bool> updatePcApp(String zipDownloadUrl) async {
    if (!kIsWeb) return false;
    try {
      final uri = Uri.parse('/api/app-update?url=${Uri.encodeComponent(zipDownloadUrl)}');
      final res = await http.get(uri).timeout(const Duration(minutes: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data is Map && data['ok'] == true;
      }
    } catch (e) {
      debugPrint('Error updating PC app: $e');
    }
    return false;
  }
}

class _AutoUpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  final String? todayStr;

  const _AutoUpdateDialog({
    Key? key,
    required this.release,
    this.todayStr,
  }) : super(key: key);

  @override
  State<_AutoUpdateDialog> createState() => _AutoUpdateDialogState();
}

class _AutoUpdateDialogState extends State<_AutoUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorText;

  Future<void> _startOneTapUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorText = null;
      _progress = kIsWeb ? -1.0 : 0.0;
      _statusText = kIsWeb
          ? 'Descargando e instalando actualización en tu PC...'
          : 'Preparando actualización...';
    });

    if (kIsWeb) {
      final ok = await UpdaterService.updatePcApp(widget.release.apkDownloadUrl);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _statusText = '¡Actualización lista! Reiniciando NovaMusic...';
        });
      } else {
        setState(() {
          _isDownloading = false;
          _errorText = 'No se pudo actualizar automáticamente la versión de PC.';
        });
      }
      return;
    }

    final apkFile = await UpdaterService.downloadApk(
      widget.release.apkDownloadUrl,
      onProgress: (p, status) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusText = status;
          });
        }
      },
    );

    if (!mounted) return;

    if (apkFile == null) {
      setState(() {
        _isDownloading = false;
        _errorText = 'No se pudo descargar la actualización. Revisa tu internet e inténtalo de nuevo.';
      });
      return;
    }

    setState(() {
      _statusText = 'Instalando automáticamente...';
    });

    final ok = await UpdaterService.installApk(apkFile);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isDownloading = false;
        _errorText = 'No se pudo abrir el instalador automático.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.system_update_rounded, color: Colors.deepPurpleAccent, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '¡Nueva actualización lista!',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versión ${widget.release.tagName}',
            style: const TextStyle(color: Color(0xFFB388FF), fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            widget.release.releaseNotes.isNotEmpty
                ? widget.release.releaseNotes
                : 'Se encontraron mejoras de rendimiento, nuevas funciones y correcciones para tu aplicación.',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress >= 0 ? _progress : null,
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _statusText,
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
      actions: _isDownloading
          ? []
          : [
              TextButton(
                onPressed: () async {
                  if (widget.todayStr != null) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                      'dismissed_update_tag_date',
                      '${widget.release.tagName}_${widget.todayStr}',
                    );
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Más tarde', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text(
                  'Actualizar ahora',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _startOneTapUpdate,
              ),
            ],
    );
  }
}
