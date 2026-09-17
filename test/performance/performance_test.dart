@Tags(['performance'])
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/analytics_queries.dart';
import 'package:sungerbob/data/repo/dashboard_queries.dart';
import 'package:sungerbob/data/repo/search_queries.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

/// Performans ölçümü (BRIEF §9 Faz 5).
///
/// "50.000 satış satırıyla ana sayfa ve raporların makul sürede açıldığını
/// ölç ve DECISIONS.md'ye yaz."
///
/// Veriyi repository üzerinden üretmek çok yavaş olurdu; burada doğrudan
/// toplu INSERT kullanılıyor. Amaç iş kurallarını değil **sorgu
/// performansını** ölçmek.
void main() {
  test('50.000 satış satırıyla ana sayfa ve raporlar', () async {
    final f = await ScenarioFixture.create();
    final sw = Stopwatch();

    try {
      const saleCount = 5000;
      const linesPerSale = 10; // 50.000 satır

      final mainLocation = await f.db.locationId(LocationCode.mainWarehouse);

      sw.start();
      await f.db.batch((b) {
        // Tek parti: tüm satışların maliyeti buradan gelmiş sayılır.
        b.insert(
          f.db.inventoryBatches,
          InventoryBatchesCompanion.insert(
            id: 'perf-batch',
            variantId: f.v10,
            locationId: mainLocation,
            sourceType: BatchSourceType.purchase,
            receivedAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
            bareUnitCostM3: UnitPrice.parse('3000'),
            realUnitCostM3: UnitPrice.parse('3000'),
            inPieces: saleCount * linesPerSale,
            inVolume: Volume.parse('100000'),
            remainingPieces: saleCount * linesPerSale,
            remainingVolume: Volume.parse('100000'),
            createdAt: 0,
          ),
        );
      });
      sw.stop();

      // --- 50.000 satış satırı üret --------------------------------
      sw
        ..reset()
        ..start();
      for (var chunk = 0; chunk < saleCount ~/ 500; chunk++) {
        await f.db.batch((b) {
          for (var i = 0; i < 500; i++) {
            final index = chunk * 500 + i;
            final saleId = 'perf-sale-$index';
            final date = DateTime.utc(
              2026,
              1 + (index % 12),
              1 + (index % 28),
            ).millisecondsSinceEpoch;

            b.insert(
              f.db.sales,
              SalesCompanion.insert(
                id: saleId,
                docNo: 'STS-PERF-$index',
                customerId: f.customerId,
                docDate: date,
                priceMode: PriceMode.excl,
                subtotalNet: Money.parse('9800'),
                vatTotal: Money.parse('1960'),
                grandTotal: Money.parse('11760'),
                costTotal: Money.parse('8400'),
                createdAt: date,
              ),
            );

            for (var line = 0; line < linesPerSale; line++) {
              b.insert(
                f.db.saleItems,
                SaleItemsCompanion.insert(
                  id: 'perf-item-$index-$line',
                  saleId: saleId,
                  lineNo: line + 1,
                  variantId: f.v10,
                  pieces: 1,
                  volume: Volume.parse('0.28'),
                  listPriceM3: UnitPrice.parse('3500'),
                  unitPriceM3: UnitPrice.parse('3500'),
                  netTotal: Money.parse('980'),
                  vatRate: Rate.percent('20'),
                  vatTotal: Money.parse('196'),
                  grossTotal: Money.parse('1176'),
                  costTotal: Money.parse('840'),
                ),
              );
            }

            b.insert(
              f.db.customerLedger,
              CustomerLedgerCompanion.insert(
                id: 'perf-ledger-$index',
                customerId: f.customerId,
                occurredAt: date,
                docType: LedgerDocType.sale,
                docId: Value(saleId),
                amount: Money.parse('11760'),
                createdAt: date,
              ),
            );
          }
        });
      }
      sw.stop();
      final seedMs = sw.elapsedMilliseconds;

      final itemCount = await f.db
          .customSelect('SELECT COUNT(*) AS c FROM sale_items')
          .getSingle()
          .then((r) => r.read<int>('c'));
      expect(itemCount, saleCount * linesPerSale);

      // --- Ölçümler -------------------------------------------------
      final results = <String, int>{};

      Future<void> measure(String name, Future<void> Function() action) async {
        sw
          ..reset()
          ..start();
        await action();
        sw.stop();
        results[name] = sw.elapsedMilliseconds;
      }

      await measure(
        'Ana sayfa (12 kart)',
        () => f.db.dashboardSnapshot(now: DateTime.utc(2026, 12, 31)),
      );
      await measure('Cari bakiye', () => f.db.customerBalance(f.customerId));
      await measure(
        'Müşteri analizi',
        () => f.db.customerAnalysis(f.customerId),
      );
      await measure('Ürün analizi', () => f.db.productAnalysis());
      await measure(
        'Kârlılık raporu (yıllık)',
        () => f.db.profitability(
          from: DateTime.utc(2026),
          to: DateTime.utc(2026, 12, 31),
        ),
      );
      await measure(
        'Aylık satış raporu',
        () => f.db.salesByPeriod(
          from: DateTime.utc(2026),
          to: DateTime.utc(2026, 12, 31),
        ),
      );
      await measure('Global arama', () => f.db.globalSearch('ABC'));
      await measure('Stok sorgusu', () => f.db.variantStock(f.v10));

      // ignore: avoid_print
      print('\n=== PERFORMANS: ${saleCount * linesPerSale} satış satırı ===');
      // ignore: avoid_print
      print('Veri üretimi: ${seedMs}ms');
      for (final e in results.entries) {
        // ignore: avoid_print
        print('${e.key.padRight(28)} ${e.value}ms');
      }

      // Kabul eşiği: hiçbir ekran 2 saniyeden uzun sürmemeli.
      for (final e in results.entries) {
        expect(
          e.value,
          lessThan(2000),
          reason: '${e.key} çok yavaş: ${e.value}ms',
        );
      }
    } finally {
      await f.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
