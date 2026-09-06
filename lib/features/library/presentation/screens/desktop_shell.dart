import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../sharing/presentation/screens/share_screen.dart';
import '../../domain/entities/playlist.dart';
import 'library_screen.dart';
import 'playlists_screen.dart';
import 'settings_screen.dart';

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  int _selectedIndex = 0;
  bool _requestedName = false;
  PlaylistEntity? _openedPlaylist;

  Future<void> _askForName() async {
    if (_requestedName) return;
    _requestedName = true;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('¿Cómo quieres que te llamemos?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      Future<void>.delayed(
          const Duration(milliseconds: 300), controller.dispose);
      _requestedName = false;
      if (mounted) _askForName();
      return;
    }
    await ref.read(appSettingsProvider.notifier).setDisplayName(name);
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LibraryScreen(),
      _openedPlaylist == null
          ? PlaylistsScreen(
              onOpenPlaylist: (playlist) =>
                  setState(() => _openedPlaylist = playlist),
            )
          : PlaylistDetailScreen(
              playlist: _openedPlaylist!,
              onClose: () => setState(() => _openedPlaylist = null),
            ),
      const ShareScreen(),
      const SettingsScreen(),
    ];
    final currentPage = pages[_selectedIndex];
    final settings = ref.watch(appSettingsProvider);
    final playerState = ref.watch(playerProvider);
    if (settings.isLoaded && settings.displayName == null && !_requestedName) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askForName());
    }
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final playerBar = playerState.currentSong == null
        ? null
        : NowPlayingBar(
            state: playerState,
            onToggle: () => ref.read(playerProvider.notifier).toggle(),
            onPrevious: () => ref.read(playerProvider.notifier).previous(),
            onNext: () => ref.read(playerProvider.notifier).next(),
            onToggleShuffle: () =>
                ref.read(playerProvider.notifier).toggleShuffle(),
            onToggleRepeat: () =>
                ref.read(playerProvider.notifier).toggleRepeat(),
            onShowLyrics: () => showLyricsSheet(context),
            onSeek: (position) =>
                ref.read(playerProvider.notifier).seek(position),
            onSetVolume: (volume) =>
                ref.read(playerProvider.notifier).setVolume(volume),
            onShowQueue: () => showPlayerQueue(context),
          );

    return Scaffold(
      body: isMobile
          ? SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _MobileTopNavigation(
                    selectedIndex: _selectedIndex,
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
                  ),
                  Expanded(
                    child: currentPage,
                  ),
                  if (playerBar != null) playerBar,
                ],
              ),
            )
          : Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme:
                      const IconThemeData(color: Colors.white, size: 28),
                  unselectedIconTheme: const IconThemeData(
                      color: AppColors.textSecondary, size: 24),
                  selectedLabelTextStyle: TextStyle(color: colorScheme.primary),
                  unselectedLabelTextStyle:
                      const TextStyle(color: AppColors.textSecondary),
                  indicatorColor: colorScheme.primary,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 24),
                    child: Icon(Icons.graphic_eq_rounded, size: 32),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Inicio'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.queue_music_outlined),
                      selectedIcon: Icon(Icons.queue_music),
                      label: Text('Playlists'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.share_outlined),
                      selectedIcon: Icon(Icons.share),
                      label: Text('Compartir'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Configuración'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: currentPage),
                      if (playerBar != null) playerBar,
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MobileTopNavigation extends StatelessWidget {
  const _MobileTopNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const destinations = [
      (label: 'Inicio', icon: Icons.home_rounded),
      (label: 'Playlists', icon: Icons.queue_music_rounded),
      (label: 'Compartir', icon: Icons.share_rounded),
      (label: 'Ajustes', icon: Icons.settings_rounded),
    ];
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded,
                  color: colorScheme.primary, size: 30),
              const SizedBox(width: 8),
              Text('MuShare', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(destinations.length, (index) {
                final destination = destinations[index];
                final selected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    avatar: Icon(
                      destination.icon,
                      size: 18,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                    label: Text(destination.label),
                    selectedColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                    onSelected: (_) => onSelected(index),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class SharePlaceholderView extends StatelessWidget {
  const SharePlaceholderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.share_rounded, size: 72),
        SizedBox(height: 16),
        Text('Compartir música'),
        SizedBox(height: 8),
        Text('Próximamente podrás compartir canciones en tu red local.'),
      ]),
    );
  }
}
