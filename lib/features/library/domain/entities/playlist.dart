import 'song.dart';

class PlaylistEntity {
  const PlaylistEntity(
      {required this.id,
      required this.name,
      required this.createdAt,
      this.isFavorites = false,
      this.coverPath,
      this.virtualSongs = const []});

  final int id;
  final String name;
  final DateTime createdAt;
  final bool isFavorites;
  final String? coverPath;
  final List<SongEntity> virtualSongs;
}
