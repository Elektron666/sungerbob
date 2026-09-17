import 'package:flutter/material.dart';

/// Tasarım dili: sade, premium, kurumsal (BRIEF §7).
///
/// Material 3, nötr tonlar, **tek vurgu rengi**. Rakamlar tabular (sütunlarda
/// hizalansın diye). Dokunma alanları en az 48 dp.
abstract final class AppTheme {
  /// Tek vurgu rengi — derin teal. Kurumsal, dikkat çekmeyen.
  static const accent = Color(0xFF00695C);

  static const minTouchTarget = 48.0;

  /// Rakamların sütunlarda hizalanması için tabular figür özelliği.
  static const tabularFigures = FontFeature.tabularFigures();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 1,
        backgroundColor: scheme.surface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Rakam gösterimi için ortak metin stilleri.
extension NumericTextStyles on BuildContext {
  TextStyle get numberStyle =>
      Theme.of(this).textTheme.bodyLarge!
          .copyWith(fontFeatures: const [AppTheme.tabularFigures]);

  TextStyle get bigNumberStyle => Theme.of(this).textTheme.headlineSmall!
      .copyWith(
        fontFeatures: const [AppTheme.tabularFigures],
        fontWeight: FontWeight.w600,
      );

  TextStyle get labelStyle =>
      Theme.of(this).textTheme.bodySmall!
          .copyWith(color: Theme.of(this).colorScheme.onSurfaceVariant);
}
