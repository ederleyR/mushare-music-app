// lib/core/utils/permission_utils.dart
//
// Centraliza la solicitud de permisos. Solo aplica en móvil;
// en Desktop no se requiere ningún permiso especial porque el
// usuario elige explícitamente la carpeta con file_picker.

import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Solicita el permiso correcto según la versión de Android/iOS.
  /// Retorna true si el permiso fue concedido.
  static Future<bool> requestAudioPermission() async {
    // En Desktop no hay nada que pedir.
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      // permission_handler detecta automáticamente si el dispositivo
      // es Android 13+ (usa READ_MEDIA_AUDIO) o anterior (usa storage).
      final status = await Permission.audio.request();
      if (status.isGranted) return true;

      // Fallback para versiones antiguas de Android
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }

    if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.request();
      return status.isGranted;
    }

    return false;
  }

  /// Verifica si el permiso ya fue concedido sin volver a pedirlo.
  static Future<bool> hasAudioPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      return await Permission.audio.isGranted ||
          await Permission.storage.isGranted;
    }

    if (Platform.isIOS) {
      return await Permission.mediaLibrary.isGranted;
    }

    return false;
  }
}
