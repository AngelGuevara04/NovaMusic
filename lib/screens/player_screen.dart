import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/audio_provider.dart';
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

  void _loadLyricsForSong(SongModel song) async {
    final key = '${song.title}_${song.artist}';
    if (_loadedSongKey == key) return;
    setState(() {
      _loadingLyrics = true;
      _loadedSongKey = key;
    });

    final fetched = await LyricsService.fetchLyrics(song.title, song.artist ?? '');
    if (mounted) {
      setState(() {
        _lyrics = fetched;
        _loadingLyrics = false;
      });
    }
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
                    color: Colors.white54,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Progress Bar
                Consumer<AudioProvider>(
                  builder: (context, audioProvider, child) {
                    return ProgressBar(
                      progress: audioProvider.currentPosition,
                      total: audioProvider.totalDuration,
                      progressBarColor: Theme.of(context).primaryColor,
                      baseBarColor: Colors.white24,
                      thumbColor: Theme.of(context).primaryColor,
                      timeLabelTextStyle: const TextStyle(color: Colors.white54, fontSize: 12),
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
                            color: audioProvider.isShuffle ? Theme.of(context).primaryColor : Colors.white54,
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
                            color: audioProvider.loopMode != LoopMode.off ? Theme.of(context).primaryColor : Colors.white54,
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
          Text('Buscando letra...', style: TextStyle(color: Colors.white54)),
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
            const Text('No se encontró letra para esta canción', style: TextStyle(color: Colors.white54)),
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

    return Consumer<AudioProvider>(
      builder: (context, provider, child) {
        final currentPos = provider.currentPosition;
        
        // Find current lyric index
        int activeIndex = -1;
        for (int i = 0; i < _lyrics.length; i++) {
          if (_lyrics[i].timestamp <= currentPos) {
            activeIndex = i;
          } else {
            break;
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
          ),
          child: ListView.builder(
            itemCount: _lyrics.length,
            itemBuilder: (context, index) {
              final line = _lyrics[index];
              final isActive = index == activeIndex;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isActive ? 20 : 16,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Theme.of(context).primaryColor : Colors.white38,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
