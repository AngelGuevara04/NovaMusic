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

  @override
  void initState() {
    super.initState();
    _initSharingIntent();
    
    // Al abrir la pantalla, cargar recomendaciones
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final downloader = Provider.of<DownloaderProvider>(context, listen: false);
      final audioProvider = Provider.of<AudioProvider>(context, listen: false);
      
      if (!downloader.isSearching && downloader.searchResults.isEmpty) {
        // Sacar artistas locales únicos
        final artists = audioProvider.songs
            .map((s) => s.artist ?? '')
            .where((a) => a.isNotEmpty && a != '<unknown>')
            .toSet()
            .toList();
            
        downloader.loadRecommendations(artists);
      }
    });
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
      if (query.startsWith('http')) {
        // Es un link directo, descargar
        _startDownload(query);
      } else {
        // Es una búsqueda
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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Descargas',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Consumer<DownloaderProvider>(
        builder: (context, downloader, child) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) => _performSearch(),
                        decoration: InputDecoration(
                          hintText: 'Buscar canción o pegar link...',
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
                  ],
                ),
              ),
              if (downloader.activeDownloads.isNotEmpty)
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(bottom: 8),
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (downloader.previewingUrl == video.url && downloader.isDownloadingPreview)
                                      const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    else
                                      IconButton(
                                        icon: Icon(
                                          downloader.previewingUrl == video.url && downloader.isPreviewPlaying
                                              ? Icons.pause_circle_filled
                                              : Icons.play_circle_filled,
                                          color: Colors.white,
                                        ),
                                        onPressed: () => downloader.togglePreview(video),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.download, color: Colors.deepPurpleAccent),
                                      onPressed: () {
                                        _startDownload(video.url);
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descarga iniciada')));
                                      },
                                    ),
                                  ],
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
