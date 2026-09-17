import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/cutting_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/costing/costing_engine.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import 'scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

/// ALTIN SENARYO Ek C — Fason kesim (docs/GOLDEN_SCENARIO.md).
void main() {
  late ScenarioFixture f;
  late String blockVariantId;
  late String target140;
  late String target60;
  late String cutterId;

  setUp(() async {
    f = await ScenarioFixture.create();

    Future<String> variant(String w, String h, String t, String kind) async {
      final id = uuid.v7();
      await f.db
          .into(f.db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: id,
              productId: f.beyazProductId,
              width: Dimension.cm(w),
              height: Dimension.cm(h),
              thickness: Dimension.cm(t),
              kind: kind,
              unitVolume: Volume.fromDimensions(
                width: Dimension.cm(w),
                height: Dimension.cm(h),
                thickness: Dimension.cm(t),
                pieces: 1,
              ),
            ),
          );
      return id;
    }

    blockVariantId = await variant('200', '200', '100', VariantKind.block);
    // 140×200×10 fixture'da zaten var; artık parça ölçüsü yeni.
    target140 = f.v10;
    target60 = await variant('60', '200', '10', VariantKind.plate);

    cutterId = uuid.v7();
    await f.db
        .into(f.db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: cutterId,
            code: 'KESIM1',
            title: 'Kesimhane',
            titleNormalized: 'kesimhane',
            type: SupplierType.cutter,
          ),
        );
  });

  tearDown(() async => f.close());

  test('Ek C — blok kesimi: 12.600,00 / 3,6 m³ = 3.500,0000 TL/m³', () async {
    // Alış: Beyaz blok 200×200×100 × 2 = 8 m³, 2.900 TL/m³ → 23.200,00
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 1),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: blockVariantId,
            pieces: 2,
            volume: Volume.parse('8'),
            unitPriceM3: UnitPrice.parse('2900'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );

    expect(await f.db.stockCostTotal(), Money.parse('23200'));

    final sourceBatch = (await f.db.select(f.db.inventoryBatches).get()).single;

    // Kesime gönder: 1 blok (4 m³, 11.600,00)
    final orderId = await CuttingRepository(f.db).sendToCutting(
      cutterSupplierId: cutterId,
      sentDate: DateTime.utc(2026, 9, 5),
      sources: [CuttingSourceInput(batchId: sourceBatch.id, pieces: 1)],
      ctx: ctxFor('CUTTING_SEND'),
    );

    // Ana depo 1 blok / 4 m³, "Kesimde" 1 blok / 4 m³
    final mainStock = await f.db.variantStock(blockVariantId);
    expect(mainStock.pieces, 1);
    expect(mainStock.volume, Volume.parse('4'));

    final cuttingStock = await f.db.variantStock(
      blockVariantId,
      locationCode: LocationCode.cutting,
    );
    expect(cuttingStock.pieces, 1);
    expect(cuttingStock.volume, Volume.parse('4'));
    expect(
      await f.db.stockCostTotal(locationCode: LocationCode.cutting),
      Money.parse('11600'),
    );

    // Dönüş: 140×200×10 × 9 (2,52 m³) + 60×200×10 × 9 (1,08 m³) = 3,6 m³
    // Kesim ücreti 1.000,00 (KDV hariç)
    await CuttingRepository(f.db).receiveFromCutting(
      orderId: orderId,
      returnedAt: DateTime.utc(2026, 9, 10),
      results: [
        CuttingResultInput(variantId: target140, pieces: 9),
        CuttingResultInput(variantId: target60, pieces: 9, isRemnant: true),
      ],
      cuttingFeeNet: Money.parse('1000'),
      ctx: ctxFor('CUTTING_RECEIVE'),
    );

    final order = await (f.db.select(
      f.db.cuttingOrders,
    )..where((o) => o.id.equals(orderId))).getSingle();

    // Beklenen: toplam maliyet 12.600,00 → 3.500,0000 TL/m³
    final results = await (f.db.select(
      f.db.cuttingOrderResults,
    )..where((r) => r.cuttingOrderId.equals(orderId))).get();
    final r140 = results.firstWhere((r) => r.variantId == target140);
    final r60 = results.firstWhere((r) => r.variantId == target60);

    expect(r140.volume, Volume.parse('2.52'));
    expect(r140.allocatedCost, Money.parse('8820'));
    expect(r60.volume, Volume.parse('1.08'));
    expect(r60.allocatedCost, Money.parse('3780'));
    expect(
      sumMoney([r140.allocatedCost, r60.allocatedCost]),
      Money.parse('12600'),
    );

    // Kesim firesi 0,4 m³
    expect(order.wasteVolume, Volume.parse('0.4'));

    // Kesimhane carisi +1.200,00 (1.000 + %20 KDV)
    expect(await f.db.supplierBalance(cutterId), Money.parse('1200'));

    // "Kesimde" boş, emir Tamamlandı
    final cuttingAfter = await f.db.variantStock(
      blockVariantId,
      locationCode: LocationCode.cutting,
    );
    expect(cuttingAfter.pieces, 0);
    expect(order.status, CuttingStatus.completed);
  });

  test('hedef m³ kaynağı aşamaz', () async {
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 1),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: blockVariantId,
            pieces: 2,
            volume: Volume.parse('8'),
            unitPriceM3: UnitPrice.parse('2900'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );
    final sourceBatch = (await f.db.select(f.db.inventoryBatches).get()).first;
    final orderId = await CuttingRepository(f.db).sendToCutting(
      cutterSupplierId: cutterId,
      sentDate: DateTime.utc(2026, 9, 5),
      sources: [CuttingSourceInput(batchId: sourceBatch.id, pieces: 1)],
      ctx: ctxFor('CUTTING_SEND'),
    );

    // 4 m³ kaynaktan 20 adet 140×200×10 (5,6 m³) çıkamaz.
    await expectLater(
      CuttingRepository(f.db).receiveFromCutting(
        orderId: orderId,
        returnedAt: DateTime.utc(2026, 9, 10),
        results: [CuttingResultInput(variantId: target140, pieces: 20)],
        ctx: ctxFor('CUTTING_RECEIVE'),
      ),
      throwsA(isA<CuttingVolumeException>()),
    );
  });

  test('kesimdeki mal satılamaz — FIFO taramasına girmez', () async {
    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 1),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: blockVariantId,
            pieces: 2,
            volume: Volume.parse('8'),
            unitPriceM3: UnitPrice.parse('2900'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );
    final sourceBatch = (await f.db.select(f.db.inventoryBatches).get()).first;
    await CuttingRepository(f.db).sendToCutting(
      cutterSupplierId: cutterId,
      sentDate: DateTime.utc(2026, 9, 5),
      sources: [CuttingSourceInput(batchId: sourceBatch.id, pieces: 1)],
      ctx: ctxFor('CUTTING_SEND'),
    );

    // Ana depoda 1 blok kaldı; 2 blok satılmaya çalışılırsa reddedilmeli.
    final batches = await f.db.batchesForVariant(blockVariantId);
    expect(
      batches.fold(0, (s, b) => s + b.remainingPieces),
      1,
      reason: 'kesimdeki parti ana depo FIFO listesinde görünmemeli',
    );
  });
}
