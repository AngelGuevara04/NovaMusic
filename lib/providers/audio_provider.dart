import '../models/playlist_model.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
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
import 'package:http/http.dart' as http;
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import '../services/equalizer_service.dart';
import 'downloader_provider.dart';

class AudioProvider with ChangeNotifier {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<SongModel> _allSongs = [];
  List<SongModel> _visibleSongs = [];
  List<int> _hiddenSongIds = [];
  Set<String> _hiddenSongKeys = {};
  Set<String> _deletedSongKeys = {};
  Set<String> _dislikedDiscoveryKeys = {};
  List<int> _favoriteSongIds = [];
  String? _currentUsername;
  bool _showOnlyFavorites = false;
  List<Map<String, dynamic>> _cloudLibrarySongs = [];
  List<PlaylistModel> _playlists = [];
  List<PlaylistModel> get playlists => _playlists;
  Map<String, dynamic>? _activeCloudDevice;
  Map<String, dynamic>? get activeCloudDevice => _activeCloudDevice;
  Map<String, dynamic>? _lastRemotePlaybackState;
  String? _lastHandledCommandId;
  SongModel? _currentPlayingSong;
  bool _isSingleTrackSource = false;

  // ---- Modo Descubrimiento Inteligente (Recomendaciones basadas en descargas) ----
  bool _isDiscoveryMode = false;
  bool _isLoadingDiscovery = false;
  String _discoveryStatusText = '';
  SongModel? _currentDiscoverySong;
  Video? _currentDiscoveryVideo;
  String? _currentDiscoveryTempPath;
  String _currentDiscoverySeedInfo = '';
  bool _isCurrentDiscoverySaved = false;
  final Set<String> _sessionPlayedDiscoveryIds = {};
  bool _isAutoAdvancing = false;

  bool get isDiscoveryMode => _isDiscoveryMode;
  bool get isLoadingDiscovery => _isLoadingDiscovery;
  String get discoveryStatusText => _discoveryStatusText;
  SongModel? get currentDiscoverySong => _currentDiscoverySong;
  String get currentDiscoverySeedInfo => _currentDiscoverySeedInfo;
  bool get isCurrentDiscoverySaved => _isCurrentDiscoverySaved;
  bool get isPlayingDiscoverySong =>
      _currentDiscoverySong != null && _currentPlayingSong?.id == _currentDiscoverySong?.id;

  String? _deviceId;
  String? get deviceId => _deviceId;
  List<Map<String, dynamic>> _connectedDevices = [];
  List<Map<String, dynamic>> get connectedDevices => _connectedDevices;
  RealtimeChannel? _realtimeChannel;
  Timer? _heartbeatTimer;
  Timer? _fastSyncTimer;

  String get currentDeviceName {
    if (kIsWeb) return 'Computadora (Web)';
    if (!kIsWeb && Platform.isWindows) {
      final host = Platform.localHostname;
      return host.isNotEmpty ? 'PC ($host)' : 'Computadora (Windows)';
    }
    if (!kIsWeb && Platform.isAndroid) return 'Teléfono (Android)';
    if (!kIsWeb && Platform.isIOS) return 'iPhone';
    if (!kIsWeb && Platform.isMacOS) return 'Mac';
    if (!kIsWeb && Platform.isLinux) return 'Linux';
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
    if (kIsWeb || (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)) return true;
    if (song.getMap['is_cloud'] == true) return true;
    if (song.data.isEmpty) return true;
    try {
      final f = File(song.data);
      return !f.existsSync();
    } catch (_) {
      return true;
    }
  }

  bool _isSongHiddenOrDeleted(SongModel s) {
    final norm = normalizeForDedup(s.title);
    if (_hiddenSongIds.contains(s.id)) return true;
    if (norm.isNotEmpty && (_hiddenSongKeys.contains(norm) || _deletedSongKeys.contains(norm))) return true;
    return false;
  }

