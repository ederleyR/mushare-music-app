import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/song.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/song_tile.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key, required this.onOpenPlaylist});

  final ValueChanged<PlaylistEntity> onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsStreamProvider);
    final favorites = ref.watch(favoritesStreamProvider).valueOrNull ??
        const <SongEntity>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
              tooltip: 'Crear playlist',
              icon: const Icon(Icons.add),
              onPressed: () => _createPlaylist(context, ref))
        ],
      ),
      body: playlists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (items) {
          final visibleItems = [
            if (favorites.isNotEmpty)
              PlaylistEntity(
                id: -1,
                name: 'Favoritas',
                createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                isFavorites: true,
              ),
            ...items,
          ];
          final allSongs = ref.watch(songsStreamProvider).valueOrNull ??
              const <SongEntity>[];
          final artistGroups = <String, List<SongEntity>>{};
          for (final song in allSongs) {
            final artist = song.artist.trim().isEmpty
                ? 'Artista desconocido'
                : song.artist.trim();
            (artistGroups[artist] ??= []).add(song);
          }
          final artistItems = artistGroups.entries
              .where((entry) => entry.value.length >= 2)
              .map((entry) => PlaylistEntity(
                    id: -100000 - entry.key.hashCode.abs(),
                    name: entry.key,
                    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                    virtualSongs: List.unmodifiable(entry.value),
                  ))
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (visibleItems.isEmpty && artistItems.isEmpty) {
            return const Center(child: Text('Aún no has creado playlists.'));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 180).floor().clamp(1, 6);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (visibleItems.isNotEmpty) ...[
                    const _PlaylistSectionTitle(title: 'Mis playlists'),
                    _PlaylistGrid(items: visibleItems, columns: columns,
                        onOpenPlaylist: onOpenPlaylist),
                  ],
                  if (artistItems.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const _PlaylistSectionTitle(title: 'Artistas'),
                    _PlaylistGrid(items: artistItems, columns: columns,
                        onOpenPlaylist: onOpenPlaylist),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva playlist'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Crear')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(libraryRepositoryProvider).createPlaylist(name);
    }
  }
}

class _PlaylistSectionTitle extends StatelessWidget {
  const _PlaylistSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({required this.items, required this.columns, required this.onOpenPlaylist});

  final List<PlaylistEntity> items;
  final int columns;
  final ValueChanged<PlaylistEntity> onOpenPlaylist;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    childAspectRatio: .9,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16),
    itemCount: items.length,
    itemBuilder: (context, index) => _PlaylistCard(
      playlist: items[index], onOpenPlaylist: onOpenPlaylist),
  );
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist, required this.onOpenPlaylist});
  final PlaylistEntity playlist;
  final ValueChanged<PlaylistEntity> onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = playlist.virtualSongs.isNotEmpty
      ? playlist.virtualSongs
      : (playlist.isFavorites
                ? ref.watch(favoritesStreamProvider)
                : ref.watch(playlistSongsStreamProvider(playlist.id)))
            .valueOrNull ??
        const <SongEntity>[];
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onOpenPlaylist(playlist),
      child: Column(children: [
        Expanded(
          child: playlist.isFavorites
              ? const _FavoritesArtwork()
              : _PlaylistArtwork(songs: songs),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text(playlist.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (!playlist.isFavorites && playlist.virtualSongs.isEmpty)
            IconButton(
              tooltip: 'Eliminar playlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref))
        ]),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text('¿Seguro que quieres eliminar "${playlist.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (shouldDelete == true) {
      await ref.read(libraryRepositoryProvider).deletePlaylist(playlist.id);
    }
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.songs});
  final List<SongEntity> songs;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.queue_music_rounded, size: 56),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 4,
        itemBuilder: (context, index) {
          final song = index < songs.length ? songs[index] : null;
          return song != null && song.artworkPath != null
              ? Image.file(File(song.artworkPath!), fit: BoxFit.cover)
              : _ThemedFallbackArtwork();
        },
      ),
    );
  }
}

class _FavoritesArtwork extends StatelessWidget {
  const _FavoritesArtwork();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.favorite_rounded, size: 58, color: Colors.white),
      );
}

