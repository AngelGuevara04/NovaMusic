import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class YouTubeAudioSource extends StreamAudioSource {
  final Uri uri;
  final int totalBytes;
  final String contentType;
  final http.Client _client = http.Client();

  YouTubeAudioSource({
    required this.uri,
    required this.totalBytes,
    required this.contentType,
    dynamic tag,
  }) : super(tag: tag);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= totalBytes;

    final request = http.Request('GET', uri);
    request.headers['Range'] = 'bytes=$start-${end - 1}';
    request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
    final response = await _client.send(request);

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalBytes,
      contentLength: response.contentLength ?? (end - start),
      offset: start,
      stream: response.stream,
      contentType: contentType,
    );
  }
}
