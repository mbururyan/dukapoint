import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens from the wireframes. Every screen pulls from here,
/// so a rebrand for a client is a one-file change.
class AppColors {
  static const primary = Color(0xFF6D28D9); // plum
  static const primaryTint = Color(0x1F6D28D9); // primary at ~12%, nav indicator
  static const accent = Color(0xFFF59E0B); // amber: highlights, never body text on white
  static const ink = Color(0xFF111827);
  static const inkSoft = Color(0xFF4B5563);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF5F3FF); // faint plum tint for cards/panels
  static const border = Color(0xFFD1D5DB);
  static const borderStrong = Color(0xFF6B7280);
  static const success = Color(0xFF166534);
  static const successBg = Color(0xFFDCFCE7);
  static const warning = Color(0xFF78350F);
  static const warningBg = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB42318);
  // Chart colours for the payment split. Neither uses plum, so a chart
  // segment is never mistaken for a button; M-Pesa green is what people expect.
  static const cash = Color(0xFFF59E0B);
  static const mpesa = Color(0xFF15803D);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.borderStrong, width: 1.5),
    );

    return base.copyWith(
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryTint,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.inkSoft,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.primary : AppColors.inkSoft);
        }),
      ),
    );
  }

  /// Money, barcodes and receipt numbers use mono so digits line up in columns.
  static TextStyle mono({double size = 16, FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: weight, color: color ?? AppColors.ink);
}