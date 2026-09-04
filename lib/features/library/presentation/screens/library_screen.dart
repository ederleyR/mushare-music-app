// lib/features/library/presentation/screens/library_screen.dart
//
// Pantalla principal: muestra la lista de canciones y permite disparar
// el escaneo (solicitando permisos primero si es necesario en móvil).
//
// Este archivo mantiene EXACTAMENTE la misma lógica funcional que ya
// tenías (providers, manejo de escaneo, reproducción); el único cambio
// es visual: layout, colores, tipografía y el mini-reproductor flotante.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/utils/permission_utils.dart';
import '../providers/library_provider.dart';
import '../widgets/song_tile.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/now_playing_screen.dart';
import '../../../player/domain/entities/lyrics.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/playlist.dart';

enum SongSort { alphabetical, duration, mostPlayed, leastPlayed, newest }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  SongSort _sort = SongSort.alphabetical;
  final Set<int> _selectedSongIds = {};

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsStreamProvider);
    final scanState = ref.watch(scanNotifierProvider);
    final playerState = ref.watch(playerProvider);
    final favorites =
        ref.watch(favoritesStreamProvider).valueOrNull ?? const <SongEntity>[];
    final favoriteIds =
        favorites.map((song) => song.id).whereType<int>().toSet();
    final displayName = ref.watch(appSettingsProvider).displayName;
    final playlists = ref.watch(playlistsStreamProvider).valueOrNull ??
        const <PlaylistEntity>[];

    ref.listen<ScanState>(scanNotifierProvider, (previous, next) {
      switch (next) {
        case ScanCompleted(:final songsFound):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Se encontraron $songsFound canciones')),
          );
        case ScanError(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al escanear: $message')),
          );
        default:
          break;
      }
    });

    // El mini-reproductor flotante ocupa espacio real en pantalla, así
    // que dejamos espacio extra al final de la lista para que la última
    // canción no quede tapada detrás de él.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _LibraryHeader(
              displayName: displayName,
              sort: _sort,
              onSortChanged: (sort) => setState(() => _sort = sort),
              isMobile: Platform.isAndroid || Platform.isIOS,
              isScanning: scanState is ScanScanning,
              onScanPressed: scanState is ScanScanning
                  ? null
                  : () => _handleScan(context, ref),
              onPickFiles: scanState is ScanScanning
                  ? null
                  : () => _handleScan(context, ref, pickFiles: true),
            ),
            if (_selectedSongIds.isNotEmpty)
              _SelectionActions(
                count: _selectedSongIds.length,
                onCancel: () => setState(_selectedSongIds.clear),
                onHide: _hideSelected,
                onAddToPlaylist: () => _addSelectedToPlaylist(playlists),
                onDelete: _deleteSelected,
              ),
            Expanded(
              child: songsAsync.when(
                data: (songs) {
                  final sortedSongs = _sortSongs(songs);
                  if (songs.isEmpty) {
                    return _EmptyLibraryView(
                      onScanPressed: () => _handleScan(context, ref),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: 16,
                    ),
                    itemCount: sortedSongs.length,
                    itemBuilder: (context, index) {
                      final song = sortedSongs[index];
                      return SongTile(
                        song: song,
                        isSelected: song.id != null &&
                            _selectedSongIds.contains(song.id),
                        onTap: () => _selectedSongIds.isNotEmpty
                            ? _toggleSelection(song)
                            : _playSong(song, sortedSongs),
                        onLongPress: song.id == null
                            ? null
                            : () => _toggleSelection(song),
                        isPlaying: playerState.isPlaying &&
                            playerState.currentSong?.filePath == song.filePath,
                        isFavorite:
                            song.id != null && favoriteIds.contains(song.id),
                        onFavoriteTap: song.id == null
                            ? null
                            : () => ref
                                .read(libraryRepositoryProvider)
                                .toggleFavorite(song.id!),
                        onDeleteTap: song.id == null
                            ? null
                            : () => _confirmRemoveSong(context, ref, song),
                        onAddToPlaylistTap: song.id == null
                            ? null
                            : () => _showPlaylistPicker(
                                context, ref, song, playlists),
                      );
                    },
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                error: (err, stack) => Center(
                  child: Text('Error: $err',
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<SongEntity> _sortSongs(List<SongEntity> songs) {
    final sorted = List<SongEntity>.of(songs);
    switch (_sort) {
      case SongSort.alphabetical:
        sorted.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SongSort.duration:
        sorted.sort((a, b) => b.durationMs.compareTo(a.durationMs));
      case SongSort.mostPlayed:
        sorted.sort((a, b) => b.playCount.compareTo(a.playCount));
      case SongSort.leastPlayed:
        sorted.sort((a, b) => a.playCount.compareTo(b.playCount));
      case SongSort.newest:
        sorted.sort((a, b) =>
            (b.dateAdded ?? DateTime(0)).compareTo(a.dateAdded ?? DateTime(0)));
    }
    return sorted;
  }

  Future<void> _playSong(SongEntity song, List<SongEntity> queue) async {
    if (song.id != null) {
      await ref.read(libraryRepositoryProvider).incrementPlayCount(song.id!);
    }
    await ref.read(playerProvider.notifier).playSong(song, queue);
  }

  void _toggleSelection(SongEntity song) {
    if (song.id == null) return;
    setState(() {
      if (!_selectedSongIds.add(song.id!)) _selectedSongIds.remove(song.id);
    });
  }

  Future<void> _hideSelected() async {
    await ref
        .read(libraryRepositoryProvider)
        .setSongsHidden(_selectedSongIds, true);
    if (mounted) setState(_selectedSongIds.clear);
  }

  Future<void> _deleteSelected() async {
    final ids = List<int>.of(_selectedSongIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar canciones'),
        content: Text(
            '¿Quitar ${ids.length} canciones de MuShare? Los archivos originales no se borrarán.'),
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
      await repository.removeSong(id);
    }
    if (mounted) setState(_selectedSongIds.clear);
  }

  Future<void> _addSelectedToPlaylist(List<PlaylistEntity> playlists) async {
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea una playlist primero.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: playlists
            .map((playlist) => ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: Text(playlist.name),
                  onTap: () async {
                    final repository = ref.read(libraryRepositoryProvider);
                    for (final id in _selectedSongIds) {
                      await repository.addSongToPlaylist(playlist.id, id);
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (mounted) setState(_selectedSongIds.clear);
                  },
                ))
            .toList(),
      ),
    );
  }

  Future<void> _handleScan(
    BuildContext context,
    WidgetRef ref, {
    bool pickFiles = false,
  }) async {
    final hasPermission = await PermissionUtils.requestAudioPermission();

    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Se necesita permiso para acceder a la música')),
        );
      }
      return;
    }

    ref.read(scanNotifierProvider.notifier).startScan(pickFiles: pickFiles);
  }

  Future<void> _confirmRemoveSong(
      BuildContext context, WidgetRef ref, SongEntity song) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar canción'),
        content: Text(
            '¿Quitar "${song.title}" de MuShare? El archivo original no se borrará del disco.'),
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
    if (shouldRemove == true && song.id != null) {
      await ref.read(libraryRepositoryProvider).removeSong(song.id!);
    }
  }

  Future<void> _showPlaylistPicker(
    BuildContext context,
    WidgetRef ref,
    SongEntity song,
    List<PlaylistEntity> playlists,
  ) async {
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea una playlist primero.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Agregar "${song.title}" a...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...playlists.map(
              (playlist) => ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.queue_music_rounded),
                ),
                title: Text(playlist.name),
                onTap: () async {
                  await ref
                      .read(libraryRepositoryProvider)
                      .addSongToPlaylist(playlist.id, song.id!);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Agregada a ${playlist.name}')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.count,
    required this.onCancel,
    required this.onHide,
    required this.onAddToPlaylist,
    required this.onDelete,
  });
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onHide;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close), onPressed: onCancel),
          Expanded(child: Text('$count seleccionadas')),
          IconButton(
              tooltip: 'Agregar a playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: onAddToPlaylist),
          IconButton(
              tooltip: 'Ocultar',
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: onHide),
          IconButton(
              tooltip: 'Quitar de MuShare',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete),
        ],
      ),
    );
  }
}

