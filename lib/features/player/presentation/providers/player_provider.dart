import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/database_provider.dart';
import '../../../library/domain/entities/song.dart';
import '../../../../core/database/app_database.dart';
import '../../data/lyrics_service.dart';
import '../../domain/entities/lyrics.dart';
import '../services/system_media_service.dart';

enum PlaybackRepeatMode { off, one, all }

class PlayerState {
  const PlayerState(
      {this.currentSong,
      this.isPlaying = false,
      this.position = Duration.zero,
      this.duration = Duration.zero,
      this.canGoPrevious = false,
      this.canGoNext = false,
      this.isShuffleEnabled = false,
      this.repeatMode = PlaybackRepeatMode.off,
      this.lyrics,
      this.lyricsLoading = false,
      this.lyricsError,
      this.volume = 100,
      this.queue = const [],
      this.queueIndex = -1,
      this.sleepTimerRemaining,
      this.error});
  final SongEntity? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool isShuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final Lyrics? lyrics;
  final bool lyricsLoading;
  final String? lyricsError;
  final double volume;
  final List<SongEntity> queue;
  final int queueIndex;
  final Duration? sleepTimerRemaining;
  final String? error;

  PlayerState copyWith(
          {SongEntity? currentSong,
          bool? isPlaying,
          Duration? position,
          Duration? duration,
          bool? canGoPrevious,
          bool? canGoNext,
          bool? isShuffleEnabled,
          PlaybackRepeatMode? repeatMode,
          Lyrics? lyrics,
          bool? lyricsLoading,
          String? lyricsError,
          double? volume,
          List<SongEntity>? queue,
          int? queueIndex,
          Duration? sleepTimerRemaining,
          String? error,
          bool clearError = false,
          bool clearSleepTimer = false}) =>
      PlayerState(
        currentSong: currentSong ?? this.currentSong,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        canGoPrevious: canGoPrevious ?? this.canGoPrevious,
        canGoNext: canGoNext ?? this.canGoNext,
        isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
        repeatMode: repeatMode ?? this.repeatMode,
        lyrics: lyrics ?? this.lyrics,
        lyricsLoading: lyricsLoading ?? this.lyricsLoading,
        lyricsError: lyricsError ?? this.lyricsError,
        volume: volume ?? this.volume,
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        sleepTimerRemaining: clearSleepTimer
            ? null
            : (sleepTimerRemaining ?? this.sleepTimerRemaining),
        error: clearError ? null : error ?? this.error,
      );
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier(AppDatabase database)
      : _lyricsService = LyricsService(database),
        super(const PlayerState()) {
    SystemMediaService.bind(
      onToggle: toggle,
      onNext: next,
      onPrevious: previous,
    );
    unawaited(_restoreLastSession());
  }

