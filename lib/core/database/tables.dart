// lib/core/database/tables.dart
//
// Definición de las tablas de la base de datos SQLite usando Drift.
// Cada clase representa una tabla; Drift genera el código SQL y las
// clases de datos (data classes) automáticamente vía build_runner.

import 'package:drift/drift.dart';

/// Tabla principal: canciones indexadas desde el almacenamiento local.
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Ruta absoluta del archivo en disco. Es única para evitar duplicados
  // al re-escanear la biblioteca.
  TextColumn get filePath => text().unique()();

  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('Desconocido'))();
  TextColumn get album => text().withDefault(const Constant('Desconocido'))();

  // Duración en milisegundos (más preciso que segundos para el seek bar)
  IntColumn get durationMs => integer()();

  // Ruta local de la portada extraída y cacheada en disco (no se guarda
  // el binario de la imagen en la BD, solo la referencia al archivo).
  TextColumn get artworkPath => text().nullable()();

  IntColumn get fileSizeBytes => integer().nullable()();
  TextColumn get format => text().nullable()(); // mp3, flac, wav

  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();

  IntColumn get playCount => integer().withDefault(const Constant(0))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
}

class LyricsCache extends Table {
  TextColumn get filePath => text()();
  TextColumn get plainLyrics => text().nullable()();
  TextColumn get syncedLyrics => text().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {filePath};
}

/// Playlists creadas manualmente por el usuario.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get coverPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Tabla intermedia N:M entre Playlists y Songs.
/// Guarda también la posición para mantener el orden de la lista.
class PlaylistSongs extends Table {
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get songId =>
      integer().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, songId};
}

/// Canciones marcadas como favoritas por el usuario.
class Favorites extends Table {
  IntColumn get songId =>
      integer().references(Songs, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {songId};
}

/// Historial de reproducción (cada vez que se reproduce una canción
/// se inserta un registro nuevo, permitiendo analizar hábitos de escucha).
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get songId =>
      integer().references(Songs, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
}
