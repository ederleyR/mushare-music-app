class Lyrics {
  const Lyrics({this.plain, this.synced});

  final String? plain;
  final String? synced;

  bool get isEmpty =>
      (plain == null || plain!.trim().isEmpty) &&
      (synced == null || synced!.trim().isEmpty);
  bool get isSynced => synced != null && synced!.trim().isNotEmpty;
  String get text => isSynced ? synced! : plain ?? '';
}

class LyricLine {
  const LyricLine(this.timestamp, this.text);

  final Duration timestamp;
  final String text;
}

List<LyricLine> parseSyncedLyrics(String lyrics) {
  final lines = <LyricLine>[];
  final pattern = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\](.*)');
  for (final line in lyrics.split('\n')) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final fraction = match.group(3) ?? '0';
    final milliseconds = fraction.length == 1
        ? int.parse(fraction) * 100
        : fraction.length == 2
            ? int.parse(fraction) * 10
            : int.parse(fraction.substring(0, 3));
    lines.add(LyricLine(
      Duration(
        minutes: int.parse(match.group(1)!),
        seconds: int.parse(match.group(2)!),
        milliseconds: milliseconds,
      ),
      match.group(4)!.trim(),
    ));
  }
  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return lines;
}
