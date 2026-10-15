import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Boje aplikacije: tamnoplava podloga i mesing za ulazne ekrane i zaglavlja,
/// svijetla neutralna podloga za rad.
abstract final class SankoColors {
  static const navy = Color(0xFF0F1B33);

  /// Izdignuta površina na tamnoj podlozi.
  static const navyRaised = Color(0xFF1B2A4A);
  static const brass = Color(0xFFC9A45C);
  static const paper = Color(0xFFF3F5F8);
  static const line = Color(0xFFE1E5EC);
  static const ink = Color(0xFF131A26);
  static const muted = Color(0xFF5F6878);

  /// Stanja slanja na tamnoj podlozi.
  static const ok = Color(0xFF6FCF97);
  static const waiting = Color(0xFFF2B84B);
  static const failed = Color(0xFFFF8A80);
}

/// Brojevi iste širine, da se količine i iznosi ne pomjeraju dok se mijenjaju.
const tabularFigures = [FontFeature.tabularFigures()];

ThemeData sankoTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: SankoColors.navy).copyWith(
    primary: SankoColors.navy,
    onPrimary: Colors.white,
    secondary: SankoColors.brass,
    surface: Colors.white,
    onSurface: SankoColors.ink,
    onSurfaceVariant: SankoColors.muted,
    outlineVariant: SankoColors.line,
  );
  final button = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  // Stil dugmeta zamjenjuje podrazumijevani, pa mora ponijeti i font platforme.
  final buttonText = Typography.material2021(platform: defaultTargetPlatform)
      .black
      .labelLarge!
      .copyWith(
        fontFamily: 'Manrope',
        fontSize: 17,
        fontWeight: FontWeight.w700,
      );
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: SankoColors.line),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    colorScheme: scheme,
    scaffoldBackgroundColor: SankoColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: SankoColors.paper,
      foregroundColor: SankoColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: button, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: button,
        side: const BorderSide(color: SankoColors.line),
        foregroundColor: SankoColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: SankoColors.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      // Na telefonu dijalog zauzima skoro cijelu širinu ekrana.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: const BorderSide(color: SankoColors.navy, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: SankoColors.line, space: 1),
  );
}
