import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/audio_provider.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);

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
            icon: const Icon(Icons.favorite_border, color: Colors.white),
            onPressed: () {
              // TODO: Implement favorites
            },
          ),
        ],
      ),
      body: Selector<AudioProvider, SongModel?>(
        selector: (context, provider) => provider.currentSong,
        builder: (context, song, child) {
          if (song == null) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Artwork
                Expanded(
                  child: Center(
                    child: Hero(
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
}
