import 'package:flutter/services.dart';

/// Abre el selector de salida del sistema.
///
/// La reproducción conserva el mismo reproductor: al escoger un parlante o
/// auricular Bluetooth en el sistema, MuShare envía el audio a ese dispositivo.
class AudioOutputService {
  AudioOutputService._();

  static const _channel = MethodChannel('mushare/audio_output');

  static Future<bool> openSystemOutputSettings() async {
    try {
      await _channel.invokeMethod<void>('openOutputSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openBluetoothSettings() async {
    try {
      await _channel.invokeMethod<void>('openBluetoothSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

}
