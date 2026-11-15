import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class HiddenSongsScreen extends StatefulWidget {
  const HiddenSongsScreen({Key? key}) : super(key: key);

  @override
  State<HiddenSongsScreen> createState() => _HiddenSongsScreenState();
}

class _HiddenSongsScreenState extends State<HiddenSongsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
              return TextButton.icon(
                onPressed: () {
                  provider.restoreAllHiddenSongs();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Todas las canciones han sido restauradas a tu lista')),
                  );
                },
                icon: const Icon(Icons.restore, color: Colors.deepPurpleAccent, size: 18),
                label: const Text('Restaurar todas', style: TextStyle(color: Colors.deepPurpleAccent)),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioProvider>(
        builder: (context, provider, child) {
          if (provider.autoDeleteFromDevice) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 72, color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      'Lista de ocultas desactivada',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Tienes activa la opción de "Borrar archivo del dispositivo al quitar de la lista", por lo que las canciones eliminadas se borran directamente y no se acumulan aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }

          final allHidden = provider.hiddenSongs;
          if (allHidden.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off_outlined, size: 80, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'No tienes canciones ocultas',
                    style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          final filteredSongs = _searchQuery.trim().isEmpty
              ? allHidden
              : allHidden.where((s) {
                  final q = _searchQuery.toLowerCase().trim();
                  return s.title.toLowerCase().contains(q) ||
                      (s.artist?.toLowerCase().contains(q) ?? false);
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar canción oculta para restaurar...',
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.deepPurpleAccent),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filteredSongs.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron canciones ocultas con ese nombre.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredSongs.length,
                        itemBuilder: (context, index) {
                          final song = filteredSongs[index];
                          return ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.music_off, color: Colors.white54, size: 20),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              song.artist ?? 'Artista desconocido',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurpleAccent.withOpacity(0.25),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.restore, size: 16, color: Color(0xFFB388FF)),
                              label: const Text('Restaurar', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                provider.unhideSong(song);
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('"${song.title}" restaurada a tu lista')),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
