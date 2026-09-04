import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../../../library/domain/entities/song.dart';

/// Puente entre MuShare y los controles del sistema: audífonos, notificación
/// y pantalla bloqueada en Android. En escritorio no realiza ninguna acción.
class SystemMediaService {
  static _MuShareAudioHandler? _handler;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _handler != null) return;
    _handler = await AudioService.init(
      builder: _MuShareAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'mushare.playback',
        androidNotificationChannelName: 'Reproducción de MuShare',
        androidStopForegroundOnPause: false,
      ),
    );
  }

  static void bind({
    required Future<void> Function() onToggle,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    final handler = _handler;
    if (handler == null) return;
    handler.onToggle = onToggle;
    handler.onNext = onNext;
    handler.onPrevious = onPrevious;
  }

  static void update({
    required SongEntity? song,
    required bool isPlaying,
    required Duration position,
  }) {
    final handler = _handler;
    if (handler == null) return;
    handler.update(song: song, isPlaying: isPlaying, position: position);
  }
}

class _MuShareAudioHandler extends BaseAudioHandler {
  Future<void> Function()? onToggle;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  String? _lastMediaId;

  void update({
    required SongEntity? song,
    required bool isPlaying,
    required Duration position,
  }) {
    if (song == null) return;
    if (_lastMediaId != song.filePath) {
      _lastMediaId = song.filePath;
      mediaItem.add(MediaItem(
        id: song.filePath,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: Duration(milliseconds: song.durationMs),
        artUri: song.artworkPath == null ? null : Uri.file(song.artworkPath!),
      ));
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: position,
    ));
  }

  @override
  Future<void> play() async {
    if (onToggle != null) await onToggle!();
  }

  @override
  Future<void> pause() async {
    if (onToggle != null) await onToggle!();
  }

  @override
  Future<void> skipToNext() async {
    if (onNext != null) await onNext!();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) await onPrevious!();
  }
}
