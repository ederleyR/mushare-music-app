import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:palette_generator/palette_generator.dart';

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
    final favorites =
        ref.watch(favoritesStreamProvider).valueOrNull ?? const <SongEntity>[];
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
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final albumGroups = <String, List<SongEntity>>{};
          for (final song in allSongs) {
            final album = song.album.trim();
            final artist = song.artist.trim();
            if (album.isEmpty || album.toLowerCase() == 'desconocido') continue;
            final groupKey = '${artist.toLowerCase()}::$album';
            (albumGroups[groupKey] ??= []).add(song);
          }
          final albumItems = albumGroups.entries
              .where((entry) => entry.value.length >= 2)
              .map((entry) {
            final songs = entry.value;
            final firstSong = songs.first;
            return PlaylistEntity(
              id: -200000 - entry.key.hashCode.abs(),
              name: firstSong.album.trim(),
              coverPath: songs
                  .map((song) => song.artworkPath)
                  .firstWhere((path) => path != null, orElse: () => null),
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
              virtualSongs: List.unmodifiable(songs),
            );
          }).toList()
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (visibleItems.isEmpty &&
              artistItems.isEmpty &&
              albumItems.isEmpty) {
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
                    _PlaylistGrid(
                        items: visibleItems,
                        columns: columns,
                        onOpenPlaylist: onOpenPlaylist),
                  ],
                  if (artistItems.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const _PlaylistSectionTitle(title: 'Artistas'),
                    _PlaylistGrid(
                        items: artistItems,
                        columns: columns,
                        onOpenPlaylist: onOpenPlaylist),
                  ],
                  if (albumItems.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const _PlaylistSectionTitle(title: 'Álbumes'),
                    _PlaylistGrid(
                        items: albumItems,
                        columns: columns,
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
    final result = await _showPlaylistEditor(context, title: 'Nueva playlist');
    if (result != null && result.name.isNotEmpty) {
      await ref
          .read(libraryRepositoryProvider)
          .createPlaylist(result.name, coverPath: result.coverPath);
    }
  }
}

Future<({String name, String? coverPath})?> _showPlaylistEditor(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialCoverPath,
}) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<({String name, String? coverPath})>(
    context: context,
    builder: (context) {
      var coverPath = initialCoverPath;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Icon(Icons.queue_music_rounded,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la playlist',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final selected = await _pickAndStorePlaylistCover();
                  if (selected != null) setState(() => coverPath = selected);
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                    coverPath == null ? 'Elegir portada' : 'Cambiar portada'),
              ),
              if (coverPath != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(coverPath!),
                      width: 140, height: 140, fit: BoxFit.cover),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                name: controller.text.trim(),
                coverPath: coverPath,
              )),
              child: Text(title == 'Nueva playlist' ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}