class _ThemedFallbackArtwork extends StatelessWidget {
  const _ThemedFallbackArtwork();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient(context),
        ),
        child: const Icon(Icons.music_note_rounded, color: Colors.white),
      );
}

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.onClose,
  });
  final PlaylistEntity playlist;
  final VoidCallback onClose;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final Set<int> _selectedSongIds = {};

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final playlistSongs = playlist.virtualSongs.isNotEmpty
      ? AsyncValue.data(playlist.virtualSongs)
      : playlist.isFavorites
        ? ref.watch(favoritesStreamProvider)
        : ref.watch(playlistSongsStreamProvider(playlist.id));
    final allSongs =
        ref.watch(songsStreamProvider).valueOrNull ?? const <SongEntity>[];
    final player = ref.watch(playerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name), actions: [
        if (!playlist.isFavorites && playlist.virtualSongs.isEmpty)
          IconButton(
            tooltip: 'Agregar canciones',
            icon: const Icon(Icons.library_add_rounded),
            onPressed: () => _pickSong(context, ref, allSongs)),
        IconButton(
          tooltip: 'Cerrar playlist',
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onClose,
        ),
      ]),
      body: Column(children: [
        if (_selectedSongIds.isNotEmpty &&
          !playlist.isFavorites &&
          playlist.virtualSongs.isEmpty)
          _PlaylistSelectionActions(
            count: _selectedSongIds.length,
            onCancel: () => setState(_selectedSongIds.clear),
            onRemove: () => _confirmRemoveSelected(playlist),
          ),
        Expanded(child: playlistSongs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (songs) => songs.isEmpty
            ? const Center(child: Text('Esta playlist está vacía.'))
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return SongTile(
                      song: song,
                      isSelected: song.id != null && _selectedSongIds.contains(song.id),
                            onLongPress: playlist.isFavorites ||
                              playlist.virtualSongs.isNotEmpty ||
                              song.id == null
                          ? null
                          : () => _toggleSelected(song.id!),
                      isPlaying: player.isPlaying &&
                          player.currentSong?.filePath == song.filePath,
                      onTap: () async {
                        if (!playlist.isFavorites &&
                          playlist.virtualSongs.isEmpty &&
                            _selectedSongIds.isNotEmpty &&
                            song.id != null) {
                          _toggleSelected(song.id!);
                          return;
                        }
                        if (song.id != null) {
                          await ref
                              .read(libraryRepositoryProvider)
                              .incrementPlayCount(song.id!);
                        }
                        await ref
                            .read(playerProvider.notifier)
                            .playSong(song, songs);
                      },
                            onDeleteTap: playlist.isFavorites ||
                              playlist.virtualSongs.isNotEmpty ||
                              song.id == null
                          ? null
                          : () => _confirmRemoveOne(playlist, song));
                }),
      )),
      ]),
    );
  }

  void _toggleSelected(int id) {
    setState(() {
      if (!_selectedSongIds.add(id)) _selectedSongIds.remove(id);
    });
  }

  Future<void> _confirmRemoveOne(
      PlaylistEntity playlist, SongEntity song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar de la playlist'),
        content: Text('¿Quitar "${song.title}" de "${playlist.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirmed == true && song.id != null) {
      await ref.read(libraryRepositoryProvider)
          .removeSongFromPlaylist(playlist.id, song.id!);
    }
  }

  Future<void> _confirmRemoveSelected(PlaylistEntity playlist) async {
    final ids = List<int>.of(_selectedSongIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar canciones de la playlist'),
        content: Text('¿Quitar ${ids.length} canciones de "${playlist.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = ref.read(libraryRepositoryProvider);
    for (final id in ids) {
      await repository.removeSongFromPlaylist(playlist.id, id);
    }
    if (mounted) setState(_selectedSongIds.clear);
  }

  Future<void> _pickSong(
      BuildContext context, WidgetRef ref, List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Agregar canción'),
        children: songs
            .map((song) => SimpleDialogOption(
                  onPressed: () async {
                    if (song.id != null) {
                      await ref
                          .read(libraryRepositoryProvider)
                          .addSongToPlaylist(widget.playlist.id, song.id!);
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: song.artworkPath != null
                            ? Image.file(File(song.artworkPath!),
                                width: 42, height: 42, fit: BoxFit.cover)
                            : Container(
                                width: 42,
                                height: 42,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: const Icon(Icons.music_note_rounded),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _PlaylistSelectionActions extends StatelessWidget {
  const _PlaylistSelectionActions({
    required this.count,
    required this.onCancel,
    required this.onRemove,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            IconButton(
              tooltip: 'Cancelar selección',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(child: Text('$count seleccionadas')),
            IconButton(
              tooltip: 'Quitar de la playlist',
              onPressed: onRemove,
              icon: const Icon(Icons.playlist_remove_rounded),
            ),
          ]),
        ),
      );
}