  Player? _player;
  final LyricsService _lyricsService;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    MediaKit.ensureInitialized();
    final player = Player();
    _player = player;
    _subscriptions.addAll([
      player.stream.playing.listen((value) {
        state = state.copyWith(isPlaying: value);
        _syncSystemMedia();
        unawaited(_saveLastSession());
      }),
      player.stream.position.listen((value) {
        state = state.copyWith(position: value);
        _syncSystemMedia();
        if (DateTime.now().difference(_lastSavedAt).inSeconds >= 2) {
          _lastSavedAt = DateTime.now();
          unawaited(_saveLastSession());
        }
      }),
      player.stream.duration
          .listen((value) => state = state.copyWith(duration: value)),
      player.stream.volume
          .listen((value) => state = state.copyWith(volume: value)),
      player.stream.error.listen(
        (error) => state = state.copyWith(error: error.toString()),
      ),
      player.stream.completed.listen((completed) {
        if (completed) unawaited(_playAutomaticNext());
      }),
    ]);
    return player;
  }

  void _syncSystemMedia() => SystemMediaService.update(
        song: state.currentSong,
        isPlaying: state.isPlaying,
        position: state.position,
      );

  Future<void> _saveLastSession() async {
    final song = state.currentSong;
    if (song == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('last_song_path', song.filePath);
    await preferences.setString('last_song_title', song.title);
    await preferences.setString('last_song_artist', song.artist);
    await preferences.setString('last_song_album', song.album);
    await preferences.setInt('last_song_duration', song.durationMs);
    await preferences.setInt(
        'last_song_position', state.position.inMilliseconds);
    await preferences.setBool('playback_shuffle', state.isShuffleEnabled);
    await preferences.setString(
      'playback_queue',
      jsonEncode(state.queue.map(_songToJson).toList()),
    );
    await preferences.setInt('playback_queue_index', state.queueIndex);
    if (song.artworkPath != null) {
      await preferences.setString('last_song_artwork', song.artworkPath!);
    } else {
      await preferences.remove('last_song_artwork');
    }
  }

  Future<void> _restoreLastSession() async {
    final preferences = await SharedPreferences.getInstance();
    final filePath = preferences.getString('last_song_path');
    if (filePath == null || !File(filePath).existsSync()) return;
    final durationMs = preferences.getInt('last_song_duration') ?? 0;
    final positionMs = preferences.getInt('last_song_position') ?? 0;
    final song = SongEntity(
      filePath: filePath,
      title: preferences.getString('last_song_title') ?? 'Canción',
      artist: preferences.getString('last_song_artist') ?? 'Desconocido',
      album: preferences.getString('last_song_album') ?? 'Desconocido',
      durationMs: durationMs,
      artworkPath: preferences.getString('last_song_artwork'),
    );
    final restoredQueue =
        _restoreQueue(preferences.getString('playback_queue'));
    _sourceQueue = restoredQueue.isEmpty ? [song] : restoredQueue;
    _queue = _sourceQueue;
    final savedQueueIndex = preferences.getInt('playback_queue_index') ?? 0;
    _queueIndex = savedQueueIndex.clamp(0, _queue.length - 1);
    final queueSong = _queue[_queueIndex];
    _history
      ..clear()
      ..addAll(_queue.take(_queueIndex + 1));
    _historyIndex = _history.length - 1;
    state = state.copyWith(
      currentSong: queueSong,
      position: Duration(milliseconds: positionMs.clamp(0, durationMs).toInt()),
      duration: Duration(milliseconds: durationMs),
      isShuffleEnabled: preferences.getBool('playback_shuffle') ?? false,
      canGoPrevious: _canGoPrevious(),
      canGoNext: _canGoNext(),
      queue: _queue,
      queueIndex: _queueIndex,
    );
    unawaited(_loadLyrics(queueSong));
    _syncSystemMedia();
  }

  Map<String, dynamic> _songToJson(SongEntity song) => {
        'id': song.id,
        'filePath': song.filePath,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'durationMs': song.durationMs,
        'artworkPath': song.artworkPath,
        'fileSizeBytes': song.fileSizeBytes,
        'format': song.format,
        'dateAdded': song.dateAdded?.toIso8601String(),
        'playCount': song.playCount,
        'isHidden': song.isHidden,
      };

  List<SongEntity> _restoreQueue(String? encodedQueue) {
    if (encodedQueue == null) return const [];
    try {
      final decoded = jsonDecode(encodedQueue) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((json) => SongEntity(
                id: json['id'] as int?,
                filePath: json['filePath'] as String,
                title: json['title'] as String,
                artist: json['artist'] as String? ?? 'Desconocido',
                album: json['album'] as String? ?? 'Desconocido',
                durationMs: json['durationMs'] as int? ?? 0,
                artworkPath: json['artworkPath'] as String?,
                fileSizeBytes: json['fileSizeBytes'] as int?,
                format: json['format'] as String?,
                dateAdded: json['dateAdded'] == null
                    ? null
                    : DateTime.tryParse(json['dateAdded'] as String),
                playCount: json['playCount'] as int? ?? 0,
                isHidden: json['isHidden'] as bool? ?? false,
              ))
          .where((song) => File(song.filePath).existsSync())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<SongEntity> _queue = const [];
  List<SongEntity> _sourceQueue = const [];
  int _queueIndex = -1;
  final List<SongEntity> _history = [];
  int _historyIndex = -1;
  final Random _random = Random();
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isTransitioning = false;
  static const _crossfadeSteps = 16;
  static const _crossfadeStepDuration = Duration(milliseconds: 50);

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    if (duration == null || duration <= Duration.zero) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }
    _sleepDeadline = DateTime.now().add(duration);
    state = state.copyWith(sleepTimerRemaining: duration);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final deadline = _sleepDeadline;
      if (deadline == null) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _sleepTimer?.cancel();
        _sleepTimer = null;
        _sleepDeadline = null;
        state = state.copyWith(clearSleepTimer: true);
        final player = _player;
        if (player != null) await player.pause();
      } else {
        state = state.copyWith(sleepTimerRemaining: remaining);
      }
    });
  }

  Future<void> playSong(SongEntity song, List<SongEntity> queue) async {
    _sourceQueue = queue.isEmpty ? [song] : List.unmodifiable(queue);
    _queue = state.isShuffleEnabled
        ? _shuffledQueueStartingWith(song, _sourceQueue)
        : _sourceQueue;
    _queueIndex = _queue.indexWhere((item) => item.filePath == song.filePath);
    if (_queueIndex < 0) {
      _queue = [song];
      _queueIndex = 0;
    }
    _recordInHistory(song);
    await _play(song);
  }

  void _recordInHistory(SongEntity song) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(song);
    _historyIndex = _history.length - 1;
  }

  Future<void> _play(SongEntity song) async {
    try {
      state = PlayerState(
        currentSong: song,
        canGoPrevious: _canGoPrevious(),
        canGoNext: _canGoNext(),
        isShuffleEnabled: state.isShuffleEnabled,
        repeatMode: state.repeatMode,
        volume: state.volume,
        queue: _queue,
        queueIndex: _queueIndex,
        sleepTimerRemaining: state.sleepTimerRemaining,
      );
      unawaited(_loadLyrics(song));
      final player = _ensurePlayer();
      await player.open(Media(song.filePath));
      await player.play();
      _syncSystemMedia();
    } catch (error) {
      state = state.copyWith(error: 'No se pudo abrir el archivo: $error');
    }
  }

  Future<void> _loadLyrics(SongEntity song) async {
    state = state.copyWith(lyricsLoading: true, lyricsError: null);
    final lyrics = await _lyricsService.find(song);
    if (state.currentSong?.filePath != song.filePath) return;
    state = state.copyWith(
      lyrics: lyrics,
      lyricsLoading: false,
      lyricsError: lyrics == null ? 'Letra no disponible' : null,
    );
  }

  Future<void> toggle() async {
    if (state.currentSong == null) return;
    final player = _player;
    if (player == null) {
      final song = state.currentSong!;
      final resumeAt = state.position;
      final restoredPlayer = _ensurePlayer();
      await restoredPlayer.open(Media(song.filePath));
      await restoredPlayer.seek(resumeAt);
      await restoredPlayer.play();
      return;
    }
    if (state.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player != null) await player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    final player = _player;
    if (player != null) await player.setVolume(volume);
  }

  Future<void> previous() async {
    if (_historyIndex <= 0) return;
    _historyIndex--;
    final song = _history[_historyIndex];
    _queueIndex = _queue.indexWhere((item) => item.filePath == song.filePath);
    await _play(song);
  }

  Future<void> next() async {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      final song = _history[_historyIndex];
      _queueIndex = _queue.indexWhere((item) => item.filePath == song.filePath);
      await _playWithCrossfade(song);
      return;
    }
    await _playAutomaticNext();
  }

  Future<void> playQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    final song = _queue[index];
    _recordInHistory(song);
    await _play(song);
  }

  void toggleShuffle() {
    final isShuffleEnabled = !state.isShuffleEnabled;
    final currentSong = state.currentSong;
    if (currentSong != null) {
      _queue = isShuffleEnabled
          ? _shuffledQueueStartingWith(currentSong, _sourceQueue)
          : _sourceQueue;
      _queueIndex =
          _queue.indexWhere((song) => song.filePath == currentSong.filePath);
    }
    state = state.copyWith(
      isShuffleEnabled: isShuffleEnabled,
      canGoPrevious: _canGoPrevious(),
      canGoNext: _canGoNext(),
      queue: _queue,
      queueIndex: _queueIndex,
    );
    unawaited(_saveLastSession());
  }

  void toggleRepeat() {
    final repeatMode = switch (state.repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.off,
    };
    state = state.copyWith(repeatMode: repeatMode);
  }

  Future<void> _playAutomaticNext() async {
    if (_isTransitioning) return;
    if (_queue.isEmpty) return;
    if (state.repeatMode == PlaybackRepeatMode.one) {
      final song = state.currentSong;
      if (song != null) await _playWithCrossfade(song);
      return;
    }
    if (_queueIndex >= _queue.length - 1) {
      _queueIndex = 0;
    } else {
      _queueIndex++;
    }
    final song = _queue[_queueIndex];
    _recordInHistory(song);
    await _playWithCrossfade(song);
  }

  Future<void> _playWithCrossfade(SongEntity song) async {
    final player = _player;
    if (player == null) {
      await _play(song);
      return;
    }

    _isTransitioning = true;
    final targetVolume = state.volume.clamp(0, 100).toDouble();
    try {
      for (var step = _crossfadeSteps; step >= 0; step--) {
        await player.setVolume(targetVolume * step / _crossfadeSteps);
        await Future<void>.delayed(_crossfadeStepDuration);
      }
      await _play(song);
      for (var step = 1; step <= _crossfadeSteps; step++) {
        await player.setVolume(targetVolume * step / _crossfadeSteps);
        await Future<void>.delayed(_crossfadeStepDuration);
      }
    } finally {
      _isTransitioning = false;
    }
  }

  bool _hasQueueNext() {
    return _queue.length > 1;
  }

  bool _canGoPrevious() =>
      _historyIndex > 0 || (_queueIndex > 0 && _queue.isNotEmpty);

  bool _canGoNext() =>
      _historyIndex < _history.length - 1 || _hasQueueNext();

  List<SongEntity> _shuffledQueueStartingWith(
      SongEntity currentSong, List<SongEntity> sourceQueue) {
    final remaining = sourceQueue
        .where((song) => song.filePath != currentSong.filePath)
        .toList()
      ..shuffle(_random);
    return List.unmodifiable([currentSong, ...remaining]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    _sleepTimer?.cancel();
    unawaited(_saveLastSession());
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
    (ref) => PlayerNotifier(ref.watch(databaseProvider)));
