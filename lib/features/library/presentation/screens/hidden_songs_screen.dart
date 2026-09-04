import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/song.dart';
import '../providers/library_provider.dart';

class HiddenSongsScreen extends ConsumerWidget {
  const HiddenSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hiddenSongs = ref.watch(hiddenSongsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Músicas ocultas')),
      body: hiddenSongs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (songs) => songs.isEmpty
            ? const Center(child: Text('No tienes canciones ocultas.'))
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) => _HiddenSongTile(song: songs[index]),
              ),
      ),
    );
  }
}

class _HiddenSongTile extends ConsumerWidget {
  const _HiddenSongTile({required this.song});
  final SongEntity song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: song.artworkPath != null
            ? Image.file(File(song.artworkPath!),
                width: 48, height: 48, fit: BoxFit.cover)
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient(context),
                ),
                child: const Icon(Icons.music_note_rounded, color: Colors.white),
              ),
      ),
      title: Text(song.title),
      subtitle: Text(song.artist),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: 'Mostrar en biblioteca',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: song.id == null
                ? null
                : () => ref
                    .read(libraryRepositoryProvider)
                    .setSongsHidden([song.id!], false),
          ),
          IconButton(
            tooltip: 'Borrar de MuShare',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: song.id == null ? null : () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar de MuShare'),
        content: Text('¿Quitar "${song.title}" de la aplicación? El archivo no se borrará del teléfono.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmed == true && song.id != null) {
      await ref.read(libraryRepositoryProvider).removeSong(song.id!);
    }
  }
}
