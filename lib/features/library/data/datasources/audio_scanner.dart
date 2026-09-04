// lib/features/library/data/datasources/audio_scanner.dart
//
// Escanea el almacenamiento en busca de archivos de audio y extrae
// sus metadatos. Usa una estrategia distinta según la plataforma:
//
// - Móvil (Android/iOS): on_audio_query consulta el MediaStore nativo,
//   es rápido porque el SO ya tiene los archivos indexados.
// - Desktop (Windows/Linux/macOS): no existe MediaStore, así que el
//   usuario elige una carpeta y recorremos el árbol de archivos a mano,
//   leyendo metadatos con audiotags.

import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/song.dart';

// Extensiones de audio soportadas. Se usan para filtrar archivos
// al recorrer carpetas en Desktop.
const _supportedExtensions = [
  '.mp3',
  '.flac',
  '.wav',
  '.m4a',
  '.ogg',
  '.aac',
  '.wma',
  '.opus',
  '.aiff',
  '.alac',
  '.m4r',
];

abstract class AudioScanner {
  /// Escanea y retorna la lista de canciones encontradas.
  Future<List<SongEntity>> scan({bool pickFiles = false});
}

/// Implementación para Android/iOS usando el MediaStore del sistema.
class MobileAudioScanner implements AudioScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  @override
  Future<List<SongEntity>> scan({bool pickFiles = false}) async {
    if (pickFiles) return _pickAudioFiles();
    // on_audio_query ya requiere que los permisos se hayan solicitado
    // antes (esto se maneja en permission_utils.dart, capa superior).
    final List<SongModel> songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    final artworkDir = await _getArtworkCacheDir();
    final List<SongEntity> result = [];

    for (final song in songs) {
      // Filtramos archivos que no sean música real (ej. tonos de llamada,
      // notificaciones cortas que a veces MediaStore incluye).
      if (song.duration == null || song.duration! < 5000) continue;

      String? artworkPath;
      try {
        final artworkBytes = await _audioQuery.queryArtwork(
          song.id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 500,
        );
        if (artworkBytes != null) {
          final file = File(p.join(artworkDir.path, '${song.id}.jpg'));
          await file.writeAsBytes(artworkBytes);
          artworkPath = file.path;
        }
      } catch (_) {
        // Si falla la extracción de portada, seguimos sin ella.
        // No debe detener el escaneo completo por una canción.
      }

      result.add(SongEntity(
        filePath: song.data,
        title: song.title,
        artist: song.artist ?? 'Desconocido',
        album: song.album ?? 'Desconocido',
        durationMs: song.duration ?? 0,
        artworkPath: artworkPath,
        fileSizeBytes: song.size,
        format: p.extension(song.data).replaceAll('.', ''),
      ));
    }

    return result;
  }

  Future<List<SongEntity>> _pickAudioFiles() async {
    final pickedFiles = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedExtensions
          .map((extension) => extension.substring(1))
          .toList(),
      allowMultiple: true,
      withData: true,
      dialogTitle: 'Selecciona tus canciones',
    );
    if (pickedFiles == null) return [];

    final importedDirectory =
        Directory(p.join((await getApplicationDocumentsDirectory()).path, 'imported_music'));
    if (!await importedDirectory.exists()) {
      await importedDirectory.create(recursive: true);
    }

    final result = <SongEntity>[];
    for (final pickedFile in pickedFiles.files) {
      File? file;
      if (pickedFile.path != null) {
        file = File(pickedFile.path!);
      } else if (pickedFile.bytes != null) {
        final safeName = pickedFile.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        file = File(p.join(importedDirectory.path, safeName));
        await file.writeAsBytes(pickedFile.bytes!);
      }
      if (file == null || !await file.exists() || !isSupportedAudioFile(file.path)) {
        continue;
      }

      Tag? tag;
      try {
        tag = await AudioTags.read(file.path);
      } catch (_) {
        // Los metadatos no son obligatorios para importar y reproducir.
      }
      final stat = await file.stat();
      result.add(SongEntity(
        filePath: file.path,
        title: tag?.title?.trim().isNotEmpty == true
            ? tag!.title!
            : p.basenameWithoutExtension(file.path),
        artist: tag?.trackArtist ?? 'Desconocido',
        album: tag?.album ?? 'Desconocido',
        durationMs: (tag?.duration ?? 0) * 1000,
        fileSizeBytes: stat.size,
        format: p.extension(file.path).replaceFirst('.', ''),
      ));
    }
    return result;
  }
}