/// Encabezado custom en vez de un AppBar genérico: saludo + botón de
/// escaneo con estado visual claro (girando mientras escanea).
class _LibraryHeader extends StatelessWidget {
  final String? displayName;
  final SongSort sort;
  final ValueChanged<SongSort> onSortChanged;
  final bool isMobile;
  final bool isScanning;
  final VoidCallback? onScanPressed;
  final VoidCallback? onPickFiles;

  const _LibraryHeader({
    required this.displayName,
    required this.sort,
    required this.onSortChanged,
    required this.isMobile,
    required this.isScanning,
    required this.onScanPressed,
    required this.onPickFiles,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName == null ? 'Tu música' : 'Hola, $displayName',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('Inicio',
                    style: Theme.of(context).textTheme.headlineLarge),
              ],
            ),
          ),
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceElevated,
              padding: const EdgeInsets.all(12),
            ),
            icon: isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : Icon(isMobile ? Icons.add_rounded : Icons.library_add_rounded,
                    color: AppColors.textPrimary),
            tooltip: isMobile ? 'Agregar archivos' : 'Agregar música',
            onPressed: isMobile ? onPickFiles : onScanPressed,
          ),
          if (isMobile)
            IconButton(
              tooltip: 'Buscar música en el dispositivo',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onScanPressed,
            ),
          const SizedBox(width: 4),
          PopupMenuButton<SongSort>(
            tooltip: 'Ordenar música',
            icon: const Icon(Icons.filter_list_rounded),
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: SongSort.alphabetical, child: Text('A-Z')),
              PopupMenuItem(value: SongSort.duration, child: Text('Duración')),
              PopupMenuItem(
                  value: SongSort.mostPlayed, child: Text('Más escuchadas')),
              PopupMenuItem(
                  value: SongSort.leastPlayed, child: Text('Menos escuchadas')),
              PopupMenuItem(
                  value: SongSort.newest, child: Text('Más recientes')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mini-reproductor flotante: se separa visualmente del resto de la UI
/// con margen, bordes redondeados y sombra, en vez de una barra pegada
/// al borde inferior de la pantalla.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar(
      {required this.state,
      required this.onToggle,
      required this.onPrevious,
      required this.onNext,
      required this.onToggleShuffle,
      required this.onToggleRepeat,
      required this.onShowLyrics,
      required this.onSeek,
      required this.onSetVolume,
      this.onShowQueue});

  final PlayerState state;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback onShowLyrics;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSetVolume;
  final VoidCallback? onShowQueue;

  @override
  Widget build(BuildContext context) {
    final song = state.currentSong;
    if (song == null) return const SizedBox.shrink();
    final max = state.duration.inMilliseconds > 0
        ? state.duration.inMilliseconds.toDouble()
        : 1.0;
    final value =
        state.position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 720 || screenSize.height < 600;

    return GestureDetector(
      onTap: () => showNowPlaying(context),
      onVerticalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dy < -300) {
          showNowPlaying(context);
        }
      },
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCompact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Hero(
                            tag: nowPlayingArtworkHeroTag,
                            child: ArtworkImage(song: song, size: 44, radius: 10),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Anterior',
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: state.canGoPrevious ? onPrevious : null,
                          ),
                          _PlayPauseButton(
                              isPlaying: state.isPlaying, onPressed: onToggle),
                          IconButton(
                            tooltip: 'Siguiente',
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: state.canGoNext ? onNext : null,
                          ),
                        ],
                      ),
                      _ProgressSlider(
                        value: value,
                        max: max,
                        onSeek: onSeek,
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: state.isShuffleEnabled
                                ? 'Desactivar aleatorio'
                                : 'Activar aleatorio',
                            icon: Icon(Icons.shuffle_rounded,
                                color: state.isShuffleEnabled
                                    ? Theme.of(context).colorScheme.primary
                                    : null),
                            onPressed: onToggleShuffle,
                          ),
                          _RepeatButton(
                            mode: state.repeatMode,
                            onPressed: onToggleRepeat,
                          ),
                          IconButton(
                            tooltip: 'Ver letras',
                            icon: Icon(
                              Icons.lyrics_rounded,
                              color: state.lyrics != null
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            onPressed: onShowLyrics,
                          ),
                          if (onShowQueue != null)
                            IconButton(
                              tooltip: 'Ver cola',
                              icon: const Icon(Icons.queue_music_rounded),
                              onPressed: onShowQueue,
                            ),
                          const Icon(Icons.volume_down_rounded, size: 18),
                          Expanded(
                            child: _VolumeSlider(
                              value: state.volume,
                              onChanged: onSetVolume,
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              if (!isCompact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Hero(
                              tag: nowPlayingArtworkHeroTag,
                              child: ArtworkImage(song: song, size: 44, radius: 10),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Anterior',
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed:
                                  state.canGoPrevious ? onPrevious : null,
                            ),
                            _PlayPauseButton(
                              isPlaying: state.isPlaying,
                              onPressed: onToggle,
                            ),
                            IconButton(
                              tooltip: 'Siguiente',
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: state.canGoNext ? onNext : null,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: state.isShuffleEnabled
                                  ? 'Desactivar aleatorio'
                                  : 'Activar aleatorio',
                              icon: Icon(
                                Icons.shuffle_rounded,
                                color: state.isShuffleEnabled
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              onPressed: onToggleShuffle,
                            ),
                            _RepeatButton(
                              mode: state.repeatMode,
                              onPressed: onToggleRepeat,
                            ),
                            IconButton(
                              tooltip: 'Ver letras',
                              icon: Icon(
                                Icons.lyrics_rounded,
                                color: state.lyrics != null
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              onPressed: onShowLyrics,
                            ),
                            if (onShowQueue != null)
                              IconButton(
                                tooltip: 'Ver cola',
                                icon: const Icon(Icons.queue_music_rounded),
                                onPressed: onShowQueue,
                              ),
                            const Icon(Icons.volume_down_rounded, size: 20),
                            SizedBox(
                              width: 100,
                              child: _VolumeSlider(
                                value: state.volume,
                                onChanged: onSetVolume,
                              ),
                            ),
                            const Icon(Icons.volume_up_rounded, size: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isCompact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    children: [
                      _ProgressSlider(
                        value: value,
                        max: max,
                        onSeek: onSeek,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(state.position)),
                          Text(_formatDuration(state.duration)),
                        ],
                      ),
                    ],
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    state.error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.mode, required this.onPressed});

  final PlaybackRepeatMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = mode != PlaybackRepeatMode.off;
    final isRepeatOne = mode == PlaybackRepeatMode.one;
    return IconButton(
      tooltip: switch (mode) {
        PlaybackRepeatMode.off => 'Activar repetir una canción',
        PlaybackRepeatMode.one => 'Activar repetir continuamente',
        PlaybackRepeatMode.all => 'Desactivar repetir',
      },
      icon: Icon(
        isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
        color: isEnabled ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: onPressed,
    );
  }
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({
    required this.value,
    required this.max,
    required this.onSeek,
  });

  final double value;
  final double max;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.18),
      ),
      child: Slider(
        value: value,
        max: max,
        onChanged: (milliseconds) =>
            onSeek(Duration(milliseconds: milliseconds.round())),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.18),
      ),
      child: Slider(
        value: value.clamp(0, 100).toDouble(),
        max: 100,
        onChanged: onChanged,
      ),
    );
  }
}

