import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

void showAddToPlaylistDialog(BuildContext context, SongModel song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AddToPlaylistModal(song: song),
  );
}

class _AddToPlaylistModal extends StatefulWidget {
  final SongModel song;
  const _AddToPlaylistModal({Key? key, required this.song}) : super(key: key);

  @override
  State<_AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends State<_AddToPlaylistModal> {
  final TextEditingController _newPlaylistController = TextEditingController();

  void _showCreateDialog(AudioProvider provider) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nueva Lista de Reproducción', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: _newPlaylistController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej. Baladas de Oro, Rock, Entrenar...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepPurpleAccent)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepPurpleAccent, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = _newPlaylistController.text.trim();
              if (name.isNotEmpty) {
                final created = await provider.createPlaylist(name);
                _newPlaylistController.clear();
                if (mounted) {
                  Navigator.pop(dialogCtx);
                  await provider.addSongToPlaylist(created.id, widget.song);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Añadida a "$name" y sincronizada en la nube')),
                    );
                  }
                }
              }
            },
            child: const Text('Crear y Añadir'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final playlists = audioProvider.playlists;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.playlist_add, color: Colors.deepPurpleAccent, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Añadir a lista de reproducción',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: Colors.deepPurpleAccent, size: 24),
            ),
            title: const Text('Nueva lista de reproducción', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Crear y sincronizar con la nube', style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () => _showCreateDialog(audioProvider),
          ),
          const Divider(color: Colors.white12),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text('Aún no tienes listas de reproducción creadas.', style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, idx) {
                  final p = playlists[idx];
                  final hasSong = p.songs.any((s) => s.id == widget.song.id || s.title.toLowerCase().trim() == widget.song.title.toLowerCase().trim());

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.queue_music, color: Colors.white70, size: 20),
                    ),
                    title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('${p.songs.length} canciones', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: hasSong
                        ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22)
                        : const Icon(Icons.add_circle_outline, color: Colors.white38, size: 22),
                    onTap: () async {
                      if (hasSong) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Esta canción ya está en "${p.name}"')),
                        );
                      } else {
                        await audioProvider.addSongToPlaylist(p.id, widget.song);
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Añadida a "${p.name}" (Sincronizada en la nube)')),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
