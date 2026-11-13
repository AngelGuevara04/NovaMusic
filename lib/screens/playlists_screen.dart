import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({Key? key}) : super(key: key);

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _showCreateDialog(BuildContext context, AudioProvider provider) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nueva Lista de Reproducción', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nombre de la lista (ej. Favoritas de José José)',
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
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                final created = await provider.createPlaylist(name);
                _nameController.clear();
                if (mounted) {
                  Navigator.pop(dialogCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaylistDetailScreen(playlistId: created.id),
                    ),
                  );
                }
              }
            },
            child: const Text('Crear Lista'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final playlists = audioProvider.playlists;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mis Listas de Reproducción',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.deepPurpleAccent, size: 28),
            tooltip: 'Crear nueva lista',
            onPressed: () => _showCreateDialog(context, audioProvider),
          ),
        ],
      ),
      body: playlists.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.queue_music, size: 60, color: Colors.deepPurpleAccent),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Sin listas de reproducción',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Crea listas de reproducción para organizar tu música favorita. Se sincronizan automáticamente entre tu celular y tu PC.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear mi primera lista'),
                      onPressed: () => _showCreateDialog(context, audioProvider),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final p = playlists[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.deepPurpleAccent.withOpacity(0.4),
                            Colors.purpleAccent.withOpacity(0.2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.queue_music, color: Colors.deepPurpleAccent, size: 28),
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Row(
                      children: [
                        Text('${p.songs.length} canciones', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 8),
                        const Icon(Icons.cloud_done, size: 14, color: Color(0xFF69F0AE)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.songs.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.play_circle_filled, color: Colors.deepPurpleAccent, size: 30),
                            tooltip: 'Reproducir',
                            onPressed: () {
                              audioProvider.playPlaylist(p);
                            },
                          ),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white30),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlaylistDetailScreen(playlistId: p.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