  Future<void> syncLocalSongsToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username == null || username.isEmpty) return;

    // Respaldar únicamente las canciones que están en la lista de canciones activa (_visibleSongs)
    final List<Map<String, dynamic>> cleanCloud = [];
    final Set<String> seenNorms = {};

    for (var s in _visibleSongs) {
      if (_isSongHiddenOrDeleted(s)) continue;
      final title = s.title.trim();
      final norm = normalizeForDedup(title);
      if (norm.isEmpty || seenNorms.contains(norm)) continue;
      seenNorms.add(norm);

      // Conservar youtube_id previo si ya existía en _cloudLibrarySongs
      String ytId = s.getMap['youtube_id']?.toString() ?? '';
      if (ytId.isEmpty) {
        final match = _cloudLibrarySongs.firstWhere(
          (c) => normalizeForDedup(c['title'] ?? '') == norm,
          orElse: () => {},
        );
        ytId = match['youtube_id']?.toString() ?? '';
      }

      cleanCloud.add({
        'id': s.id,
        'title': title,
        'artist': s.artist ?? 'Artista desconocido',
        'youtube_id': ytId,
        'duration': s.duration ?? 0,
        'url': s.data,
        'is_cloud': true,
        'added_at': DateTime.now().toIso8601String(),
      });
    }

    _cloudLibrarySongs = cleanCloud;
    await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
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

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('local_device_id');
    if (_deviceId == null) {
      final rand = Random().nextInt(9000) + 1000;
      _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_$rand';
      await prefs.setString('local_device_id', _deviceId!);
    }
  }

  Future<void> registerDeviceInCloud() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return;
    if (_deviceId == null) await _initDeviceId();

    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('user_preferences')
          .select('connected_devices')
          .eq('username', _currentUsername!)
          .maybeSingle();

      List<dynamic> raw = res?['connected_devices'] ?? [];
      final now = DateTime.now();

      // Filtrar dispositivos vistos en los últimos 4 minutos
      List<Map<String, dynamic>> activeList = [];
      for (var item in raw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          if (m['id'] != _deviceId) {
            final lastSeen = DateTime.tryParse(m['last_seen'] ?? '');
            if (lastSeen != null && now.difference(lastSeen).inMinutes < 4) {
              activeList.add(m);
            }
          }
        }
      }

      final platformStr = kIsWeb
          ? 'web'
          : (Platform.isWindows
              ? 'windows'
              : (Platform.isAndroid
                  ? 'android'
                  : (Platform.isIOS ? 'ios' : 'desktop')));

      final cs = currentSong;
      final currentSongPayload = cs != null
          ? <String, dynamic>{
              '_id': cs.id,
              'id': cs.id,
              'title': cs.title,
              'artist': cs.artist ?? 'Artista desconocido',
              'duration': cs.duration ?? 0,
              '_data': cs.data,
              'youtube_id': cs.getMap['youtube_id'] ?? '',
            }
          : null;

      // Agregar este dispositivo con canción completa y posición actual
      activeList.add({
        'id': _deviceId,
        'name': currentDeviceName,
        'platform': platformStr,
        'last_seen': now.toIso8601String(),
        'is_playing': _isPlaying,
        'song_title': cs?.title ?? '',
        'position_ms': _currentPosition.inMilliseconds,
        if (currentSongPayload != null) 'song': currentSongPayload,
      });

      _connectedDevices = activeList;
      notifyListeners();

      final updateData = <String, dynamic>{
        'connected_devices': activeList,
        'last_active': now.toIso8601String(),
      };
      if (_isPlaying && cs != null) {
        final activeDev = {
          'device_id': _deviceId,
          'device_name': currentDeviceName,
          'is_playing': true,
          'song_title': cs.title,
          'position_ms': _currentPosition.inMilliseconds,
          'song': currentSongPayload,
          'updated_at': now.toIso8601String(),
        };
        _activeCloudDevice = activeDev;
        updateData['active_device'] = activeDev;
      }

      await supabase.from('user_preferences').update(updateData).eq('username', _currentUsername!);
    } catch (_) {}
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      registerDeviceInCloud();
    });

    _fastSyncTimer?.cancel();
    _fastSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollCloudPlaybackAndDevices();
    });
  }

  Future<void> refreshConnectedDevices() async {
    await registerDeviceInCloud();
    await _pollCloudPlaybackAndDevices();
  }

  Future<void> _pollCloudPlaybackAndDevices() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('user_preferences')
          .select('connected_devices, active_device, playback_state')
          .eq('username', _currentUsername!)
          .maybeSingle();
      if (res != null) {
        _handleIncomingCloudRecord(Map<String, dynamic>.from(res));
      }
    } catch (_) {}
  }

  void _handleIncomingCloudRecord(Map<String, dynamic> newRec) {
    bool changed = false;

    // 1. Sincronizar dispositivos conectados
    if (newRec['connected_devices'] != null && newRec['connected_devices'] is List) {
      final now = DateTime.now();
      final list = (newRec['connected_devices'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) {
            if (m['id'] == _deviceId) return true;
            final lastSeen = DateTime.tryParse(m['last_seen']?.toString() ?? '');
            return lastSeen == null || now.difference(lastSeen).inMinutes < 4;
          })
          .toList();
      _connectedDevices = list;
      changed = true;
    }

    if (newRec['active_device'] != null && newRec['active_device'] is Map) {
      _activeCloudDevice = Map<String, dynamic>.from(newRec['active_device'] as Map);
      changed = true;
    }

    // 2. Control de salida de audio remoto (tipo Spotify Connect)
    if (newRec['playback_state'] != null && newRec['playback_state'] is Map) {
      final pb = Map<String, dynamic>.from(newRec['playback_state'] as Map);
      _lastRemotePlaybackState = pb;
      final cmdId = pb['command_id']?.toString() ?? pb['updated_at']?.toString() ?? '';
      final targetId = pb['target_device_id']?.toString();
      final action = pb['action']?.toString();

      if (cmdId.isNotEmpty && cmdId != _lastHandledCommandId) {
        // Ignorar si la orden es vieja (> 45 segundos) al abrir la app
        final updatedAt = DateTime.tryParse(pb['updated_at']?.toString() ?? '');
        final isRecent = updatedAt == null || DateTime.now().difference(updatedAt).inSeconds < 45;

        _lastHandledCommandId = cmdId;

        if (isRecent) {
          if (targetId == _deviceId) {
            // Este dispositivo fue elegido como salida de audio
            if (action == 'play') {
              final songMap = pb['song'];
              final posMs = (pb['position_ms'] is num) ? (pb['position_ms'] as num).toInt() : 0;
              if (songMap is Map) {
                _playTransferredSong(Map<String, dynamic>.from(songMap), posMs);
              }
            } else if (action == 'pause') {
              _audioPlayer.pause();
            }
          } else if (targetId != null && targetId != _deviceId) {
            // Otro dispositivo tiene la salida activa: pausar este dispositivo inmediatamente
            if (_isPlaying || _audioPlayer.playing) {
              _audioPlayer.pause();
              _isPlaying = false;
            }
          }
        }
      }
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  int _findBestMatchingSongIndex(List<SongModel> list, String targetIdStr, String targetTitle, String targetArtist) {
    final normTarget = normalizeForDedup(targetTitle);
    final normFull = normalizeForDedup('$targetArtist $targetTitle');

    // 1. Coincidencia exacta por título normalizado
    if (normTarget.isNotEmpty) {
      final exactIdx = list.indexWhere((s) => normalizeForDedup(s.title) == normTarget);
      if (exactIdx != -1) return exactIdx;

      // 2. Coincidencia combinando artista + título (p. ej. "Autor - Canción" vs título="Canción", artista="Autor")
      final fullIdx = list.indexWhere((s) {
        final sNormTitle = normalizeForDedup(s.title);
        final sNormFull = normalizeForDedup('${s.artist ?? ""} ${s.title}');
        return sNormFull == normFull || sNormTitle == normFull || sNormFull == normTarget;
      });
      if (fullIdx != -1) return fullIdx;

      // 3. Coincidencia por contención de subcadena (para títulos largos con o sin artista)
      if (normTarget.length >= 5) {
        final subIdx = list.indexWhere((s) {
          final sNorm = normalizeForDedup(s.title);
          return sNorm.length >= 5 && (sNorm.contains(normTarget) || normTarget.contains(sNorm));
        });
        if (subIdx != -1) return subIdx;
      }
    }

    // 4. Respaldo por ID exacto
    if (targetIdStr.isNotEmpty) {
      final idIdx = list.indexWhere((s) => s.id.toString() == targetIdStr);
      if (idIdx != -1) return idIdx;
    }

    return -1;
  }

  Future<void> _playTransferredSong(Map<String, dynamic> songMap, int posMs) async {
    final targetIdStr = (songMap['_id'] ?? songMap['id'] ?? '').toString();
    final targetTitle = (songMap['title'] ?? '').toString();
    final targetArtist = (songMap['artist'] ?? '').toString();

    int songIdx = _findBestMatchingSongIndex(songs, targetIdStr, targetTitle, targetArtist);

    // Si hay un filtro de búsqueda o favoritos activo que oculta la canción, quitar el filtro para reproducirla
    if (songIdx == -1 && (_showOnlyFavorites || _searchQuery.isNotEmpty)) {
      final visibleIdx = _findBestMatchingSongIndex(_visibleSongs, targetIdStr, targetTitle, targetArtist);
      if (visibleIdx != -1) {
        _showOnlyFavorites = false;
        _searchQuery = '';
        _needsPlaylistRebuild = true;
        songIdx = _findBestMatchingSongIndex(songs, targetIdStr, targetTitle, targetArtist);
      }
    }

    final initialPos = posMs > 0 ? Duration(milliseconds: posMs) : Duration.zero;

    if (songIdx != -1) {
      await playSong(songIdx, initialPosition: initialPos);
    } else {
      // Si la canción no está en la lista local de este dispositivo, reproducirla directamente desde la nube
      // sin insertarla en la posición 0 para no alterar los índices de la lista
      final tempSong = SongModel({
        '_id': int.tryParse(targetIdStr) ?? DateTime.now().millisecondsSinceEpoch,
        'title': targetTitle.isNotEmpty ? targetTitle : 'Canción transferida',
        'artist': targetArtist.isNotEmpty ? targetArtist : 'En la Nube ☁️',
        'duration': songMap['duration'] is int ? songMap['duration'] : 0,
        '_data': songMap['_data'] ?? songMap['url'] ?? '',
        'is_cloud': true,
        'youtube_id': songMap['youtube_id'] ?? '',
      });
      await _playCloudSong(tempSong, -1, initialPosition: initialPos);
    }
  }

  void _subscribeToRealtimeSync() {
    if (_currentUsername == null || _currentUsername!.isEmpty) return;
    _realtimeChannel?.unsubscribe();

    final supabase = Supabase.instance.client;
    _realtimeChannel = supabase
        .channel('public:user_preferences:${_currentUsername}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_preferences',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'username',
            value: _currentUsername!,
          ),
          callback: (payload) {
            final newRec = payload.newRecord;
            if (newRec == null) return;
            _handleIncomingCloudRecord(Map<String, dynamic>.from(newRec));
          },
        )
        .subscribe();
  }

  static String normalizeForDedup(String raw) {
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

  SongModel? _resolveSongFromRemoteTitle(String rawTitle, {Map<String, dynamic>? fallbackMap}) {
    if (fallbackMap != null && (fallbackMap['title'] ?? '').toString().trim().isNotEmpty) {
      final tTitle = fallbackMap['title'].toString();
      final tArtist = (fallbackMap['artist'] ?? '').toString();
      final tId = (fallbackMap['_id'] ?? fallbackMap['id'] ?? '').toString();
      final idx = _findBestMatchingSongIndex(_visibleSongs, tId, tTitle, tArtist);
      if (idx != -1) return _visibleSongs[idx];
      return SongModel({
        '_id': int.tryParse(tId) ?? DateTime.now().millisecondsSinceEpoch,
        'title': tTitle,
        'artist': tArtist.isNotEmpty ? tArtist : 'Artista desconocido',
        'duration': fallbackMap['duration'] is int ? fallbackMap['duration'] : 0,
        '_data': fallbackMap['_data'] ?? fallbackMap['url'] ?? '',
        'is_cloud': true,
        'youtube_id': fallbackMap['youtube_id'] ?? '',
      });
    }
    if (rawTitle.trim().isEmpty) return null;
    final idx = _findBestMatchingSongIndex(_visibleSongs, '', rawTitle, '');
    if (idx != -1) return _visibleSongs[idx];
    final allIdx = _findBestMatchingSongIndex(_allSongs, '', rawTitle, '');
    if (allIdx != -1) return _allSongs[allIdx];
    final norm = normalizeForDedup(rawTitle);
    final cloudMatch = _cloudLibrarySongs.firstWhere(
      (c) => normalizeForDedup(c['title'] ?? '') == norm,
      orElse: () => {},
    );
    if (cloudMatch.isNotEmpty) {
      return SongModel({
        '_id': int.tryParse(cloudMatch['id']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
        'title': cloudMatch['title'] ?? rawTitle,
        'artist': cloudMatch['artist'] ?? 'Artista desconocido',
        'duration': cloudMatch['duration'] is int ? cloudMatch['duration'] : 0,
        '_data': cloudMatch['url'] ?? '',
        'is_cloud': true,
        'youtube_id': cloudMatch['youtube_id'] ?? '',
      });
    }
    return SongModel({
      '_id': DateTime.now().millisecondsSinceEpoch,
      'title': rawTitle,
      'artist': 'En la Nube ☁️',
      'duration': 0,
      '_data': '',
      'is_cloud': true,
      'youtube_id': '',
    });
  }

  Future<void> switchAudioOutput(String targetDeviceId) async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return;
    if (_deviceId == null) await _initDeviceId();

    // Sincronizar primero con la nube para tener el estado más reciente del otro dispositivo
    await _pollCloudPlaybackAndDevices();

    SongModel? songToTransfer;
    int positionMs = 0;

    // 1. Si ESTE dispositivo está reproduciendo activamente ahora mismo, transferir su canción actual
    if (_isPlaying && currentSong != null) {
      songToTransfer = currentSong;
      positionMs = _currentPosition.inMilliseconds;
    }

    // 2. Si este dispositivo NO está reproduciendo, buscar qué canción está sonando en el otro dispositivo activo
    if (songToTransfer == null) {
      // Buscar primero en connected_devices algún dispositivo remoto con is_playing == true
      final playingRemoteDev = _connectedDevices.firstWhere(
        (d) => d['id'] != _deviceId && d['is_playing'] == true && ((d['song_title'] ?? '').toString().isNotEmpty || d['song'] is Map),
        orElse: () => {},
      );
      if (playingRemoteDev.isNotEmpty) {
        final remoteSongMap = playingRemoteDev['song'] is Map
            ? Map<String, dynamic>.from(playingRemoteDev['song'] as Map)
            : null;
        songToTransfer = _resolveSongFromRemoteTitle(
          (playingRemoteDev['song_title'] ?? '').toString(),
          fallbackMap: remoteSongMap,
        );
        if (playingRemoteDev['position_ms'] is num) {
          positionMs = (playingRemoteDev['position_ms'] as num).toInt();
        }
      }
    }

    // 3. Revisar _activeCloudDevice si pertenece a otro dispositivo o tiene canción activa
    if (songToTransfer == null && _activeCloudDevice != null) {
      final activeTitle = (_activeCloudDevice!['song_title'] ?? '').toString();
      final activeSongMap = _activeCloudDevice!['song'] is Map
          ? Map<String, dynamic>.from(_activeCloudDevice!['song'] as Map)
          : null;
      if (activeTitle.isNotEmpty || activeSongMap != null) {
        songToTransfer = _resolveSongFromRemoteTitle(activeTitle, fallbackMap: activeSongMap);
        if (_activeCloudDevice!['position_ms'] is num) {
          positionMs = (_activeCloudDevice!['position_ms'] as num).toInt();
        }
      }
    }

    // 4. Si en este dispositivo hay una canción seleccionada (aunque esté en pausa), usarla antes que estados viejos
    if (songToTransfer == null && currentSong != null) {
      songToTransfer = currentSong;
      positionMs = _currentPosition.inMilliseconds;
    }

    // 5. Respaldo del último playback_state remoto
    if (songToTransfer == null && _lastRemotePlaybackState != null && _lastRemotePlaybackState!['song'] is Map) {
      final remoteSongMap = Map<String, dynamic>.from(_lastRemotePlaybackState!['song'] as Map);
      songToTransfer = _resolveSongFromRemoteTitle(
        (remoteSongMap['title'] ?? '').toString(),
        fallbackMap: remoteSongMap,
      );
      positionMs = (_lastRemotePlaybackState!['position_ms'] is num)
          ? (_lastRemotePlaybackState!['position_ms'] as num).toInt()
          : 0;
    }

    // 6. Último recurso: primera canción de la lista
    if (songToTransfer == null && songs.isNotEmpty) {
      songToTransfer = songs.first;
      positionMs = 0;
    }
    if (songToTransfer == null) return;

    final targetName = targetDeviceId == _deviceId
        ? currentDeviceName
        : (_connectedDevices.firstWhere(
              (d) => d['id'] == targetDeviceId,
              orElse: () => {'name': 'Dispositivo Remoto'},
            )['name'] ??
            'Dispositivo Remoto');

    final commandId = 'cmd_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final songPayload = <String, dynamic>{
      '_id': songToTransfer.id,
      'id': songToTransfer.id,
      'title': songToTransfer.title,
      'artist': songToTransfer.artist ?? 'Artista desconocido',
      'duration': songToTransfer.duration ?? 0,
      '_data': songToTransfer.data,
      'youtube_id': songToTransfer.getMap['youtube_id'] ?? '',
    };

    try {
      final supabase = Supabase.instance.client;
      final nowIso = DateTime.now().toIso8601String();
      final newActiveDevice = {
        'device_id': targetDeviceId,
        'device_name': targetName,
        'is_playing': true,
        'song_title': songToTransfer.title,
        'position_ms': positionMs,
        'song': songPayload,
        'updated_at': nowIso,
      };
      final newPlaybackState = {
        'command_id': commandId,
        'target_device_id': targetDeviceId,
        'action': 'play',
        'song': songPayload,
        'position_ms': positionMs,
        'sender_device_id': _deviceId,
        'updated_at': nowIso,
      };

      _activeCloudDevice = newActiveDevice;
      _lastRemotePlaybackState = newPlaybackState;

      if (targetDeviceId == _deviceId) {
        // Traer la salida de audio a ESTE dispositivo
        _lastHandledCommandId = commandId;
        await supabase.from('user_preferences').update({
          'playback_state': newPlaybackState,
          'active_device': newActiveDevice,
          'last_active': nowIso,
        }).eq('username', _currentUsername!);
        await _playTransferredSong(songPayload, positionMs);
      } else {
        // Enviar la salida de audio a OTRO dispositivo y pausar este
        _lastHandledCommandId = commandId;
        await _audioPlayer.pause();
        _isPlaying = false;
        notifyListeners();

        await supabase.from('user_preferences').update({
          'playback_state': newPlaybackState,
          'active_device': newActiveDevice,
          'last_active': nowIso,
        }).eq('username', _currentUsername!);
      }
      notifyListeners();
    } catch (e) {
      print('Error switching audio output: $e');
    }
  }

  /// Sobrescribir toda la biblioteca de la nube desde 0 ÚNICAMENTE con las canciones actuales en la lista de canciones
  Future<bool> overwriteCloudLibraryWithDeviceSongs() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return false;
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();

      // Tomar EXCLUSIVAMENTE las canciones que están en la lista de canciones visible (_visibleSongs)
      // y que NO estén ocultas ni eliminadas. En celular priorizamos archivos físicos reales.
      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final List<SongModel> currentListSongs = _visibleSongs.where((s) {
        if (_isSongHiddenOrDeleted(s)) return false;
        if (isMobile && isCloudSong(s)) return false;
        return true;
      }).toList();

      final List<Map<String, dynamic>> newLibrary = [];
      final Set<String> seenNorms = {};

      for (var s in currentListSongs) {
        final norm = normalizeForDedup(s.title);
        if (norm.isEmpty || seenNorms.contains(norm)) continue;
        seenNorms.add(norm);

        String ytId = s.getMap['youtube_id']?.toString() ?? '';
        if (ytId.isEmpty) {
          final oldMatch = _cloudLibrarySongs.firstWhere(
            (c) => normalizeForDedup(c['title'] ?? '') == norm,
            orElse: () => {},
          );
          ytId = oldMatch['youtube_id']?.toString() ?? '';
        }

        newLibrary.add({
          'id': s.id,
          'title': s.title.trim(),
          'artist': s.artist ?? 'Artista desconocido',
          'duration': s.duration ?? 0,
          'url': s.data,
          'youtube_id': ytId,
          'is_cloud': true,
          'added_at': DateTime.now().toIso8601String(),
        });
      }

      // Actualizar en Supabase reemplazando desde 0 library_songs y hidden_songs
      await supabase.from('user_preferences').update({
        'library_songs': newLibrary,
        'hidden_songs': _hiddenSongIds.map((e) => e.toString()).toList(),
        'last_active': DateTime.now().toIso8601String(),
      }).eq('username', _currentUsername!);

      _cloudLibrarySongs = newLibrary;
      await prefs.setString('cached_library_songs', jsonEncode(newLibrary));

      await fetchSongs();
      notifyListeners();
      return true;
    } catch (e) {
      print('Error overwriting cloud library: $e');
      return false;
    }
  }

  /// Fusionar las canciones activas de la lista de este dispositivo con la nube (respetando las eliminadas/ocultas)
  Future<bool> mergeDeviceSongsIntoCloudLibrary() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return false;
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();

      // Primero limpiar de la nube cualquier canción que haya sido ocultada o eliminada en este dispositivo
      final existing = _cloudLibrarySongs.where((c) {
        final norm = normalizeForDedup(c['title'] ?? '');
        final idInt = int.tryParse(c['id']?.toString() ?? '');
        if (idInt != null && _hiddenSongIds.contains(idInt)) return false;
        if (norm.isNotEmpty && (_hiddenSongKeys.contains(norm) || _deletedSongKeys.contains(norm))) return false;
        return true;
      }).toList();

      final activeListSongs = _visibleSongs.where((s) => !_isSongHiddenOrDeleted(s) && !isCloudSong(s)).toList();

      for (var s in activeListSongs) {
        final normTitle = normalizeForDedup(s.title);
        if (normTitle.isEmpty) continue;
        final exists = existing.any((c) {
          final cId = c['id']?.toString();
          final cTitle = normalizeForDedup(c['title'] ?? '');
          return cId == s.id.toString() || cTitle == normTitle;
        });

        if (!exists) {
          existing.add({
            'id': s.id,
            'title': s.title.trim(),
            'artist': s.artist ?? 'Artista desconocido',
            'duration': s.duration ?? 0,
            'url': s.data,
            'youtube_id': s.getMap['youtube_id'] ?? '',
            'is_cloud': true,
            'added_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await supabase.from('user_preferences').update({
        'library_songs': existing,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('username', _currentUsername!);

      _cloudLibrarySongs = existing;
      await prefs.setString('cached_library_songs', jsonEncode(existing));

      await fetchSongs();
      notifyListeners();
      return true;
    } catch (e) {
      print('Error merging cloud library: $e');
      return false;
    }
  }

  /// Limpiar toda la biblioteca en la nube
  Future<bool> clearCloudLibrary() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return false;
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('user_preferences').update({
        'library_songs': [],
        'last_active': DateTime.now().toIso8601String(),
      }).eq('username', _currentUsername!);

      _cloudLibrarySongs = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_library_songs');

      await fetchSongs();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> updateActiveDeviceInCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username == null || username.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      final cs = currentSong;
      final songPayload = cs != null
          ? <String, dynamic>{
              '_id': cs.id,
              'id': cs.id,
              'title': cs.title,
              'artist': cs.artist ?? 'Artista desconocido',
              'duration': cs.duration ?? 0,
              '_data': cs.data,
              'youtube_id': cs.getMap['youtube_id'] ?? '',
            }
          : null;
      final activeDev = <String, dynamic>{
        'device_id': _deviceId,
        'device_name': currentDeviceName,
        'is_playing': _isPlaying,
        'song_title': cs?.title ?? '',
        'position_ms': _currentPosition.inMilliseconds,
        if (songPayload != null) 'song': songPayload,
        'updated_at': DateTime.now().toIso8601String(),
      };
      _activeCloudDevice = activeDev;
      await supabase.from('user_preferences').update({
        'active_device': activeDev,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('username', username);
    } catch (_) {}
  }
  
  int? get currentIndex => _currentIndex;
  
  SongModel? get currentSong {
    if (_currentPlayingSong != null) return _currentPlayingSong;
    if (_currentIndex != null && _currentIndex! >= 0 && _currentIndex! < songs.length) {
      return songs[_currentIndex!];
    }
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
    await _initDeviceId();

    // Conectar botones interactivos de la notificación de Modo Descubrimiento (❤️ Me gusta / ✕ Quitar)
    await DownloaderProvider.initNotificationsStatic();
    DownloaderProvider.onDiscoveryNotificationAction = (String actionId) async {
      if (actionId == 'discovery_like') {
        await likeCurrentDiscoverySong();
      } else if (actionId == 'discovery_dislike') {
        await dislikeCurrentDiscoverySong();
      } else if (actionId == 'discovery_next') {
        await playNextDiscoverySong();
      }
    };

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
      if (state.processingState == ProcessingState.completed && !_isAutoAdvancing) {
        _isAutoAdvancing = true;
        Future.microtask(() async {
          try {
            if (_isDiscoveryMode) {
              await playNextDiscoverySong();
            } else if (_isSingleTrackSource && songs.isNotEmpty) {
              await nextSong();
            }
          } finally {
            _isAutoAdvancing = false;
          }
        });
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
      // Si se está reproduciendo una pista única (Nube o Modo Descubrimiento), just_audio emite index=0.
      // Ignorarlo para NUNCA sobrescribir la canción activa con songs[0].
      if (_isSingleTrackSource || _playlist == null) return;

      if (index != null && index >= 0 && index < _playlist!.children.length) {
        try {
          final tag = (_playlist!.children[index] as UriAudioSource).tag as MediaItem;
          final matchedIdx = songs.indexWhere((s) => s.id.toString() == tag.id);
          if (matchedIdx != -1) {
            final changed = _currentIndex != matchedIdx || _currentPlayingSong?.id != songs[matchedIdx].id;
            _currentIndex = matchedIdx;
            _currentPlayingSong = songs[matchedIdx];
            if (changed) {
              notifyListeners();
              if (_isPlaying) {
                updateActiveDeviceInCloud();
              }
            }
            return;
          }
        } catch (_) {}

        if (index != _currentIndex && index < songs.length) {
          _currentIndex = index;
          _currentPlayingSong = songs[index];
          notifyListeners();
          if (_isPlaying) {
            updateActiveDeviceInCloud();
          }
        }
      }
    });
  }

  Future<void> _loadHiddenSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenList = prefs.getStringList('hidden_songs') ?? [];
    _hiddenSongIds = [];
    _hiddenSongKeys = (prefs.getStringList('hidden_song_keys') ?? []).toSet();
    _deletedSongKeys = (prefs.getStringList('permanently_deleted_songs') ?? []).toSet();
    _dislikedDiscoveryKeys = (prefs.getStringList('disliked_discovery_songs') ?? []).toSet();

    for (var entry in hiddenList) {
      if (entry.startsWith('key:')) {
        _hiddenSongKeys.add(entry.substring(4));
      } else if (entry.startsWith('del:')) {
        _deletedSongKeys.add(entry.substring(4));
      } else if (entry.startsWith('dislike:')) {
        _dislikedDiscoveryKeys.add(entry.substring(8));
      } else {
        final parsed = int.tryParse(entry);
        if (parsed != null) _hiddenSongIds.add(parsed);
      }
    }
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

        // 1. Ocultas, Eliminadas y Recomendaciones Descartadas (✕)
        if (response['hidden_songs'] != null) {
          List<dynamic> hidden = response['hidden_songs'];
          _hiddenSongIds = [];
          for (var e in hidden) {
            final s = e.toString();
            if (s.startsWith('key:')) {
              _hiddenSongKeys.add(s.substring(4));
            } else if (s.startsWith('del:')) {
              _deletedSongKeys.add(s.substring(4));
            } else if (s.startsWith('dislike:')) {
              _dislikedDiscoveryKeys.add(s.substring(8));
            } else {
              final id = int.tryParse(s);
              if (id != null) _hiddenSongIds.add(id);
            }
          }
          await prefs.setStringList('hidden_songs', _hiddenSongIds.map((e) => e.toString()).toList());
          await prefs.setStringList('hidden_song_keys', _hiddenSongKeys.toList());
          await prefs.setStringList('permanently_deleted_songs', _deletedSongKeys.toList());
          await prefs.setStringList('disliked_discovery_songs', _dislikedDiscoveryKeys.toList());
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

        // 4. Biblioteca personal de canciones en la nube (filtrando ocultas/eliminadas)
        if (response['library_songs'] != null) {
          List<dynamic> lib = response['library_songs'];
          _cloudLibrarySongs = lib
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((c) {
                final norm = normalizeForDedup(c['title'] ?? '');
                final cId = int.tryParse(c['id']?.toString() ?? '');
                if (cId != null && _hiddenSongIds.contains(cId)) return false;
                if (norm.isNotEmpty && (_hiddenSongKeys.contains(norm) || _deletedSongKeys.contains(norm))) return false;
                return true;
              })
              .toList();
          await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
        }

        // 5. Listas de reproducción sincronizadas
        if (response['playlists'] != null) {
          List<dynamic> pls = response['playlists'];
          _playlists = pls.map((e) => PlaylistModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          await prefs.setString('cached_playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
        }

        // 6. Dispositivo activo y conectados
        if (response['active_device'] != null && response['active_device'] is Map) {
          _activeCloudDevice = Map<String, dynamic>.from(response['active_device'] as Map);
        }
        if (response['connected_devices'] != null && response['connected_devices'] is List) {
          _connectedDevices = (response['connected_devices'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        if (response['playback_state'] != null && response['playback_state'] is Map) {
          final pb = Map<String, dynamic>.from(response['playback_state'] as Map);
          _lastRemotePlaybackState = pb;
          _lastHandledCommandId = pb['command_id']?.toString() ?? pb['updated_at']?.toString();
        }

        // Registrar este dispositivo e iniciar sincronización en tiempo real
        await registerDeviceInCloud();
        _startHeartbeatTimer();
        _subscribeToRealtimeSync();

        // 7. Actualizar última conexión
        try {
          await supabase.from('user_preferences').update({
            'last_active': DateTime.now().toIso8601String(),
          }).eq('username', username);
        } catch (_) {}

        await fetchSongs();
      }
    } catch (e) {
      print('Error loading from Supabase: $e');
    }
  }

  Future<void> _saveHiddenSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final idStrings = _hiddenSongIds.map((e) => e.toString()).toList();
    await prefs.setStringList('hidden_songs', idStrings);
    await prefs.setStringList('hidden_song_keys', _hiddenSongKeys.toList());
    await prefs.setStringList('permanently_deleted_songs', _deletedSongKeys.toList());
    await prefs.setStringList('disliked_discovery_songs', _dislikedDiscoveryKeys.toList());

    final combinedForCloud = <String>[
      ...idStrings,
      ..._hiddenSongKeys.map((k) => 'key:$k'),
      ..._deletedSongKeys.map((k) => 'del:$k'),
      ..._dislikedDiscoveryKeys.map((k) => 'dislike:$k'),
    ];

    // Sync to Supabase
    final username = _currentUsername ?? prefs.getString('current_username');
    if (username != null && username.isNotEmpty) {
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('user_preferences').update({
          'hidden_songs': combinedForCloud,
          'library_songs': _cloudLibrarySongs,
          'last_active': DateTime.now().toIso8601String(),
        }).eq('username', username);
      } catch (e) {
        print('Error syncing hidden/library songs to Supabase: $e');
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

  List<SongModel> get hiddenSongs => _allSongs.where((s) {
        final norm = normalizeForDedup(s.title);
        if (_deletedSongKeys.contains(norm)) return false;
        return _hiddenSongIds.contains(s.id) || (norm.isNotEmpty && _hiddenSongKeys.contains(norm));
      }).toList();

  Future<void> fetchSongs() async {
    if (kIsWeb || (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)) {
      _allSongs = _cloudLibrarySongs.map((c) => SongModel({
        '_id': c['id'] is int ? c['id'] : int.tryParse(c['id'].toString()) ?? DateTime.now().millisecondsSinceEpoch,
        'title': c['title'] ?? 'Sin título',
        'artist': c['artist'] ?? 'Artista desconocido',
        'duration': c['duration'] is int ? c['duration'] : int.tryParse(c['duration'].toString()) ?? 0,
        '_data': c['url'] ?? '',
        'is_cloud': true,
        'youtube_id': c['youtube_id'] ?? '',
      })).toList();
      _visibleSongs = _allSongs.where((song) => !_isSongHiddenOrDeleted(song)).toList();
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

      // Si el usuario borró permanentemente esta canción, ignorar aunque MediaStore aún no haya refrescado
      if (_deletedSongKeys.contains(normTitle)) return;

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
    _visibleSongs = _allSongs.where((song) => !_isSongHiddenOrDeleted(song)).toList();
    _applySort();

    // 4. Sincronizar catálogo de respaldo en la nube: SOLO las canciones que están en _visibleSongs
    // y limpiar de _cloudLibrarySongs cualquier canción que haya sido quitada de la lista o eliminada
    if (!isGuest) {
      bool needsCloudSync = false;
      final beforeLen = _cloudLibrarySongs.length;
      _cloudLibrarySongs.removeWhere((c) {
        final cNorm = normalizeForDedup(c['title'] ?? '');
        final cId = int.tryParse(c['id']?.toString() ?? '');
        if (cId != null && _hiddenSongIds.contains(cId)) return true;
        if (cNorm.isNotEmpty && (_hiddenSongKeys.contains(cNorm) || _deletedSongKeys.contains(cNorm))) return true;
        return false;
      });
      if (_cloudLibrarySongs.length != beforeLen) {
        needsCloudSync = true;
      }

      for (var local in _visibleSongs) {
        final localNorm = normalizeForDedup(local.title);
        if (localNorm.isEmpty) continue;
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
        await syncPreferencesToCloud();
      }
    }
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
    final currentList = songs;
    if (currentList.isEmpty) {
      await _audioPlayer.stop();
      _playlist = null;
      _currentIndex = null;
      return;
    }

    final validIndex = (initialIndex >= 0 && initialIndex < currentList.length) ? initialIndex : 0;
    _isSingleTrackSource = false;
    _currentPlayingSong = currentList[validIndex];

    _playlist = ConcatenatingAudioSource(
      children: currentList.map((song) {
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
      _currentPlayingSong = currentList[validIndex];
      _needsPlaylistRebuild = false;
    } catch (e) {
      print("Error setting audio source: $e");
    }
  }

  Future<void> _playCloudSong(
    SongModel song,
    int index, {
    Duration initialPosition = Duration.zero,
    bool keepDiscoveryState = false,
  }) async {
    try {
      if (!keepDiscoveryState && _isDiscoveryMode) {
        _isDiscoveryMode = false;
        _currentDiscoverySong = null;
        _currentDiscoveryVideo = null;
        await _cleanupUnsavedDiscoveryTempFile();
        await DownloaderProvider.cancelDiscoveryNotification();
      }

      _isSingleTrackSource = true;
      _currentIndex = index;
      _currentPlayingSong = song;
      _isPlaying = false;
      _isConnectingCloudStream = true;
      notifyListeners();

      final mediaItem = MediaItem(
        id: song.id.toString(),
        title: song.title,
        artist: (song.artist != null && song.artist!.isNotEmpty) ? song.artist! : 'En la Nube ☁️',
        album: keepDiscoveryState ? _currentDiscoverySeedInfo : 'NovaMusic Nube',
      );

      String ytId = song.getMap['youtube_id']?.toString() ?? '';

      if (kIsWeb) {
        // En PC / Web usar el proxy local libre de CORS (/api/stream)
        final queryStr = '${song.title} ${song.artist ?? ""}'.trim();
        final streamUri = Uri.parse(
          '/api/stream?id=${Uri.encodeComponent(ytId)}&q=${Uri.encodeComponent(queryStr)}',
        );
        final source = AudioSource.uri(streamUri, tag: mediaItem);
        await _audioPlayer
            .setAudioSource(source, initialPosition: initialPosition)
            .timeout(const Duration(seconds: 15));
        _currentIndex = index;
        _currentPlayingSong = song;
        _isConnectingCloudStream = false;
        _isPlaying = true;
        notifyListeners();
        await _audioPlayer.play();
        if (initialPosition > Duration.zero) {
          try {
            await _audioPlayer.seek(initialPosition);
          } catch (_) {}
        }
        updateActiveDeviceInCloud();
        return;
      }

      if (ytId.isEmpty) {
        final searchResults = await _ytCloud.search
            .search('${song.title} ${song.artist ?? ""} official audio')
            .timeout(const Duration(seconds: 10));
        if (searchResults.isNotEmpty) {
          ytId = searchResults.first.id.value;
          song.getMap['youtube_id'] = ytId;
        }
      }

      if (ytId.isEmpty) {
        throw Exception("No se encontró el audio en la nube");
      }

      StreamManifest manifest;
      try {
        manifest = await _ytCloud.videos.streamsClient
            .getManifest(ytId, requireWatchPage: false)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        manifest = await _ytCloud.videos.streamsClient
            .getManifest(ytId)
            .timeout(const Duration(seconds: 10));
      }
      StreamInfo? streamInfo;
      if (manifest.muxed.isNotEmpty) {
        streamInfo = manifest.muxed.withHighestBitrate();
      } else {
        final mp4Audios = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        if (mp4Audios.isNotEmpty) {
          streamInfo = mp4Audios.withHighestBitrate();
        } else if (manifest.audioOnly.isNotEmpty) {
          streamInfo = manifest.audioOnly.withHighestBitrate();
        }
      }

      if (streamInfo == null) throw Exception("Stream no disponible");

      final contentType = streamInfo.container.name.toLowerCase() == 'mp4' ? 'audio/mp4' : 'audio/webm';

      final source = YouTubeAudioSource(
        uri: streamInfo.url,
        totalBytes: streamInfo.size.totalBytes,
        contentType: contentType,
        tag: mediaItem,
      );

      await _audioPlayer
          .setAudioSource(source, initialPosition: initialPosition)
          .timeout(const Duration(seconds: 12));
      _currentIndex = index;
      _currentPlayingSong = song;
      _isConnectingCloudStream = false;
      _isPlaying = true;
      notifyListeners();
      await _audioPlayer.play();
      if (initialPosition > Duration.zero) {
        try {
          await _audioPlayer.seek(initialPosition);
        } catch (_) {}
      }
      updateActiveDeviceInCloud();
    } catch (e) {
      _isConnectingCloudStream = false;
      notifyListeners();
      print('Error streaming cloud song: $e');
    }
  }

  Future<void> playSong(int index, {Duration initialPosition = Duration.zero}) async {
    final currentList = songs;
    if (index < 0 || index >= currentList.length) return;

    // Si estaba en Modo Descubrimiento y el usuario toca una canción de su lista, salir de Descubrimiento
    if (_isDiscoveryMode || _currentDiscoverySong != null) {
      _isDiscoveryMode = false;
      _currentDiscoverySong = null;
      _currentDiscoveryVideo = null;
      await _cleanupUnsavedDiscoveryTempFile();
      await DownloaderProvider.cancelDiscoveryNotification();
    }

    final targetSong = currentList[index];
    _currentPlayingSong = targetSong;
    _currentIndex = index;

    if (isCloudSong(targetSong)) {
      await _playCloudSong(targetSong, index, initialPosition: initialPosition);
      return;
    }

    if (_playlist == null || _needsPlaylistRebuild || _isSingleTrackSource) {
      await _setupAudioSource(initialIndex: index, initialPosition: initialPosition);
    } else {
      try {
        await _audioPlayer.seek(initialPosition, index: index);
      } catch (e) {
        await _setupAudioSource(initialIndex: index, initialPosition: initialPosition);
      }
    }
    
    _currentIndex = index;
    _currentPlayingSong = targetSong;
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final session = await AudioSession.instance;
        await session.setActive(true);
      }
      await _audioPlayer.play();
      if (initialPosition > Duration.zero && (_audioPlayer.position - initialPosition).abs().inSeconds > 2) {
        try {
          await _audioPlayer.seek(initialPosition);
        } catch (_) {}
      }
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
    if (_isDiscoveryMode) {
      await playNextDiscoverySong();
      return;
    }
    if (!_isSingleTrackSource && _audioPlayer.hasNext) {
      await _audioPlayer.seekToNext();
      updateActiveDeviceInCloud();
      return;
    }
    final currentList = songs;
    if (currentList.isNotEmpty) {
      int nextIdx;
      if (_isShuffle && currentList.length > 1) {
        nextIdx = Random().nextInt(currentList.length);
      } else {
        nextIdx = ((_currentIndex ?? -1) + 1) % currentList.length;
      }
      await playSong(nextIdx);
    }
  }

  Future<void> previousSong() async {
    if (_currentPosition.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }
    if (!_isSingleTrackSource && _audioPlayer.hasPrevious) {
      await _audioPlayer.seekToPrevious();
      updateActiveDeviceInCloud();
      return;
    }
    final currentList = songs;
    if (currentList.isNotEmpty) {
      final prevIdx = ((_currentIndex ?? 1) - 1 + currentList.length) % currentList.length;
      await playSong(prevIdx);
    }
  }

  // ===========================================================================
  // MODO DESCUBRIMIENTO INTELIGENTE (Basado en la música descargada del usuario)
  // ===========================================================================

  Future<void> _cleanupUnsavedDiscoveryTempFile() async {
    if (_currentDiscoveryTempPath != null && !_isCurrentDiscoverySaved) {
      final oldPath = _currentDiscoveryTempPath!;
      _currentDiscoveryTempPath = null;
      try {
        final f = File(oldPath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    } else {
      _currentDiscoveryTempPath = null;
    }
  }

  Future<void> toggleDiscoveryMode() async {
    if (_isDiscoveryMode) {
      await stopDiscoveryMode();
    } else {
      await startDiscoveryMode();
    }
  }

  Future<void> startDiscoveryMode() async {
    _isDiscoveryMode = true;
    notifyListeners();
    await playNextDiscoverySong();
  }

  Future<void> stopDiscoveryMode() async {
    _isDiscoveryMode = false;
    _isLoadingDiscovery = false;
    _discoveryStatusText = '';
    final wasDiscovery = isPlayingDiscoverySong;
    _currentDiscoverySong = null;
    _currentDiscoveryVideo = null;
    await _cleanupUnsavedDiscoveryTempFile();
    await DownloaderProvider.cancelDiscoveryNotification();
    if (wasDiscovery) {
      await _audioPlayer.stop();
      _isPlaying = false;
      _currentPlayingSong = null;
    }
    notifyListeners();
  }

  bool _isGenericArtistName(String? artist) {
    if (artist == null) return true;
    final lower = artist.toLowerCase().trim();
    return lower.isEmpty ||
        lower == '<unknown>' ||
        lower.contains('desconocido') ||
        lower.contains('novamusic') ||
        lower.contains('descargado') ||
        lower.contains('en la nube') ||
        lower.contains('audio');
  }

  bool _isSongAlreadyInLibraryOrDisliked(Video candidate) {
    final vidId = candidate.id.value;
    if (_sessionPlayedDiscoveryIds.contains(vidId)) return true;
    if (_dislikedDiscoveryKeys.contains('id:$vidId')) return true;

    final rawTitle = candidate.title;
    final normFull = normalizeForDedup(rawTitle);
    if (normFull.isEmpty) return true;

    // Si el título viene como "Artista - Canción", extraer también solo la parte de la canción
    String songPart = rawTitle;
    if (rawTitle.contains(' - ')) {
      final parts = rawTitle.split(' - ');
      if (parts.length >= 2) {
        songPart = parts.sublist(1).join(' - ');
      }
    }
    final normSongOnly = normalizeForDedup(songPart);

    if (_dislikedDiscoveryKeys.contains(normFull) ||
        (normSongOnly.isNotEmpty && _dislikedDiscoveryKeys.contains(normSongOnly)) ||
        _hiddenSongKeys.contains(normFull) ||
        _deletedSongKeys.contains(normFull)) {
      return true;
    }

    // Verificar que NO esté ya descargada en el celular ni en la lista de canciones
    final allCheck = <SongModel>[..._visibleSongs, ..._allSongs];
    for (var s in allCheck) {
      if (s.getMap['youtube_id']?.toString() == vidId) return true;
      final sNorm = normalizeForDedup(s.title);
      if (sNorm.isEmpty) continue;
      if (sNorm == normFull || (normSongOnly.isNotEmpty && sNorm == normSongOnly)) {
        return true;
      }
      if (sNorm.length >= 6 && normSongOnly.length >= 6) {
        if (sNorm.contains(normSongOnly) || normSongOnly.contains(sNorm)) {
          return true;
        }
      }
    }

    for (var c in _cloudLibrarySongs) {
      if (c['youtube_id']?.toString() == vidId) return true;
      final cNorm = normalizeForDedup(c['title']?.toString() ?? '');
      if (cNorm.isNotEmpty && (cNorm == normFull || cNorm == normSongOnly)) return true;
    }

    return false;
  }

  Future<void> playNextDiscoverySong() async {
    if (_isLoadingDiscovery) return;

    _isDiscoveryMode = true;
    _isLoadingDiscovery = true;
    _isCurrentDiscoverySaved = false;
    _discoveryStatusText = 'Analizando tu música descargada...';
    notifyListeners();

    await _cleanupUnsavedDiscoveryTempFile();
    await DownloaderProvider.showDiscoveryLoadingNotification(
      '✨ Modo Descubrimiento',
      'Analizando tus canciones descargadas para recomendarte música nueva...',
    );

    try {
      final rand = Random();
      final sourcePool = <SongModel>[
        ..._visibleSongs,
        // Dar doble peso a las canciones favoritas del usuario
        ...favoriteSongs,
      ];

      String targetArtist = '';
      String seedLabel = 'Tu biblioteca';
      String seedSongNorm = '';

      if (sourcePool.isNotEmpty) {
        final seedSong = sourcePool[rand.nextInt(sourcePool.length)];
        seedSongNorm = normalizeForDedup(seedSong.title);
        final rawArtist = seedSong.artist?.trim() ?? '';

        if (!_isGenericArtistName(rawArtist)) {
          targetArtist = rawArtist;
          seedLabel = rawArtist;
        } else if (seedSong.title.contains(' - ')) {
          final parts = seedSong.title.split(' - ');
          if (parts.first.trim().length >= 2) {
            targetArtist = parts.first.trim();
            seedLabel = targetArtist;
          }
        }

        // Si el archivo solo tiene el nombre de la canción sin artista, descubrir su autor en YouTube
        if (targetArtist.isEmpty) {
          seedLabel = seedSong.title.trim();
          _discoveryStatusText = 'Identificando estilo de "$seedLabel"...';
          notifyListeners();
          try {
            final probe = await _ytCloud.search
                .search('${seedSong.title} official audio')
                .timeout(const Duration(seconds: 8));
            if (probe.isNotEmpty) {
              targetArtist = probe.first.author
                  .replaceAll(RegExp(r'-\s*Topic', caseSensitive: false), '')
                  .replaceAll('VEVO', '')
                  .replaceAll('Official', '')
                  .trim();
              if (targetArtist.isNotEmpty) {
                seedLabel = '$targetArtist (${seedSong.title})';
              }
            }
          } catch (_) {}
        }
      }

      // Construir consultas variadas para descubrir canciones nuevas de esos artistas o estilo
      final List<String> queries = [];
      if (targetArtist.isNotEmpty) {
        final modifiers = [
          '$targetArtist canciones official audio',
          '$targetArtist exitos official audio',
          '$targetArtist official audio',
          '$targetArtist mix audio oficial',
        ];
        modifiers.shuffle(rand);
        queries.addAll(modifiers);
      } else if (seedLabel != 'Tu biblioteca') {
        queries.add('$seedLabel mix official audio');
      } else {
        queries.add('exitos musica popular official audio');
      }

      _discoveryStatusText = 'Buscando recomendación basada en $seedLabel...';
      notifyListeners();

      Video? chosenVideo;
      for (final q in queries) {
        try {
          final results = await _ytCloud.search.search(q).timeout(const Duration(seconds: 10));
          final candidates = results.where((v) {
            if (DownloaderProvider.isLiveOrLowQuality(v)) return false;
            final dur = v.duration;
            if (dur != null && (dur.inSeconds < 65 || dur.inMinutes > 9)) return false;
            if (seedSongNorm.isNotEmpty && normalizeForDedup(v.title) == seedSongNorm) return false;
            if (_isSongAlreadyInLibraryOrDisliked(v)) return false;
            return true;
          }).toList();

          if (candidates.isNotEmpty) {
            candidates.sort((a, b) =>
                DownloaderProvider.getAudioQualityScore(b).compareTo(DownloaderProvider.getAudioQualityScore(a)));
            // Elegir entre las 3 mejores pistas de estudio para dar variedad manteniendo máxima calidad
            final topCount = min(3, candidates.length);
            chosenVideo = candidates[rand.nextInt(topCount)];
            break;
          }
        } catch (_) {}
      }

      if (chosenVideo == null) {
        throw Exception('No se encontraron más recomendaciones nuevas en este intento.');
      }

      _sessionPlayedDiscoveryIds.add(chosenVideo.id.value);

      final cleanAuthor = chosenVideo.author
          .replaceAll(RegExp(r'-\s*Topic', caseSensitive: false), '')
          .replaceAll('VEVO', '')
          .trim();
      final cleanTitle = chosenVideo.title
          .replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), '')
          .replaceAll(RegExp(r'official\s*audio|audio\s*oficial|video\s*oficial|official\s*video|lyrics|letra', caseSensitive: false), '')
          .trim();
      final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : chosenVideo.title.trim();
      final displayArtist = cleanAuthor.isNotEmpty ? cleanAuthor : chosenVideo.author.trim();

      _currentDiscoverySeedInfo = 'Basada en $seedLabel';

      // En Android: descargar temporalmente y aplicar masterización + recorte de silencio inicial y final
      if (!kIsWeb && Platform.isAndroid) {
        _discoveryStatusText = 'Preparando "$displayTitle" (quitando silencios)...';
        notifyListeners();
        await DownloaderProvider.showDiscoveryLoadingNotification(
          '✨ Preparando: $displayTitle',
          '$displayArtist • Quitando silencios del inicio y final...',
        );

        final tempDir = await getTemporaryDirectory();
        final vidId = chosenVideo.id.value;
        final rawFile = File('${tempDir.path}/disc_raw_$vidId.mp4');
        final thumbFile = File('${tempDir.path}/disc_thumb_$vidId.jpg');
        final readyMp3 = File('${tempDir.path}/disc_ready_$vidId.mp3');

        if (await rawFile.exists()) await rawFile.delete();
        if (await readyMp3.exists()) await readyMp3.delete();

        StreamManifest manifest;
        try {
          manifest = await _ytCloud.videos.streamsClient
              .getManifest(vidId, requireWatchPage: false)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          manifest = await _ytCloud.videos.streamsClient
              .getManifest(vidId)
              .timeout(const Duration(seconds: 12));
        }

        StreamInfo? streamInfo;
        if (manifest.muxed.isNotEmpty) {
          streamInfo = manifest.muxed.withHighestBitrate();
        } else {
          final mp4s = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
          if (mp4s.isNotEmpty) {
            streamInfo = mp4s.withHighestBitrate();
          } else if (manifest.audioOnly.isNotEmpty) {
            streamInfo = manifest.audioOnly.withHighestBitrate();
          }
        }
        if (streamInfo == null) throw Exception('Stream no disponible para recomendación');

        // Descargar stream al archivo temporal
        final stream = _ytCloud.videos.streamsClient.get(streamInfo);
        final sink = rawFile.openWrite();
        try {
          await for (final chunk in stream.timeout(const Duration(seconds: 25))) {
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }

        // Descargar carátula para incrustarla en el MP3
        bool hasThumb = false;
        try {
          final thumbUrl = chosenVideo.thumbnails.maxResUrl.isNotEmpty
              ? chosenVideo.thumbnails.maxResUrl
              : chosenVideo.thumbnails.highResUrl;
          final tRes = await http.get(Uri.parse(thumbUrl)).timeout(const Duration(seconds: 4));
          if (tRes.statusCode == 200) {
            await thumbFile.writeAsBytes(tRes.bodyBytes);
            hasThumb = true;
          }
        } catch (_) {}

        final safeMetaTitle = displayTitle.replaceAll('"', '');
        final safeMetaArtist = displayArtist.replaceAll('"', '');
        const afFilter = DownloaderProvider.studioMasterAndTrimSilenceFilter;
        final metadata = '-metadata title="$safeMetaTitle" -metadata artist="$safeMetaArtist"';
        const codecFlags = '-ar 44100 -ac 2 -b:a 320k';

        String cmd;
        if (hasThumb) {
          cmd = '-y -i "${rawFile.path}" -i "${thumbFile.path}" -map 0:a -map 1:v $afFilter $codecFlags -c:v mjpeg -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" $metadata "${readyMp3.path}"';
        } else {
          cmd = '-y -i "${rawFile.path}" -vn $afFilter $codecFlags $metadata "${readyMp3.path}"';
        }

        var session = await FFmpegKit.execute(cmd);
        var rc = await session.getReturnCode();
        if (!ReturnCode.isSuccess(rc)) {
          cmd = '-y -i "${rawFile.path}" -vn $codecFlags $metadata "${readyMp3.path}"';
          session = await FFmpegKit.execute(cmd);
          rc = await session.getReturnCode();
        }

        if (await rawFile.exists()) await rawFile.delete();
        if (await thumbFile.exists()) await thumbFile.delete();

        if (!ReturnCode.isSuccess(rc) || !await readyMp3.exists()) {
          throw Exception('Error procesando audio recomendado');
        }

        _currentDiscoveryTempPath = readyMp3.path;
        final stat = await readyMp3.stat();
        final discSong = SongModel({
          '_id': vidId.hashCode.abs() % 2147483647,
          'title': displayTitle,
          'artist': displayArtist,
          'album': _currentDiscoverySeedInfo,
          'duration': chosenVideo.duration?.inMilliseconds ?? 0,
          '_data': readyMp3.path,
          '_uri': readyMp3.uri.toString(),
          '_size': stat.size,
          'file_extension': 'mp3',
          'is_music': true,
          'is_discovery': true,
          'youtube_id': vidId,
        });

        _isSingleTrackSource = true;
        _currentDiscoverySong = discSong;
        _currentDiscoveryVideo = chosenVideo;
        _currentPlayingSong = discSong;
        _currentIndex = -1;
        _isLoadingDiscovery = false;
        _discoveryStatusText = '';

        final mediaItem = MediaItem(
          id: discSong.id.toString(),
          title: '✨ $displayTitle',
          artist: '$displayArtist • $_currentDiscoverySeedInfo',
          album: 'Modo Descubrimiento (❤️ Me gusta o ✕ en notificación)',
        );

        await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.file(readyMp3.path), tag: mediaItem),
        );
        final audioSession = await AudioSession.instance;
        await audioSession.setActive(true);
        _isPlaying = true;
        notifyListeners();
        await _audioPlayer.play();
        updateActiveDeviceInCloud();

        // Mostrar notificación interactiva con botones ❤️ Me gusta (Guardar) y ✕ Quitar
        await DownloaderProvider.showDiscoveryPlayingNotification(
          songTitle: displayTitle,
          artist: displayArtist,
          seedInfo: _currentDiscoverySeedInfo,
          isSaved: false,
        );
      } else {
        // En PC / Web reproducir por stream directo y mostrar controles ❤️ / ✕ en pantalla
        final vidId = chosenVideo.id.value;
        final discSong = SongModel({
          '_id': vidId.hashCode.abs() % 2147483647,
          'title': displayTitle,
          'artist': displayArtist,
          'album': _currentDiscoverySeedInfo,
          'duration': chosenVideo.duration?.inMilliseconds ?? 0,
          '_data': '',
          'is_cloud': true,
          'is_discovery': true,
          'youtube_id': vidId,
        });
        _currentDiscoverySong = discSong;
        _currentDiscoveryVideo = chosenVideo;
        _isLoadingDiscovery = false;
        _discoveryStatusText = '';
        notifyListeners();
        await _playCloudSong(discSong, -1, keepDiscoveryState: true);
      }
    } catch (e) {
      print('Error in playNextDiscoverySong: $e');
      _isLoadingDiscovery = false;
      _discoveryStatusText = 'Error buscando recomendación. Reintentando...';
      notifyListeners();
    }
  }

  /// Acción "❤️ Me gusta": Guarda permanentemente la canción recomendada en el dispositivo y en la lista de canciones
  Future<bool> likeCurrentDiscoverySong() async {
    final discSong = _currentDiscoverySong;
    if (discSong == null) return false;
    if (_isCurrentDiscoverySaved) return true;

    try {
      final rawTitle = discSong.title.trim();
      final rawArtist = (discSong.artist ?? 'Artista').trim();
      final combinedName = rawTitle.toLowerCase().contains(rawArtist.toLowerCase())
          ? rawTitle
          : '$rawArtist - $rawTitle';
      final safeFileName = combinedName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
          .replaceAll('  ', ' ')
          .trim();

      String finalSavedPath = discSong.data;

      if (!kIsWeb && Platform.isAndroid && _currentDiscoveryTempPath != null) {
        final tempFile = File(_currentDiscoveryTempPath!);
        if (await tempFile.exists()) {
          Directory targetDir = Directory('/storage/emulated/0/Music/NovaMusic');
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          final destFile = File('${targetDir.path}/$safeFileName.mp3');
          await tempFile.copy(destFile.path);
          finalSavedPath = destFile.path;

          try {
            await MediaScanner.loadMedia(path: destFile.path);
          } catch (_) {}
        }
      }

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final savedSong = SongModel({
        '_id': finalSavedPath.isNotEmpty
            ? (finalSavedPath.hashCode.abs() % 2147483647)
            : discSong.id,
        'title': combinedName,
        'artist': rawArtist,
        'duration': discSong.duration ?? _totalDuration.inMilliseconds,
        '_data': finalSavedPath,
        '_uri': finalSavedPath.isNotEmpty ? File(finalSavedPath).uri.toString() : '',
        '_display_name': '$safeFileName.mp3',
        '_display_name_wo_ext': safeFileName,
        'file_extension': 'mp3',
        'date_added': nowSec,
        'is_music': true,
        'is_podcast': false,
        'is_cloud': kIsWeb || finalSavedPath.isEmpty,
        'youtube_id': discSong.getMap['youtube_id'] ?? '',
      });

      final normNew = normalizeForDedup(savedSong.title);
      if (!_allSongs.any((s) => normalizeForDedup(s.title) == normNew)) {
        _allSongs.insert(0, savedSong);
      }
      if (!_visibleSongs.any((s) => normalizeForDedup(s.title) == normNew)) {
        _visibleSongs.insert(0, savedSong);
        _applySort();
      }

      // Agregar al respaldo de la nube
      if (!_cloudLibrarySongs.any((c) => normalizeForDedup(c['title'] ?? '') == normNew)) {
        _cloudLibrarySongs.add({
          'id': savedSong.id,
          'title': savedSong.title,
          'artist': savedSong.artist ?? rawArtist,
          'duration': savedSong.duration ?? 0,
          'url': finalSavedPath,
          'youtube_id': discSong.getMap['youtube_id'] ?? '',
          'is_cloud': true,
          'added_at': DateTime.now().toIso8601String(),
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
        if (!isGuest) {
          await syncPreferencesToCloud();
        }
      }

      _isCurrentDiscoverySaved = true;
      _needsPlaylistRebuild = true;

      await DownloaderProvider.showDiscoveryPlayingNotification(
        songTitle: discSong.title,
        artist: rawArtist,
        seedInfo: _currentDiscoverySeedInfo,
        isSaved: true,
      );

      notifyListeners();
      return true;
    } catch (e) {
      print('Error saving liked discovery song: $e');
      return false;
    }
  }

  /// Acción "✕ Quitar": Descarta la canción recomendada, la bloquea permanentemente para que no vuelva a salir y pasa a la siguiente
  Future<void> dislikeCurrentDiscoverySong() async {
    final discSong = _currentDiscoverySong;
    if (discSong != null) {
      final ytId = discSong.getMap['youtube_id']?.toString() ?? _currentDiscoveryVideo?.id.value ?? '';
      if (ytId.isNotEmpty) {
        _dislikedDiscoveryKeys.add('id:$ytId');
      }
      final normTitle = normalizeForDedup(discSong.title);
      if (normTitle.isNotEmpty) {
        _dislikedDiscoveryKeys.add(normTitle);
      }
      final normFull = normalizeForDedup('${discSong.artist ?? ""} ${discSong.title}');
      if (normFull.isNotEmpty) {
        _dislikedDiscoveryKeys.add(normFull);
      }
      await _saveHiddenSongs();
    }

    await _audioPlayer.stop();
    await _cleanupUnsavedDiscoveryTempFile();
    await playNextDiscoverySong();
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
    final norm = normalizeForDedup(song.title);
    if (!_hiddenSongIds.contains(song.id)) {
      _hiddenSongIds.add(song.id);
    }
    if (norm.isNotEmpty) {
      _hiddenSongKeys.add(norm);
    }

    // Quitar de la lista visible y del respaldo de la nube (solo se respalda lo que está en la lista)
    _visibleSongs.removeWhere((s) => s.id == song.id || (norm.isNotEmpty && normalizeForDedup(s.title) == norm));
    _cloudLibrarySongs.removeWhere((c) {
      final cId = c['id']?.toString();
      final cNorm = normalizeForDedup(c['title'] ?? '');
      return cId == song.id.toString() || (norm.isNotEmpty && cNorm == norm);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
    await _saveHiddenSongs();
    await _handleSongRemoved(song);
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
        _currentPlayingSong = null;
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
        _currentPlayingSong = _visibleSongs[nextIndex];
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
    final norm = normalizeForDedup(song.title);

    // 1. Marcar como eliminada permanentemente para que ni MediaStore ni la nube la revivan
    if (!_hiddenSongIds.contains(song.id)) {
      _hiddenSongIds.add(song.id);
    }
    if (norm.isNotEmpty) {
      _deletedSongKeys.add(norm);
      _hiddenSongKeys.add(norm);
    }

    // 2. Quitar de memoria, favoritas y biblioteca en la nube
    _allSongs.removeWhere((s) => s.id == song.id || (norm.isNotEmpty && normalizeForDedup(s.title) == norm));
    _visibleSongs.removeWhere((s) => s.id == song.id || (norm.isNotEmpty && normalizeForDedup(s.title) == norm));
    _favoriteSongIds.remove(song.id);
    _cloudLibrarySongs.removeWhere((c) {
      final cId = c['id']?.toString();
      final cNorm = normalizeForDedup(c['title'] ?? '');
      return cId == song.id.toString() || (norm.isNotEmpty && cNorm == norm);
    });

    // 3. Liberar el archivo del reproductor ANTES de borrarlo físicamente del almacenamiento
    await _handleSongRemoved(song);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
    await _saveHiddenSongs();

    if (kIsWeb) {
      notifyListeners();
      return true;
    }

    // 4. Eliminar físicamente el archivo en song.data y en cualquier carpeta de NovaMusic
    bool deletedFile = false;
    final Set<String> pathsToDelete = {};
    if (song.data.isNotEmpty) {
      pathsToDelete.add(song.data);
    }

    final candidateDirs = <String>[
      '/storage/emulated/0/Music/NovaMusic',
      '/storage/emulated/0/Download/NovaMusic',
    ];
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

    if (norm.isNotEmpty) {
      for (var dirPath in candidateDirs) {
        try {
          final d = Directory(dirPath);
          if (d.existsSync()) {
            for (var entity in d.listSync().whereType<File>()) {
              final fName = entity.uri.pathSegments.last
                  .replaceAll(RegExp(r'\.(mp3|m4a|wav)$', caseSensitive: false), '')
                  .replaceAll('_', ' ');
              if (normalizeForDedup(fName) == norm) {
                pathsToDelete.add(entity.path);
              }
            }
          }
        } catch (_) {}
      }
    }

    for (var path in pathsToDelete) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deletedFile = true;
        }
        if (Platform.isAndroid) {
          try {
            await MediaScanner.loadMedia(path: path);
          } catch (_) {}
        }
      } catch (e) {
        print("Error deleting file at $path: $e");
      }
    }

    notifyListeners();
    return deletedFile;
  }

  Future<void> unhideSong(SongModel song) async {
    final norm = normalizeForDedup(song.title);
    _hiddenSongIds.remove(song.id);
    if (norm.isNotEmpty) {
      _hiddenSongKeys.remove(norm);
      _deletedSongKeys.remove(norm);
    }

    if (!_visibleSongs.any((s) => s.id == song.id)) {
      _visibleSongs.add(song);
      _applySort();
    }

    // Volver a respaldar en la nube al restaurarla a la lista de canciones
    if (!isGuest && norm.isNotEmpty) {
      final inCloud = _cloudLibrarySongs.any((c) => normalizeForDedup(c['title'] ?? '') == norm);
      if (!inCloud) {
        _cloudLibrarySongs.add({
          'id': song.id,
          'title': song.title,
          'artist': song.artist ?? 'Artista desconocido',
          'youtube_id': song.getMap['youtube_id'] ?? '',
          'duration': song.duration ?? 0,
          'added_at': DateTime.now().toIso8601String(),
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_library_songs', jsonEncode(_cloudLibrarySongs));
      }
    }

    await _saveHiddenSongs();
    _needsPlaylistRebuild = true;
    notifyListeners();
  }

  Future<void> restoreAllHiddenSongs() async {
    _hiddenSongIds.clear();
    _hiddenSongKeys.clear();
    await _saveHiddenSongs();

    _visibleSongs = _allSongs.where((s) => !_deletedSongKeys.contains(normalizeForDedup(s.title))).toList();
    _applySort();

    if (!isGuest) {
      await syncLocalSongsToCloud();
    }

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
