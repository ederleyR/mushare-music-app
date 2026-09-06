import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../library/data/repositories/library_repository_impl.dart';
import '../../../library/domain/entities/playlist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/presentation/providers/library_provider.dart';

const _multicastAddress = '239.255.42.99';
const _discoveryPort = 45454;

class LocalDevice {
  const LocalDevice({
    required this.id,
    required this.userName,
    required this.deviceName,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.profileImageUri,
  });

  final String id;
  final String userName;
  final String deviceName;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;
  final Uri? profileImageUri;
}

class IncomingTransfer {
  const IncomingTransfer({
    required this.id,
    required this.senderName,
    required this.senderDevice,
    required this.senderAddress,
    required this.senderPort,
    required this.token,
    required this.title,
    required this.isPlaylist,
    required this.itemCount,
    this.coverUri,
    this.senderImageUri,
  });

  final String id;
  final String senderName;
  final String senderDevice;
  final InternetAddress senderAddress;
  final int senderPort;
  final String token;
  final String title;
  final bool isPlaylist;
  final int itemCount;
  final Uri? coverUri;
  final Uri? senderImageUri;
}

class TransferProgress {
  const TransferProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
  });

  final int receivedBytes;
  final int totalBytes;
  final int completedFiles;
  final int totalFiles;

  double get fraction => totalBytes <= 0 ? 0 : receivedBytes / totalBytes;
}

class TransferCancellation {
  bool isCancelled = false;
  HttpClient? _client;

  void cancel() {
    isCancelled = true;
    _client?.close(force: true);
  }
}

class _TransferCancelled implements Exception {}

class LocalShareState {
  const LocalShareState({
    this.isRunning = false,
    this.devices = const [],
    this.incomingTransfers = const [],
    this.error,
  });

  final bool isRunning;
  final List<LocalDevice> devices;
  final List<IncomingTransfer> incomingTransfers;
  final String? error;

  LocalShareState copyWith({
    bool? isRunning,
    List<LocalDevice>? devices,
    List<IncomingTransfer>? incomingTransfers,
    String? error,
  }) =>
      LocalShareState(
        isRunning: isRunning ?? this.isRunning,
        devices: devices ?? this.devices,
        incomingTransfers: incomingTransfers ?? this.incomingTransfers,
        error: error,
      );
}

class _OutgoingTransfer {
  const _OutgoingTransfer({
    required this.title,
    required this.isPlaylist,
    required this.songs,
    this.coverPath,
  });

  final String title;
  final bool isPlaylist;
  final List<SongEntity> songs;
  final String? coverPath;
}

final localShareProvider =
    StateNotifierProvider<LocalShareNotifier, LocalShareState>((ref) {
  return LocalShareNotifier(ref.read(libraryRepositoryProvider));
});

class LocalShareNotifier extends StateNotifier<LocalShareState> {
  LocalShareNotifier(this._library) : super(const LocalShareState());

  final LibraryRepository _library;
  final String _id =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  final Map<String, _OutgoingTransfer> _outgoing = {};
  final Map<String, LocalDevice> _devices = {};
  HttpServer? _server;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  String _userName = 'Usuario';
  String _deviceName = Platform.localHostname;
  String? _profileImagePath;

