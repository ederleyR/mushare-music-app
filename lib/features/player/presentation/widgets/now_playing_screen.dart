import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../library/domain/entities/song.dart';
import '../providers/player_provider.dart';

const nowPlayingArtworkHeroTag = 'now-playing-artwork';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  Color _dominant = AppColors.primaryMuted;
  Color _vibrant = AppColors.primary;
  Color _darkVibrant = AppColors.background;
  String? _palettePath;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final song = state.currentSong;
    if (song == null) return const SizedBox.shrink();
    if (_palettePath != song.artworkPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPalette(song));
    }

    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final artworkSize = isLandscape
      ? (size.height - 112).clamp(140.0, 250.0).toDouble()
      : (size.width - 48).clamp(220.0, 430.0).toDouble();
    final contentPadding = isLandscape
      ? const EdgeInsets.fromLTRB(24, 4, 24, 16)
      : const EdgeInsets.fromLTRB(24, 18, 24, 28);
    final max = state.duration.inMilliseconds > 0
        ? state.duration.inMilliseconds.toDouble()
        : 1.0;
    final value = state.position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    final notifier = ref.read(playerProvider.notifier);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_darkVibrant, Color.lerp(_darkVibrant, _dominant, .55)!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Minimizar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    const Expanded(
                      child: Text('REPRODUCIENDO AHORA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              letterSpacing: 1.5)),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: contentPadding,
                  child: Column(
                    children: [
                      Hero(
                        tag: nowPlayingArtworkHeroTag,
                        child: ArtworkImage(song: song, size: artworkSize, radius: 24),
                      ),
                      SizedBox(height: isLandscape ? 12 : 28),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ),
                      SizedBox(height: isLandscape ? 8 : 22),
                      Slider(
                        value: value,
                        max: max,
                        activeColor: _vibrant,
                        onChanged: (milliseconds) => notifier.seek(
                            Duration(milliseconds: milliseconds.round())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(state.position)),
                          Text(_formatDuration(state.duration)),
                        ],
                      ),
                      SizedBox(height: isLandscape ? 4 : 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            tooltip: state.isShuffleEnabled ? 'Desactivar aleatorio' : 'Activar aleatorio',
                            onPressed: notifier.toggleShuffle,
                            icon: Icon(Icons.shuffle_rounded,
                                color: state.isShuffleEnabled ? _vibrant : null),
                          ),
                          IconButton(
                            tooltip: 'Anterior',
                            onPressed: state.canGoPrevious ? notifier.previous : null,
                            icon: const Icon(Icons.skip_previous_rounded, size: 34),
                          ),
                          _LargePlayButton(isPlaying: state.isPlaying, onPressed: notifier.toggle),
                          IconButton(
                            tooltip: 'Siguiente',
                            onPressed: state.canGoNext ? notifier.next : null,
                            icon: const Icon(Icons.skip_next_rounded, size: 34),
                          ),
                          IconButton(
                            tooltip: 'Repetir',
                            onPressed: notifier.toggleRepeat,
                            icon: Icon(
                              state.repeatMode == PlaybackRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: state.repeatMode == PlaybackRepeatMode.off ? null : _vibrant,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isLandscape ? 12 : 30),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.queue_music_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text('Cola de reproducción',
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                      if (state.queue.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: Text('La cola está vacía'),
                        )
                      else
                        ...state.queue.asMap().entries.map((entry) {
                          final index = entry.key;
                          final queueSong = entry.value;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ArtworkImage(
                                song: queueSong, size: 48, radius: 8),
                            title: Text(queueSong.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(queueSong.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            selected: index == state.queueIndex,
                            onTap: () => notifier.playQueueItem(index),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _loadPalette(SongEntity song) {
    final path = song.artworkPath;
    if (path == null || path == _palettePath || !File(path).existsSync()) return;
    _palettePath = path;
    Future<void>(() async {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(FileImage(File(path)), width: 96, height: 96),
        maximumColorCount: 16,
      );
      if (!mounted || _palettePath != path) return;
      setState(() {
        _dominant = palette.dominantColor?.color ?? AppColors.primaryMuted;
        _vibrant = palette.vibrantColor?.color ?? AppColors.primary;
        _darkVibrant = palette.darkVibrantColor?.color ?? AppColors.background;
      });
    });
  }
}

class ArtworkImage extends StatelessWidget {
  const ArtworkImage({required this.song, required this.size, this.radius = 12, super.key});

  final SongEntity song;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = song.artworkPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path != null && File(path).existsSync()
            ? Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth:
                (size * MediaQuery.devicePixelRatioOf(context)).round(),
              cacheHeight:
                (size * MediaQuery.devicePixelRatioOf(context)).round(),
              filterQuality: FilterQuality.low,
            )
          : Container(
              width: size,
              height: size,
              decoration: BoxDecoration(gradient: AppTheme.primaryGradient(context)),
              child: Icon(Icons.music_note_rounded, size: size * .22, color: Colors.white),
            ),
    );
  }
}

class _LargePlayButton extends StatelessWidget {
  const _LargePlayButton({required this.isPlaying, required this.onPressed});
  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
        tooltip: isPlaying ? 'Pausar' : 'Reproducir',
        onPressed: onPressed,
        iconSize: 38,
        padding: const EdgeInsets.all(14),
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
      );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

Future<void> showNowPlaying(BuildContext context) => Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const NowPlayingScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );

Future<void> showPlayerQueue(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _NowPlayingQueueSheet(),
    );

class _NowPlayingQueueSheet extends ConsumerWidget {
  const _NowPlayingQueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: state.queue.isEmpty
            ? const Center(child: Text('No hay canciones en la cola.'))
            : ListView.builder(
                itemCount: state.queue.length,
                itemBuilder: (context, index) {
                  final song = state.queue[index];
                  return ListTile(
                    leading: ArtworkImage(song: song, size: 44, radius: 8),
                    title: Text(song.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist),
                    selected: index == state.queueIndex,
                    onTap: () {
                      ref.read(playerProvider.notifier).playQueueItem(index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
      ),
    );
  }
}

class NowPlayingSidebar extends StatelessWidget {
  const NowPlayingSidebar({
    required this.state,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    super.key,
  });

  final PlayerState state;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  @override
  Widget build(BuildContext context) {
    final song = state.currentSong;
    if (song == null) return const SizedBox.shrink();
    final notifier = ProviderScope.containerOf(context).read(playerProvider.notifier);
    final durationMs = state.duration.inMilliseconds;
    final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final value = state.position.inMilliseconds.clamp(0, max.toInt()).toDouble();

    return ColoredBox(
      color: AppColors.surface,
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('REPRODUCIENDO AHORA', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 16),
              Center(child: Hero(tag: nowPlayingArtworkHeroTag,
                  child: ArtworkImage(song: song, size: 220, radius: 16))),
              const SizedBox(height: 16),
              Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Slider(value: value, max: max,
                  onChanged: (value) => notifier.seek(
                      Duration(milliseconds: value.round()))),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_formatDuration(state.position)),
                Text(_formatDuration(state.duration)),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: state.canGoPrevious ? onPrevious : null,
                    icon: const Icon(Icons.skip_previous_rounded, size: 30)),
                _LargePlayButton(isPlaying: state.isPlaying, onPressed: onToggle),
                IconButton(onPressed: state.canGoNext ? onNext : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 30)),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(onPressed: onToggleShuffle, icon: Icon(Icons.shuffle_rounded,
                    color: state.isShuffleEnabled
                        ? Theme.of(context).colorScheme.primary : null)),
                IconButton(onPressed: onToggleRepeat, icon: Icon(
                    state.repeatMode == PlaybackRepeatMode.one
                        ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: state.repeatMode == PlaybackRepeatMode.off
                        ? null : Theme.of(context).colorScheme.primary)),
                IconButton(onPressed: () => showPlayerQueue(context),
                    icon: const Icon(Icons.queue_music_rounded)),
              ]),
              const Divider(height: 24),
              Row(children: [
                const Icon(Icons.queue_music_rounded, size: 18),
                const SizedBox(width: 8),
                Text('Siguiente', style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 8),
              Expanded(child: state.queue.isEmpty
                  ? const Center(child: Text('La cola está vacía'))
                  : ListView.builder(
                      itemCount: state.queue.length,
                      itemBuilder: (context, index) {
                        final queueSong = state.queue[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: ArtworkImage(song: queueSong, size: 42, radius: 6),
                          title: Text(queueSong.title, maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(queueSong.artist, maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          selected: index == state.queueIndex,
                          onTap: () => notifier.playQueueItem(index),
                        );
                      },
                    )),
            ],
          ),
        ),
      ),
    );
  }
}