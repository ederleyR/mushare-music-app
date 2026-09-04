import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  const AppSettings.initial()
      : isLoaded = false,
        accent = AppAccent.purple,
        customAccentValue = null,
        displayName = null;

  final bool isLoaded;
  final AppAccent accent;
  final int? customAccentValue;
  final String? displayName;

  Color get activeColor => accent == AppAccent.custom
      ? Color(customAccentValue ?? AppAccent.custom.color.toARGB32())
      : accent.color;

  AppSettings copyWith({
    bool? isLoaded,
    AppAccent? accent,
    int? customAccentValue,
    String? displayName,
    bool clearDisplayName = false,
  }) {
    return AppSettings(
      isLoaded: isLoaded ?? this.isLoaded,
      accent: accent ?? this.accent,
      customAccentValue: customAccentValue ?? this.customAccentValue,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
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
    state = AppSettings(
      isLoaded: true,
      accent: AppAccent.fromStorage(preferences.getString('theme_accent')),
      customAccentValue: preferences.getInt('theme_custom_color'),
      displayName: storedName == null || storedName.isEmpty ? null : storedName,
    );
  }

  Future<void> setDisplayName(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    state = state.copyWith(displayName: trimmedName);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('display_name', trimmedName);
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
