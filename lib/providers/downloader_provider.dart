import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DownloadTask {
  String id = UniqueKey().toString();
  int notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  String url;
  String title = "Obteniendo información...";
  String? preferredTitle;
  String? preferredArtist;
  String? preferredYoutubeId;
  String? normKey;
  double progress = 0.0;
  String status = "Iniciando...";
  bool isDownloading = true;
  bool hasError = false;

  DownloadTask({
    required this.url,
    this.preferredTitle,
    this.preferredArtist,
    this.preferredYoutubeId,
    this.normKey,
  }) {
    if (preferredTitle != null && preferredTitle!.trim().isNotEmpty) {
      title = preferredTitle!.trim();
    }
  }
}

class DownloaderProvider extends ChangeNotifier {
  final YoutubeExplode _yt = YoutubeExplode();
  final List<DownloadTask> _activeDownloads = [];
  final Set<String> _downloadingCloudNormKeys = {};

  bool _isBatchDownloadingCloud = false;
  bool _cancelBatchRequested = false;
  int _batchCompletedCount = 0;
  int _batchTotalCount = 0;
  String _batchCurrentSongTitle = '';

  bool get isBatchDownloadingCloud => _isBatchDownloadingCloud;
  int get batchCompletedCount => _batchCompletedCount;
  int get batchTotalCount => _batchTotalCount;
  String get batchCurrentSongTitle => _batchCurrentSongTitle;

  bool isCloudSongDownloading(String normKey) =>
      normKey.isNotEmpty && _downloadingCloudNormKeys.contains(normKey);

  void cancelBatchCloudDownload() {
    _cancelBatchRequested = true;
    notifyListeners();
  }