/// Implementación para Desktop: el usuario elige archivos o una carpeta y
/// recorremos recursivamente buscando archivos de audio.
class DesktopAudioScanner implements AudioScanner {
  @override
  Future<List<SongEntity>> scan({bool pickFiles = false}) async {
    final artworkDir = await _getArtworkCacheDir();
    final files = await _pickAudioFilesOrDirectories();

    if (files.isEmpty) return [];

    final List<SongEntity> result = [];

    for (final file in files) {
      if (!isSupportedAudioFile(file.path)) continue;

      String? artworkPath;
      Tag? tag;
      try {
        tag = await AudioTags.read(file.path);
      } catch (e) {
        // Si fallan los metadatos, seguimos con el nombre del archivo.
      }

      final fileStat = await file.stat();

      if (tag?.pictures.isNotEmpty ?? false) {
        try {
          final picture = tag!.pictures.first;
          final fileName = '${file.path.hashCode}.jpg';
          final artworkFile = File(p.join(artworkDir.path, fileName));
          await artworkFile.writeAsBytes(picture.bytes);
          artworkPath = artworkFile.path;
        } catch (_) {
          artworkPath = null;
        }
      }

      result.add(SongEntity(
        filePath: file.path,
        title: (tag?.title != null && tag!.title!.trim().isNotEmpty)
            ? tag.title!
            : p.basenameWithoutExtension(file.path),
        artist: tag?.trackArtist ?? 'Desconocido',
        album: tag?.album ?? 'Desconocido',
        durationMs: (tag?.duration ?? 0) * 1000,
        artworkPath: artworkPath,
        fileSizeBytes: fileStat.size,
        format: p.extension(file.path).replaceAll('.', ''),
      ));
    }

    return result;
  }

  Future<List<File>> _pickAudioFilesOrDirectories() async {
    final pickedFiles = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      dialogTitle: 'Selecciona tus canciones',
    );

    if (pickedFiles != null && pickedFiles.files.isNotEmpty) {
      return pickedFiles.files
          .where((file) => file.path != null)
          .map((file) => File(file.path!))
          .toList();
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecciona la carpeta de tu música',
    );

    if (selectedDirectory != null) {
      final paths = await compute<String, List<String>>(
        _listFilesInDirectory,
        selectedDirectory,
      );
      return paths.map((path) => File(path)).toList();
    }

    // No es seguro escanear carpetas por defecto en Desktop: puede recorrer
    // directorios muy grandes y congelar la app si se ejecuta en el hilo UI.
    return [];
  }

  List<Directory> _defaultMusicDirectories() {
    final homeDir =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (homeDir == null) return const [];

    return [
      Directory(p.join(homeDir, 'Music')),
      Directory(p.join(homeDir, 'OneDrive', 'Music')),
      Directory(p.join(homeDir, 'Documents', 'Music')),
      Directory(p.join(homeDir, 'Downloads')),
    ];
  }
}

bool isSupportedAudioFile(String path,
    {List<String> supportedExtensions = _supportedExtensions}) {
  final ext = p.extension(path).toLowerCase();
  return supportedExtensions.contains(ext);
}

List<File> findSupportedAudioFilesInDirectory(Directory directory) {
  if (!directory.existsSync()) return const [];

  final files = <File>[];
  for (final entity in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is File && isSupportedAudioFile(entity.path)) {
      files.add(entity);
    }
  }
  return files;
}

List<String> _listFilesInDirectory(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) return [];

  final files = <String>[];
  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is File &&
        isSupportedAudioFile(entity.path)) {
      files.add(entity.path);
    }
  }

  return files;
}

/// Directorio local donde se cachean las portadas extraídas.
/// Se reutiliza entre escaneos.
Future<Directory> _getArtworkCacheDir() async {
  final appDir = await getApplicationDocumentsDirectory();
  final artworkDir = Directory(p.join(appDir.path, 'artwork_cache'));
  if (!await artworkDir.exists()) {
    await artworkDir.create(recursive: true);
  }
  return artworkDir;
}

/// Factory que decide qué implementación usar según la plataforma actual.
AudioScanner createAudioScanner() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MobileAudioScanner();
  }
  return DesktopAudioScanner();
}
