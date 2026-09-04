// lib/core/theme/app_theme.dart
//
// Sistema de diseño centralizado de MuShare. Define la paleta de colores,
// la tipografía y los estilos de componentes reutilizables. Cambiar el
// "look" de toda la app se hace editando SOLO este archivo.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Fondo casi negro, no negro puro: se ve menos "duro" en pantallas OLED
  // y da mejor contraste con las portadas de álbumes.
  static const background = Color(0xFF0B0B0F);
  static const surface = Color(0xFF17171D);
  static const surfaceElevated = Color(0xFF1F1F27);

  // Acento principal: violeta vibrante, la identidad de marca de MuShare.
  static const primary = Color(0xFFB24BF3);
  static const primaryMuted = Color(0xFF7C3AED);

  // Acento secundario: ámbar cálido, reservado para el estado
  // "reproduciendo ahora" y elementos de energía/actividad.
  static const accent = Color(0xFFFFB84D);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFF9A9AA5);
  static const divider = Color(0xFF2A2A33);

  static const error = Color(0xFFFF6B6B);

  // Gradiente usado en el fondo del mini-reproductor y en portadas
  // sin imagen, para que nunca se vea un bloque de color plano y aburrido.
  static const artworkFallbackGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryMuted, Color(0xFF3B1E6B)],
  );
}

class AppTheme {
  AppTheme._();

  /// Gradiente unificado para todas las superficies que representan el tema
  /// elegido por el usuario (portadas sin imagen, Favoritas y destacados).
  static LinearGradient primaryGradient(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [primary, primary.withValues(alpha: .55)],
    );
  }

  static ThemeData dark([Color primaryColor = AppColors.primary]) {
    final baseTextTheme =
        GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,

      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),

      // Inter para texto de cuerpo (listas, subtítulos): es muy legible
      // en tamaños pequeños, ideal para nombres de canciones/artistas.
      textTheme: baseTextTheme.copyWith(
        // Poppins para títulos grandes: le da más personalidad a la marca
        // sin sacrificar legibilidad en encabezados de sección.
        headlineLarge: GoogleFonts.poppins(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: AppColors.divider,
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.15),
        trackHeight: 3,
      ),

      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    );
  }
}