  static String normalizeKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'feat\..*|ft\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'official|video|audio|lyrics|en vivo|letra|remastered', caseSensitive: false), '')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .trim();
  }
  
  List<Video> _searchResults = [];
  bool _isSearching = false;
  bool _highQualityFilter = true;
  String _lastQuery = '';

  List<Video> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get highQualityFilter => _highQualityFilter;

  void setHighQualityFilter(bool value) {
    _highQualityFilter = value;
    notifyListeners();
    if (_lastQuery.isNotEmpty) {
      searchYoutube(_lastQuery);
    }
  }

  static bool isLiveOrLowQuality(Video video) {
    final title = video.title.toLowerCase();
    return title.contains('en vivo') ||
        title.contains('live') ||
        title.contains('concierto') ||
        title.contains('festival') ||
        title.contains('recital') ||
        title.contains('acustico') ||
        title.contains('acústico') ||
        title.contains('fancam') ||
        title.contains('grabado de') ||
        title.contains('bootleg') ||
        title.contains('8d audio') ||
        title.contains('bass boost') ||
        title.contains('slowed') ||
        title.contains('reverb') ||
        title.contains('karaoke') ||
        title.contains('reaccion') ||
        title.contains('reacción');
  }

  static bool isStudioOfficial(Video video) {
    final title = video.title.toLowerCase();
    final author = video.author.toLowerCase();
    return author.contains('- topic') ||
        author.contains('vevo') ||
        author.contains('official') ||
        author.contains('records') ||
        author.contains('music') ||
        author.contains('sony') ||
        author.contains('warner') ||
        author.contains('universal') ||
        title.contains('audio oficial') ||
        title.contains('official audio') ||
        title.contains('remastered') ||
        title.contains('version del album') ||
        title.contains('album version') ||
        title.contains('(audio)') ||
        title.contains('[audio]') ||
        title.contains('lyric video') ||
        title.contains('letras');
  }

  static int getAudioQualityScore(Video video) {
    final title = video.title.toLowerCase();
    final author = video.author.toLowerCase();
    int score = 0;

    // Máxima prioridad: Pistas máster de estudio de YouTube Music ("- Topic")
    if (author.contains('- topic')) {
      score += 120;
    }

    // Alta prioridad: Audio oficial sin efectos ni diálogos de videoclip
    if (title.contains('official audio') ||
        title.contains('audio oficial') ||
        title.contains('(audio)') ||
        title.contains('[audio]') ||
        title.contains('remastered') ||
        title.contains('album version') ||
        title.contains('version del album')) {
      score += 90;
    } else if (title.contains('lyric') || title.contains('letra')) {
      score += 60;
    }

    // Canales oficiales / sellos discográficos
    if (author.contains('vevo') ||
        author.contains('official') ||
        author.contains('records') ||
        author.contains('sony') ||
        author.contains('warner') ||
        author.contains('universal') ||
        author.contains('music')) {
      score += 45;
    }

    // Penalizar grabaciones en vivo, saturadas o alteradas
    if (isLiveOrLowQuality(video)) {
      score -= 150;
    }

    // Penalizar Shorts (<45s) o compilaciones largas (>15 min)
    final dur = video.duration;
    if (dur != null) {
      if (dur.inSeconds < 45 || dur.inMinutes > 15) {
        score -= 80;
      }
    }

    return score;
  }

  String? _currentRecommendationArtist;
  String? get currentRecommendationArtist => _currentRecommendationArtist;

  static final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();
  static Future<void> Function(String actionId)? onDiscoveryNotificationAction;
  static const int discoveryNotificationId = 888999;

  // Filtro de masterización de estudio en streaming + recorte de silencio al inicio y al final:
  // - start_periods=1:start_duration=0.05:start_threshold=-44dB -> elimina todo el silencio inicial
  // - stop_periods=-1:stop_duration=1.8:stop_threshold=-48dB -> elimina silencios muertos al final sin congelar la RAM
  // - highpass=f=25, acompressor y alimiter -> sonido limpio de estudio a -0.4 dB
  static const String studioMasterAndTrimSilenceFilter =
      '-af "silenceremove=start_periods=1:start_duration=0.05:start_threshold=-44dB:stop_periods=-1:stop_duration=1.8:stop_threshold=-48dB,highpass=f=25,acompressor=threshold=-16dB:ratio=2.2:attack=15:release=200:makeup=2.5dB,alimiter=limit=0.95:attack=5:release=50"';

  static bool _initialized = false;
  
  List<DownloadTask> get activeDownloads => _activeDownloads;

  DownloaderProvider() {
    initNotificationsStatic();
  }

  static Future<void> initNotificationsStatic() async {
    if (kIsWeb) return;
    if (_initialized) return;
    
    if (Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final actionId = response.actionId;
        if (actionId != null && actionId.isNotEmpty && onDiscoveryNotificationAction != null) {
          onDiscoveryNotificationAction!(actionId);
        }
      },
    );
    _initialized = true;
  }

  static Future<void> showDiscoveryLoadingNotification(String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await initNotificationsStatic();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'discovery_channel',
      'Modo Descubrimiento ✨',
      channelDescription: 'Recomendaciones inteligentes de música nueva',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      indeterminate: true,
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/launcher_icon',
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      id: discoveryNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> showDiscoveryPlayingNotification({
    required String songTitle,
    required String artist,
    required String seedInfo,
    bool isSaved = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await initNotificationsStatic();

    final List<AndroidNotificationAction> actions = isSaved
        ? const [
            AndroidNotificationAction(
              'discovery_next',
              '⏭️ Siguiente recomendación',
              showsUserInterface: false,
              cancelNotification: false,
            ),
          ]
        : const [
            AndroidNotificationAction(
              'discovery_like',
              '❤️ Me gusta (Guardar)',
              showsUserInterface: false,
              cancelNotification: false,
            ),
            AndroidNotificationAction(
              'discovery_dislike',
              '✕ Quitar',
              showsUserInterface: false,
              cancelNotification: false,
            ),
          ];

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'discovery_channel',
      'Modo Descubrimiento ✨',
      channelDescription: 'Recomendaciones inteligentes con botones Me gusta y Quitar',
      importance: Importance.high,
      priority: Priority.high,
      onlyAlertOnce: true,
      ongoing: !isSaved,
      autoCancel: isSaved,
      icon: '@mipmap/launcher_icon',
      styleInformation: BigTextStyleInformation(
        isSaved
            ? '$artist\n✅ Descargada permanentemente en tu Lista de Canciones ($seedInfo)'
            : '$artist • $seedInfo\nToca "❤️ Me gusta" para guardarla en tu lista o "✕ Quitar" para no volver a recomendarla.',
        contentTitle: isSaved ? '✅ Guardada: $songTitle' : '✨ Recomendada: $songTitle',
      ),
      actions: actions,
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      id: discoveryNotificationId,
      title: isSaved ? '✅ Guardada: $songTitle' : '✨ Recomendada: $songTitle',
      body: '$artist • $seedInfo',
      notificationDetails: details,
    );
  }

  static Future<void> cancelDiscoveryNotification() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await notificationsPlugin.cancel(id: discoveryNotificationId);
    } catch (_) {}
  }

  String _formatBytes(num bytes) {
    if (bytes == 0) return "0 MB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Future<void> _showProgressNotification(DownloadTask task, int progressPercent, String body) async {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Descargas Activas',
      channelDescription: 'Muestra el progreso de tus descargas',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: progressPercent >= 0,
      maxProgress: 100,
      progress: progressPercent,
      icon: '@mipmap/launcher_icon',
    );
    NotificationDetails details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      id: task.notifId,
      title: task.title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> _showSuccessNotification(DownloadTask task) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'success_channel',
      'Descargas Completadas',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/launcher_icon',
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      id: task.notifId,
      title: '✅ ¡Descarga Completada!',
      body: task.title,
      notificationDetails: details,
    );
  }

  Future<void> _showErrorNotification(DownloadTask task) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'error_channel',
      'Errores de Descarga',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      id: task.notifId,
      title: '❌ Error en la descarga',
      body: task.title,
      notificationDetails: details,
    );
  }

  Future<void> searchYoutube(String query) async {
    if (query.isEmpty) return;
    _lastQuery = query;
    _isSearching = true;
    notifyListeners();

    try {
      final results = (await _yt.search.search(query).timeout(const Duration(seconds: 12))).toList();
      if (_highQualityFilter) {
        // Ordenar por puntaje de calidad de estudio (priorizando "- Topic" y "Official Audio")
        results.sort((a, b) => getAudioQualityScore(b).compareTo(getAudioQualityScore(a)));
      }
      _searchResults = results;
    } catch (e) {
      _searchResults = [];
    }

    _isSearching = false;
    notifyListeners();
  }

  Future<void> loadRecommendations(List<String> artists) async {
    if (artists.isEmpty) {
      _currentRecommendationArtist = "Top 2026";
      await searchYoutube("Musica 2026");
      return;
    }
    
    final validArtists = artists.where((a) => a.trim().isNotEmpty && a != '<unknown>' && a != 'Unknown').toList();
    if (validArtists.isEmpty) {
      _currentRecommendationArtist = "Top 2026";
      await searchYoutube("Musica 2026");
      return;
    }

    validArtists.shuffle();
    String randomArtist = validArtists.first;
    _currentRecommendationArtist = randomArtist;
    await searchYoutube("$randomArtist canciones");
  }

  Future<void> recommendForArtist(String artist) async {
    _currentRecommendationArtist = artist;
    await searchYoutube("$artist canciones");
  }

  Future<void> startDownload(
    String url, {
    required Function() onSuccess,
    String? preferredTitle,
    String? preferredArtist,
    String? preferredYoutubeId,
  }) async {
    if (url.isEmpty) return;

    // Detectar si es una playlist de YouTube
    if (!kIsWeb && (url.contains('list=') || url.contains('/playlist'))) {
      try {
        final playlistIdMatch = RegExp(r'[?&]list=([^#&?]+)').firstMatch(url);
        final playlistId = playlistIdMatch?.group(1) ?? url;

        var playlistVideos = _yt.playlists.getVideos(playlistId);
        int queuedCount = 0;

        await for (var video in playlistVideos) {
          final newTask = DownloadTask(url: video.url, preferredTitle: video.title);
          newTask.title = video.title;
          _activeDownloads.insert(0, newTask);
          notifyListeners();
          queuedCount++;

          _processDownloadTask(newTask, onSuccess);
          if (queuedCount >= 25) break;
        }
        return;
      } catch (e) {
        print("Error analizando playlist: $e");
      }
    }

    final normKey = normalizeKey(preferredTitle ?? url);
    final newTask = DownloadTask(
      url: url,
      preferredTitle: preferredTitle,
      preferredArtist: preferredArtist,
      preferredYoutubeId: preferredYoutubeId,
      normKey: normKey,
    );
    _activeDownloads.insert(0, newTask);
    notifyListeners();

    if (!kIsWeb && Platform.isAndroid) {
      _showProgressNotification(newTask, 0, "Iniciando conexión...");
    }
    await _processDownloadTask(newTask, onSuccess);
  }

  /// Descarga una canción respaldada en la nube (Supabase guarda el nombre/artista y opcionalmente youtube_id)
  /// Funciona tanto en Celular (Android) como en Computadora (Windows / Web).
  Future<bool> downloadCloudSong(
    Map<String, dynamic> cloudItem, {
    required FutureOr<void> Function() onSuccess,
  }) async {
    final rawTitle = (cloudItem['title'] ?? '').toString().trim();
    final rawArtist = (cloudItem['artist'] ?? '').toString().trim();
    final rawYtId = (cloudItem['youtube_id'] ?? '').toString().trim();
    if (rawTitle.isEmpty) return false;

    final normKey = normalizeKey(rawTitle);
    if (normKey.isNotEmpty && _downloadingCloudNormKeys.contains(normKey)) {
      return false;
    }

    if (normKey.isNotEmpty) {
      _downloadingCloudNormKeys.add(normKey);
      notifyListeners();
    }

    try {
      final bool hasValidYtId = RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(rawYtId);
      final lowerArtist = rawArtist.toLowerCase();
      final isGenericArtist = lowerArtist.isEmpty ||
          lowerArtist.contains('desconocido') ||
          lowerArtist.contains('novamusic') ||
          lowerArtist.contains('descargado') ||
          lowerArtist.contains('en la nube') ||
          lowerArtist == '<unknown>' ||
          lowerArtist == 'unknown';

      String queryOrUrl;
      if (hasValidYtId) {
        queryOrUrl = 'https://www.youtube.com/watch?v=$rawYtId';
      } else if (!isGenericArtist && !rawTitle.toLowerCase().contains(lowerArtist)) {
        queryOrUrl = '$rawArtist - $rawTitle';
      } else {
        queryOrUrl = rawTitle;
      }

      final task = DownloadTask(
        url: queryOrUrl,
        preferredTitle: rawTitle,
        preferredArtist: isGenericArtist ? null : rawArtist,
        preferredYoutubeId: hasValidYtId ? rawYtId : null,
        normKey: normKey,
      );
      _activeDownloads.insert(0, task);
      notifyListeners();

      if (!kIsWeb && Platform.isAndroid) {
        _showProgressNotification(task, 0, 'Recuperando de tu nube...');
      }

      await _processDownloadTask(task, () async {
        await onSuccess();
      });

      return !task.hasError;
    } finally {
      if (normKey.isNotEmpty) {
        _downloadingCloudNormKeys.remove(normKey);
      }
      notifyListeners();
    }
  }

  /// Descarga en lote todas las canciones de la nube que falten en este dispositivo (móvil o PC)
  Future<void> downloadAllCloudSongs(
    List<Map<String, dynamic>> missingSongs, {
    required FutureOr<void> Function() onProgressUpdate,
  }) async {
    if (_isBatchDownloadingCloud || missingSongs.isEmpty) return;

    _isBatchDownloadingCloud = true;
    _cancelBatchRequested = false;
    _batchCompletedCount = 0;
    _batchTotalCount = missingSongs.length;
    _batchCurrentSongTitle = 'Preparando descargas...';
    notifyListeners();

    try {
      for (final item in missingSongs) {
        if (_cancelBatchRequested) break;
        final title = (item['title'] ?? 'Canción').toString().trim();
        _batchCurrentSongTitle = title;
        notifyListeners();

        await downloadCloudSong(
          item,
          onSuccess: onProgressUpdate,
        );

        _batchCompletedCount++;
        notifyListeners();
      }
    } finally {
      _isBatchDownloadingCloud = false;
      _cancelBatchRequested = false;
      _batchCurrentSongTitle = '';
      await onProgressUpdate();
      notifyListeners();
    }
  }

  Future<void> _processDownloadTask(DownloadTask task, Function() onSuccess) async {
    if (kIsWeb) {
      await _downloadOnWebOrPc(task, onSuccess);
      return;
    }

    try {
      await _downloadNormalMethod(task, onSuccess);
    } catch (e) {
      task.status = 'Reintentando búsqueda alternativa en la nube...';
      task.progress = -1.0;
      notifyListeners();
      if (!kIsWeb && Platform.isAndroid) {
        _showProgressNotification(task, -1, 'Reintentando con búsqueda alternativa...');
      }

      try {
        await _downloadFallbackSearchMethod(task, onSuccess);
      } catch (fallbackError) {
        task.status = 'Error: No se pudo descargar.';
        task.hasError = true;
        task.isDownloading = false;
        notifyListeners();
        if (!kIsWeb && Platform.isAndroid) {
          _showErrorNotification(task);
        }
      }
    }
  }

  Future<void> _downloadOnWebOrPc(DownloadTask task, Function() onSuccess) async {
    try {
      task.status = 'Descargando canción a esta computadora...';
      task.progress = -1.0;
      notifyListeners();

      String ytId = task.preferredYoutubeId ?? '';
      if (ytId.isEmpty) {
        final m = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})').firstMatch(task.url);
        if (m != null) {
          ytId = m.group(1) ?? '';
        } else if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(task.url.trim())) {
          ytId = task.url.trim();
        }
      }

      final title = (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty)
          ? task.preferredTitle!.trim()
          : task.title.trim();
      final artist = (task.preferredArtist ?? '').trim();
      final query = (task.url.startsWith('http') && title.isNotEmpty && title != 'Obteniendo información...')
          ? '$artist $title'.trim()
          : (title.isNotEmpty && title != 'Obteniendo información...' ? '$artist $title'.trim() : task.url.trim());

      final uri = Uri.parse(
        '/api/save-local?id=${Uri.encodeComponent(ytId)}&q=${Uri.encodeComponent(query)}&title=${Uri.encodeComponent(title)}&artist=${Uri.encodeComponent(artist)}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 40));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['ok'] == true) {
          task.title = (data['filename'] ?? title).toString().replaceAll('.mp3', '');
          task.status = '¡Descargada en Music/NovaMusic!';
          task.progress = 1.0;
          task.isDownloading = false;
          task.hasError = false;
          notifyListeners();
          await onSuccess();
          return;
        }
      }
      throw Exception('Error en descarga local de PC (${response.statusCode})');
    } catch (e) {
      task.status = 'Error al descargar en este dispositivo.';
      task.hasError = true;
      task.isDownloading = false;
      notifyListeners();
    }
  }

  Future<Video> _searchBestVideoByName(String rawQuery) async {
    final cleanQuery = rawQuery.trim();
    final results = (await _yt.search.search(cleanQuery).timeout(const Duration(seconds: 12))).toList();
    if (results.isEmpty) {
      throw Exception('No se encontraron resultados para "$cleanQuery"');
    }
    final nonLive = results.where((v) => !isLiveOrLowQuality(v)).toList();
    final pool = nonLive.isNotEmpty ? nonLive : results;
    pool.sort((a, b) => getAudioQualityScore(b).compareTo(getAudioQualityScore(a)));
    return pool.first;
  }

  Future<String> _getDownloadsDirectory() async {
    // 1. Prioridad: Carpeta pública accesible /storage/emulated/0/Music/NovaMusic
    try {
      final targetDir = Directory('/storage/emulated/0/Music/NovaMusic');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir.path;
    } catch (_) {}

    // 2. Carpeta pública /storage/emulated/0/Download/NovaMusic
    try {
      final targetDir = Directory('/storage/emulated/0/Download/NovaMusic');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir.path;
    } catch (_) {}

    // 3. Carpeta externa Music estándar
    try {
      final musicDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (musicDirs != null && musicDirs.isNotEmpty) {
        final targetDir = Directory('${musicDirs.first.path}/NovaMusic');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        return targetDir.path;
      }
    } catch (_) {}

    // 3. Intentar ruta externa derivada
    try {
      Directory? dir = await getExternalStorageDirectory();
      if (dir != null) {
        String newPath = "";
        List<String> paths = dir.path.split("/");
        for (int x = 1; x < paths.length; x++) {
          String folder = paths[x];
          if (folder != "Android") {
            newPath += "/$folder";
          } else {
            break;
          }
        }
        newPath = "$newPath/Music/NovaMusic";
        Directory targetDir = Directory(newPath);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        return targetDir.path;
      }
    } catch (_) {}

    // 4. Fallback seguro a documentos de la app
    final appDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory('${appDir.path}/NovaMusic');
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    return fallbackDir.path;
  }

  Future<Video> _findStudioMasterIfBetter(Video original, String cleanArtist, String cleanTitle) async {
    if (!_highQualityFilter) return original;
    final origAuthor = original.author.toLowerCase();
    final origTitle = original.title.toLowerCase();

    // Si ya es una pista máster de estudio ("- Topic" o "Official Audio"), usarla directamente
    if (origAuthor.contains('- topic') ||
        origTitle.contains('official audio') ||
        origTitle.contains('audio oficial')) {
      return original;
    }

    // Si el usuario explícitamente eligió algo "en vivo" o "live", respetarlo
    if (isLiveOrLowQuality(original)) {
      return original;
    }

    try {
      final searchQuery = '$cleanArtist $cleanTitle official audio';
      final candidates = await _yt.search.search(searchQuery).timeout(const Duration( milliseconds: 3500));
      final normTargetTitle = cleanTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normTargetArtist = cleanArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      if (normTargetTitle.length < 3) return original;

      for (final c in candidates) {
        if (isLiveOrLowQuality(c)) continue;
        final cAuthor = c.author.toLowerCase();
        final cTitle = c.title.toLowerCase();
        final cNormTitle = cTitle.replaceAll(RegExp(r'[^a-z0-9]'), '');
        final cNormAuthor = cAuthor.replaceAll(RegExp(r'[^a-z0-9]'), '');

        final isTopicOrAudio = cAuthor.contains('- topic') ||
            cTitle.contains('official audio') ||
            cTitle.contains('audio oficial') ||
            cTitle.contains('(audio)');

        if (!isTopicOrAudio) continue;

        final titleMatches = cNormTitle.contains(normTargetTitle) || normTargetTitle.contains(cNormTitle);
        final artistMatches = normTargetArtist.isEmpty ||
            cNormAuthor.contains(normTargetArtist) ||
            cNormTitle.contains(normTargetArtist);

        if (titleMatches && artistMatches) {
          final dur = c.duration;
          if (dur == null || (dur.inSeconds >= 50 && dur.inMinutes <= 12)) {
            return c;
          }
        }
      }
    } catch (_) {}

    return original;
  }

  Future<StreamManifest> _fetchManifestSafely(dynamic videoId) async {
    try {
      return await _yt.videos.streamsClient
          .getManifest(videoId, requireWatchPage: false)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return await _yt.videos.streamsClient
          .getManifest(videoId, requireWatchPage: true)
          .timeout(const Duration(seconds: 10));
    }
  }

  Future<void> _downloadNormalMethod(DownloadTask task, Function() onSuccess) async {
    task.status = "Conectando con YouTube...";
    notifyListeners();

    Video video;
    final rawInput = task.url.trim();
    final isDirectVideoUrlOrId = rawInput.startsWith('http://') ||
        rawInput.startsWith('https://') ||
        RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(rawInput);

    if (isDirectVideoUrlOrId) {
      try {
        video = await _yt.videos.get(rawInput).timeout(const Duration(seconds: 10));
      } catch (_) {
        final fallbackQuery = (task.preferredTitle != null && task.preferredTitle!.isNotEmpty)
            ? '${task.preferredArtist ?? ""} ${task.preferredTitle} official audio'
            : '$rawInput official audio';
        video = await _searchBestVideoByName(fallbackQuery);
      }
    } else {
      // Caso canciones de la nube (Supabase guarda el nombre/artista)
      task.status = 'Buscando "${task.preferredTitle ?? rawInput}" en la nube...';
      notifyListeners();
      video = await _searchBestVideoByName('$rawInput official audio');
    }

    task.preferredYoutubeId = video.id.value;
    if (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty) {
      task.title = task.preferredTitle!.trim();
    } else {
      task.title = video.title;
    }
    task.status = "Analizando mejor calidad de estudio...";
    notifyListeners();
    if (!kIsWeb && Platform.isAndroid) {
      _showProgressNotification(task, 0, "Preparando audio de alta calidad...");
    }

    // Auto-etiquetado previo para búsqueda de máster de estudio
    String author = (task.preferredArtist != null && task.preferredArtist!.trim().isNotEmpty)
        ? task.preferredArtist!.trim()
        : video.author;
    String songTitle = (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty)
        ? task.preferredTitle!.trim()
        : video.title;

    author = author
        .replaceAll(RegExp(r'VEVO', caseSensitive: false), '')
        .replaceAll(RegExp(r'- Topic', caseSensitive: false), '')
        .trim();

    if (songTitle.contains(' - ') && (task.preferredArtist == null || task.preferredArtist!.isEmpty)) {
      var parts = songTitle.split(' - ');
      if (parts.length >= 2) {
        author = parts[0].trim();
        songTitle = parts[1].trim();
      }
    }

    songTitle = songTitle.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '').trim();
    if (author.isEmpty) author = "Desconocido";
    if (songTitle.isEmpty) songTitle = "Canción desconocida";

    // Buscar si existe la pista máster "- Topic" / "Official Audio" sin diálogos de videoclip
    Video audioSourceVideo = await _findStudioMasterIfBetter(video, author, songTitle);
    task.preferredYoutubeId = audioSourceVideo.id.value;

    StreamManifest manifest;
    try {
      manifest = await _fetchManifestSafely(audioSourceVideo.id);
    } catch (_) {
      audioSourceVideo = video;
      manifest = await _fetchManifestSafely(video.id);
    }

    // Priorizar muxed en el cliente Android de youtube_explode_dart porque los streams
    // adaptativos audioOnly reciben HTTP 403 (bloqueo SABR) y causan bucle infinito en "Iniciando..."
    StreamInfo? streamInfo;
    if (manifest.muxed.isNotEmpty) {
      streamInfo = manifest.muxed.withHighestBitrate();
    } else if (manifest.audioOnly.isNotEmpty) {
      streamInfo = manifest.audioOnly.withHighestBitrate();
    }
    if (streamInfo == null) throw Exception("No se encontró stream de audio compatible");

    Directory tempDir = await getTemporaryDirectory();
    final baseDisplayTitle = (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty)
        ? task.preferredTitle!.trim()
        : video.title;
    String safeTitle = baseDisplayTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
    if (safeTitle.isEmpty) safeTitle = 'NovaMusic_${DateTime.now().millisecondsSinceEpoch}';
    final ext = streamInfo.container.name.toLowerCase();
    File tempVideoFile = File('${tempDir.path}/${task.id}.$ext');

    if (await tempVideoFile.exists()) await tempVideoFile.delete();

    task.status = "Iniciando descarga...";
    notifyListeners();

    var stream = _yt.videos.streamsClient.get(streamInfo);
    var fileStream = tempVideoFile.openWrite(mode: FileMode.write);
    var totalBytes = streamInfo.size.totalBytes;
    var receivedBytes = 0;

    try {
      await for (var data in stream.timeout(const Duration(seconds: 12))) {
        receivedBytes += data.length;
        fileStream.add(data);
        double currentProgress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;

        if (currentProgress - task.progress > 0.02 || currentProgress >= 1.0) {
          task.progress = currentProgress.clamp(0.0, 1.0);
          task.status = 'Descargando: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
          notifyListeners();
          if (!kIsWeb && Platform.isAndroid) {
            _showProgressNotification(task, (task.progress * 100).toInt(), task.status);
          }
        }
      }
    } finally {
      await fileStream.flush();
      await fileStream.close();
    }

    if (receivedBytes == 0) {
      throw Exception("Descarga vacía (0 bytes)");
    }

    task.status = 'Masterizando a MP3 320kbps...';
    task.progress = -1.0;
    notifyListeners();
    if (!kIsWeb && Platform.isAndroid) {
      _showProgressNotification(task, -1, "Masterizando audio de estudio 320kbps...");
    }

    File tempThumbFile = File('${tempDir.path}/${task.id}_thumb.jpg');
    bool hasThumbnail = false;
    try {
      final thumbUrl = video.thumbnails.maxResUrl.isNotEmpty ? video.thumbnails.maxResUrl : video.thumbnails.highResUrl;
      final thumbRes = await http.get(Uri.parse(thumbUrl)).timeout(const Duration(seconds: 4));
      if (thumbRes.statusCode == 200) {
        await tempThumbFile.writeAsBytes(thumbRes.bodyBytes);
        hasThumbnail = true;
      }
    } catch (_) {}

    File tempAudioFile = File('${tempDir.path}/${task.id}.mp3');
    if (await tempAudioFile.exists()) await tempAudioFile.delete();

    // Cadena de masterización en tiempo real sin buffering en RAM (evita que FFmpeg se congele):
    String afFilter = studioMasterAndTrimSilenceFilter;
    final safeMetaTitle = baseDisplayTitle.replaceAll('"', '');
    final safeMetaArtist = author.replaceAll('"', '');
    String metadata = '-metadata title="$safeMetaTitle" -metadata artist="$safeMetaArtist"';
    String audioCodecFlags = '-ar 44100 -ac 2 -b:a 320k';

    String command;
    if (hasThumbnail) {
      command = '-y -i "${tempVideoFile.path}" -i "${tempThumbFile.path}" -map 0:a -map 1:v $afFilter $audioCodecFlags -c:v mjpeg -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" $metadata "${tempAudioFile.path}"';
    } else {
      command = '-y -i "${tempVideoFile.path}" -vn $afFilter $audioCodecFlags $metadata "${tempAudioFile.path}"';
    }

    var session = await FFmpegKit.execute(command);
    var returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      // Fallback directo a 320kbps sin filtros complejos si algún contenedor falla
      if (hasThumbnail) {
        command = '-y -i "${tempVideoFile.path}" -i "${tempThumbFile.path}" -map 0:a -map 1:v $audioCodecFlags -c:v mjpeg -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" $metadata "${tempAudioFile.path}"';
      } else {
        command = '-y -i "${tempVideoFile.path}" -vn $audioCodecFlags $metadata "${tempAudioFile.path}"';
      }
      session = await FFmpegKit.execute(command);
      returnCode = await session.getReturnCode();
    }

    if (ReturnCode.isSuccess(returnCode)) {
      await _autoSaveToDownloads(task, tempAudioFile.path, '$safeTitle.mp3', onSuccess);
    } else {
      throw Exception('FFmpeg falló');
    }

    if (await tempVideoFile.exists()) await tempVideoFile.delete();
    if (await tempAudioFile.exists()) await tempAudioFile.delete();
    if (await tempThumbFile.exists()) await tempThumbFile.delete();
  }

  Future<void> _downloadFallbackSearchMethod(DownloadTask task, Function() onSuccess) async {
    final fallbackQuery = (task.preferredTitle != null && task.preferredTitle!.isNotEmpty)
        ? '${task.preferredArtist ?? ""} ${task.preferredTitle} audio'
        : '${task.url} audio';
    final results = (await _yt.search.search(fallbackQuery).timeout(const Duration(seconds: 12))).toList();
    if (results.isEmpty) throw Exception('Sin resultados de respaldo');

    Video? workingVideo;
    StreamInfo? workingStream;
    for (final candidate in results.take(4)) {
      try {
        final manifest = await _fetchManifestSafely(candidate.id);
        if (manifest.muxed.isNotEmpty) {
          workingVideo = candidate;
          workingStream = manifest.muxed.withHighestBitrate();
          break;
        } else if (manifest.audioOnly.isNotEmpty) {
          workingVideo = candidate;
          workingStream = manifest.audioOnly.withHighestBitrate();
          break;
        }
      } catch (_) {}
    }

    if (workingVideo == null || workingStream == null) {
      throw Exception('Ningún stream alternativo funcionó');
    }

    task.preferredYoutubeId = workingVideo.id.value;
    final baseDisplayTitle = (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty)
        ? task.preferredTitle!.trim()
        : workingVideo.title;
    task.title = baseDisplayTitle;

    Directory tempDir = await getTemporaryDirectory();
    final ext = workingStream.container.name.toLowerCase();
    File tempVideoFile = File('${tempDir.path}/${task.id}_fb.$ext');
    File tempAudioFile = File('${tempDir.path}/${task.id}_fb.mp3');

    var stream = _yt.videos.streamsClient.get(workingStream);
    var fileStream = tempVideoFile.openWrite(mode: FileMode.write);
    var totalBytes = workingStream.size.totalBytes;
    var receivedBytes = 0;

    try {
      await for (var data in stream.timeout(const Duration(seconds: 15))) {
        receivedBytes += data.length;
        fileStream.add(data);
        if (totalBytes > 0) {
          double currentProgress = receivedBytes / totalBytes;
          if (currentProgress - task.progress > 0.03 || currentProgress >= 1.0) {
            task.progress = currentProgress.clamp(0.0, 1.0);
            task.status = 'Descargando: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
            notifyListeners();
          }
        }
      }
    } finally {
      await fileStream.flush();
      await fileStream.close();
    }

    final safeMetaTitle = baseDisplayTitle.replaceAll('"', '');
    final safeMetaArtist = (task.preferredArtist ?? workingVideo.author).replaceAll('"', '');
    final cmd = '-y -i "${tempVideoFile.path}" -vn -ar 44100 -ac 2 -b:a 320k -metadata title="$safeMetaTitle" -metadata artist="$safeMetaArtist" "${tempAudioFile.path}"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();

    String safeTitle = baseDisplayTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
    if (safeTitle.isEmpty) safeTitle = 'NovaMusic_${DateTime.now().millisecondsSinceEpoch}';

    if (ReturnCode.isSuccess(rc) && await tempAudioFile.exists()) {
      await _autoSaveToDownloads(task, tempAudioFile.path, '$safeTitle.mp3', onSuccess);
    } else {
      await _autoSaveToDownloads(task, tempVideoFile.path, '$safeTitle.mp3', onSuccess);
    }

    if (await tempVideoFile.exists()) await tempVideoFile.delete();
    if (await tempAudioFile.exists()) await tempAudioFile.delete();
  }

  Future<void> _autoSaveToDownloads(DownloadTask task, String tempPath, String fileName, Function() onSuccess) async {
    try {
      String targetDirectory = await _getDownloadsDirectory();

      String safeFileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      String finalPath = '$targetDirectory/$safeFileName';

      File tempFile = File(tempPath);
      await tempFile.copy(finalPath);

      if (!kIsWeb && Platform.isAndroid) {
        await MediaScanner.loadMedia(path: finalPath);
      }

      task.status = '¡Guardado!';
      task.progress = 1.0;
      task.isDownloading = false;
      notifyListeners();

      // Auto-registrar o actualizar youtube_id en la biblioteca en la nube del usuario actual
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('current_username');
        if (username != null && username.isNotEmpty) {
          final supabase = Supabase.instance.client;
          final res = await supabase.from('user_preferences').select('library_songs').eq('username', username).maybeSingle();
          List<dynamic> existing = res != null && res['library_songs'] != null ? List.from(res['library_songs']) : [];

          String ytId = task.preferredYoutubeId ?? '';
          if (ytId.isEmpty) {
            final reg = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})');
            final m = reg.firstMatch(task.url);
            if (m != null) ytId = m.group(1) ?? '';
          }

          final cleanTitle = (task.preferredTitle != null && task.preferredTitle!.trim().isNotEmpty)
              ? task.preferredTitle!.trim()
              : safeFileName
                  .replaceAll(RegExp(r'\.(mp3|m4a|wav)$', caseSensitive: false), '')
                  .replaceAll('_', ' ')
                  .trim();

          final normNew = normalizeKey(cleanTitle);
          bool updatedExisting = false;

          for (int i = 0; i < existing.length; i++) {
            final item = existing[i];
            if (item is! Map) continue;
            final itemTitle = (item['title'] ?? '').toString();
            final normExisting = normalizeKey(itemTitle);
            if (normExisting == normNew || (ytId.isNotEmpty && item['youtube_id'] == ytId)) {
              updatedExisting = true;
              if (ytId.isNotEmpty && (item['youtube_id'] == null || item['youtube_id'].toString().isEmpty)) {
                final updatedMap = Map<String, dynamic>.from(item);
                updatedMap['youtube_id'] = ytId;
                existing[i] = updatedMap;
                await supabase.from('user_preferences').update({
                  'library_songs': existing,
                  'last_active': DateTime.now().toIso8601String(),
                }).eq('username', username);
              }
              break;
            }
          }

          if (!updatedExisting) {
            existing.add({
              'id': DateTime.now().millisecondsSinceEpoch,
              'title': cleanTitle,
              'artist': task.preferredArtist ?? 'Descargado',
              'youtube_id': ytId,
              'url': finalPath,
              'file_name': safeFileName,
              'added_at': DateTime.now().toIso8601String(),
            });
            await supabase.from('user_preferences').update({
              'library_songs': existing,
              'last_active': DateTime.now().toIso8601String(),
            }).eq('username', username);
          }
        }
      } catch (e) {
        print('Error registrando canción en nube: $e');
      }

      if (!kIsWeb && Platform.isAndroid) {
        _showSuccessNotification(task);
      }
      onSuccess();
    } catch (e) {
      task.status = 'Error al guardar archivo.';
      task.hasError = true;
      task.isDownloading = false;
      notifyListeners();
      if (!kIsWeb && Platform.isAndroid) {
        _showErrorNotification(task);
      }
    }
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}


