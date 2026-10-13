// lib/main.dart
//
// Punto de entrada de MuShare. Envuelve toda la app en un ProviderScope
// (requisito de Riverpod) para que cualquier widget pueda acceder a
// los providers definidos en toda la aplicación.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/screens/desktop_shell.dart';
import 'features/player/presentation/services/system_media_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemMediaService.initialize();

  runApp(
    const ProviderScope(
      child: MuShareApp(),
    ),
  );
}

class MuShareApp extends ConsumerWidget {
  const MuShareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuredAccent = ref.watch(
      appSettingsProvider.select((settings) => settings.activeColor),
    );
    final accentColor =
        ref.watch(backgroundAccentProvider).valueOrNull ?? configuredAccent;
    final backgroundPath = ref.watch(
      appSettingsProvider.select((settings) => settings.backgroundImagePath),
    );
    final isDarkMode = ref.watch(
      appSettingsProvider.select((settings) => settings.isDarkMode),
    );
    return MaterialApp(
      title: 'MuShare',
      debugShowCheckedModeBanner: false,
      theme:
          isDarkMode ? AppTheme.dark(accentColor) : AppTheme.light(accentColor),
      home: _AppBackground(
        imagePath: backgroundPath,
        isDarkMode: isDarkMode,
        child: const DesktopShell(),
      ),
    );
  }
}

class _AppBackground extends StatelessWidget {
  const _AppBackground(
      {required this.imagePath, required this.isDarkMode, required this.child});

  final String? imagePath;
  final bool isDarkMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final imageFile = imagePath == null ? null : File(imagePath!);
    final hasImage = imageFile != null && imageFile.existsSync();
    return ColoredBox(
      // Conserva el gris oscuro original de MuShare, y usa una base clara
      // real cuando el usuario selecciona el modo claro.
      color: isDarkMode ? AppColors.background : const Color(0xFFF8F7FC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Image.file(imageFile,
                fit: BoxFit.cover, filterQuality: FilterQuality.low),
          if (hasImage)
            ColoredBox(
                color: isDarkMode
                    ? const Color(0xB30B0B0F)
                    : const Color(0xB3FFFFFF)),
          child,
        ],
      ),
    );
  }
}
