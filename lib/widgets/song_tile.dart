import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/audio_provider.dart';

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
                content: Text('${song.title} eliminada del dispositivo'),
                backgroundColor: Colors.black87,
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
                Expanded(child: Text('¿Eliminar canción?', style: TextStyle(color: Colors.white, fontSize: 18))),
              ],
            ),
            content: Text(
              '¿Deseas solo quitar "${song.title}" de la lista o borrar el archivo permanentemente de tu dispositivo?',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.deepPurpleAccent),
                ),
                onPressed: () => Navigator.pop(ctx, 'hide'),
                child: const Text('Solo de la lista', style: TextStyle(color: Colors.deepPurpleAccent)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Borrar del celular', style: TextStyle(color: Colors.white)),
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
                content: Text('${song.title} quitada de la lista'),
                backgroundColor: Colors.black87,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                action: SnackBarAction(
                  label: 'Deshacer',
                  textColor: Theme.of(context).primaryColor,
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
                content: Text('${song.title} borrada del celular'),
                backgroundColor: Colors.black87,
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
          color: isPlaying ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isPlaying ? Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)) : null,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.music_note,
              color: Colors.deepPurpleAccent,
            ),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              color: isPlaying ? Theme.of(context).primaryColor : Colors.white,
            ),
          ),
          subtitle: Text(
            song.artist ?? "Artista desconocido",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
          trailing: isPlaying
              ? Icon(Icons.bar_chart, color: Theme.of(context).primaryColor)
              : null,
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
