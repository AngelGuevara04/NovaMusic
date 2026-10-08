import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AudioProvider with ChangeNotifier {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<SongModel> _allSongs = [];
  List<SongModel> _visibleSongs = [];
  List<int> _hiddenSongIds = [];
  
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
    if (_searchQuery.isEmpty) return _visibleSongs;
    return _visibleSongs.where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase()) || (s.artist?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)).toList();
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
    await _loadHiddenSongs();
    
    // Configurar salto automático de silencios (gapless/skip silence)
    try {
      await _audioPlayer.setSkipSilenceEnabled(true);
    } catch (e) {
      print("Skip silence not supported on this platform: $e");
    }

    _listenToPlayerEvents();
    await checkAndRequestPermissions();
    
    // Auto-sync from Supabase if logged in
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    if (username != null && username.isNotEmpty) {
      loadPreferencesFromSupabase(username);
    }
  }

  void _listenToPlayerEvents() {
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
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
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('user_preferences')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (response != null && response['hidden_songs'] != null) {
        List<dynamic> hidden = response['hidden_songs'];
        _hiddenSongIds = hidden.map((e) => int.parse(e.toString())).toList();
        
        final prefs = await SharedPreferences.getInstance();
        final hiddenList = _hiddenSongIds.map((e) => e.toString()).toList();
        await prefs.setStringList('hidden_songs', hiddenList);
        
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
        final artist = song.artist?.toLowerCase().trim() ?? '';
        final size = song.size ?? 0;
        
        // Use title and size as a robust duplicate key to prevent same files appearing twice
        final key = '${title}_$size';
        
        if (!uniqueSongs.containsKey(key)) {
          uniqueSongs[key] = song;
        }
      }
    }

    _allSongs = uniqueSongs.values.toList();
    _visibleSongs = _allSongs.where((song) => !_hiddenSongIds.contains(song.id)).toList();
    
    _applySort();
    await _setupAudioSource();
    notifyListeners();
  }

  Future<void> _setupAudioSource() async {
    if (_visibleSongs.isEmpty) return;

    _playlist = ConcatenatingAudioSource(
      children: songs.map((song) {
        return AudioSource.uri(
          Uri.parse(song.uri!),
          tag: MediaItem(
            id: song.id.toString(),
            album: song.album ?? 'Album desconocido',
            title: song.title,
            artist: song.artist ?? 'Artista desconocido',
            artUri: Uri.parse('content://media/external/audio/media/${song.id}/albumart'),
          ),
        );
      }).toList(),
    );

    try {
      await _audioPlayer.setAudioSource(_playlist!);
      _needsPlaylistRebuild = false;
    } catch (e) {
      print("Error setting audio source: $e");
    }
  }

  Future<void> playSong(int index) async {
    if (_needsPlaylistRebuild) {
      await _setupAudioSource();
    }
    
    _currentIndex = index;
    try {
      await _audioPlayer.seek(Duration.zero, index: index);
      await _audioPlayer.play();
    } catch (e) {
      print("Error playing song: $e");
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
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
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    await _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  Future<void> hideSong(SongModel song) async {
    if (!_hiddenSongIds.contains(song.id)) {
      _hiddenSongIds.add(song.id);
      await _saveHiddenSongs();
      
      _visibleSongs.remove(song);
      _needsPlaylistRebuild = true;
      
      notifyListeners();
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
