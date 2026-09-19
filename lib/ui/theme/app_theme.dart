import 'package:flutter/material.dart';

/// Tasarım dili: sade, premium, kurumsal (BRIEF §7).
///
/// Referans, mobilyacı vitrinlerinin sıcak minimalizmi: kâğıt tonunda zemin,
/// ceviz ve pirinç vurgular, ince çizgiler, bol boşluk. Ekran bir tablo
/// değil, düzenli bir tezgâh gibi görünmeli.
///
/// Kurallar:
/// - **Tek vurgu rengi** (ceviz). Pirinç ve adaçayı yalnızca durum belirtir.
/// - Rakamlar **Inter**, tabular figürlerle — sütunlarda kayma olmaz.
/// - Başlıklar ve Günün Sözü **Lora**; serif yalnızca bu iki yerde kullanılır,
///   yoksa ciddiyetini kaybeder.
/// - Dokunma alanı en az 48 dp.
abstract final class AppTheme {
  /// Arayüz fontu. Rakamlar, etiketler, düğmeler.
  static const sansFamily = 'Inter';

  /// Vurgu fontu. Uygulama adı, ekran başlıkları, Günün Sözü.
  static const serifFamily = 'Lora';

  /// Tek vurgu rengi — ceviz. Sıcak, kurumsal, dikkat çalmayan.
  static const accent = Color(0xFF6E5843);

  static const minTouchTarget = 48.0;
  static const radius = 14.0;
  static const tabularFigures = FontFeature.tabularFigures();

  // --------------------------------------------------------------- paletler

  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6E5843),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEFE3D6),
    onPrimaryContainer: Color(0xFF2A1F14),
    secondary: Color(0xFF6B7263),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE4E8DE),
    onSecondaryContainer: Color(0xFF232921),
    tertiary: Color(0xFF9A6C3C),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF6E5CF),
    onTertiaryContainer: Color(0xFF2F1E0A),
    error: Color(0xFF8F3A2C),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF7DDD6),
    onErrorContainer: Color(0xFF3A120C),
    surface: Color(0xFFFBF9F6),
    onSurface: Color(0xFF1F1B16),
    onSurfaceVariant: Color(0xFF6B6155),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F3EE),
    surfaceContainer: Color(0xFFF2EDE6),
    surfaceContainerHigh: Color(0xFFECE5DC),
    surfaceContainerHighest: Color(0xFFE6DED3),
    outline: Color(0xFF9C9082),
    outlineVariant: Color(0xFFE0D7CA),
    inverseSurface: Color(0xFF34302A),
    onInverseSurface: Color(0xFFF6F0E8),
    inversePrimary: Color(0xFFDDBFA1),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFDCBD9B),
    onPrimary: Color(0xFF3A2A1A),
    primaryContainer: Color(0xFF53402D),
    onPrimaryContainer: Color(0xFFF6E3D0),
    secondary: Color(0xFFB9C0AE),
    onSecondary: Color(0xFF2B3227),
    secondaryContainer: Color(0xFF414937),
    onSecondaryContainer: Color(0xFFD6DDCA),
    tertiary: Color(0xFFE2B784),
    onTertiary: Color(0xFF472A0C),
    tertiaryContainer: Color(0xFF6B4620),
    onTertiaryContainer: Color(0xFFFFDDB8),
    error: Color(0xFFF0B0A2),
    onError: Color(0xFF5C1A10),
    errorContainer: Color(0xFF78291C),
    onErrorContainer: Color(0xFFFFDAD2),
    surface: Color(0xFF16130F),
    onSurface: Color(0xFFEFE7DC),
    onSurfaceVariant: Color(0xFFB5A897),
    surfaceContainerLowest: Color(0xFF100E0B),
    surfaceContainerLow: Color(0xFF1C1814),
    surfaceContainer: Color(0xFF211D18),
    surfaceContainerHigh: Color(0xFF2B261F),
    surfaceContainerHighest: Color(0xFF363029),
    outline: Color(0xFF7E7264),
    outlineVariant: Color(0xFF3D372F),
    inverseSurface: Color(0xFFEFE7DC),
    onInverseSurface: Color(0xFF34302A),
    inversePrimary: Color(0xFF6E5843),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData light() => _build(_light);
  static ThemeData dark() => _build(_dark);

  // ------------------------------------------------------------- tipografi

  static TextTheme _textTheme(ColorScheme scheme) {
    // Serif yalnızca display seviyesinde. Başlık büyüdükçe harf aralığı
    // daralır — büyük puntoda geniş aralık dağınık durur.
    TextStyle serif(
      double size, {
      double height = 1.15,
      double spacing = -0.4,
    }) => TextStyle(
      fontFamily: serifFamily,
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );

    TextStyle sans(
      double size, {
      FontWeight weight = FontWeight.w400,
      double height = 1.35,
      double spacing = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: sansFamily,
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      fontWeight: weight,
      color: color ?? scheme.onSurface,
    );

    return TextTheme(
      displayLarge: serif(44),
      displayMedium: serif(36),
      displaySmall: serif(29),
      headlineLarge: serif(26, spacing: -0.3),
      headlineMedium: serif(23, spacing: -0.2),
      headlineSmall: sans(21, weight: FontWeight.w600, spacing: -0.3),
      titleLarge: sans(19, weight: FontWeight.w600, spacing: -0.2),
      titleMedium: sans(16, weight: FontWeight.w500, spacing: -0.1),
      titleSmall: sans(14, weight: FontWeight.w600, spacing: 0.1),
      bodyLarge: sans(16, height: 1.45),
      bodyMedium: sans(14, height: 1.45),
      bodySmall: sans(12.5, height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge: sans(14, weight: FontWeight.w500, spacing: 0.1),
      labelMedium: sans(12, weight: FontWeight.w500, spacing: 0.2),
      // Bölüm başlıklarında kullanılan "eyebrow": küçük, seyrek, büyük harf.
      labelSmall: sans(11, weight: FontWeight.w600, spacing: 0.8),
    );
  }

  // ------------------------------------------------------------------ tema

  static ThemeData _build(ColorScheme scheme) {
    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: sansFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge,
        // Kabuk yerine ince bir çizgi: gölge yok, sınır var.
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius - 2),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius - 2),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 2),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall,
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.primary, width: 1.6),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLow,
        labelStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        titleTextStyle: text.titleLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius + 6)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 3,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius - 2),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Rakam ve vurgu metinleri için ortak stiller.
extension NumericTextStyles on BuildContext {
  /// Tablolarda ve satırlarda okunan rakam.
  TextStyle get numberStyle => Theme.of(this).textTheme.bodyLarge!.copyWith(
    fontFeatures: const [AppTheme.tabularFigures],
    fontWeight: FontWeight.w500,
  );

  /// Kart üstündeki büyük rakam. Negatif harf aralığı puntoyu toparlar.
  TextStyle get bigNumberStyle =>
      Theme.of(this).textTheme.headlineSmall!.copyWith(
        fontFeatures: const [AppTheme.tabularFigures],
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
      );

  TextStyle get labelStyle => Theme.of(this).textTheme.bodySmall!;

  /// Bölüm üstü küçük başlık: BÜYÜK HARF, seyrek aralık.
  TextStyle get eyebrowStyle =>
      Theme.of(this).textTheme.labelSmall!
          .copyWith(color: Theme.of(this).colorScheme.onSurfaceVariant);

  /// Serif vurgu — uygulama adı, Günün Sözü.
  TextStyle get serifStyle => Theme.of(this).textTheme.headlineMedium!;
}
