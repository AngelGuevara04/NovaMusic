import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class SongArtworkWidget extends StatelessWidget {
  final SongModel song;
  final double size;
  final double borderRadius;
  final bool isCloud;
  final bool isDiscovery;

  const SongArtworkWidget({
    Key? key,
    required this.song,
    this.size = 50,
    this.borderRadius = 10,
    this.isCloud = false,
    this.isDiscovery = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ytId = song.getMap['youtube_id']?.toString().trim() ?? '';
    final customArtUrl = song.getMap['custom_art_url']?.toString().trim() ?? '';

    Widget fallbackWidget() {
      if (customArtUrl.isNotEmpty) {
        return Image.network(
          customArtUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIconBox(),
        );
      }
      if (ytId.isNotEmpty) {
        return Image.network(
          'https://i.ytimg.com/vi/$ytId/hqdefault.jpg',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIconBox(),
        );
      }
      return _defaultIconBox();
    }

    Widget content;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && !isCloud && !isDiscovery) {
      content = QueryArtworkWidget(
        key: ValueKey('art_${song.id}_${song.title}'),
        id: song.id,
        type: ArtworkType.AUDIO,
        artworkWidth: size,
        artworkHeight: size,
        artworkFit: BoxFit.cover,
        keepOldArtwork: true,
        artworkBorder: BorderRadius.circular(borderRadius),
        nullArtworkWidget: fallbackWidget(),
      );
    } else {
      content = fallbackWidget();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: content,
      ),
    );
  }

  Widget _defaultIconBox() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDiscovery
              ? [const Color(0xFF4A3712), const Color(0xFF281D0A)]
              : (isCloud
                  ? [const Color(0xFF12324A), const Color(0xFF102030)]
                  : [const Color(0xFF332056), const Color(0xFF1D1530)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        isDiscovery
            ? Icons.auto_awesome
            : (isCloud ? Icons.cloud_outlined : Icons.music_note_rounded),
        color: isDiscovery
            ? Colors.amberAccent
            : (isCloud ? Colors.lightBlueAccent : const Color(0xFFB388FF)),
        size: size * 0.5,
      ),
    );
  }
}
