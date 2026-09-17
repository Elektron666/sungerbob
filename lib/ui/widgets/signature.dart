import 'package:flutter/material.dart';

import '../content/daily_quote.dart';
import '../theme/app_theme.dart';

/// **Günün Sözü** — uygulamanın imza öğesi.
///
/// Ana sayfanın üstünde, rakamlardan önce durur: kullanıcı güne sayılarla
/// değil, bir cümleyle başlar. Serif tipografi ve kâğıt tonundaki zemin
/// burada bilerek kullanılır; ekranın geri kalanından ayrı bir "nefes".
class DailyQuoteCard extends StatelessWidget {
  final DateTime? now;

  const DailyQuoteCard({super.key, this.now});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = now ?? DateTime.now();
    final quote = DailyQuote.of(today);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // İnce pirinç çizgi — başlığı taşıyan tek süs öğesi.
              Container(width: 18, height: 1.5, color: scheme.tertiary),
              const SizedBox(width: 8),
              Text('GÜNÜN SÖZÜ', style: context.eyebrowStyle),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            quote.text,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(height: 1.35, color: scheme.onSurface),
          ),
          const SizedBox(height: 12),
          Text('— ${quote.source}', style: context.labelStyle),
        ],
      ),
    );
  }
}

/// Ana sayfanın karşılama satırı: selam + tarih.
class GreetingHeader extends StatelessWidget {
  final String? userName;
  final DateTime? now;

  const GreetingHeader({super.key, this.userName, this.now});

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final name = userName?.trim();
    final greeting = greetingFor(today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null || name.isEmpty ? greeting : '$greeting, $name',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 4),
        Text(_longDate(today), style: context.labelStyle),
      ],
    );
  }

  static const _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  static const _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static String _longDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}, ${_days[d.weekday - 1]}';
}

/// Tasarım imzası. Ana sayfanın en altında ve Ayarlar → Hakkında'da durur.
///
/// Sessiz olmalı: göz onu ararsa bulur, aramazsa rahatsız etmez.
class DesignSignature extends StatelessWidget {
  /// Uygulamayı tasarlayan.
  static const designer = 'Fatih Özdemir';

  final bool centered;

  const DesignSignature({super.key, this.centered = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Divider(color: scheme.outlineVariant, thickness: 1),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Tasarım  '),
                TextSpan(
                  text: designer,
                  style: TextStyle(
                    fontFamily: AppTheme.serifFamily,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: context.eyebrowStyle.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
