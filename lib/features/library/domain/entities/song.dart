// lib/features/library/domain/entities/song.dart
//
// Entidad de dominio pura. NO depende de Drift ni de ningún paquete
// externo de base de datos. Esto es clave en Clean Architecture:
// la capa de dominio no debe saber cómo se persisten los datos.
//
// La capa "data" (song_model.dart) se encarga de convertir entre
// esta entidad y la fila generada por Drift (clase `Song` de app_database.g.dart,
// que renombraremos como `SongEntity` para evitar colisión de nombres).

class SongEntity {
  final int? id; // null si aún no se ha insertado en la BD
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String? artworkPath;
  final int? fileSizeBytes;
  final String? format;
  final DateTime? dateAdded;
  final int playCount;
  final bool isHidden;

  const SongEntity({
    this.id,
    required this.filePath,
    required this.title,
    this.artist = 'Desconocido',
    this.album = 'Desconocido',
    required this.durationMs,
    this.artworkPath,
    this.fileSizeBytes,
    this.format,
    this.dateAdded,
    this.playCount = 0,
    this.isHidden = false,
  });

  // Helper para mostrar la duración formateada en la UI (ej. "3:45")
  String get formattedDuration {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  SongEntity copyWith({
    int? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? artworkPath,
    int? fileSizeBytes,
    String? format,
    DateTime? dateAdded,
    int? playCount,
    bool? isHidden,
  }) {
    return SongEntity(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      artworkPath: artworkPath ?? this.artworkPath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      format: format ?? this.format,
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}
