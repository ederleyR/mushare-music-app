import 'song.dart';

class PlaylistEntity {
  const PlaylistEntity(
      {required this.id,
      required this.name,
      required this.createdAt,
      this.isFavorites = false,
      this.virtualSongs = const []});

  final int id;
  final String name;
  final DateTime createdAt;
  final bool isFavorites;
  final List<SongEntity> virtualSongs;
}
