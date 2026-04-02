import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JarsColors {
  static const background = Color(0xFF08080E);
  static const surface = Color(0xFF111118);
  static const surfaceRaised = Color(0xFF1A1A26);
  static const border = Color(0xFF252535);
  static const primary = Color(0xFF7C6FFF);
  static const primaryDim = Color(0x257C6FFF);
  static const gold = Color(0xFFFFB800);
  static const goldDim = Color(0x20FFB800);
  static const green = Color(0xFF1ED97A);
  static const red = Color(0xFFFF3D55);
  static const textPrimary = Color(0xFFEEEEFF);
  static const textSecondary = Color(0xFF6B6B8A);
  static const textTertiary = Color(0xFF3D3D55);
}

class JarsSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class JarsRadius {
  static const double card = 16;
  static const double button = 9999;
  static const double sheet = 24;
  static const double sm = 8;
  static const double md = 12;
}

class JarsTheme {
  static TextTheme get _textTheme {
    final headlineFont = GoogleFonts.spaceGrotesk();
    final bodyFont = GoogleFonts.inter();
    final monoFont = GoogleFonts.spaceMono();

    return TextTheme(
      displayLarge: headlineFont.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: JarsColors.textPrimary,
      ),
      displayMedium: headlineFont.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: JarsColors.textPrimary,
      ),
      displaySmall: headlineFont.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: JarsColors.textPrimary,
      ),
      headlineLarge: headlineFont.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: JarsColors.textPrimary,
      ),
      headlineMedium: headlineFont.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: JarsColors.textPrimary,
      ),
      headlineSmall: headlineFont.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: JarsColors.textPrimary,
      ),
      titleLarge: bodyFont.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: JarsColors.textPrimary,
      ),
      titleMedium: bodyFont.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: JarsColors.textPrimary,
      ),
      titleSmall: bodyFont.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: JarsColors.textPrimary,
      ),
      bodyLarge: bodyFont.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: JarsColors.textPrimary,
      ),
      bodyMedium: bodyFont.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: JarsColors.textSecondary,
      ),
      bodySmall: bodyFont.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: JarsColors.textSecondary,
      ),
      labelLarge: monoFont.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: JarsColors.gold,
      ),
      labelMedium: monoFont.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: JarsColors.textPrimary,
      ),
      labelSmall: monoFont.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: JarsColors.textSecondary,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: JarsColors.background,
      textTheme: _textTheme,
      colorScheme: const ColorScheme.dark(
        surface: JarsColors.background,
        primary: JarsColors.primary,
        secondary: JarsColors.gold,
        error: JarsColors.red,
        onSurface: JarsColors.textPrimary,
        onPrimary: Colors.white,
        outline: JarsColors.border,
      ),
      cardTheme: CardThemeData(
        color: JarsColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JarsRadius.card),
          side: const BorderSide(color: JarsColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return JarsColors.surface;
            }
            return JarsColors.primary;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return JarsColors.textTertiary;
            }
            return Colors.white;
          }),
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JarsRadius.button),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          shadowColor: WidgetStateProperty.all(
            JarsColors.primary.withValues(alpha: 0.45),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: JarsColors.textPrimary,
          side: const BorderSide(color: JarsColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JarsRadius.button),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JarsColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JarsRadius.card),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JarsRadius.card),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JarsRadius.card),
          borderSide: const BorderSide(color: JarsColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: GoogleFonts.inter(
          color: JarsColors.textTertiary,
          fontSize: 16,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: JarsColors.background,
        selectedItemColor: JarsColors.primary,
        unselectedItemColor: JarsColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: JarsColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: JarsColors.textPrimary,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: JarsColors.border,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: JarsColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(JarsRadius.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: JarsColors.surface,
        contentTextStyle: GoogleFonts.inter(
          color: JarsColors.textPrimary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JarsRadius.card),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
