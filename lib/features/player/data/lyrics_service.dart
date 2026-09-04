import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/database/app_database.dart';
import '../../library/domain/entities/song.dart';
import '../domain/entities/lyrics.dart';

class LyricsService {
  LyricsService(this._database);

  final AppDatabase _database;

  Future<Lyrics?> find(SongEntity song) async {
    final cached = await _database.getCachedLyrics(song.filePath);
    if (cached != null) {
      final lyrics = Lyrics(
        plain: cached.plainLyrics,
        synced: cached.syncedLyrics,
      );
      if (!lyrics.isEmpty) return lyrics;
    }

    final title = _clean(song.title);
    final artist = _clean(song.artist);
    if (title.isEmpty || artist.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.https('lrclib.net', '/api/get', {
          'track_name': title,
          'artist_name': artist,
          'duration': (song.durationMs / 1000).round().toString(),
        }),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final lyrics = Lyrics(
        plain: json['plainLyrics'] as String?,
        synced: json['syncedLyrics'] as String?,
      );
      if (lyrics.isEmpty) return null;
      await _database.cacheLyrics(
        filePath: song.filePath,
        plainLyrics: lyrics.plain,
        syncedLyrics: lyrics.synced,
      );
      return lyrics;
    } catch (_) {
      return null;
    }
  }

  String _clean(String value) {
    return value
        .replaceAll(
            RegExp(
                r'\([^)]*(official|video|audio|remaster|version|lyrics)[^)]*\)',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\[[^\]]*(official|video|audio|remaster|version|lyrics)[^\]]*\]',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*', caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s+-\s+(remastered|live|acoustic|radio edit).*',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
