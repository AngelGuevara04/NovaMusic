import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/audio_provider.dart';
import '../providers/downloader_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lyrics_service.dart';
import 'equalizer_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;
  List<LyricsLine> _lyrics = [];
  bool _loadingLyrics = false;
  String? _loadedSongKey;
  int _lyricsOffsetMs = 0;
  final ScrollController _lyricsScrollController = ScrollController();
  int _lastActiveIndex = -1;
  DateTime? _lastUserScrollTime;

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _loadLyricsForSong(SongModel song) async {
    final key = '${song.title}_${song.artist}';
    if (_loadedSongKey == key) return;
    setState(() {
      _loadingLyrics = true;
      _loadedSongKey = key;
      _lastActiveIndex = -1;
    });

    final prefs = await SharedPreferences.getInstance();
    final savedOffset = prefs.getInt('lyrics_offset_${song.id}') ?? 0;

    final fetched = await LyricsService.fetchLyrics(song.title, song.artist ?? '');
    if (mounted) {
      setState(() {
        _lyrics = fetched;
        _loadingLyrics = false;
        _lyricsOffsetMs = savedOffset;
      });
    }
  }

  void _updateLyricsOffset(int deltaMs, int songId) async {
    setState(() {
      _lyricsOffsetMs += deltaMs;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lyrics_offset_$songId', _lyricsOffsetMs);
  }

  void _resetLyricsOffset(int songId) async {
    setState(() {
      _lyricsOffsetMs = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lyrics_offset_$songId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 35),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reproduciendo',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.equalizer, color: Colors.white),
            tooltip: 'Ecualizador',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EqualizerScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.lyrics,
              color: _showLyrics ? Theme.of(context).primaryColor : Colors.white70,
            ),
            tooltip: 'Letra',
            onPressed: () {
              setState(() {
                _showLyrics = !_showLyrics;
              });
            },
          ),
        ],
      ),
      body: Selector<AudioProvider, SongModel?>(
        selector: (context, provider) => provider.currentSong,
        builder: (context, song, child) {
          if (song == null) return const SizedBox.shrink();

          if (_showLyrics && _loadedSongKey != '${song.title}_${song.artist}') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadLyricsForSong(song);
            });
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Artwork or Lyrics View
                Expanded(
                  child: Center(
                    child: _showLyrics
                        ? _buildLyricsView(context)
                        : Hero(
                            tag: 'artwork_${song.id}',
                            child: QueryArtworkWidget(
                              key: ValueKey(song.id),
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              artworkWidth: 300,
                              artworkHeight: 300,
                              keepOldArtwork: true,
                              nullArtworkWidget: Container(
                                width: 300,
                                height: 300,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2C),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).primaryColor.withOpacity(0.2),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.music_note, size: 120, color: Colors.white24),
                              ),
                              artworkBorder: BorderRadius.circular(30),
                              artworkFit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Title and Artist
                Text(
                  song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song.artist ?? "Artista desconocido",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<AudioProvider>(
                  builder: (context, provider, child) {
                    final isFav = provider.isFavorite(song.id);
                    final isCloud = provider.isCloudSong(song);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (provider.isConnectingCloudStream)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.lightBlueAccent),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Conectando audio en la nube...',
                                  style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => provider.toggleFavorite(song),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isFav ? Colors.redAccent.withValues(alpha: 0.15) : Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isFav ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white24,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isFav ? Icons.favorite : Icons.favorite_border,
                                      color: isFav ? Colors.redAccent : Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isFav ? 'En tus favoritas' : 'Añadir a favoritas',
                                      style: TextStyle(
                                        color: isFav ? Colors.redAccent : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (isCloud)
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  final downloader = Provider.of<DownloaderProvider>(context, listen: false);
                                  String query = song.getMap['youtube_id']?.toString() ?? '';
                                  if (query.isEmpty) {
                                    query = '${song.title} ${song.artist ?? ""}';
                                  } else if (!query.startsWith('http')) {
                                    query = 'https://www.youtube.com/watch?v=$query';
                                  }
                                  downloader.startDownload(query, onSuccess: () {
                                    provider.fetchSongs();
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Descargando "${song.title}" a este celular...')),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.6)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.download_rounded, color: Colors.lightBlueAccent, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'Descargar offline',
                                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 25),
                
                // Progress Bar
                Consumer<AudioProvider>(
                  builder: (context, audioProvider, child) {
                    return ProgressBar(
                      progress: audioProvider.currentPosition,
                      total: audioProvider.totalDuration,
                      progressBarColor: Theme.of(context).primaryColor,
                      baseBarColor: Colors.white24,
                      thumbColor: Theme.of(context).primaryColor,
                      timeLabelTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      onSeek: (duration) {
                        audioProvider.seekTo(duration);
                      },
                    );
                  },
                ),
                
                const SizedBox(height: 20),
                
                // Controls
                Consumer<AudioProvider>(
                  builder: (context, audioProvider, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shuffle,
                            color: audioProvider.isShuffle ? Theme.of(context).primaryColor : Colors.white70,
                          ),
                          onPressed: () => audioProvider.toggleShuffle(),
                        ),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_previous, color: Colors.white),
                          onPressed: () => audioProvider.previousSong(),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).primaryColor,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).primaryColor.withOpacity(0.4),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: IconButton(
                            iconSize: 50,
                            icon: Icon(
                              audioProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed: () => audioProvider.playPause(),
                          ),
                        ),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_next, color: Colors.white),
                          onPressed: () => audioProvider.nextSong(),
                        ),
                        IconButton(
                          icon: Icon(
                            audioProvider.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                            color: audioProvider.loopMode != LoopMode.off ? Theme.of(context).primaryColor : Colors.white70,
                          ),
                          onPressed: () => audioProvider.toggleRepeat(),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context) {
    if (_loadingLyrics) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Buscando letra...', style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    if (_lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lyrics_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('No se encontró letra para esta canción', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                final current = Provider.of<AudioProvider>(context, listen: false).currentSong;
                if (current != null) {
                  _loadedSongKey = null;
                  _loadLyricsForSong(current);
                }
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final hasSyncedLyrics = _lyrics.any((l) => l.timestamp > Duration.zero);

    return Consumer<AudioProvider>(
      builder: (context, provider, child) {
        final currentPos = provider.currentPosition;
        // Compensación de corte de silencio (+/- ms)
        final effectivePos = currentPos + Duration(milliseconds: _lyricsOffsetMs);

        // Buscar línea activa
        int activeIndex = -1;
        if (hasSyncedLyrics) {
          for (int i = 0; i < _lyrics.length; i++) {
            if (_lyrics[i].timestamp <= effectivePos) {
              activeIndex = i;
            } else {
              break;
            }
          }
        }

        // Auto-desplazamiento suave para centrar la letra activa
        if (activeIndex != _lastActiveIndex && activeIndex != -1) {
          _lastActiveIndex = activeIndex;
          final now = DateTime.now();
          final userRecentlyScrolled = _lastUserScrollTime != null &&
              now.difference(_lastUserScrollTime!).inSeconds < 3;

          if (!userRecentlyScrolled && _lyricsScrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_lyricsScrollController.hasClients) return;
              final target = (activeIndex * 60.0) - 140.0;
              final maxScroll = _lyricsScrollController.position.maxScrollExtent;
              final clamped = target.clamp(0.0, maxScroll);
              _lyricsScrollController.animateTo(
                clamped,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            });
          }
        }

        final currentSong = provider.currentSong;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              // Barra de sincronización / calibración de silencio
              if (hasSyncedLyrics && currentSong != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161616),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sync, size: 14, color: Colors.white54),
                      const SizedBox(width: 4),
                      const Text(
                        'Silencio:',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      const SizedBox(width: 6),
                      // -0.5s
                      InkWell(
                        onTap: () => _updateLyricsOffset(-500, currentSong.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('-0.5s', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // -0.1s
                      InkWell(
                        onTap: () => _updateLyricsOffset(-100, currentSong.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('-0.1s', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Indicador de Offset actual
                      GestureDetector(
                        onTap: () => _resetLyricsOffset(currentSong.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _lyricsOffsetMs != 0 ? Colors.deepPurpleAccent.withOpacity(0.3) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_lyricsOffsetMs >= 0 ? '+' : ''}${(_lyricsOffsetMs / 1000.0).toStringAsFixed(1)}s',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _lyricsOffsetMs != 0 ? Colors.cyanAccent : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // +0.1s
                      InkWell(
                        onTap: () => _updateLyricsOffset(100, currentSong.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('+0.1s', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // +0.5s
                      InkWell(
                        onTap: () => _updateLyricsOffset(500, currentSong.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('+0.5s', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ),
                      if (_lyricsOffsetMs != 0) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _resetLyricsOffset(currentSong.id),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: Icon(Icons.restart_alt, size: 14, color: Colors.orangeAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Lista con seguimiento en tiempo real
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification && notification.dragDetails != null) {
                      _lastUserScrollTime = DateTime.now();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _lyricsScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _lyrics.length,
                    itemBuilder: (context, index) {
                      final line = _lyrics[index];
                      final isActive = index == activeIndex;
                      final isNear = (index - activeIndex).abs() == 1;

                      return GestureDetector(
                        onTap: hasSyncedLyrics
                            ? () {
                                final seekTarget = line.timestamp - Duration(milliseconds: _lyricsOffsetMs);
                                provider.seekTo(seekTarget < Duration.zero ? Duration.zero : seekTarget);
                              }
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.deepPurpleAccent.withOpacity(0.22) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isActive
                                ? Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4), width: 1)
                                : null,
                          ),
                          child: Text(
                            line.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isActive ? 21 : (isNear ? 16 : 15),
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
                              color: isActive
                                  ? Colors.white
                                  : (isNear ? Colors.white70 : const Color(0xFF757575)),
                              height: 1.3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}