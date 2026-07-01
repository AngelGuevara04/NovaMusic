import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadTask {
  String id = UniqueKey().toString();
  int notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  String url;
  String title = "Obteniendo información...";
  double progress = 0.0;
  String status = "Iniciando...";
  bool isDownloading = true;
  bool hasError = false;

  DownloadTask({required this.url});
}

class DownloaderProvider extends ChangeNotifier {
  final YoutubeExplode _yt = YoutubeExplode();
  final List<DownloadTask> _activeDownloads = [];
  
  List<Video> _searchResults = [];
  bool _isSearching = false;

  List<Video> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  
  List<DownloadTask> get activeDownloads => _activeDownloads;

  DownloaderProvider() {
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    if (_initialized) return;
    
    if (Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(settings: initializationSettings);
    _initialized = true;
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
    await _notificationsPlugin.show(
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
    await _notificationsPlugin.show(
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
    await _notificationsPlugin.show(
      id: task.notifId,
      title: '❌ Error en la descarga',
      body: task.title,
      notificationDetails: details,
    );
  }

  Future<void> searchYoutube(String query) async {
    if (query.isEmpty) return;
    _isSearching = true;
    notifyListeners();

    try {
      final results = await _yt.search.search(query);
      _searchResults = results.toList();
    } catch (e) {
      _searchResults = [];
    }

    _isSearching = false;
    notifyListeners();
  }

  Future<void> loadRecommendations(List<String> artists) async {
    if (artists.isEmpty) {
      await searchYoutube("Musica 2026");
      return;
    }
    
    artists.shuffle();
    String randomArtist = artists.first;
    await searchYoutube("$randomArtist oficial");
  }

  void startDownload(String url, {required Function() onSuccess}) {
    if (url.isEmpty) return;
    
    final newTask = DownloadTask(url: url);
    _activeDownloads.insert(0, newTask);
    notifyListeners();

    _showProgressNotification(newTask, 0, "Iniciando conexión...");
    _processDownloadTask(newTask, onSuccess);
  }

  Future<void> _processDownloadTask(DownloadTask task, Function() onSuccess) async {
    try {
      await _downloadNormalMethod(task, onSuccess);
    } catch (e) {
      task.status = 'YouTube bloqueó. Usando servidor de respaldo...';
      task.progress = -1.0;
      notifyListeners();
      _showProgressNotification(task, -1, 'Usando servidor de respaldo...');

      try {
        await _downloadFallbackMethod(task, onSuccess);
      } catch (fallbackError) {
        task.status = 'Error: No se pudo descargar.';
        task.hasError = true;
        task.isDownloading = false;
        notifyListeners();
        _showErrorNotification(task);
      }
    }
  }

  Future<String> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
    Directory? dir = await getExternalStorageDirectory();
    String newPath = "";
    List<String> paths = dir!.path.split("/");
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
    return newPath;
  }

  Future<void> _downloadNormalMethod(DownloadTask task, Function() onSuccess) async {
    var video = await _yt.videos.get(task.url);
    task.title = video.title;
    notifyListeners();
    _showProgressNotification(task, 0, "Preparando archivo...");

    var manifest = await _yt.videos.streamsClient.getManifest(task.url);
    StreamInfo streamInfo = manifest.muxed.withHighestBitrate();

    Directory tempDir = await getTemporaryDirectory();
    String safeTitle = video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(' ', '_');
    File tempVideoFile = File('${tempDir.path}/${task.id}.mp4');
    
    // Auto-etiquetado
    String author = video.author;
    String songTitle = video.title;
    
    // Limpiar author ("VEVO", "- Topic", etc.)
    author = author.replaceAll(RegExp(r'VEVO', caseSensitive: false), '')
                   .replaceAll(RegExp(r'- Topic', caseSensitive: false), '')
                   .trim();
                   
    // Si el título tiene el formato "Artista - Canción"
    if (songTitle.contains(' - ')) {
      var parts = songTitle.split(' - ');
      if (parts.length >= 2) {
        author = parts[0].trim();
        songTitle = parts[1].trim();
      }
    }
    
    // Limpiar corchetes tipo [Official Music Video]
    songTitle = songTitle.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '').trim();
    if (author.isEmpty) author = "Desconocido";
    if (songTitle.isEmpty) songTitle = "Canción desconocida";

    if (await tempVideoFile.exists()) await tempVideoFile.delete();

    var stream = _yt.videos.streamsClient.get(streamInfo);
    var fileStream = tempVideoFile.openWrite(mode: FileMode.write);
    var totalBytes = streamInfo.size.totalBytes;
    var receivedBytes = 0;

    await for (var data in stream) {
      receivedBytes += data.length;
      fileStream.add(data);
      double currentProgress = receivedBytes / totalBytes;

      if (currentProgress - task.progress > 0.02 || currentProgress == 1.0) {
        task.progress = currentProgress;
        task.status = 'Descargando: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
        notifyListeners();
        _showProgressNotification(task, (currentProgress * 100).toInt(), task.status);
      }
    }

    await fileStream.flush();
    await fileStream.close();

    task.status = 'Convirtiendo a MP3...';
    task.progress = -1.0;
    notifyListeners();
    _showProgressNotification(task, -1, "Extrayendo audio de alta calidad...");

    File tempAudioFile = File('${tempDir.path}/${task.id}.mp3');
    if (await tempAudioFile.exists()) await tempAudioFile.delete();

    // Inyectar metadatos con ffmpeg
    String metadata = '-metadata title="$songTitle" -metadata artist="$author"';
    String command = '-y -i "${tempVideoFile.path}" -vn -b:a 192k $metadata "${tempAudioFile.path}"';
    
    var session = await FFmpegKit.execute(command);
    var returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      await _autoSaveToDownloads(task, tempAudioFile.path, '$safeTitle.mp3', onSuccess);
    } else {
      throw Exception('FFmpeg falló');
    }

    if (await tempVideoFile.exists()) await tempVideoFile.delete();
    if (await tempAudioFile.exists()) await tempAudioFile.delete();
  }

