// lib/core/database/database_provider.dart
//
// Expone una única instancia de AppDatabase a toda la app vía Riverpod.
// Al ser un Provider simple (no autoDispose), la conexión vive durante
// todo el ciclo de vida de la app, que es lo correcto para una BD local.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();

  // Cierra la conexión limpiamente cuando el provider se destruye
  // (en la práctica esto ocurre al cerrar la app).
  ref.onDispose(() => db.close());

  return db;
});

// Ejemplo de cómo cualquier feature consumirá la lista de canciones
// de forma reactiva. Esto se moverá luego a
// lib/features/library/presentation/providers/library_provider.dart
final allSongsStreamProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllSongs();
});
