import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/documents/csv_export.dart';
import '../../../data/repo/analytics_queries.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';

/// Rapor dışa aktarma (SPEC §25). Excel doğrudan açar.
///
/// Sayılar Türkçe biçimde (virgül ondalık) yazılır; ayraç noktalı virgüldür.

Future<void> shareProfitabilityCsv(
  BuildContext context, {
  required ProfitabilityReport report,
  required DateTimeRange range,
}) => _share(
  context,
  fileName: 'karlilik_${_stamp(range.start)}_${_stamp(range.end)}.csv',
  csv: CsvExport.build(
    headers: const ['Kalem', 'Tutar (TL)'],
    rows: [
      ['Ciro (KDV hariç)', TrFormat.money(report.revenue)],
      ['Satılan malın maliyeti', TrFormat.money(report.costOfGoods)],
      ['Brüt kâr', TrFormat.money(report.grossProfit)],
      ['İadeler', TrFormat.money(report.returns)],
      ['Fire', TrFormat.money(report.waste)],
      ['Maliyet farkları', TrFormat.money(report.costAdjustments)],
      ['Giderler', TrFormat.money(report.expenses)],
      ['Net kâr', TrFormat.money(report.netProfit)],
    ],
  ),
);

Future<void> sharePeriodSalesCsv(
  BuildContext context, {
  required List<({DateTime period, Money net, Money profit, int count})> rows,
  required String granularity,
}) => _share(
  context,
  fileName: 'donemsel_satis.csv',
  csv: CsvExport.build(
    headers: const ['Dönem', 'Satış adedi', 'Ciro (TL)', 'Brüt kâr (TL)'],
    rows: [
      for (final r in rows)
        [
          granularity == 'month'
              ? TrFormat.monthYear(r.period)
              : TrFormat.date(r.period),
          '${r.count}',
          TrFormat.money(r.net),
          TrFormat.money(r.profit),
        ],
    ],
  ),
);

Future<void> shareProductAnalysisCsv(
  BuildContext context, {
  required List<ProductAnalysis> rows,
}) => _share(
  context,
  fileName: 'urun_analizi.csv',
  csv: CsvExport.build(
    headers: const [
      'Ürün',
      'Alınan (m³)',
      'Satılan (m³)',
      'Stok (m³)',
      'Stok (adet)',
      'Ort. maliyet (TL/m³)',
      'Ort. satış (TL/m³)',
      'Ciro (TL)',
      'Brüt kâr (TL)',
    ],
    rows: [
      for (final r in rows)
        [
          r.name,
          TrFormat.volumeBare(r.purchasedVolume),
          TrFormat.volumeBare(r.soldVolume),
          TrFormat.volumeBare(r.currentVolume),
          '${r.currentPieces}',
          TrFormat.unitPrice(r.averageCost),
          TrFormat.unitPrice(r.averageSalePrice),
          TrFormat.money(r.revenue),
          TrFormat.money(r.grossProfit),
        ],
    ],
  ),
);

Future<void> _share(
  BuildContext context, {
  required String fileName,
  required String csv,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(csv);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e')));
  }
}

String _stamp(DateTime value) =>
    '${value.year}${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}';
