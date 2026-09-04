import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushare/features/library/data/datasources/audio_scanner.dart';

void main() {
  group('Audio scanner helpers', () {
    test('detecta archivos de audio soportados en un directorio', () async {
      final tempDir = Directory.systemTemp.createTempSync('mushare_audio_test');
      addTearDown(() => tempDir.delete(recursive: true));

      File('${tempDir.path}/cancion1.mp3').writeAsStringSync('mp3');
      File('${tempDir.path}/cancion2.flac').writeAsStringSync('flac');
      File('${tempDir.path}/texto.txt').writeAsStringSync('no audio');

      final files = findSupportedAudioFilesInDirectory(tempDir);

      expect(files.length, 2);
      expect(files.map((file) => file.path).toList(), containsAll([
        '${tempDir.path}\\cancion1.mp3',
        '${tempDir.path}\\cancion2.flac',
      ]));
    });

    test('acepta extensiones soportadas', () {
      expect(isSupportedAudioFile('cancion.mp3'), isTrue);
      expect(isSupportedAudioFile('cancion.flac'), isTrue);
      expect(isSupportedAudioFile('cancion.txt'), isFalse);
    });
  });
}
