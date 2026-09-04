// lib/features/library/data/repositories/library_repository_impl.dart
//
// Implementación concreta del repositorio. Traduce entre:
// - SongEntity (entidad de dominio, usada por toda la app)
// - Song / SongsCompanion (clases generadas por Drift para la tabla `songs`)
//
// Esta capa es la única que "sabe" que la BD es Drift. Si algún día
// cambias de Drift a otro ORM, solo tocas este archivo.

import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/playlist.dart';
import '../datasources/audio_scanner.dart';

class LibraryRepository {
  final AppDatabase _db;
  final AudioScanner _scanner;

  LibraryRepository(this._db, this._scanner);

  /// Escanea el dispositivo y sincroniza los resultados con la BD.
  /// Usa `insertOnConflictUpdate` para no duplicar canciones ya
  /// existentes (se identifican por filePath, que es UNIQUE).
  Future<int> scanAndSync({bool pickFiles = false}) async {
    final foundSongs = await _scanner.scan(pickFiles: pickFiles);

    for (final song in foundSongs) {
      await _db.insertSong(_toCompanion(song));
    }

    return foundSongs.length;
  }

  /// Inserta una canción recibida desde otro dispositivo de forma que quede
  /// disponible inmediatamente en la biblioteca local.
  Future<int> importSong(SongEntity song) => _db.insertSong(_toCompanion(song));

  Future<int?> findMatchingSongId(SongEntity song) => _db.findSongByMetadata(
        title: song.title,
        artist: song.artist,
        durationMs: song.durationMs,
      );

  /// Stream reactivo de todas las canciones. La UI se suscribe a esto
  /// y se actualiza sola cuando cambia algo en la tabla `songs`.
  Stream<List<SongEntity>> watchAllSongs() {
    return _db.watchAllSongs().map(
          (rows) => rows.map(_toEntity).toList(),
        );
  }

  Stream<List<SongEntity>> watchFavorites() {
    return _db.watchFavoriteSongs().map(
          (rows) => rows.map(_toEntity).toList(),
        );
  }

  Future<void> toggleFavorite(int songId) {
    return _db.toggleFavorite(songId);
  }

  Stream<List<PlaylistEntity>> watchPlaylists() {
    return _db.watchPlaylists().map((rows) => rows
        .map((row) => PlaylistEntity(
            id: row.id, name: row.name, createdAt: row.createdAt))
        .toList());
  }

  Future<int> createPlaylist(String name) => _db.createPlaylist(name);

  Future<void> deletePlaylist(int playlistId) => _db.deletePlaylist(playlistId);

  Stream<List<SongEntity>> watchPlaylistSongs(int playlistId) {
    return _db
        .watchPlaylistSongs(playlistId)
        .map((rows) => rows.map(_toEntity).toList());
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) =>
      _db.addSongToPlaylist(playlistId, songId);

  Future<void> removeSong(int songId) => _db.removeSong(songId);

  Future<void> removeSongFromPlaylist(int playlistId, int songId) =>
      _db.removeSongFromPlaylist(playlistId, songId);

  Future<void> incrementPlayCount(int songId) => _db.incrementPlayCount(songId);

  Stream<List<SongEntity>> watchHiddenSongs() {
    return _db.watchHiddenSongs().map((rows) => rows.map(_toEntity).toList());
  }

  Future<void> setSongsHidden(Iterable<int> songIds, bool hidden) =>
      _db.setSongsHidden(songIds, hidden);

  // --- Mapeo entre capas ---

  SongEntity _toEntity(Song row) {
    return SongEntity(
      id: row.id,
      filePath: row.filePath,
      title: row.title,
      artist: row.artist,
      album: row.album,
      durationMs: row.durationMs,
      artworkPath: row.artworkPath,
      fileSizeBytes: row.fileSizeBytes,
      format: row.format,
      dateAdded: row.dateAdded,
      playCount: row.playCount,
      isHidden: row.isHidden,
    );
  }

  SongsCompanion _toCompanion(SongEntity entity) {
    return SongsCompanion(
      filePath: Value(entity.filePath),
      title: Value(entity.title),
      artist: Value(entity.artist),
      album: Value(entity.album),
      durationMs: Value(entity.durationMs),
      artworkPath: Value(entity.artworkPath),
      fileSizeBytes: Value(entity.fileSizeBytes),
      format: Value(entity.format),
    );
  }
}