Future<void> showPlayerQueue(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _PlayerQueueSheet(),
  );
}

Future<void> showLyricsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _LyricsSheet(),
  );
}

class _LyricsSheet extends ConsumerWidget {
  const _LyricsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final song = player.currentSong;
    final lyrics = player.lyrics;
    final lines = lyrics?.isSynced == true
        ? parseSyncedLyrics(lyrics!.synced!)
        : const <LyricLine>[];
    final activeIndex = lines.lastIndexWhere(
      (line) => line.timestamp <= player.position,
    );

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Letras', style: Theme.of(context).textTheme.headlineSmall),
              if (song != null)
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Expanded(
                child: player.lyricsLoading
                    ? const Center(child: CircularProgressIndicator())
                    : lyrics == null || lyrics.isEmpty
                        ? Center(
                            child: Text(
                                player.lyricsError ?? 'Letra no disponible'))
                        : lyrics.isSynced
                            ? ListView.builder(
                                itemCount: lines.length,
                                itemBuilder: (context, index) {
                                  final isActive = index == activeIndex;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: InkWell(
                                      onTap: () => ref
                                          .read(playerProvider.notifier)
                                          .seek(lines[index].timestamp),
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: Text(
                                          lines[index].text,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: isActive
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : null,
                                                fontWeight: isActive
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : SingleChildScrollView(
                                child: Text(lyrics.text,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerQueueSheet extends ConsumerWidget {
  const _PlayerQueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Row(
                children: [
                  Text('Cola de reproducción',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text('${player.queue.length} canciones'),
                ],
              ),
            ),
            Expanded(
              child: player.queue.isEmpty
                  ? const Center(child: Text('No hay canciones en la cola.'))
                  : ListView.builder(
                      itemCount: player.queue.length,
                      itemBuilder: (context, index) {
                        final song = player.queue[index];
                        final isCurrent = index == player.queueIndex;
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song.artworkPath != null
                                ? Image.file(File(song.artworkPath!),
                                    width: 44, height: 44, fit: BoxFit.cover)
                                : Container(
                                    width: 44,
                                    height: 44,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    child: Icon(isCurrent
                                        ? Icons.equalizer_rounded
                                        : Icons.music_note_rounded),
                                  ),
                          ),
                          title: Text(song.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(song.artist),
                          selected: isCurrent,
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .playQueueItem(index);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayPauseButton({required this.isPlaying, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

class _EmptyLibraryView extends StatelessWidget {
  final VoidCallback onScanPressed;

  const _EmptyLibraryView({required this.onScanPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.library_music_rounded,
                size: 40, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text('No hay canciones aún',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Escanea una carpeta para empezar',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onScanPressed,
            icon: const Icon(Icons.library_add_rounded),
            label: const Text('Escanear música'),
          ),
        ],
      ),
    );
  }
}
