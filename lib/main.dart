// lib/main.dart
//
// Punto de entrada de MuShare. Envuelve toda la app en un ProviderScope
// (requisito de Riverpod) para que cualquier widget pueda acceder a
// los providers definidos en toda la aplicación.

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
    final accentColor = ref.watch(
      appSettingsProvider.select((settings) => settings.activeColor),
    );
    return MaterialApp(
      title: 'MuShare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(accentColor),
      home: const DesktopShell(),
    );
  }
}
