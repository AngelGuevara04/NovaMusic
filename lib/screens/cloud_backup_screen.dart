import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../providers/audio_provider.dart';
import '../providers/downloader_provider.dart';
import '../widgets/password_dialogs.dart';
import 'downloader_screen.dart';

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({Key? key}) : super(key: key);

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  String _normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'feat\..*|ft\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'official|video|audio|lyrics|en vivo|letra|remastered', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .trim();
  }

  bool _isSongOnDevice(Map<String, dynamic> cloudItem, List<SongModel> localSongs) {
    final cTitle = _normalize(cloudItem['title'] ?? '');
    if (cTitle.isEmpty) return false;

    return localSongs.any((local) {
      final lTitle = _normalize(local.title);
      if (lTitle == cTitle) return true;
      if (cTitle.length >= 6 && lTitle.length >= 6) {
        if (lTitle.contains(cTitle) || cTitle.contains(lTitle)) return true;
      }
      return false;
    });
  }

  void _confirmOverwriteCloud(BuildContext context, AudioProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Sobrescribir Nube', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Esta acción reemplazará toda tu biblioteca en la nube únicamente con las canciones limpias que tienes actualmente en este dispositivo.\n\nÚtil si tienes canciones que se subieron mal o duplicadas.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.overwriteCloudLibraryWithDeviceSongs();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '¡Biblioteca de la nube actualizada desde cero con éxito!' : 'Error al conectar con la nube.'),
                    backgroundColor: ok ? const Color(0xFF7C4DFF) : Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Sí, sobrescribir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final cloudList = audioProvider.cloudLibrarySongs;
    final localSongs = audioProvider.songs;

    // Deduplicate cloud list for display
    final List<Map<String, dynamic>> uniqueCloud = [];
    final Set<String> seen = {};
    for (var item in cloudList) {
      final norm = _normalize(item['title'] ?? '');
      if (norm.isNotEmpty && !seen.contains(norm)) {
        seen.add(norm);
        uniqueCloud.add(item);
      }
    }

    final int totalBackup = uniqueCloud.length;
    final int downloadedCount = uniqueCloud.where((c) => _isSongOnDevice(c, localSongs)).length;
    final int missingCount = totalBackup - downloadedCount;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Copia de Seguridad en la Nube',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Sincronizar',
            onPressed: () {
              audioProvider.fetchSongs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Catálogo sincronizado con la nube')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header resumen
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurpleAccent.withOpacity(0.35),
                  const Color(0xFF1E1E1E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done, color: Colors.cyanAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usuario: ${audioProvider.currentUsername ?? "Invitado"}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '$totalBackup canciones respaldadas en tu cuenta',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (!audioProvider.isGuest && audioProvider.currentUsername != null)
                      IconButton(
                        tooltip: 'Actualizar Contraseña',
                        icon: const Icon(Icons.lock_reset_rounded, color: Color(0xFFB388FF)),
                        onPressed: () => showChangePasswordDialog(context, audioProvider.currentUsername!),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$downloadedCount',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Text('En este celular', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$missingCount',
                              style: TextStyle(
                                color: missingCount > 0 ? Colors.orangeAccent : Colors.white38,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text('No descargadas', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (missingCount > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text('Buscar y recuperar canciones ($missingCount pendientes)'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DownloaderScreen()),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Botones de sincronización y limpieza solicitados por el usuario
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB388FF),
                          side: const BorderSide(color: Color(0xFF7C4DFF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                        label: const Text('Sobrescribir nube de 0', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _confirmOverwriteCloud(context, audioProvider),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.tealAccent,
                          side: const BorderSide(color: Colors.teal),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.playlist_add, size: 16),
                        label: const Text('Unir locales a la nube', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final ok = await audioProvider.mergeDeviceSongsIntoCloudLibrary();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Canciones locales añadidas a tu nube sin duplicados.' : 'Error al conectar con la nube.'),
                                backgroundColor: ok ? const Color(0xFF7C4DFF) : Colors.redAccent,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'LISTA DE CANCIONES RESPALDADAS',
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                ),
                const Spacer(),
                Text(
                  '${uniqueCloud.length} temas',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          // Lista de canciones respaldadas
          Expanded(
            child: uniqueCloud.isEmpty
                ? const Center(
                    child: Text(
                      'No tienes canciones respaldadas en la nube aún.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: uniqueCloud.length,
                    itemBuilder: (context, index) {
                      final item = uniqueCloud[index];
                      final title = item['title'] ?? 'Sin título';
                      final artist = item['artist'] ?? 'Artista desconocido';
                      final isOnDevice = _isSongOnDevice(item, localSongs);
                      final url = item['url']?.toString() ?? '';

                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isOnDevice ? Colors.green.withOpacity(0.15) : Colors.deepPurpleAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isOnDevice ? Icons.check_circle : Icons.cloud_outlined,
                            color: isOnDevice ? Colors.greenAccent : Colors.deepPurpleAccent,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: isOnDevice
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Descargada',
                                  style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurpleAccent.withOpacity(0.3),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.download, size: 14),
                                label: const Text('Descargar', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const DownloaderScreen()),
                                  );
                                },
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
