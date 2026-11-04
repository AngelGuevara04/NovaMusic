import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:on_audio_query/on_audio_query.dart';
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
        'auto_delete': autoDelete,
        'last_active': DateTime.now().toIso8601String(),
      });
      notifyListeners();
    } catch (e) {
      print('Error syncing all to Supabase: $e');
    }
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
    await _loadHiddenSongs();
    await _loadFavoriteSongs();
    _listenToPlayerEvents();
    await checkAndRequestPermissions();
    
    // Auto-sync from Supabase if logged in
    if (_currentUsername != null && _currentUsername!.isNotEmpty) {
      loadPreferencesFromSupabase(_currentUsername!);
    }
  }

  Future<void> _setupAudioSession() async {
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
      _visibleSongs.sort((a, b) => a.title.compareTo(b.title));
    } else if (_currentSort == 'artist') {
      _visibleSongs.sort((a, b) => (a.artist ?? '').compareTo(b.artist ?? ''));
    } else if (_currentSort == 'date') {
      _visibleSongs.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
    }
  }

  List<SongModel> get hiddenSongs => _allSongs.where((s) => _hiddenSongIds.contains(s.id)).toList();

  Future<void> fetchSongs() async {
    List<SongModel> fetchedSongs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final uniqueSongs = <String, SongModel>{};
    for (var song in fetchedSongs) {
      if (song.isMusic == true || song.isPodcast == false) {
        final title = song.title.toLowerCase().trim();
        final size = song.size ?? 0;
        
        final key = '${title}_$size';
        
        if (!uniqueSongs.containsKey(key)) {
          uniqueSongs[key] = song;
        }
      }
    }

    // Check if the visible songs changed to prevent unnecessary audio restarts
    final oldSongIds = _visibleSongs.map((s) => s.id).toList();
    _allSongs = uniqueSongs.values.toList();
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

  Future<void> playSong(int index) async {
    if (index < 0 || index >= _visibleSongs.length) return;

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
      final session = await AudioSession.instance;
      await session.setActive(true);
      await _audioPlayer.play();
    } catch (e) {
      print("Error playing song: $e");
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    final session = await AudioSession.instance;
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await session.setActive(true);
      await _audioPlayer.play();
    }
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
            final session = await AudioSession.instance;
            await session.setActive(true);
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
