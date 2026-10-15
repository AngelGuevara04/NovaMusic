import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsLine {
  final Duration timestamp;
  final String text;

  LyricsLine({required this.timestamp, required this.text});
}

class LyricsService {
  static final Map<String, List<LyricsLine>> _cache = {};

  static Future<List<LyricsLine>> fetchLyrics(String title, String artist) async {
    // Limpiar texto para búsqueda más certera
    String cleanTitle = title
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'feat\..*|ft\..*', caseSensitive: false), '')
        .trim();

    String cleanArtist = artist
        .replaceAll(RegExp(r'VEVO|- Topic', caseSensitive: false), '')
        .trim();

    String cacheKey = '${cleanTitle}_$cleanArtist'.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final uri = Uri.parse('https://lrclib.net/api/get').replace(queryParameters: {
        'track_name': cleanTitle,
        if (cleanArtist.isNotEmpty && cleanArtist.toLowerCase() != 'desconocido')
          'artist_name': cleanArtist,
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'NovaMusic/1.0.0 (https://github.com/AngelGuevara04/NovaMusic)',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? syncedLyrics = data['syncedLyrics'];
        String? plainLyrics = data['plainLyrics'];

        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          final lines = _parseLrc(syncedLyrics);
          _cache[cacheKey] = lines;
          return lines;
        } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
          final lines = plainLyrics
              .split('\n')
              .map((line) => LyricsLine(timestamp: Duration.zero, text: line.trim()))
              .where((l) => l.text.isNotEmpty)
              .toList();
          _cache[cacheKey] = lines;
          return lines;
        }
      }
    } catch (e) {
      print('Error fetching lyrics: $e');
    }

    return [];
  }

  static List<LyricsLine> _parseLrc(String lrc) {
    List<LyricsLine> lines = [];
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (var rawLine in lrc.split('\n')) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3)!;
        final millis = millisStr.length == 2 ? int.parse(millisStr) * 10 : int.parse(millisStr);
        final text = match.group(4)!.trim();

        if (text.isNotEmpty) {
          lines.add(LyricsLine(
            timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text: text,
          ));
        }
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }
}
