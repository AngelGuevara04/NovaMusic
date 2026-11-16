import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/song_artwork.dart';
import 'player_screen.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Estadísticas y Más Escuchadas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Reiniciar estadísticas',
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('¿Reiniciar estadísticas?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Se pondrán en 0 los contadores de tus canciones y artistas más escuchados.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () {
                        Provider.of<AudioProvider>(context, listen: false).clearPlayStats();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Reiniciar', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioProvider>(
        builder: (context, provider, _) {
          final topSongs = provider.topPlayedSongs;
          final topArtists = provider.topArtists;
          final totalPlays = provider.totalPlayCount;

          if (totalPlays == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 80, color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      'Aún no hay estadísticas',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Reproduce tus canciones favoritas y aquí aparecerán tus temas y artistas más escuchados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Tarjeta resumen
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurpleAccent.withValues(alpha: 0.4),
                      const Color(0xFF1E1E1E),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'REPRODUCCIONES TOTALES',
                            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$totalPlays',
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                          if (topArtists.isNotEmpty)
                            Text(
                              'Artista #1: ${topArtists.first.key}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.auto_graph_rounded, color: Colors.cyanAccent, size: 46),
                  ],
                ),
              ),
              if (topArtists.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text(
                  'TUS ARTISTAS FAVORITOS',
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topArtists.take(6).map((entry) {
                    return Chip(
                      backgroundColor: const Color(0xFF222222),
                      side: BorderSide(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                      avatar: const Icon(Icons.person, color: Color(0xFFB388FF), size: 16),
                      label: Text(
                        '${entry.key} (${entry.value})',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 22),
              const Text(
                'TUS CANCIONES MÁS ESCUCHADAS',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              ...List.generate(topSongs.length, (i) {
                final song = topSongs[i];
                final plays = provider.getPlayCount(song);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '#${i + 1}',
                            style: TextStyle(
                              color: i < 3 ? Colors.amberAccent : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SongArtworkWidget(
                          song: song,
                          size: 46,
                          borderRadius: 8,
                          isCloud: provider.isCloudSong(song),
                        ),
                      ],
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${song.artist ?? "Artista desconocido"} • $plays ${plays == 1 ? "vez" : "veces"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Colors.deepPurpleAccent, size: 32),
                      onPressed: () {
                        final idx = provider.songs.indexWhere((s) => s.id == song.id);
                        if (idx != -1) {
                          provider.playSong(idx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PlayerScreen()),
                          );
                        }
                      },
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