  Future<void> start(
      {required String userName, String? profileImagePath}) async {
    _userName = userName.trim().isEmpty ? 'Usuario' : userName.trim();
    _deviceName = Platform.localHostname;
    _profileImagePath = profileImagePath;
    if (_server != null) {
      _announce();
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
      unawaited(_server!.forEach(_handleHttpRequest));
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket!.joinMulticast(InternetAddress(_multicastAddress));
      _socketSubscription = _socket!.listen(_onSocketEvent);
      _announceTimer =
          Timer.periodic(const Duration(seconds: 4), (_) => _announce());
      _cleanupTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _removeOfflineDevices());
      state = state.copyWith(isRunning: true, error: null);
      _announce();
    } catch (error) {
      state = state.copyWith(error: 'No se pudo iniciar la red local: $error');
      await stop();
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      try {
        final message =
            jsonDecode(utf8.decode(datagram!.data)) as Map<String, dynamic>;
        if (message['senderId'] == _id) continue;
        switch (message['type']) {
          case 'mushare-discovery':
            _registerDevice(message, datagram.address);
          case 'mushare-offer':
            _registerIncomingTransfer(message, datagram.address);
        }
      } catch (_) {
        // Ignora paquetes ajenos o corruptos en la red local.
      }
    }
  }

  void _registerDevice(Map<String, dynamic> message, InternetAddress address) {
    final id = message['senderId'] as String?;
    final port = message['port'] as int?;
    if (id == null || port == null) return;
    _devices[id] = LocalDevice(
      id: id,
      userName: message['userName'] as String? ?? 'Usuario',
      deviceName: message['deviceName'] as String? ?? 'Dispositivo',
      address: address,
      port: port,
      lastSeen: DateTime.now(),
      profileImageUri: message['hasProfileImage'] == true
          ? Uri(
              scheme: 'http',
              host: address.address,
              port: port,
              path: '/mushare/profile/$id',
            )
          : null,
    );
    _publishDevices();
  }

  void _registerIncomingTransfer(
      Map<String, dynamic> message, InternetAddress address) {
    if (message['targetId'] != _id) return;
    final id = message['offerId'] as String?;
    final token = message['token'] as String?;
    final port = message['port'] as int?;
    if (id == null ||
        token == null ||
        port == null ||
        state.incomingTransfers.any((transfer) => transfer.id == id)) {
      return;
    }
    final transfer = IncomingTransfer(
      id: id,
      senderName: message['userName'] as String? ?? 'Usuario',
      senderDevice: message['deviceName'] as String? ?? 'Dispositivo',
      senderAddress: address,
      senderPort: port,
      token: token,
      title: message['title'] as String? ?? 'Contenido musical',
      isPlaylist: message['isPlaylist'] == true,
      itemCount: message['itemCount'] as int? ?? 1,
      senderImageUri: message['hasProfileImage'] == true
          ? Uri(
              scheme: 'http',
              host: address.address,
              port: port,
              path: '/mushare/profile/${message['senderId']}',
            )
          : null,
      coverUri:
          message['hasPlaylistCover'] == true || message['coverIndex'] is int
              ? Uri(
                  scheme: 'http',
                  host: address.address,
                  port: port,
                  path: message['hasPlaylistCover'] == true
                      ? '/mushare/playlist-cover/$token'
                      : '/mushare/artwork/$token/${message['coverIndex']}',
                )
              : null,
    );
    state = state
        .copyWith(incomingTransfers: [...state.incomingTransfers, transfer]);
  }

  void _announce() => _broadcast({
        'type': 'mushare-discovery',
        'senderId': _id,
        'userName': _userName,
        'deviceName': _deviceName,
        'port': _server?.port,
        'hasProfileImage':
            _profileImagePath != null && File(_profileImagePath!).existsSync(),
      });

  Future<void> shareSong(LocalDevice device, SongEntity song) =>
      _offer(device, title: song.title, songs: [song], isPlaylist: false);

  Future<void> sharePlaylist(
    LocalDevice device,
    PlaylistEntity playlist,
    List<SongEntity> songs,
  ) =>
      _offer(
        device,
        title: playlist.name,
        songs: songs,
        isPlaylist: true,
        coverPath: playlist.coverPath,
      );

  Future<void> _offer(
    LocalDevice device, {
    required String title,
    required List<SongEntity> songs,
    required bool isPlaylist,
    String? coverPath,
  }) async {
    if (songs.isEmpty) {
      state =
          state.copyWith(error: 'La playlist no tiene canciones para enviar.');
      return;
    }
    final unavailable =
        songs.where((song) => !File(song.filePath).existsSync());
    if (unavailable.isNotEmpty) {
      state = state.copyWith(
          error:
              'Una o más canciones ya no están disponibles en este dispositivo.');
      return;
    }
    final token =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final hasPlaylistCover =
        isPlaylist && coverPath != null && await File(coverPath).exists();
    _outgoing[token] = _OutgoingTransfer(
      title: title,
      isPlaylist: isPlaylist,
      songs: songs,
      coverPath: hasPlaylistCover ? coverPath : null,
    );
    final coverIndex = songs.indexWhere((song) =>
        song.artworkPath != null && File(song.artworkPath!).existsSync());
    _broadcast({
      'type': 'mushare-offer',
      'senderId': _id,
      'targetId': device.id,
      'offerId': '$_id-$token',
      'token': token,
      'userName': _userName,
      'deviceName': _deviceName,
      'port': _server?.port,
      'hasProfileImage':
          _profileImagePath != null && File(_profileImagePath!).existsSync(),
      'title': title,
      'isPlaylist': isPlaylist,
      'itemCount': songs.length,
      'hasPlaylistCover': hasPlaylistCover,
      if (coverIndex >= 0) 'coverIndex': coverIndex,
    });
  }

  Future<bool> acceptTransfer(
    IncomingTransfer transfer, {
    void Function(TransferProgress progress)? onProgress,
    TransferCancellation? cancellation,
  }) async {
    final importedSongIds = <int>[];
    final downloadedFiles = <File>[];
    final downloadedArtwork = <File>[];
    File? downloadedPlaylistCover;
    try {
      _throwIfCancelled(cancellation);
      final manifest = await _getJson(transfer.senderAddress,
          transfer.senderPort, '/mushare/offer/${transfer.token}',
          cancellation: cancellation);
      final files =
          (manifest['songs'] as List<dynamic>).cast<Map<String, dynamic>>();
      final totalBytes = files.fold<int>(
        0,
        (total, data) => total + (data['fileSizeBytes'] as int? ?? 0),
      );
      var receivedBytes = 0;
      final folder = Directory(path.join(
          (await getApplicationDocumentsDirectory()).path, 'shared_music'));
      final artworkFolder = Directory(path.join(
          (await getApplicationDocumentsDirectory()).path, 'artwork_cache'));
      final playlistCoverFolder = Directory(path.join(
          (await getApplicationDocumentsDirectory()).path, 'playlist_covers'));
      await folder.create(recursive: true);
      await artworkFolder.create(recursive: true);
      await playlistCoverFolder.create(recursive: true);
      final receivedIds = <int>[];
      for (var itemIndex = 0; itemIndex < files.length; itemIndex++) {
        _throwIfCancelled(cancellation);
        final data = files[itemIndex];
        final safeName =
            path.basename(data['fileName'] as String? ?? 'audio.mp3');
        final incomingSong = SongEntity(
          filePath: '',
          title: data['title'] as String? ??
              path.basenameWithoutExtension(safeName),
          artist: data['artist'] as String? ?? 'Desconocido',
          durationMs: data['durationMs'] as int? ?? 0,
        );
        final existingId = await _library.findMatchingSongId(incomingSong);
        if (existingId != null) {
          receivedIds.add(existingId);
          onProgress?.call(TransferProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            completedFiles: itemIndex + 1,
            totalFiles: files.length,
          ));
          continue;
        }
        final output = _availablePath(folder, safeName);
        downloadedFiles.add(output);
        await _download(transfer.senderAddress, transfer.senderPort,
            '/mushare/file/${transfer.token}/${data['index']}', output,
            cancellation: cancellation, onBytes: (count) {
          receivedBytes += count;
          onProgress?.call(TransferProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            completedFiles: itemIndex,
            totalFiles: files.length,
          ));
        });
        String? artworkPath;
        if (data['hasArtwork'] == true) {
          final artwork = File(path.join(artworkFolder.path,
              '${DateTime.now().microsecondsSinceEpoch}-${data['index']}.jpg'));
          try {
            await _download(transfer.senderAddress, transfer.senderPort,
                '/mushare/artwork/${transfer.token}/${data['index']}', artwork,
                cancellation: cancellation);
            artworkPath = artwork.path;
            downloadedArtwork.add(artwork);
          } catch (_) {
            _throwIfCancelled(cancellation);
            // La portada es opcional; la canción sigue siendo válida sin ella.
          }
        }
        final song = incomingSong.copyWith(
          filePath: output.path,
          album: data['album'] as String? ?? 'Desconocido',
          artworkPath: artworkPath,
          fileSizeBytes: await output.length(),
          format: path.extension(safeName).replaceFirst('.', ''),
          dateAdded: DateTime.now(),
        );
        final importedId = await _library.importSong(song);
        receivedIds.add(importedId);
        importedSongIds.add(importedId);
        onProgress?.call(TransferProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          completedFiles: itemIndex + 1,
          totalFiles: files.length,
        ));
      }
      String? playlistCoverPath;
      if (transfer.isPlaylist && (manifest['hasPlaylistCover'] == true)) {
        final cover = File(path.join(playlistCoverFolder.path,
            '${DateTime.now().microsecondsSinceEpoch}-playlist.jpg'));
        try {
          await _download(transfer.senderAddress, transfer.senderPort,
              '/mushare/playlist-cover/${transfer.token}', cover,
              cancellation: cancellation);
          playlistCoverPath = cover.path;
          downloadedPlaylistCover = cover;
        } catch (_) {
          _throwIfCancelled(cancellation);
          // La portada es opcional; la playlist sigue siendo válida sin ella.
        }
      }
      if (transfer.isPlaylist) {
        final playlistId = await _library.createPlaylist(transfer.title,
            coverPath: playlistCoverPath);
        for (final id in receivedIds) {
          await _library.addSongToPlaylist(playlistId, id);
        }
      }
      _removeIncoming(transfer.id);
      return true;
    } on _TransferCancelled {
      for (final id in importedSongIds) {
        await _library.removeSong(id);
      }
      for (final file in [
        ...downloadedFiles,
        ...downloadedArtwork,
        if (downloadedPlaylistCover != null) downloadedPlaylistCover
      ]) {
        if (await file.exists()) await file.delete();
      }
      _removeIncoming(transfer.id);
      return false;
    } catch (error) {
      state = state.copyWith(error: 'No se pudo recibir el envío: $error');
      return false;
    }
  }

  void _throwIfCancelled(TransferCancellation? cancellation) {
    if (cancellation?.isCancelled == true) throw _TransferCancelled();
  }

  void rejectTransfer(String id) => _removeIncoming(id);

  void _removeIncoming(String id) {
    state = state.copyWith(
      incomingTransfers:
          state.incomingTransfers.where((item) => item.id != id).toList(),
    );
  }

  Future<Map<String, dynamic>> _getJson(
      InternetAddress address, int port, String endpoint,
      {TransferCancellation? cancellation}) async {
    final client = HttpClient();
    cancellation?._client = client;
    try {
      _throwIfCancelled(cancellation);
      final request = await client.getUrl(Uri(
          scheme: 'http', host: address.address, port: port, path: endpoint));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Respuesta ${response.statusCode}');
      }
      return jsonDecode(await utf8.decodeStream(response))
          as Map<String, dynamic>;
    } finally {
      if (cancellation?._client == client) cancellation!._client = null;
      client.close(force: true);
    }
  }

  Future<void> _download(
    InternetAddress address,
    int port,
    String endpoint,
    File output, {
    TransferCancellation? cancellation,
    void Function(int bytes)? onBytes,
  }) async {
    final client = HttpClient();
    cancellation?._client = client;
    try {
      _throwIfCancelled(cancellation);
      final request = await client.getUrl(Uri(
          scheme: 'http', host: address.address, port: port, path: endpoint));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Respuesta ${response.statusCode}');
      }
      final sink = output.openWrite();
      await for (final bytes in response) {
        _throwIfCancelled(cancellation);
        sink.add(bytes);
        onBytes?.call(bytes.length);
      }
      await sink.close();
    } finally {
      if (cancellation?._client == client) cancellation!._client = null;
      client.close(force: true);
    }
  }

  File _availablePath(Directory folder, String name) {
    final stem = path.basenameWithoutExtension(name);
    final extension = path.extension(name);
    var candidate = File(path.join(folder.path, name));
    var number = 2;
    while (candidate.existsSync()) {
      candidate = File(path.join(folder.path, '$stem ($number)$extension'));
      number++;
    }
    return candidate;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      final parts = request.uri.pathSegments;
      if (parts.length < 3 || parts[0] != 'mushare') {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (parts[1] == 'profile' && parts.length == 3) {
        final profilePath = _profileImagePath;
        final profile = profilePath == null ? null : File(profilePath);
        if (profile == null || !await profile.exists()) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          await profile.openRead().pipe(request.response);
          return;
        }
      }
      final transfer = _outgoing[parts[2]];
      if (transfer == null) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (parts[1] == 'offer') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'title': transfer.title,
          'isPlaylist': transfer.isPlaylist,
          'hasPlaylistCover': transfer.coverPath != null,
          'hasCover': transfer.coverPath != null ||
              transfer.songs.any((song) =>
                  song.artworkPath != null &&
                  File(song.artworkPath!).existsSync()),
          'songs': List.generate(transfer.songs.length, (index) {
            final song = transfer.songs[index];
            return {
              'index': index,
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'durationMs': song.durationMs,
              'fileName': path.basename(song.filePath),
              'fileSizeBytes':
                  song.fileSizeBytes ?? File(song.filePath).lengthSync(),
              'hasArtwork': song.artworkPath != null &&
                  File(song.artworkPath!).existsSync(),
            };
          }),
        }));
      } else if (parts[1] == 'file' && parts.length == 4) {
        final index = int.tryParse(parts[3]);
        if (index == null || index < 0 || index >= transfer.songs.length) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final file = File(transfer.songs[index].filePath);
          if (!await file.exists()) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.contentType = ContentType.binary;
            await file.openRead().pipe(request.response);
            return;
          }
        }
      } else if (parts[1] == 'playlist-cover' && parts.length == 3) {
        final coverPath = transfer.coverPath;
        final cover = coverPath == null ? null : File(coverPath);
        if (cover == null || !await cover.exists()) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          await cover.openRead().pipe(request.response);
          return;
        }
      } else if (parts[1] == 'artwork' && parts.length == 4) {
        final index = int.tryParse(parts[3]);
        final artworkPath =
            index == null || index < 0 || index >= transfer.songs.length
                ? null
                : transfer.songs[index].artworkPath;
        final artwork = artworkPath == null ? null : File(artworkPath);
        if (artwork == null || !await artwork.exists()) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          await artwork.openRead().pipe(request.response);
          return;
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  void _broadcast(Map<String, dynamic> message) {
    _socket?.send(utf8.encode(jsonEncode(message)),
        InternetAddress(_multicastAddress), _discoveryPort);
  }

  void _removeOfflineDevices() {
    _devices.removeWhere((_, device) =>
        DateTime.now().difference(device.lastSeen).inSeconds > 12);
    _publishDevices();
  }

  void _publishDevices() => state = state.copyWith(
        devices: _devices.values.toList()
          ..sort((a, b) =>
              a.userName.toLowerCase().compareTo(b.userName.toLowerCase())),
      );

  void retryDiscovery() {
    _devices.clear();
    _publishDevices();
    if (_socket != null) _announce();
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    await _socketSubscription?.cancel();
    _socket?.close();
    _socket = null;
    await _server?.close(force: true);
    _server = null;
    state = state.copyWith(isRunning: false);
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