Future<String?> _pickAndStorePlaylistCover() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    dialogTitle: 'Selecciona una portada',
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.single;
  final directory = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path, 'playlist_covers'));
  await directory.create(recursive: true);
  final extension =
      p.extension(picked.name).isEmpty ? '.jpg' : p.extension(picked.name);
  final target = File(p.join(
      directory.path, '${DateTime.now().microsecondsSinceEpoch}$extension'));
  if (picked.path != null) {
    await File(picked.path!).copy(target.path);
  } else if (picked.bytes != null) {
    await target.writeAsBytes(picked.bytes!);
  } else {
    return null;
  }
  return target.path;
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
  const _PlaylistGrid(
      {required this.items,
      required this.columns,
      required this.onOpenPlaylist});

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
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => onOpenPlaylist(playlist),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 4),
          child: Column(children: [
            Expanded(
              child: playlist.isFavorites
                  ? const _FavoritesArtwork()
                  : _PlaylistArtwork(playlist: playlist, songs: songs),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
              if (!playlist.isFavorites && playlist.virtualSongs.isEmpty)
                IconButton(
                    tooltip: 'Editar playlist',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _editPlaylist(context, ref)),
              if (!playlist.isFavorites && playlist.virtualSongs.isEmpty)
                IconButton(
                    tooltip: 'Eliminar playlist',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmDelete(context, ref))
            ]),
          ]),
        ),
      ),
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

  Future<void> _editPlaylist(BuildContext context, WidgetRef ref) async {
    final result = await _showPlaylistEditor(
      context,
      title: 'Editar playlist',
      initialName: playlist.name,
      initialCoverPath: playlist.coverPath,
    );
    if (result == null || result.name.isEmpty) return;
    await ref.read(libraryRepositoryProvider).updatePlaylist(
          playlist.id,
          result.name,
          result.coverPath,
        );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist, required this.songs});
  final PlaylistEntity playlist;
  final List<SongEntity> songs;

  @override
  Widget build(BuildContext context) {
    if (playlist.coverPath != null && File(playlist.coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(File(playlist.coverPath!),
            width: double.infinity, fit: BoxFit.cover),
      );
    }
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
              : const _ThemedFallbackArtwork();
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
        child:
            const Icon(Icons.favorite_rounded, size: 58, color: Colors.white),
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

/// Header "hero" de la pantalla de detalle de playlist.
///
/// Este widget ahora vive DENTRO del área con scroll (ver
/// [PlaylistDetailScreen], donde se envuelve en un `SliverToBoxAdapter`
/// dentro de un `CustomScrollView`), por lo que se desplaza junto con la
/// lista de canciones en vez de quedarse fijo arriba.
///
/// También reduce su tamaño (artwork, tipografías y paddings) cuando el
/// ancho disponible es angosto (pantallas de celular).
class _PlaylistHeroHeader extends StatelessWidget {
  const _PlaylistHeroHeader({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    required this.onShuffle,
  });

  final PlaylistEntity playlist;
  final List<SongEntity> songs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final artworkPath = playlist.coverPath ??
        songs
            .map((song) => song.artworkPath)
            .firstWhere((path) => path != null, orElse: () => null);
    final isVirtual = playlist.virtualSongs.isNotEmpty;
    final typeLabel = playlist.isFavorites
        ? 'Playlist de canciones favoritas'
        : isVirtual
            ? 'Colección automática'
            : 'Playlist';
    return _PlaylistHeroPalette(
      artworkPath: artworkPath,
      child: SizedBox(
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final artworkSize = compact ? 110.0 : 214.0;
            final artwork = _DetailArtwork(
              path: artworkPath,
              isFavorites: playlist.isFavorites,
              size: artworkSize,
            );
            final details = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(typeLabel,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: (compact
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.labelLarge)
                        ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(playlist.name,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (compact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.displaySmall)
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${songs.length} canciones',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Reproducir'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onShuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text('Aleatorio'),
                    ),
                  ],
                ),
              ],
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24, 8, compact ? 16 : 24, compact ? 12 : 18),
              child: compact
                  ? Column(children: [
                      artwork,
                      const SizedBox(height: 12),
                      details,
                    ])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        artwork,
                        const SizedBox(width: 24),
                        Expanded(child: details),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaylistHeroPalette extends StatefulWidget {
  const _PlaylistHeroPalette({required this.artworkPath, required this.child});

  final String? artworkPath;
  final Widget child;

  @override
  State<_PlaylistHeroPalette> createState() => _PlaylistHeroPaletteState();
}

class _PlaylistHeroPaletteState extends State<_PlaylistHeroPalette> {
  Color? _dominant;

  @override
  void initState() {
    super.initState();
    _loadPalette();
  }

  @override
  void didUpdateWidget(covariant _PlaylistHeroPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkPath != widget.artworkPath) _loadPalette();
  }

  void _loadPalette() {
    final path = widget.artworkPath;
    if (path == null || !File(path).existsSync()) {
      if (mounted) setState(() => _dominant = null);
      return;
    }
    Future<void>(() async {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(FileImage(File(path)), width: 64, height: 64),
        maximumColorCount: 12,
      );
      if (mounted && widget.artworkPath == path) {
        setState(() => _dominant = palette.dominantColor?.color);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = _dominant ?? Theme.of(context).colorScheme.primaryContainer;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.black, .25)!,
            Color.lerp(base, Theme.of(context).scaffoldBackgroundColor, .82)!,
          ],
        ),
      ),
      child: widget.child,
    );
  }
}

class _DetailArtwork extends StatelessWidget {
  const _DetailArtwork({
    required this.path,
    required this.isFavorites,
    required this.size,
  });

  final String? path;
  final bool isFavorites;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasArtwork = path != null && File(path!).existsSync();
    return Material(
      elevation: 10,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
        child: hasArtwork
            ? Image.file(File(path!), fit: BoxFit.cover)
            : Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient(context),
                ),
                child: Icon(
                  isFavorites
                      ? Icons.favorite_rounded
                      : Icons.queue_music_rounded,
                  size: size * .3,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
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
      appBar: AppBar(title: const Text(''), actions: [
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
      body: playlistSongs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (songs) => CustomScrollView(
          // Todo -incluyendo el header hero- vive dentro de este
          // CustomScrollView, así que el header se desplaza junto con la
          // lista de canciones en vez de quedar fijo arriba.
          slivers: [
            SliverToBoxAdapter(
              child: _PlaylistHeroHeader(
                playlist: playlist,
                songs: songs,
                onPlay: songs.isEmpty ? null : () => _playAll(songs),
                onShuffle: songs.isEmpty ? null : () => _playShuffled(songs),
              ),
            ),
            if (songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Esta playlist está vacía.')),
              )
            else ...[
              if (_selectedSongIds.isNotEmpty &&
                  !playlist.isFavorites &&
                  playlist.virtualSongs.isEmpty)
                SliverToBoxAdapter(
                  child: _PlaylistSelectionActions(
                    count: _selectedSongIds.length,
                    onCancel: () => setState(_selectedSongIds.clear),
                    onRemove: () => _confirmRemoveSelected(playlist),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.only(top: 6, bottom: 20),
                sliver: SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongTile(
                        song: song,
                        isSelected: song.id != null &&
                            _selectedSongIds.contains(song.id),
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
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    await ref.read(playerProvider.notifier).playSong(songs.first, songs);
  }

  Future<void> _playShuffled(List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<SongEntity>.of(songs)..shuffle();
    await ref.read(playerProvider.notifier).playSong(shuffled.first, shuffled);
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar')),
        ],
      ),
    );
    if (confirmed == true && song.id != null) {
      await ref
          .read(libraryRepositoryProvider)
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar')),
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