import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:palette_generator/palette_generator.dart';

enum AppAccent {
  purple('Morado', Color(0xFFB24BF3)),
  orange('Naranja', Color(0xFFFF8A3D)),
  green('Verde', Color(0xFF39C98A)),
  red('Rojo', Color(0xFFFF5C6C)),
  pink('Rosa', Color(0xFFFF5FA2)),
  custom('Personalizado', Color(0xFFB24BF3));

  const AppAccent(this.label, this.color);

  final String label;
  final Color color;

  static AppAccent fromStorage(String? value) {
    return AppAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => AppAccent.purple,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.isLoaded,
    required this.accent,
    this.customAccentValue,
    this.displayName,
    this.profileImagePath,
    this.backgroundImagePath,
    bool? isDarkMode,
    bool? adaptAccentToBackground,
  })  : _isDarkMode = isDarkMode,
        _adaptAccentToBackground = adaptAccentToBackground;

  const AppSettings.initial()
      : isLoaded = false,
        accent = AppAccent.purple,
        customAccentValue = null,
        displayName = null,
        profileImagePath = null,
        backgroundImagePath = null,
        _isDarkMode = true,
        _adaptAccentToBackground = false;

  final bool isLoaded;
  final AppAccent accent;
  final int? customAccentValue;
  final String? displayName;
  final String? profileImagePath;
  final String? backgroundImagePath;
  // Nullable internamente para que una recarga en caliente desde versiones
  // anteriores (sin este campo) siga usando modo oscuro con seguridad.
  final bool? _isDarkMode;
  bool get isDarkMode => _isDarkMode ?? true;
  final bool? _adaptAccentToBackground;
  bool get adaptAccentToBackground => _adaptAccentToBackground ?? false;

  Color get activeColor => accent == AppAccent.custom
      ? Color(customAccentValue ?? AppAccent.custom.color.toARGB32())
      : accent.color;

  AppSettings copyWith({
    bool? isLoaded,
    AppAccent? accent,
    int? customAccentValue,
    String? displayName,
    String? profileImagePath,
    String? backgroundImagePath,
    bool? isDarkMode,
    bool? adaptAccentToBackground,
    bool clearDisplayName = false,
    bool clearBackgroundImage = false,
  }) {
    return AppSettings(
      isLoaded: isLoaded ?? this.isLoaded,
      accent: accent ?? this.accent,
      customAccentValue: customAccentValue ?? this.customAccentValue,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      profileImagePath: profileImagePath ?? this.profileImagePath,
      backgroundImagePath: clearBackgroundImage
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      isDarkMode: isDarkMode ?? this.isDarkMode,
      adaptAccentToBackground:
          adaptAccentToBackground ?? this.adaptAccentToBackground,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings.initial()) {
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedName = preferences.getString('display_name')?.trim();
    final storedProfileImage = preferences.getString('profile_image_path');
    final storedBackgroundImage =
        preferences.getString('background_image_path');
    state = AppSettings(
      isLoaded: true,
      accent: AppAccent.fromStorage(preferences.getString('theme_accent')),
      customAccentValue: preferences.getInt('theme_custom_color'),
      displayName: storedName == null || storedName.isEmpty ? null : storedName,
      profileImagePath: storedProfileImage,
      backgroundImagePath: storedBackgroundImage,
      isDarkMode: preferences.getBool('dark_mode') ?? true,
      adaptAccentToBackground:
          preferences.getBool('adapt_accent_to_background') ?? false,
    );
  }

  Future<void> setDisplayName(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    state = state.copyWith(displayName: trimmedName);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('display_name', trimmedName);
  }

  Future<void> setProfileImagePath(String path) async {
    state = state.copyWith(profileImagePath: path);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('profile_image_path', path);
  }

  Future<void> setBackgroundImagePath(String path) async {
    state = state.copyWith(backgroundImagePath: path);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('background_image_path', path);
  }

  Future<void> clearBackgroundImage() async {
    state = state.copyWith(clearBackgroundImage: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('background_image_path');
  }

  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(isDarkMode: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('dark_mode', value);
  }

  Future<void> setAdaptAccentToBackground(bool value) async {
    state = state.copyWith(adaptAccentToBackground: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('adapt_accent_to_background', value);
  }

  Future<void> setAccent(AppAccent accent) async {
    state = state.copyWith(accent: accent);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('theme_accent', accent.name);
  }

  Future<void> setCustomAccent(Color color) async {
    final value = color.toARGB32();
    state = state.copyWith(
      accent: AppAccent.custom,
      customAccentValue: value,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('theme_accent', AppAccent.custom.name);
    await preferences.setInt('theme_custom_color', value);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);

final backgroundAccentProvider = FutureProvider<Color?>((ref) async {
  final settings = ref.watch(appSettingsProvider);
  if (!settings.adaptAccentToBackground || settings.backgroundImagePath == null)
    return null;
  final file = File(settings.backgroundImagePath!);
  if (!await file.exists()) return null;
  final palette = await PaletteGenerator.fromImageProvider(
    ResizeImage(FileImage(file), width: 96, height: 96),
    maximumColorCount: 12,
  );
  return palette.vibrantColor?.color ?? palette.dominantColor?.color;
});
