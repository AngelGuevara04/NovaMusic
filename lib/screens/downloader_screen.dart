import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../providers/downloader_provider.dart';
import '../providers/audio_provider.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({Key? key}) : super(key: key);

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  late StreamSubscription _intentSubscription;
  String _selectedChip = 'Para ti';

  @override
  void initState() {
    super.initState();
    _initSharingIntent();
    
    // Al abrir la pantalla, cargar recomendaciones
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final downloader = Provider.of<DownloaderProvider>(context, listen: false);
      final audioProvider = Provider.of<AudioProvider>(context, listen: false);
      
      if (!downloader.isSearching && downloader.searchResults.isEmpty) {
        final artists = _getLocalArtists(audioProvider);
        downloader.loadRecommendations(artists);
      }
    });
  }

  List<String> _getLocalArtists(AudioProvider audioProvider) {
    return audioProvider.songs
        .map((s) => s.artist?.trim() ?? '')
        .where((a) => a.isNotEmpty && a != '<unknown>' && a != 'Unknown' && a.length > 1)
        .toSet()
        .toList();
  }

  void _initSharingIntent() {
    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) _processSharedText(value.first.path);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) _processSharedText(value.first.path);
    });
  }

  void _processSharedText(String text) {
    RegExp regExp = RegExp(r"(https?://[^\s]+)");
    var match = regExp.firstMatch(text);

    if (match != null) {
      setState(() {
        _urlController.text = match.group(0)!;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace recibido. Presiona descargar.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _performSearch() {
    final query = _urlController.text.trim();
    if (query.isNotEmpty) {
      FocusScope.of(context).unfocus();
      setState(() {
        _selectedChip = '';
      });
      if (query.startsWith('http')) {
        _startDownload(query);
      } else {
        Provider.of<DownloaderProvider>(context, listen: false).searchYoutube(query);
      }
    }
  }

  void _startDownload(String url) {
    if (url.isNotEmpty) {
      final downloader = Provider.of<DownloaderProvider>(context, listen: false);
      final audioProvider = Provider.of<AudioProvider>(context, listen: false);
      
      downloader.startDownload(url, onSuccess: () {
        audioProvider.fetchSongs();
      });
    }
  }

  @override
  void dispose() {
    _intentSubscription.cancel();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final localArtists = _getLocalArtists(audioProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Descargas',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Consumer<DownloaderProvider>(
        builder: (context, downloader, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _performSearch(),
                  decoration: InputDecoration(
                    hintText: 'Buscar canción, artista o link...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.white54),
                      onPressed: _performSearch,
                    ),
                  ),
                ),
              ),

              // Chips de artistas recomendados basados en su música
              if (localArtists.isNotEmpty)
                Container(
                  height: 42,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: _selectedChip == 'Para ti',
                          label: const Text('✨ Para ti'),
                          selectedColor: Theme.of(context).primaryColor,
                          labelStyle: TextStyle(
                            color: _selectedChip == 'Para ti' ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedChip = 'Para ti');
                              downloader.loadRecommendations(localArtists);
                            }
                          },
                        ),
                      ),
                      ...localArtists.take(12).map((artist) {
                        final isSelected = _selectedChip == artist;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: isSelected,
                            label: Text(artist),
                            selectedColor: Theme.of(context).primaryColor,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedChip = artist;
                                  _urlController.text = artist;
                                });
                                downloader.recommendForArtist(artist);
                              }
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // Banner explicativo de recomendación
              if (downloader.currentRecommendationArtist != null && !downloader.isSearching)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Recomendado para ti basado en: ${downloader.currentRecommendationArtist}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          downloader.loadRecommendations(localArtists);
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.refresh, color: Colors.white70, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

              // Descargas activas
              if (downloader.activeDownloads.isNotEmpty)
                Container(
                  height: 120,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: downloader.activeDownloads.length,
                    itemBuilder: (context, index) {
                      final task = downloader.activeDownloads[index];
                      return Container(
                        width: 280,
                        margin: const EdgeInsets.only(left: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (task.isDownloading)
                              LinearProgressIndicator(value: task.progress >= 0 ? task.progress : null),
                            const SizedBox(height: 8),
                            Text(task.status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: task.hasError ? Colors.red : Colors.greenAccent)),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              const Divider(color: Colors.white10),

              // Lista de resultados o recomendaciones
              Expanded(
                child: downloader.isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : downloader.searchResults.isEmpty
                        ? const Center(
                            child: Text('Busca tu música favorita para descargarla.', style: TextStyle(color: Colors.white54)),
                          )
                        : ListView.builder(
                            itemCount: downloader.searchResults.length,
                            itemBuilder: (context, index) {
                              final video = downloader.searchResults[index];
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(video.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.download, color: Colors.deepPurpleAccent),
                                  onPressed: () {
                                    _startDownload(video.url);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descarga iniciada')));
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
