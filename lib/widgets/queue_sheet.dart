import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import 'song_artwork.dart';

void showQueueBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) {
          return Consumer<AudioProvider>(
            builder: (context, provider, _) {
              final current = provider.currentSong;
              final queue = provider.upNextQueue;

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music_rounded, color: Color(0xFFB388FF)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Cola de reproducción',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (queue.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => provider.clearQueue(),
                            icon: const Icon(Icons.clear_all, size: 18, color: Colors.redAccent),
                            label: const Text('Vaciar', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      children: [
                        if (current != null) ...[
                          const Text(
                            'REPRODUCIENDO AHORA',
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.9),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              children: [
                                SongArtworkWidget(
                                  song: current,
                                  size: 46,
                                  borderRadius: 10,
                                  isCloud: provider.isCloudSong(current),
                                  isDiscovery: provider.isPlayingDiscoverySong,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        current.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Color(0xFFB388FF), fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        current.artist ?? 'Artista desconocido',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.graphic_eq, color: Color(0xFFB388FF), size: 22),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Row(
                          children: [
                            Text(
                              'A CONTINUACIÓN (${queue.length})',
                              style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.9),
                            ),
                            const Spacer(),
                            if (queue.length > 1)
                              const Text(
                                'Mantén y arrastra para ordenar',
                                style: TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (queue.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF202020),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.playlist_play_rounded, color: Colors.white24, size: 42),
                                SizedBox(height: 8),
                                Text(
                                  'Tu cola manual está vacía',
                                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Toca el menú (⋮) de cualquier canción y elige "Reproducir a continuación" o "Agregar a la cola".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: queue.length,
                            onReorder: (oldIndex, newIndex) => provider.reorderQueue(oldIndex, newIndex),
                            itemBuilder: (ctx, i) {
                              final qSong = queue[i];
                              return Container(
                                key: ValueKey('q_${qSong.id}_$i'),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  leading: SongArtworkWidget(
                                    song: qSong,
                                    size: 42,
                                    borderRadius: 8,
                                    isCloud: provider.isCloudSong(qSong),
                                  ),
                                  title: Text(
                                    qSong.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    qSong.artist ?? 'Artista desconocido',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                                        tooltip: 'Quitar de la cola',
                                        onPressed: () => provider.removeFromQueue(i),
                                      ),
                                      const Icon(Icons.drag_handle, color: Colors.white38),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}