  Future<void> _downloadFallbackMethod(DownloadTask task, Function() onSuccess) async {
    final response = await http.post(
      Uri.parse('https://api.cobalt.tools/api/json'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      },
      body: jsonEncode({
        'url': task.url,
        'isAudioOnly': true,
        'aFormat': 'mp3',
      }),
    );

    if (response.statusCode != 200) throw Exception('API rechazada');

    final json = jsonDecode(response.body);
    final downloadUrl = json['url'];
    if (downloadUrl == null) throw Exception('No link');

    task.status = 'Descargando desde servidor de respaldo...';
    task.progress = 0.0;
    notifyListeners();

    var request = http.Request('GET', Uri.parse(downloadUrl));
    var streamedResponse = await request.send();

    var totalBytes = streamedResponse.contentLength ?? 0;
    var receivedBytes = 0;

    Directory tempDir = await getTemporaryDirectory();
    String safeTitle = 'NovaMusic_${DateTime.now().millisecondsSinceEpoch}';
    File tempFile = File('${tempDir.path}/${task.id}.mp3');

    var fileStream = tempFile.openWrite(mode: FileMode.write);

    await for (var data in streamedResponse.stream) {
      receivedBytes += data.length;
      fileStream.add(data);

      if (totalBytes > 0) {
        double currentProgress = receivedBytes / totalBytes;
        if (currentProgress - task.progress > 0.02 || currentProgress == 1.0) {
          task.progress = currentProgress;
          task.status = 'Respaldo: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
          notifyListeners();
          _showProgressNotification(task, (currentProgress * 100).toInt(), task.status);
        }
      } else {
        task.progress = -1.0;
        task.status = 'Respaldo: ${_formatBytes(receivedBytes)} descargados...';
        notifyListeners();
        _showProgressNotification(task, -1, task.status);
      }
    }

    await fileStream.flush();
    await fileStream.close();

    task.title = safeTitle;
    notifyListeners();
    await _autoSaveToDownloads(task, tempFile.path, '$safeTitle.mp3', onSuccess);

    if (await tempFile.exists()) await tempFile.delete();
  }

  Future<void> _autoSaveToDownloads(DownloadTask task, String tempPath, String fileName, Function() onSuccess) async {
    try {
      String targetDirectory = await _getDownloadsDirectory();

      String safeFileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      String finalPath = '$targetDirectory/$safeFileName';

      File tempFile = File(tempPath);
      await tempFile.copy(finalPath);

      if (Platform.isAndroid) {
        await MediaScanner.loadMedia(path: finalPath);
      }

      task.status = '¡Guardado!';
      task.progress = 1.0;
      task.isDownloading = false;
      notifyListeners();

      _showSuccessNotification(task);
      onSuccess();
    } catch (e) {
      task.status = 'Error al guardar archivo.';
      task.hasError = true;
      task.isDownloading = false;
      notifyListeners();
      _showErrorNotification(task);
    }
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}
