import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class HiddenSongsScreen extends StatelessWidget {
  const HiddenSongsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Canciones Ocultas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Consumer<AudioProvider>(
            builder: (context, provider, child) {
              if (provider.hiddenSongs.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: () {
                  provider.restoreAllHiddenSongs();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Todas las canciones han sido restauradas')),
                  );
                },
                child: const Text('Restaurar Todo', style: TextStyle(color: Colors.redAccent)),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioProvider>(
        builder: (context, provider, child) {
          final hiddenSongs = provider.hiddenSongs;

          if (hiddenSongs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off, size: 80, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'No hay canciones ocultas',
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: hiddenSongs.length,
            itemBuilder: (context, index) {
              final song = hiddenSongs[index];
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_off, color: Colors.white54, size: 20),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  song.artist ?? "Artista desconocido",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.restore, color: Colors.deepPurpleAccent),
                  tooltip: 'Restaurar',
                  onPressed: () {
                    provider.unhideSong(song);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
