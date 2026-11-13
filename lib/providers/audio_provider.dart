import '../models/playlist_model.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/youtube_audio_source.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:on_audio_query/on_audio_query.dart' hide PlaylistModel;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:media_scanner/media_scanner.dart';
import '../services/equalizer_service.dart';

class AudioProvider with ChangeNotifier {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<SongModel> _allSongs = [];
  List<SongModel> _visibleSongs = [];
  List<int> _hiddenSongIds = [];
  List<int> _favoriteSongIds = [];
  String? _currentUsername;
  bool _showOnlyFavorites = false;
  List<Map<String, dynamic>> _cloudLibrarySongs = [];
  List<PlaylistModel> _playlists = [];
  List<PlaylistModel> get playlists => _playlists;
  Map<String, dynamic>? _activeCloudDevice;
  Map<String, dynamic>? get activeCloudDevice => _activeCloudDevice;

  String get currentDeviceName {
    if (kIsWeb) return 'Computadora (Web)';
    if (Platform.isWindows) {
      final host = Platform.localHostname;
      return host.isNotEmpty ? 'PC ($host)' : 'Computadora (Windows)';
    }
    if (Platform.isAndroid) return 'Teléfono (Android)';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux';
    return 'Este Dispositivo';
  }

  IconData get currentDeviceIcon {
    if (kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux))) {
      return Icons.computer;
    }
    return Icons.smartphone;
  }
  bool _isConnectingCloudStream = false;
  final YoutubeExplode _ytCloud = YoutubeExplode();
  
  int? _currentIndex;
  bool _isPlaying = false;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  String _currentSort = 'title';
  String _searchQuery = '';
  
  ConcatenatingAudioSource? _playlist;
  bool _needsPlaylistRebuild = false;

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;

  AudioProvider() {
    _init();
  }

  List<SongModel> get songs {
    List<SongModel> baseList = _showOnlyFavorites
        ? _visibleSongs.where((s) => _favoriteSongIds.contains(s.id)).toList()
        : _visibleSongs;
    if (_searchQuery.isEmpty) return baseList;
    return baseList.where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase()) || (s.artist?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)).toList();
  }

  List<int> get favoriteSongIds => _favoriteSongIds;
  List<SongModel> get favoriteSongs => _allSongs.where((s) => _favoriteSongIds.contains(s.id)).toList();
  String? get currentUsername => _currentUsername;
  bool get isGuest => _currentUsername == null || _currentUsername!.isEmpty;
  bool get showOnlyFavorites => _showOnlyFavorites;
  int get totalSongsCount => _visibleSongs.length;
  int get totalFavoritesCount => _favoriteSongIds.length;
  int get totalHiddenCount => _hiddenSongIds.length;
  List<Map<String, dynamic>> get cloudLibrarySongs => _cloudLibrarySongs;
  bool get isConnectingCloudStream => _isConnectingCloudStream;
  int get localSongsCount => _visibleSongs.where((s) => !isCloudSong(s)).length;
  int get cloudOnlySongsCount => _visibleSongs.where((s) => isCloudSong(s)).length;

  bool isCloudSong(SongModel song) {
    if (kIsWeb) return true;
    if (song.getMap['is_cloud'] == true) return true;
    if (song.data.isEmpty) return true;
    try {
      final f = File(song.data);
      return !f.existsSync();
    } catch (_) {
      return true;
    }
  }

  Future<void> syncLocalSongsToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username == null || username.isEmpty) return;

    for (var s in _visibleSongs) {
      final title = s.title.trim();
      final exists = _cloudLibrarySongs.any((c) => (c['title'] ?? '').toString().toLowerCase().trim() == title.toLowerCase());
      if (!exists) {
        _cloudLibrarySongs.add({
          'id': s.id,
          'title': title,
          'artist': s.artist ?? 'Artista desconocido',
          'youtube_id': s.getMap['youtube_id'] ?? '',
          'duration': s.duration ?? 0,
          'added_at': DateTime.now().toIso8601String(),
        });
      }
    }
    await syncPreferencesToCloud();
    await fetchSongs();
    notifyListeners();
  }

  void setShowOnlyFavorites(bool val) {
    if (_showOnlyFavorites != val) {
      _showOnlyFavorites = val;
      _needsPlaylistRebuild = true;
      notifyListeners();
    }
  }

  bool isFavorite(int songId) => _favoriteSongIds.contains(songId);

  Future<void> toggleFavorite(SongModel song) async {
    if (_favoriteSongIds.contains(song.id)) {
      _favoriteSongIds.remove(song.id);
    } else {
      _favoriteSongIds.add(song.id);
    }
    _needsPlaylistRebuild = true;
    notifyListeners();
    await _saveFavoriteSongs();
  }

  Future<void> _loadFavoriteSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favorite_songs') ?? [];
    _favoriteSongIds = favList.map((e) => int.tryParse(e)).whereType<int>().toList();
  }

  Future<void> _saveFavoriteSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = _favoriteSongIds.map((e) => e.toString()).toList();
    await prefs.setStringList('favorite_songs', favList);

    final username = _currentUsername ?? prefs.getString('current_username');
    if (username != null && username.isNotEmpty) {
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('user_preferences').update({
          'favorite_songs': favList,
          'last_active': DateTime.now().toIso8601String(),
        }).eq('username', username);
      } catch (e) {
        print('Error syncing favorites to Supabase: $e');
      }
    }
  }

  Future<void> syncPreferencesToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username == null || username.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      final autoDelete = prefs.getBool('auto_delete_from_device') ?? false;
      await supabase.from('user_preferences').upsert({
        'username': username,
        'hidden_songs': _hiddenSongIds.map((e) => e.toString()).toList(),
        'favorite_songs': _favoriteSongIds.map((e) => e.toString()).toList(),
        'library_songs': _cloudLibrarySongs,
        'playlists': _playlists.map((p) => p.toJson()).toList(),
        'active_device': {
          'device_name': currentDeviceName,
          'is_playing': _isPlaying,
          'song_title': currentSong?.title ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        'auto_delete': autoDelete,
        'last_active': DateTime.now().toIso8601String(),
      });
      notifyListeners();
    } catch (e) {
      print('Error syncing all to Supabase: $e');
    }
  }

  Future<void> updateActiveDeviceInCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username == null || username.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('user_preferences').update({
        'active_device': {
          'device_name': currentDeviceName,
          'is_playing': _isPlaying,
          'song_title': currentSong?.title ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        'last_active': DateTime.now().toIso8601String(),
      }).eq('username', username);
    } catch (_) {}
  }
  
  int? get currentIndex => _currentIndex;
  
  SongModel? get currentSong {
    if (_currentIndex == null || _playlist == null || _currentIndex! >= _playlist!.children.length) return null;
    try {
      final tag = (_playlist!.children[_currentIndex!] as UriAudioSource).tag as MediaItem;
      return _allSongs.firstWhere((s) => s.id.toString() == tag.id);
    } catch (e) {
      return null;
    }
  }
  
  bool get isPlaying => _isPlaying;
  bool get isShuffle => _isShuffle;
  LoopMode get loopMode => _loopMode;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  AudioPlayer get player => _audioPlayer;
  String get currentSort => _currentSort;
  DateTime? get sleepTimerEndTime => _sleepTimerEndTime;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentSort = prefs.getString('pref_sort') ?? 'title';
    _isShuffle = prefs.getBool('pref_shuffle') ?? false;
    final savedLoop = prefs.getString('pref_loop') ?? 'off';
    if (savedLoop == 'one') {
      _loopMode = LoopMode.one;
    } else if (savedLoop == 'all') {
      _loopMode = LoopMode.all;
    } else {
      _loopMode = LoopMode.off;
    }
    
    await _audioPlayer.setShuffleModeEnabled(_isShuffle);
    await _audioPlayer.setLoopMode(_loopMode);

    // Configurar sesión de audio profesional para manejar foco y segundo plano
    await _setupAudioSession();

    _currentUsername = prefs.getString('current_username');
    final cachedLib = prefs.getString('cached_library_songs');
    if (cachedLib != null && cachedLib.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(cachedLib);
        _cloudLibrarySongs = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    await _loadHiddenSongs();
    await _loadFavoriteSongs();
    final cachedPlaylists = prefs.getString('cached_playlists');
    if (cachedPlaylists != null && cachedPlaylists.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(cachedPlaylists);
        _playlists = parsed.map((e) => PlaylistModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {}
    }
    _listenToPlayerEvents();
    await checkAndRequestPermissions();
    
    // Auto-sync from Supabase if logged in
    if (_currentUsername != null && _currentUsername!.isNotEmpty) {
      loadPreferencesFromSupabase(_currentUsername!);
    }
  }

  Future<void> _setupAudioSession() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
              _audioPlayer.pause();
              break;
            case AudioInterruptionType.unknown:
              // Do not pause on unknown events (e.g. minimizing on MagicOS/Android 14)
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              _audioPlayer.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        _audioPlayer.pause();
      });
    } catch (e) {
      print('AudioSession setup skipped: $e');
    }
  }

  void _listenToPlayerEvents() {
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.playing && !EqualizerService.isInitialized) {
        final sessionId = _audioPlayer.androidAudioSessionId;
        if (sessionId != null) {
          EqualizerService.init(sessionId);
        }
      }
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((position) {
      _currentPosition = position;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((duration) {
      _totalDuration = duration ?? Duration.zero;
      notifyListeners();
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        _currentIndex = index;
        notifyListeners();
      }
    });
  }

  Future<void> _loadHiddenSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenList = prefs.getStringList('hidden_songs') ?? [];
    _hiddenSongIds = hiddenList.map((e) => int.parse(e)).toList();
  }

  Future<void> loadPreferencesFromSupabase(String username) async {
    _currentUsername = username;
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('user_preferences')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (response != null) {
        final prefs = await SharedPreferences.getInstance();

        // 1. Ocultas
        if (response['hidden_songs'] != null) {
          List<dynamic> hidden = response['hidden_songs'];
          _hiddenSongIds = hidden.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
          final hiddenList = _hiddenSongIds.map((e) => e.toString()).toList();
          await prefs.setStringList('hidden_songs', hiddenList);
        }

        // 2. Favoritas
        if (response['favorite_songs'] != null) {
          List<dynamic> favs = response['favorite_songs'];
          _favoriteSongIds = favs.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
          final favList = _favoriteSongIds.map((e) => e.toString()).toList();
          await prefs.setStringList('favorite_songs', favList);
        }

        // 3. Auto-delete
        if (response['auto_delete'] != null) {
          final autoDel = response['auto_delete'] as bool;
          await prefs.setBool('auto_delete_from_device', autoDel);
        }

        // 4. Biblioteca personal de canciones en la nube
        if (response['library_songs'] != null) {
          List<dynamic> lib = response['library_songs'];
          _cloudLibrarySongs = lib.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
        }

        // 5. Listas de reproducción sincronizadas
        if (response['playlists'] != null) {
          List<dynamic> pls = response['playlists'];
          _playlists = pls.map((e) => PlaylistModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          await prefs.setString('cached_playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
        }

        // 6. Dispositivo activo
        if (response['active_device'] != null && response['active_device'] is Map) {
          _activeCloudDevice = Map<String, dynamic>.from(response['active_device'] as Map);
        }

        // 4. Actualizar última conexión
        try {
          await supabase.from('user_preferences').update({
            'last_active': DateTime.now().toIso8601String(),
          }).eq('username', username);
        } catch (_) {}

        _visibleSongs = _allSongs.where((song) => !_hiddenSongIds.contains(song.id)).toList();
        _applySort();
        _needsPlaylistRebuild = true;
        notifyListeners();
      }
    } catch (e) {
      print('Error loading from Supabase: $e');
    }
  }

  Future<void> _saveHiddenSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenList = _hiddenSongIds.map((e) => e.toString()).toList();
    await prefs.setStringList('hidden_songs', hiddenList);
    
    // Sync to Supabase
    final username = prefs.getString('current_username');
    if (username != null && username.isNotEmpty) {
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('user_preferences').update({
          'hidden_songs': hiddenList,
        }).eq('username', username);
      } catch (e) {
        print('Error syncing to Supabase: $e');
      }
    }
  }

  Future<void> checkAndRequestPermissions() async {
    if (kIsWeb) {
      await fetchSongs();
      return;
    }

    // Permiso de notificaciones (Android 13+)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Permiso de optimización de batería para no detener la música en segundo plano
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    PermissionStatus status = await Permission.audio.status;
    if (!status.isGranted) {
      status = await Permission.audio.request();
    }
    
    if (status.isGranted || await Permission.storage.request().isGranted) {
      await fetchSongs();
    } else {
      print("No se otorgaron permisos de almacenamiento");
    }
  }

  void searchSongs(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> sortSongsBy(String sortType) async {
    _currentSort = sortType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_sort', sortType);
    _applySort();
    _needsPlaylistRebuild = true;
    notifyListeners();
  }

  void _applySort() {
    if (_currentSort == 'title') {
      _visibleSongs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_currentSort == 'artist') {
      _visibleSongs.sort((a, b) => (a.artist ?? '').toLowerCase().compareTo((b.artist ?? '').toLowerCase()));
    } else if (_currentSort == 'date') {
      _visibleSongs.sort((a, b) {
        final dateA = a.dateAdded ?? 0;
        final dateB = b.dateAdded ?? 0;
        return dateB.compareTo(dateA); // Descendente: más nuevas primero
      });
    }
  }

  List<SongModel> get hiddenSongs => _allSongs.where((s) => _hiddenSongIds.contains(s.id)).toList();

  Future<void> fetchSongs() async {
    if (kIsWeb) {
      _allSongs = _cloudLibrarySongs.map((c) => SongModel({
        '_id': c['id'] is int ? c['id'] : int.tryParse(c['id'].toString()) ?? DateTime.now().millisecondsSinceEpoch,
        'title': c['title'] ?? 'Sin título',
        'artist': c['artist'] ?? 'Artista desconocido',
        'duration': c['duration'] is int ? c['duration'] : int.tryParse(c['duration'].toString()) ?? 0,
        '_data': c['url'] ?? '',
        'is_cloud': true,
        'youtube_id': c['youtube_id'] ?? '',
      })).toList();
      _visibleSongs = _allSongs.where((song) => !_hiddenSongIds.contains(song.id)).toList();
      _applySort();
      _needsPlaylistRebuild = true;
      notifyListeners();
      return;
    }

    final oldSongIds = _visibleSongs.map((s) => s.id).toList();
    List<SongModel> fetchedSongs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    // 2. Obtener canciones de carpetas locales de NovaMusic
    final List<File> directFiles = [];
    final candidateDirs = <String>[
      '/storage/emulated/0/Music/NovaMusic',
      '/storage/emulated/0/Download/NovaMusic',
    ];

    if (!Platform.isAndroid) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        candidateDirs.add('$userProfile\\Music');
        candidateDirs.add('$userProfile\\Music\\NovaMusic');
        candidateDirs.add('$userProfile\\Downloads');
        candidateDirs.add('$userProfile\\Downloads\\NovaMusic');
      }
    }

    try {
      final extMusic = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (extMusic != null && extMusic.isNotEmpty) {
        candidateDirs.add('${extMusic.first.path}/NovaMusic');
      }
    } catch (_) {}

    try {
      final appDoc = await getApplicationDocumentsDirectory();
      candidateDirs.add('${appDoc.path}/NovaMusic');
    } catch (_) {}

    for (var dirPath in candidateDirs) {
      try {
        final d = Directory(dirPath);
        if (d.existsSync()) {
          final files = d.listSync().whereType<File>();
          for (var file in files) {
            final lower = file.path.toLowerCase();
            if (lower.endsWith('.mp3') || lower.endsWith('.m4a') || lower.endsWith('.wav')) {
              directFiles.add(file);
            }
          }
        }
      } catch (_) {}
    }

    // 3. PIPELINE DE DEDUPLICACIÓN ESTRICTA (¡Cero duplicados, cero canciones fantasma!)
    String normalizeForDedup(String raw) {
      return raw
          .toLowerCase()
          .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')
          .replaceAll(RegExp(r'feat\..*|ft\..*', caseSensitive: false), '')
          .replaceAll(RegExp(r'official|video|audio|lyrics|en vivo|letra|remastered', caseSensitive: false), '')
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ñ', 'n')
          .trim();
    }

    final List<SongModel> verifiedSongs = [];
    final Set<String> seenPaths = {};

    void tryAddSong(SongModel song, {int? fallbackDate}) {
      if (song.data.isEmpty) return;
      final file = File(song.data);
      if (!file.existsSync()) return; // Solo archivos reales que existen físicamente en este celular

      final canonicalPath = song.data.toLowerCase().replaceAll('\\', '/');
      if (seenPaths.contains(canonicalPath)) return; // Ya agregada por ruta exacta

      final normTitle = normalizeForDedup(song.title);
      if (normTitle.isEmpty) return;

      // Comprobar si ya existe una canción con título similar o archivo duplicado
      bool isDuplicate = false;
      for (var existing in verifiedSongs) {
        final existingNorm = normalizeForDedup(existing.title);
        if (existingNorm == normTitle) {
          isDuplicate = true;
          break;
        }
        if (normTitle.length >= 6 && existingNorm.length >= 6) {
          if (normTitle.contains(existingNorm) || existingNorm.contains(normTitle)) {
            final durDiff = ((existing.duration ?? 0) - (song.duration ?? 0)).abs();
            if (durDiff < 15000 || existing.size == song.size) {
              isDuplicate = true;
              break;
            }
          }
        }
      }

      if (isDuplicate) return;

      // Asegurar fecha válida para ordenamiento por fecha
      if (song.dateAdded == null || song.dateAdded == 0) {
        try {
          song.getMap['date_added'] = fallbackDate ?? (file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000);
        } catch (_) {
          song.getMap['date_added'] = fallbackDate ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
        }
      }

      seenPaths.add(canonicalPath);
      verifiedSongs.add(song);
    }

    // 1. Agregar canciones reales de Android MediaStore
    for (var song in fetchedSongs) {
      if (song.isMusic == true || song.isPodcast == false) {
        tryAddSong(song);
      }
    }

    // 2. Agregar canciones de carpetas locales de NovaMusic que no estuvieran en MediaStore
    for (var file in directFiles) {
      final fileName = file.uri.pathSegments.last;
      final cleanTitle = fileName.replaceAll(RegExp(r'\.(mp3|m4a|wav)$', caseSensitive: false), '').replaceAll('_', ' ').trim();
      final stat = file.statSync();
      final song = SongModel({
        '_id': file.path.hashCode.abs() % 2147483647,
        'title': cleanTitle,
        'artist': 'NovaMusic',
        '_data': file.path,
        '_uri': file.uri.toString(),
        '_display_name': fileName,
        '_display_name_wo_ext': cleanTitle,
        '_size': stat.size,
        'file_extension': 'mp3',
        'date_added': stat.modified.millisecondsSinceEpoch ~/ 1000,
        'is_music': true,
        'is_podcast': false,
      });
      tryAddSong(song, fallbackDate: stat.modified.millisecondsSinceEpoch ~/ 1000);
    }

    // 3. ASIGNAR LISTA FINAL (SOLO LOCALES, 100% REPRODUCIBLES, CERO DUPLICADOS)
    _allSongs = verifiedSongs;

    // 4. Sincronizar catálogo de respaldo en la nube del usuario (sin inyectar canciones fantasma en pantalla)
    if (!isGuest) {
      bool needsCloudSync = false;
      for (var local in verifiedSongs) {
        final localNorm = normalizeForDedup(local.title);
        final inCloud = _cloudLibrarySongs.any((c) => normalizeForDedup(c['title'] ?? '') == localNorm);
        if (!inCloud) {
          _cloudLibrarySongs.add({
            'id': local.id,
            'title': local.title,
            'artist': local.artist ?? 'Artista desconocido',
            'youtube_id': '',
            'duration': local.duration ?? 0,
            'added_at': DateTime.now().toIso8601String(),
          });
          needsCloudSync = true;
        }
      }
      if (needsCloudSync) {
        await syncPreferencesToCloud();
      }
    }

    _visibleSongs = _allSongs.where((song) => !_hiddenSongIds.contains(song.id)).toList();
    _applySort();
    final newSongIds = _visibleSongs.map((s) => s.id).toList();
    final bool songsChanged = !listEquals(oldSongIds, newSongIds);

    final currentSongId = currentSong?.id;
    final wasPlaying = _isPlaying;
    final savedPosition = _currentPosition;

    if (!songsChanged && _playlist != null) {
      // Si la lista no ha cambiado, no tocar el reproductor
      notifyListeners();
      return;
    }

    if (currentSongId != null) {
      final newIndex = songs.indexWhere((s) => s.id == currentSongId);
      if (newIndex != -1) {
        _currentIndex = newIndex;
        await _setupAudioSource(
          initialIndex: newIndex,
          initialPosition: savedPosition,
        );
        if (wasPlaying) {
          try {
            await _audioPlayer.play();
          } catch (_) {}
        }
      } else {
        // La canción que sonaba fue eliminada
        await _audioPlayer.stop();
        _currentIndex = null;
        _playlist = null;
        _needsPlaylistRebuild = true;
      }
    } else {
      // Ninguna canción estaba seleccionada ni reproduciéndose.
      // NO poner la primera canción ni seleccionarla automáticamente.
      _currentIndex = null;
      _playlist = null;
      _needsPlaylistRebuild = true;
    }

    notifyListeners();
  }

  Future<void> _setupAudioSource({int initialIndex = 0, Duration initialPosition = Duration.zero}) async {
    if (_visibleSongs.isEmpty) {
      await _audioPlayer.stop();
      _playlist = null;
      _currentIndex = null;
      return;
    }

    final validIndex = (initialIndex >= 0 && initialIndex < _visibleSongs.length) ? initialIndex : 0;

    _playlist = ConcatenatingAudioSource(
      children: songs.map((song) {
        final artistName = (song.artist != null && song.artist!.isNotEmpty && song.artist != '<unknown>')
            ? song.artist!
            : 'Artista desconocido';
        final albumName = (song.album != null && song.album!.isNotEmpty && song.album != '<unknown>')
            ? song.album!
            : 'Álbum desconocido';
        final songTitle = song.title.trim().isNotEmpty ? song.title.trim() : 'Canción sin título';

        return AudioSource.uri(
          Uri.parse(song.uri!),
          tag: MediaItem(
            id: song.id.toString(),
            album: albumName,
            title: songTitle,
            artist: artistName,
            artUri: null,
          ),
        );
      }).toList(),
    );

    try {
      await _audioPlayer.setAudioSource(
        _playlist!,
        initialIndex: validIndex,
        initialPosition: initialPosition,
      );
      _currentIndex = validIndex;
      _needsPlaylistRebuild = false;
    } catch (e) {
      print("Error setting audio source: $e");
    }
  }

  Future<void> _playCloudSong(SongModel song, int index) async {
    try {
      _currentIndex = index;
      _isPlaying = false;
      _isConnectingCloudStream = true;
      notifyListeners();

      String ytId = song.getMap['youtube_id']?.toString() ?? '';
      if (ytId.isEmpty) {
        final searchResults = await _ytCloud.search.search('${song.title} ${song.artist ?? ""}');
        if (searchResults.isNotEmpty) {
          ytId = searchResults.first.id.value;
          song.getMap['youtube_id'] = ytId;
        }
      }

      if (ytId.isEmpty) {
        throw Exception("No se encontró el audio en la nube");
      }

      final manifest = await _ytCloud.videos.streamsClient.getManifest(ytId).timeout(const Duration(seconds: 12));
      StreamInfo? streamInfo;
      final mp4Audios = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4Audios.isNotEmpty) {
        streamInfo = mp4Audios.withHighestBitrate();
      } else if (manifest.audioOnly.isNotEmpty) {
        streamInfo = manifest.audioOnly.withHighestBitrate();
      } else if (manifest.muxed.isNotEmpty) {
        streamInfo = manifest.muxed.withHighestBitrate();
      }

      if (streamInfo == null) throw Exception("Stream no disponible");

      final contentType = streamInfo.container.name.toLowerCase() == 'mp4' ? 'audio/mp4' : 'audio/webm';
      final mediaItem = MediaItem(
        id: song.id.toString(),
        title: song.title,
        artist: (song.artist != null && song.artist!.isNotEmpty) ? song.artist! : 'En la Nube ☁️',
        album: 'NovaMusic Nube',
      );

      final source = YouTubeAudioSource(
        uri: streamInfo.url,
        totalBytes: streamInfo.size.totalBytes,
        contentType: contentType,
        tag: mediaItem,
      );

      await _audioPlayer.setAudioSource(source).timeout(const Duration(seconds: 12));
      _isConnectingCloudStream = false;
      _isPlaying = true;
      notifyListeners();
      await _audioPlayer.play();
      updateActiveDeviceInCloud();
    } catch (e) {
      _isConnectingCloudStream = false;
      notifyListeners();
      print('Error streaming cloud song: $e');
    }
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= _visibleSongs.length) return;

    final targetSong = songs[index];
    if (isCloudSong(targetSong)) {
      await _playCloudSong(targetSong, index);
      return;
    }

    if (_playlist == null || _needsPlaylistRebuild) {
      await _setupAudioSource(initialIndex: index);
    } else if (_currentIndex != index) {
      try {
        await _audioPlayer.seek(Duration.zero, index: index);
      } catch (e) {
        await _setupAudioSource(initialIndex: index);
      }
    }
    
    _currentIndex = index;
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final session = await AudioSession.instance;
        await session.setActive(true);
      }
      await _audioPlayer.play();
      updateActiveDeviceInCloud();
    } catch (e) {
      print("Error playing song: $e");
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
    }
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    updateActiveDeviceInCloud();
  }

  Future<void> nextSong() async {
    if (_audioPlayer.hasNext) {
      await _audioPlayer.seekToNext();
    }
  }

  Future<void> previousSong() async {
    if (_audioPlayer.hasPrevious) {
      await _audioPlayer.seekToPrevious();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> toggleShuffle() async {
    _isShuffle = !_isShuffle;
    await _audioPlayer.setShuffleModeEnabled(_isShuffle);
    if (_isShuffle) {
      await _audioPlayer.shuffle();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_shuffle', _isShuffle);
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    String loopStr = 'off';
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
      loopStr = 'all';
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
      loopStr = 'one';
    } else {
      _loopMode = LoopMode.off;
      loopStr = 'off';
    }
    await _audioPlayer.setLoopMode(_loopMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_loop', loopStr);
    notifyListeners();
  }

  Future<void> hideSong(SongModel song) async {
    if (!_hiddenSongIds.contains(song.id)) {
      _hiddenSongIds.add(song.id);
      await _saveHiddenSongs();
      
      _visibleSongs.removeWhere((s) => s.id == song.id);
      await _handleSongRemoved(song);
    }
  }

  Future<void> _handleSongRemoved(SongModel song) async {
    final isCurrent = currentSong?.id == song.id;
    final wasPlaying = _isPlaying;
    final savedPosition = _currentPosition;
    final currentId = currentSong?.id;

    if (isCurrent) {
      if (_visibleSongs.isEmpty) {
        await _audioPlayer.stop();
        _playlist = null;
        _currentIndex = null;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
        _isPlaying = false;
      } else {
        int nextIndex = _currentIndex ?? 0;
        if (nextIndex >= _visibleSongs.length) {
          nextIndex = 0;
        }
        await _audioPlayer.stop();
        _currentIndex = nextIndex;
        await _setupAudioSource(initialIndex: nextIndex, initialPosition: Duration.zero);
        if (wasPlaying) {
          try {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              final session = await AudioSession.instance;
              await session.setActive(true);
            }
            await _audioPlayer.play();
          } catch (e) {
            print("Error playing next song after deletion: $e");
          }
        }
      }
    } else if (currentId != null) {
      final newIndex = _visibleSongs.indexWhere((s) => s.id == currentId);
      if (newIndex != -1) {
        _currentIndex = newIndex;
        await _setupAudioSource(initialIndex: newIndex, initialPosition: savedPosition);
        if (wasPlaying) {
          await _audioPlayer.play();
        }
      }
    } else {
      _needsPlaylistRebuild = true;
    }

    notifyListeners();
  }

  Future<bool> deletePhysicalSong(SongModel song) async {
    if (kIsWeb) {
      _allSongs.removeWhere((s) => s.id == song.id);
      _visibleSongs.removeWhere((s) => s.id == song.id);
      await _handleSongRemoved(song);
      notifyListeners();
      return true;
    }
    try {
      final file = File(song.data);
      if (await file.exists()) {
        await file.delete();
      }
      try {
        await MediaScanner.loadMedia(path: song.data);
      } catch (e) {
        print("MediaScanner error: $e");
      }
      _allSongs.removeWhere((s) => s.id == song.id);
      _visibleSongs.removeWhere((s) => s.id == song.id);
      _hiddenSongIds.remove(song.id);
      await _saveHiddenSongs();
      await _handleSongRemoved(song);
      return true;
    } catch (e) {
      print("Error deleting physical song: $e");
      await hideSong(song);
      return false;
    }
  }

  Future<void> unhideSong(SongModel song) async {
    if (_hiddenSongIds.contains(song.id)) {
      _hiddenSongIds.remove(song.id);
      await _saveHiddenSongs();
      
      _visibleSongs.add(song);
      _applySort();
      
      _needsPlaylistRebuild = true;
      notifyListeners();
    }
  }

  Future<void> restoreAllHiddenSongs() async {
    _hiddenSongIds.clear();
    await _saveHiddenSongs();
    
    _visibleSongs = List.from(_allSongs);
    _applySort();
    
    _needsPlaylistRebuild = true;
    notifyListeners();
  }

  // ---- Playlist Management & Cloud Sync ----
  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<PlaylistModel> createPlaylist(String name) async {
    final newPlaylist = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now().toIso8601String(),
      songs: [],
    );
    _playlists.add(newPlaylist);
    await _savePlaylists();
    await syncPreferencesToCloud();
    notifyListeners();
    return newPlaylist;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _playlists[idx].name = newName;
      await _savePlaylists();
      await syncPreferencesToCloud();
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    await _savePlaylists();
    await syncPreferencesToCloud();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, SongModel song) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final exists = _playlists[idx].songs.any((s) => s.title.toLowerCase().trim() == song.title.toLowerCase().trim());
      if (!exists) {
        final ytId = song.getMap['youtube_id']?.toString() ?? '';
        final url = song.getMap['url']?.toString() ?? '';
        _playlists[idx].songs.add(PlaylistSong(
          id: song.id,
          title: song.title,
          artist: song.artist ?? 'Artista desconocido',
          duration: song.duration ?? 0,
          youtubeId: ytId,
          url: url,
          addedAt: DateTime.now().toIso8601String(),
        ));
        await _savePlaylists();
        await syncPreferencesToCloud();
        notifyListeners();
      }
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songTitle) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx].songs.removeWhere((s) => s.title == songTitle);
      await _savePlaylists();
      await syncPreferencesToCloud();
      notifyListeners();
    }
  }

  Future<void> playPlaylist(PlaylistModel playlist, {int initialIndex = 0}) async {
    if (playlist.songs.isEmpty) return;
    
    List<SongModel> playlistSongs = [];
    for (var ps in playlist.songs) {
      final localMatch = _allSongs.firstWhere(
        (s) => s.title.toLowerCase().trim() == ps.title.toLowerCase().trim() && !isCloudSong(s),
        orElse: () => SongModel({
          '_id': ps.id,
          'title': ps.title,
          'artist': ps.artist,
          'duration': ps.duration,
          '_data': ps.url,
          'is_cloud': true,
          'youtube_id': ps.youtubeId,
        }),
      );
      playlistSongs.add(localMatch);
    }
    
    _visibleSongs = playlistSongs;
    _needsPlaylistRebuild = true;
    notifyListeners();
    
    if (initialIndex >= 0 && initialIndex < _visibleSongs.length) {
      await playSong(initialIndex);
    }
  }

  // ---- Sleep Timer ----
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerEndTime = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _audioPlayer.pause();
      _sleepTimerEndTime = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
