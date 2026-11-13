class PlaylistSong {
  final int id;
  final String title;
  final String artist;
  final int duration;
  final String youtubeId;
  final String url;
  final String addedAt;

  PlaylistSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.youtubeId = '',
    this.url = '',
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'duration': duration,
    'youtube_id': youtubeId,
    'url': url,
    'added_at': addedAt,
  };

  factory PlaylistSong.fromJson(Map<String, dynamic> json) => PlaylistSong(
    id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? DateTime.now().millisecondsSinceEpoch,
    title: json['title'] ?? 'Sin título',
    artist: json['artist'] ?? 'Artista desconocido',
    duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration'].toString()) ?? 0,
    youtubeId: json['youtube_id'] ?? '',
    url: json['url'] ?? '',
    addedAt: json['added_at'] ?? DateTime.now().toIso8601String(),
  );
}

class PlaylistModel {
  final String id;
  String name;
  final String createdAt;
  List<PlaylistSong> songs;

  PlaylistModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt,
    'songs': songs.map((s) => s.toJson()).toList(),
  };

  factory PlaylistModel.fromJson(Map<String, dynamic> json) => PlaylistModel(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] ?? 'Mi Lista',
    createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
    songs: (json['songs'] as List? ?? [])
        .map((e) => PlaylistSong.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
