import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/audio_provider.dart';
import '../providers/downloader_provider.dart';

class SongTile extends StatelessWidget {
  final SongModel song;
  final int index;
  final VoidCallback onTap;

  const SongTile({
    Key? key,
    required this.song,
    required this.index,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final isPlaying = audioProvider.currentSong?.id == song.id;

    return Dismissible(
      key: Key(song.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final prefs = await SharedPreferences.getInstance();
        final autoDelete = prefs.getBool('auto_delete_from_device') ?? false;

        if (autoDelete) {
          await audioProvider.deletePhysicalSong(song);
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${song.title} eliminada del dispositivo',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                backgroundColor: const Color(0xFF262626),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return true;
        }

        if (!context.mounted) return false;

        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '¿Eliminar canción?',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              '¿Deseas solo quitar "${song.title}" de la lista o borrar el archivo permanentemente de tu dispositivo?',
              style: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 15, height: 1.3),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFB388FF)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => Navigator.pop(ctx, 'hide'),
                child: const Text(
                  'Solo de la lista',
                  style: TextStyle(color: Color(0xFFD1C4E9), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text(
                  'Borrar del celular',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

        if (choice == 'hide') {
          await audioProvider.hideSong(song);
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${song.title} quitada de la lista',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                backgroundColor: const Color(0xFF262626),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                action: SnackBarAction(
                  label: 'Deshacer',
                  textColor: const Color(0xFFB388FF),
                  onPressed: () => audioProvider.unhideSong(song),
                ),
              ),
            );
          }
          return true;
        } else if (choice == 'delete') {
          await audioProvider.deletePhysicalSong(song);
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${song.title} borrada del celular',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                backgroundColor: const Color(0xFF262626),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return true;
        }

        return false;
      },
      onDismissed: (direction) {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isPlaying ? Theme.of(context).primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isPlaying ? Border.all(color: Theme.of(context).primaryColor.withOpacity(0.6)) : null,
        ),
        child: Builder(
          builder: (context) {
            final isCloud = audioProvider.isCloudSong(song);

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isCloud
                      ? Colors.lightBlueAccent.withValues(alpha: 0.15)
                      : Colors.deepPurpleAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCloud ? Icons.cloud_outlined : Icons.music_note,
                  color: isCloud ? Colors.lightBlueAccent : Colors.deepPurpleAccent,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                        color: isPlaying ? const Color(0xFFB388FF) : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (isCloud) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_outlined, color: Colors.lightBlueAccent, size: 10),
                          SizedBox(width: 3),
                          Text(
                            'Nube',
                            style: TextStyle(color: Colors.lightBlueAccent, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                song.artist ?? "Artista desconocido",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 13,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPlaying)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: audioProvider.isConnectingCloudStream
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFB388FF)),
                            )
                          : const Icon(Icons.bar_chart, color: Color(0xFFB388FF), size: 22),
                    ),
                  if (isCloud)
                    IconButton(
                      splashRadius: 20,
                      padding: const EdgeInsets.only(right: 6),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.download_for_offline_outlined, color: Colors.deepPurpleAccent, size: 22),
                      tooltip: 'Descargar a este dispositivo',
                      onPressed: () {
                        final downloader = Provider.of<DownloaderProvider>(context, listen: false);
                        String query = song.getMap['youtube_id']?.toString() ?? '';
                        if (query.isEmpty) {
                          query = '${song.title} ${song.artist ?? ""}';
                        } else if (!query.startsWith('http')) {
                          query = 'https://www.youtube.com/watch?v=$query';
                        }
                        downloader.startDownload(query, onSuccess: () {
                          audioProvider.fetchSongs();
                        });
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Descargando "${song.title}" a este celular...'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  IconButton(
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      audioProvider.isFavorite(song.id) ? Icons.favorite : Icons.favorite_border,
                      color: audioProvider.isFavorite(song.id) ? Colors.redAccent : Colors.white38,
                      size: 22,
                    ),
                    tooltip: audioProvider.isFavorite(song.id) ? 'Quitar de favoritas' : 'Marcar como favorita',
                    onPressed: () => audioProvider.toggleFavorite(song),
                  ),
                ],
              ),
              onTap: onTap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          },
        ),
      ),
    );
  }
}
