// lib/features/library/presentation/providers/library_provider.dart
//
// Providers de Riverpod para la biblioteca musical. Expone:
// - El repositorio (inyectado con la BD y el escáner correcto)
// - Un stream reactivo de canciones para la UI
// - Un "notifier" para disparar el escaneo manualmente (botón de refrescar)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_provider.dart';
import '../../data/datasources/audio_scanner.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/playlist.dart';

/// Repositorio de biblioteca, con sus dependencias ya inyectadas.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final scanner =
      createAudioScanner(); // elige Mobile o Desktop automáticamente
  return LibraryRepository(db, scanner);
});

/// Stream reactivo con todas las canciones. La UI escucha esto y se
/// redibuja sola cada vez que se insertan canciones nuevas.
final songsStreamProvider = StreamProvider<List<SongEntity>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchAllSongs();
});

final favoritesStreamProvider = StreamProvider<List<SongEntity>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchFavorites();
});

final hiddenSongsStreamProvider = StreamProvider<List<SongEntity>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchHiddenSongs();
});

final playlistsStreamProvider = StreamProvider<List<PlaylistEntity>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchPlaylists();
});

final playlistSongsStreamProvider =
    StreamProvider.family<List<SongEntity>, int>((ref, playlistId) {
  return ref.watch(libraryRepositoryProvider).watchPlaylistSongs(playlistId);
});

/// Notifier que controla el estado del proceso de escaneo
/// (para mostrar un spinner de "Escaneando..." en la UI).
class ScanNotifier extends StateNotifier<ScanState> {
  final LibraryRepository _repository;

  ScanNotifier(this._repository) : super(const ScanState.idle());

  Future<void> startScan({bool pickFiles = false}) async {
    state = const ScanState.scanning();
    try {
      final count = await _repository.scanAndSync(pickFiles: pickFiles);
      state = ScanState.completed(count);
    } catch (e) {
      state = ScanState.error(e.toString());
    }
  }
}

final scanNotifierProvider =
    StateNotifierProvider<ScanNotifier, ScanState>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return ScanNotifier(repo);
});

/// Estados posibles del proceso de escaneo, usando pattern matching
/// con sealed classes (Dart 3+).
sealed class ScanState {
  const ScanState();
  const factory ScanState.idle() = ScanIdle;
  const factory ScanState.scanning() = ScanScanning;
  const factory ScanState.completed(int songsFound) = ScanCompleted;
  const factory ScanState.error(String message) = ScanError;
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanScanning extends ScanState {
  const ScanScanning();
}

class ScanCompleted extends ScanState {
  final int songsFound;
  const ScanCompleted(this.songsFound);
}

class ScanError extends ScanState {
  final String message;
  const ScanError(this.message);
}
