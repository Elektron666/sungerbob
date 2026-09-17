import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Sayısal PIN tuş takımı (BRIEF §7 — dokunma alanı en az 48 dp).
///
/// **Basış biriktirme burada YAPILMAZ.** Widget yalnızca hangi tuşa
/// basıldığını bildirir; yeni değeri çağıran taraf kendi güncel durumundan
/// hesaplar.
///
/// Neden: bu widget durumsuz. Kullanıcı hızlı bastığında iki dokunuş arasında
/// kare çizilmeyebilir ve widget hâlâ **bayat** bir `value` taşır. Yeni değer
/// `value + digit` ile hesaplanırsa o basışlar sessizce kaybolur veya yanlış
/// alana yazılır — PIN ekranı kilitlenir.
class PinPad extends StatelessWidget {
  /// Standart PIN uzunluğu.
  static const pinLength = 4;

  final int length;

  /// Şu ana kadar girilmiş hane sayısı kadar nokta dolu gösterilir.
  final String value;

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final String? errorText;
  final String title;
  final String? subtitle;
  final Widget? footer;

  const PinPad({
    super.key,
    required this.value,
    required this.onDigit,
    required this.onBackspace,
    this.length = pinLength,
    this.errorText,
    required this.title,
    this.subtitle,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Yatay veya küçük ekranda tuş takımı ekrana sığmalı; sığmazsa 0 ve geri
    // silme tuşu katlanır ve kullanıcı ne 0'lı PIN girebilir ne de yanlışını
    // düzeltebilir.
    final compact = MediaQuery.sizeOf(context).height < 640;
    final keyHeight = compact ? 52.0 : 72.0;
    final keyWidth = compact ? 76.0 : 88.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: compact
              ? Theme.of(context).textTheme.titleMedium
              : Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: context.labelStyle,
            textAlign: TextAlign.center,
          ),
        ],
        SizedBox(height: compact ? 12 : 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < value.length
                      ? (errorText != null ? scheme.error : scheme.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: errorText != null
                        ? scheme.error
                        : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: compact ? 26 : 36,
          child: errorText == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    errorText!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in row)
                _key(context, key, width: keyWidth, height: keyHeight),
            ],
          ),
        if (footer != null) ...[SizedBox(height: compact ? 8 : 16), footer!],
      ],
    );
  }

  Widget _key(
    BuildContext context,
    String key, {
    required double width,
    required double height,
  }) {
    if (key.isEmpty) return SizedBox(width: width, height: height);

    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          if (key == '<') {
            onBackspace();
          } else {
            onDigit(key);
          }
        },
        child: Center(
          child: key == '<'
              ? const Icon(Icons.backspace_outlined)
              : Text(key, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ),
    );
  }
}
