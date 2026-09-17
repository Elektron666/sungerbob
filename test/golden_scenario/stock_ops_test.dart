import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_ops_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import 'scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

/// ALTIN SENARYO adım 6 ve 7 (docs/GOLDEN_SCENARIO.md).
void main() {
  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  /// Adım 1–3'ü kurar: A ve B partileri, 60 adetlik satış.
  Future<void> setUpThroughStep3() async {
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 1),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: f.v10,
            pieces: 50,
            volume: f.volumeOf('140', '200', '10', 50),
            unitPriceM3: UnitPrice.parse('2930'),
            vatRate: vat20,
          ),
          PurchaseLineInput(
            variantId: f.v5,
            pieces: 40,
            volume: f.volumeOf('140', '200', '5', 40),
            unitPriceM3: UnitPrice.parse('2930'),
            vatRate: vat20,
          ),
        ],
        expenses: const [
          PurchaseExpenseInput(kind: 'NAKLIYE', amount: Money(196000)),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 15),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: f.v10,
            pieces: 30,
            volume: f.volumeOf('140', '200', '10', 30),
            unitPriceM3: UnitPrice.parse('3165'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );
    await SaleRepository(f.db).create(
      SaleInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 17),
        priceMode: PriceMode.excl,
        lines: [
          SaleLineInput(
            variantId: f.v10,
            pieces: 60,
            volume: f.volumeOf('140', '200', '10', 60),
            unitPriceM3: UnitPrice.parse('3500'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('SALE_CREATE'),
    );
  }

  test(
    'adım 6 — sayım: sistem 20, fiziksel 19 → maliyet 886,20 (B partisi)',
    () async {
      await setUpThroughStep3();
      final ops = StockOpsRepository(f.db);

      // Satıştan sonra 140×200×10 → 20 adet kalmış olmalı.
      expect((await f.db.variantStock(f.v10)).pieces, 20);

      final countId = await ops.createDraftCount(
        countDate: DateTime.utc(2026, 9, 26),
        lines: [StockCountLineInput(variantId: f.v10, countedPieces: 19)],
        ctx: ctxFor('STOCK_COUNT_CREATE'),
      );

      // DRAFT iken stok ETKİLENMEZ (SPEC §16).
      expect(
        (await f.db.variantStock(f.v10)).pieces,
        20,
        reason: 'taslak sayım stoğu değiştirmemeli',
      );

      final item = await (f.db.select(
        f.db.stockCountItems,
      )..where((i) => i.stockCountId.equals(countId))).getSingle();
      expect(item.systemPieces, 20);
      expect(item.countedPieces, 19);
      expect(item.diffPieces, -1);
      expect(item.diffVolume, Volume.parse('-0.28'));

      await ops.applyCount(countId: countId, ctx: ctxFor('STOCK_COUNT_APPLY'));

      expect((await f.db.variantStock(f.v10)).pieces, 19);
      final count = await (f.db.select(
        f.db.stockCounts,
      )..where((c) => c.id.equals(countId))).getSingle();
      expect(count.status, 'APPLIED');
      expect(
        count.costEffectTotal,
        Money.parse('-886.20'),
        reason: '0,28 m³ × 3.165 TL/m³ (B partisi)',
      );
    },
  );

  test(
    'adım 7 — fire: 140×200×5 × 2 adet "Hasarlı" → 848,40 (A partisi)',
    () async {
      await setUpThroughStep3();
      final ops = StockOpsRepository(f.db);

      final wasteId = await ops.recordWaste(
        occurredAt: DateTime.utc(2026, 9, 27),
        reasonCode: WasteReason.damaged,
        lines: [WasteLineInput(variantId: f.v5, pieces: 2)],
        ctx: ctxFor('WASTE_CREATE'),
      );

      final waste = await (f.db.select(
        f.db.stockAdjustments,
      )..where((a) => a.id.equals(wasteId))).getSingle();
      expect(
        waste.costTotal,
        Money.parse('848.40'),
        reason: '0,28 m³ × 3.030 TL/m³ (A2 partisi)',
      );
      expect(waste.reasonCode, WasteReason.damaged);

      final stock = await f.db.variantStock(f.v5);
      expect(stock.pieces, 38);
      expect(stock.volume, Volume.parse('5.32'));
    },
  );

  test('adım 6 + 7 sonrası son stok 11,76 m³ / 36.653,40 TL', () async {
    await setUpThroughStep3();

    // Adım 5: Alış C (140×200×8 × 5 adet — DECISIONS SK-06)
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 18),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: f.v8,
            pieces: 5,
            volume: f.volumeOf('140', '200', '8', 5),
            unitPriceM3: UnitPrice.parse('3300'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );

    final ops = StockOpsRepository(f.db);
    final countId = await ops.createDraftCount(
      countDate: DateTime.utc(2026, 9, 26),
      lines: [StockCountLineInput(variantId: f.v10, countedPieces: 19)],
      ctx: ctxFor('STOCK_COUNT_CREATE'),
    );
    await ops.applyCount(countId: countId, ctx: ctxFor('STOCK_COUNT_APPLY'));

    await ops.recordWaste(
      occurredAt: DateTime.utc(2026, 9, 27),
      reasonCode: WasteReason.damaged,
      lines: [WasteLineInput(variantId: f.v5, pieces: 2)],
      ctx: ctxFor('WASTE_CREATE'),
    );

    // GOLDEN_SCENARIO.md adım 7 "Son stok" tablosu
    expect((await f.db.variantStock(f.v10)).pieces, 19);
    expect((await f.db.variantStock(f.v10)).volume, Volume.parse('5.32'));
    expect((await f.db.variantStock(f.v5)).pieces, 38);
    expect((await f.db.variantStock(f.v5)).volume, Volume.parse('5.32'));
    expect((await f.db.variantStock(f.v8)).pieces, 5);
    expect((await f.db.variantStock(f.v8)).volume, Volume.parse('1.12'));

    expect(
      await f.db.stockCostTotal(),
      Money.parse('36653.40'),
      reason: '16.837,80 + 16.119,60 + 3.696,00',
    );
  });

  test('fire nedeni geçersizse reddedilir', () async {
    await setUpThroughStep3();
    await expectLater(
      StockOpsRepository(f.db).recordWaste(
        occurredAt: DateTime.utc(2026, 9, 27),
        reasonCode: 'UYDURMA_NEDEN',
        lines: [WasteLineInput(variantId: f.v5, pieces: 1)],
        ctx: ctxFor('WASTE_CREATE'),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('sayım iki kez uygulanamaz', () async {
    await setUpThroughStep3();
    final ops = StockOpsRepository(f.db);
    final countId = await ops.createDraftCount(
      countDate: DateTime.utc(2026, 9, 26),
      lines: [StockCountLineInput(variantId: f.v10, countedPieces: 19)],
      ctx: ctxFor('STOCK_COUNT_CREATE'),
    );
    await ops.applyCount(countId: countId, ctx: ctxFor('APPLY_1'));
    await expectLater(
      ops.applyCount(countId: countId, ctx: ctxFor('APPLY_2')),
      throwsA(isA<StateError>()),
    );
  });
}
