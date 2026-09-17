import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';

/// Dönemsel ciro ve brüt kâr grafiği (SPEC §25).
///
/// Grafik yalnızca **gösterim** içindir; eksen ölçeklemesi için `double`
/// kullanılır. Rakamların kendisi `Money` olarak gelir ve etiketlerde
/// biçimlendirilerek basılır — hesap yapılmaz (BRIEF §2).
class PeriodSalesChart extends StatelessWidget {
  final List<({DateTime period, Money net, Money profit, int count})> rows;
  final String granularity;
  final bool showProfit;

  const PeriodSalesChart({
    super.key,
    required this.rows,
    required this.granularity,
    this.showProfit = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = rows
        .map((r) => r.net.tl.toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);
    // Üst boşluk bırak ki en yüksek çubuk tavana yapışmasın.
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.2;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: scheme.primary, label: 'Ciro'),
            if (showProfit) ...[
              const SizedBox(width: 16),
              _Legend(color: scheme.tertiary, label: 'Brüt kâr'),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final row = rows[group.x];
                    return BarTooltipItem(
                      '${_label(row.period)}\n'
                      '${TrFormat.moneyWithCurrency(rodIndex == 0 ? row.net : row.profit)}',
                      TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (value, meta) => Text(
                      _compact(value),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= rows.length) return const SizedBox();
                      // Çok nokta varsa etiketleri seyrelt.
                      final step = (rows.length / 6).ceil();
                      if (step > 1 && i % step != 0) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortLabel(rows[i].period),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < rows.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: rows[i].net.tl.toDouble(),
                        color: scheme.primary,
                        width: showProfit ? 8 : 14,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      if (showProfit)
                        BarChartRodData(
                          // Zarar çubuğu görünmesin diye tabana sabitlenir.
                          toY: rows[i].profit.tl.toDouble().clamp(0, maxY),
                          color: scheme.tertiary,
                          width: 8,
                          borderRadius: BorderRadius.circular(3),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _label(DateTime period) => granularity == 'month'
      ? TrFormat.monthYear(period)
      : TrFormat.date(period);

  String _shortLabel(DateTime period) => granularity == 'month'
      ? '${period.month.toString().padLeft(2, '0')}.${period.year % 100}'
      : '${period.day.toString().padLeft(2, '0')}.${period.month.toString().padLeft(2, '0')}';

  /// Eksen etiketi: 1.250.000 → "1,25 M".
  static String _compact(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2).replaceAll('.', ',')} M';
    }
    if (value >= 1000) return '${(value / 1000).round()} B';
    return value.round().toString();
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
