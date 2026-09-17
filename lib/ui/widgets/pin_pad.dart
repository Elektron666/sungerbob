import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Sayısal PIN tuş takımı (BRIEF §7 — dokunma alanı en az 48 dp).
class PinPad extends StatelessWidget {
  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCompleted;
  final String? errorText;
  final String title;
  final String? subtitle;
  final Widget? footer;

  const PinPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.length = 4,
    this.onCompleted,
    this.errorText,
    required this.title,
    this.subtitle,
    this.footer,
  });

  void _press(String digit) {
    if (value.length >= length) return;
    final next = value + digit;
    HapticFeedback.selectionClick();
    onChanged(next);
    if (next.length == length) onCompleted?.call();
  }

  void _backspace() {
    if (value.isEmpty) return;
    HapticFeedback.selectionClick();
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: context.labelStyle,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
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
          height: 40,
          child: errorText == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    errorText!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final key in row) _key(context, key)],
          ),
        if (footer != null) ...[const SizedBox(height: 16), footer!],
      ],
    );
  }

  Widget _key(BuildContext context, String key) {
    if (key.isEmpty) return const SizedBox(width: 88, height: 72);

    return SizedBox(
      width: 88,
      height: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: key == '<' ? _backspace : () => _press(key),
        child: Center(
          child: key == '<'
              ? const Icon(Icons.backspace_outlined)
              : Text(key, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ),
    );
  }
}
