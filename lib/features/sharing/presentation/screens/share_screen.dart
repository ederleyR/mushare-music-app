import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../player/presentation/services/audio_output_service.dart';
import '../providers/local_share_provider.dart';

class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  String? _startedFor;

  void _ensureStarted(String? name) {
    final effectiveName = (name == null || name.trim().isEmpty) ? 'Usuario' : name;
    if (_startedFor == effectiveName) return;
    _startedFor = effectiveName;
    ref.read(localShareProvider.notifier).start(userName: effectiveName);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(appSettingsProvider.select((settings) => settings.displayName));
    final share = ref.watch(localShareProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureStarted(name));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Compartir', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Envía música a dispositivos conectados a esta misma red Wi-Fi. Cada envío debe ser aceptado por quien lo recibe.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bluetooth_connected_rounded, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Bluetooth', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _openBluetoothSettings,
                        icon: const Icon(Icons.settings_bluetooth_rounded),
                        label: const Text('Conectar Bluetooth'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _shareSongViaBluetooth,
                        icon: const Icon(Icons.music_note_rounded),
                        label: const Text('Enviar canción'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sharePlaylistViaBluetooth,
                        icon: const Icon(Icons.queue_music_rounded),
                        label: const Text('Enviar playlist'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (!share.isRunning)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
          if (share.error != null) _ErrorCard(message: share.error!),
          for (final incoming in share.incomingTransfers) ...[
            const SizedBox(height: 12),
            _IncomingTransferCard(transfer: incoming),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.devices_other_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Dispositivos en la red', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 10),
          if (share.isRunning && share.devices.isEmpty)
            const _EmptyDevices(),
          for (final device in share.devices) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(Platform.isWindows ? Icons.computer_rounded : Icons.phone_android_rounded),
                ),
                // El orden es intencional: nombre de MuShare arriba y equipo abajo.
                title: Text(device.userName),
                subtitle: Text(device.deviceName),
                trailing: const Icon(Icons.send_rounded),
                onTap: () => _showSendOptions(device),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showSendOptions(LocalDevice device) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.music_note_rounded),
            title: const Text('Enviar canción'),
            subtitle: Text('A ${device.userName}'),
            onTap: () {
              Navigator.pop(context);
              _pickSong(device);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Enviar playlist'),
            subtitle: Text('A ${device.userName}'),
            onTap: () {
              Navigator.pop(context);
              _pickPlaylist(device);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth_connected_rounded),
            title: const Text('Enviar por Bluetooth'),
            subtitle: const Text('Abre el selector del sistema'),
            onTap: () {
              Navigator.pop(context);
              _shareSongViaBluetooth();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _openBluetoothSettings() async {
    final ok = await AudioOutputService.openBluetoothSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la configuración de Bluetooth.')),
      );
    }
  }

  Future<void> _shareSongViaBluetooth() async {
    final songs = ref.read(songsStreamProvider).valueOrNull ?? const <SongEntity>[];
    if (songs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay canciones para compartir por Bluetooth.')),
        );
      }
      return;
    }

    final selected = await showDialog<SongEntity>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige una canción para Bluetooth'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return ListTile(
                leading: _ArtworkThumbnail(song: song),
                title: Text(song.title),
                subtitle: Text(song.artist),
                onTap: () => Navigator.pop(context, song),
              );
            },
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;
    final file = File(selected.filePath);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La canción ya no está disponible.')),
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        subject: 'MuShare: ${selected.title}',
        files: [XFile(file.path, name: file.uri.pathSegments.lastOrNull ?? selected.title)],
      ),
    );
  }

  Future<void> _sharePlaylistViaBluetooth() async {
    final playlists = ref.read(playlistsStreamProvider).valueOrNull ?? const [];
    if (playlists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aún no hay playlists para compartir.')),
        );
      }
      return;
    }

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige una playlist para Bluetooth'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) => _PlaylistPickerTile(
              playlist: playlists[index],
              onTap: () => Navigator.pop(context, playlists[index]),
            ),
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;
    final songs = await ref.read(playlistSongsStreamProvider(selected.id).future);
    if (!mounted) return;

    final files = songs.where((song) => File(song.filePath).existsSync()).toList();
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La playlist no tiene archivos disponibles.')),
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        subject: 'MuShare playlist: ${selected.name}',
        files: files
            .map((song) => XFile(song.filePath,
                name: File(song.filePath).uri.pathSegments.lastOrNull ?? song.title))
            .toList(),
      ),
    );
  }

  Future<void> _pickSong(LocalDevice device) async {
    final songs = ref.read(songsStreamProvider).valueOrNull ?? const <SongEntity>[];
    final selected = await showDialog<SongEntity>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige una canción'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: songs.isEmpty
              ? const Center(child: Text('No hay canciones para enviar.'))
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: _ArtworkThumbnail(song: song),
                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, song),
                    );
                  },
                ),
        ),
      ),
    );
    if (selected != null && mounted) {
      await ref.read(localShareProvider.notifier).shareSong(device, selected);
      if (mounted) _sentMessage(device.userName);
    }
  }

  Future<void> _pickPlaylist(LocalDevice device) async {
    final playlists = ref.read(playlistsStreamProvider).valueOrNull ?? const [];
    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige una playlist'),
        content: SizedBox(
          width: 460,
          child: playlists.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aún no has creado playlists.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) => _PlaylistPickerTile(
                    playlist: playlists[index],
                    onTap: () => Navigator.pop(context, playlists[index]),
                  ),
                ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final songs = await ref.read(playlistSongsStreamProvider(selected.id).future);
    if (!mounted) return;
    await ref.read(localShareProvider.notifier).sharePlaylist(device, selected, songs);
    if (mounted && songs.isNotEmpty) _sentMessage(device.userName);
  }

  void _sentMessage(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Solicitud de envío enviada a $name.')),
    );
  }
}

