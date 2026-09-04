// lib/core/database/app_database.dart
//
// Clase principal de la base de datos. Aquí se registran todas las tablas
// y se definen queries reutilizables. El archivo app_database.g.dart se
// genera automáticamente al correr build_runner (no se escribe a mano).

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Songs, LyricsCache, Playlists, PlaylistSongs, Favorites, PlayHistory],
)
class AppDatabase extends _$AppDatabase {
  // Se le pasa la conexión desde afuera (ver _openConnection abajo),
  // esto facilita el testing porque en tests se puede inyectar una
  // base de datos en memoria en lugar de una real.
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(songs, songs.isHidden);
          if (from < 3) await m.createTable(lyricsCache);
        },
      );

  // --- QUERIES REACTIVAS ---
  // Un Stream se actualiza automáticamente cuando la tabla cambia.
  // Esto es clave para Riverpod: la UI se refresca sola sin código extra.

  Stream<List<Song>> watchAllSongs() {
    return (select(songs)
          ..where((song) => song.isHidden.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  Stream<List<Song>> watchHiddenSongs() {
    return (select(songs)
          ..where((song) => song.isHidden.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  Stream<List<Song>> watchFavoriteSongs() {
    final query = select(songs).join([
      innerJoin(favorites, favorites.songId.equalsExp(songs.id)),
    ]);
    return query.watch().map(
          (rows) => rows.map((row) => row.readTable(songs)).toList(),
        );
  }

  Future<int> insertSong(SongsCompanion song) {
    return into(songs).insertOnConflictUpdate(song);
  }

  Future<LyricsCacheData?> getCachedLyrics(String filePath) {
    return (select(lyricsCache)..where((row) => row.filePath.equals(filePath)))
        .getSingleOrNull();
  }

  Future<void> cacheLyrics({
    required String filePath,
    String? plainLyrics,
    String? syncedLyrics,
  }) async {
    await into(lyricsCache).insertOnConflictUpdate(
          LyricsCacheCompanion.insert(
            filePath: filePath,
            plainLyrics: Value(plainLyrics),
            syncedLyrics: Value(syncedLyrics),
          ),
        );
  }

  /// Busca la misma obra musical aunque haya llegado desde otro dispositivo
  /// con una ruta de archivo distinta.
  Future<int?> findSongByMetadata({
    required String title,
    required String artist,
    required int durationMs,
  }) async {
    final row = await (select(songs)
          ..where((song) =>
              song.title.equals(title) &
              song.artist.equals(artist) &
              song.durationMs.equals(durationMs)))
        .getSingleOrNull();
    return row?.id;
  }

  Future<void> toggleFavorite(int songId) async {
    final existing = await (select(favorites)
          ..where((f) => f.songId.equals(songId)))
        .getSingleOrNull();

    if (existing != null) {
      await (delete(favorites)..where((f) => f.songId.equals(songId))).go();
    } else {
      await into(favorites)
          .insert(FavoritesCompanion.insert(songId: Value(songId)));
    }
  }

  Stream<List<Playlist>> watchPlaylists() {
    return (select(playlists)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<int> createPlaylist(String name) {
    return into(playlists).insert(PlaylistsCompanion.insert(name: name));
  }

  Future<void> deletePlaylist(int playlistId) {
    return (delete(playlists)
          ..where((playlist) => playlist.id.equals(playlistId)))
        .go();
  }

  Stream<List<Song>> watchPlaylistSongs(int playlistId) {
    final query = select(songs).join([
      innerJoin(playlistSongs, playlistSongs.songId.equalsExp(songs.id)),
    ])
      ..where(playlistSongs.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: playlistSongs.position)]);
    return query
        .watch()
        .map((rows) => rows.map((row) => row.readTable(songs)).toList());
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final existing = await (select(playlistSongs)
          ..where((entry) =>
              entry.playlistId.equals(playlistId) &
              entry.songId.equals(songId)))
        .getSingleOrNull();
    if (existing != null) return;

    final entries = await (select(playlistSongs)
          ..where((entry) => entry.playlistId.equals(playlistId)))
        .get();
    final position = entries.fold<int>(
        0, (max, entry) => entry.position >= max ? entry.position + 1 : max);
    await into(playlistSongs).insert(
      PlaylistSongsCompanion.insert(
          playlistId: playlistId, songId: songId, position: position),
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) {
    return (delete(playlistSongs)
          ..where((entry) =>
              entry.playlistId.equals(playlistId) & entry.songId.equals(songId)))
        .go();
  }

  Future<void> removeSong(int songId) {
    return (delete(songs)..where((song) => song.id.equals(songId))).go();
  }

  Future<void> incrementPlayCount(int songId) {
    return customUpdate(
      'UPDATE songs SET play_count = play_count + 1 WHERE id = ?',
      variables: [Variable<int>(songId)],
      updates: {songs},
    );
  }

  Future<void> setSongsHidden(Iterable<int> songIds, bool hidden) async {
    final ids = songIds.toList();
    if (ids.isEmpty) return;
    await (update(songs)..where((song) => song.id.isIn(ids))).write(
      SongsCompanion(isHidden: Value(hidden)),
    );
  }
}

// Abre la conexión física al archivo SQLite. Se guarda en el directorio
// de documentos de la app, que existe tanto en móvil como en desktop.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mushare.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