class _IncomingTransferCard extends ConsumerWidget {
  const _IncomingTransferCard({required this.transfer});
  final IncomingTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = transfer.isPlaylist ? Icons.queue_music_rounded : Icons.music_note_rounded;
    final description = transfer.isPlaylist
        ? 'Playlist con ${transfer.itemCount} canciones'
        : 'Canción';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _NetworkArtworkThumbnail(uri: transfer.coverUri, fallback: icon),
            const SizedBox(width: 8),
            Expanded(child: Text('${transfer.senderName} quiere enviarte:', style: Theme.of(context).textTheme.titleSmall)),
          ]),
          const SizedBox(height: 10),
          Text(transfer.title, style: Theme.of(context).textTheme.titleMedium),
          Text('$description · ${transfer.senderDevice}'),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => ref.read(localShareProvider.notifier).rejectTransfer(transfer.id),
              child: const Text('Rechazar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _acceptWithProgress(context, ref, transfer),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Aceptar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> _acceptWithProgress(
  BuildContext context,
  WidgetRef ref,
  IncomingTransfer transfer,
) async {
  final progress = ValueNotifier(const TransferProgress(
    receivedBytes: 0,
    totalBytes: 0,
    completedFiles: 0,
    totalFiles: 0,
  ));
  var finished = false;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<TransferProgress>(
        valueListenable: progress,
        builder: (context, value, _) {
          final percent = (value.fraction * 100).clamp(0, 100).round();
          return AlertDialog(
            title: const Text('Descargando contenido'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: value.totalBytes > 0 ? value.fraction : null),
              const SizedBox(height: 16),
              Text(value.totalBytes > 0 ? '$percent% completado' : 'Preparando descarga...'),
              const SizedBox(height: 6),
              Text('Canción ${value.completedFiles + 1} de ${value.totalFiles == 0 ? transfer.itemCount : value.totalFiles}'),
            ]),
          );
        },
      ),
    ),
  );
  await ref.read(localShareProvider.notifier).acceptTransfer(
    transfer,
    onProgress: (value) => progress.value = value,
  );
  finished = true;
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialog;
  progress.dispose();
  if (finished && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contenido recibido y guardado en tu biblioteca.')),
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  const _ArtworkThumbnail({required this.song});
  final SongEntity song;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: song.artworkPath != null && File(song.artworkPath!).existsSync()
            ? Image.file(File(song.artworkPath!), width: 46, height: 46, fit: BoxFit.cover)
            : Container(
                width: 46,
                height: 46,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.music_note_rounded),
              ),
      );
}

class _NetworkArtworkThumbnail extends StatelessWidget {
  const _NetworkArtworkThumbnail({required this.uri, required this.fallback});
  final Uri? uri;
  final IconData fallback;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 54,
          height: 54,
          child: uri == null
              ? Icon(fallback)
              : Image.network(uri.toString(), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(fallback)),
        ),
      );
}

class _PlaylistPickerTile extends ConsumerWidget {
  const _PlaylistPickerTile({required this.playlist, required this.onTap});
  final dynamic playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(playlistSongsStreamProvider(playlist.id)).valueOrNull ?? const <SongEntity>[];
    return ListTile(
      leading: songs.isEmpty
          ? const Icon(Icons.queue_music_rounded)
          : _ArtworkThumbnail(song: songs.first),
      title: Text(playlist.name),
      subtitle: Text('${songs.length} canciones'),
      onTap: onTap,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline_rounded),
          title: const Text('Red local no disponible'),
          subtitle: Text(message),
        ),
      );
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Column(children: [
          Icon(Icons.wifi_find_rounded, size: 48),
          SizedBox(height: 10),
          Text('Buscando otros dispositivos con MuShare...'),
          SizedBox(height: 4),
          Text('Conéctalos a la misma red Wi-Fi.'),
        ]),
      );
}
