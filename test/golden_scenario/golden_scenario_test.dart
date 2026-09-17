import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/instrument_repository.dart';
import 'package:sungerbob/data/repo/integrity_service.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/return_repository.dart';
import 'package:sungerbob/data/repo/reversal_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import 'scenario_fixture.dart';

final vat20 = Rate.percent('20');

OperationContext ctxFor(String type) => OperationContext(commandType: type);

void main() {
  group('ALTIN SENARYO — FIFO, KDV %20, KDV Hariç', () {
    late ScenarioFixture f;

    setUp(() async => f = await ScenarioFixture.create());
    tearDown(() async => f.close());

    test('adım 1–5, 8–10, 12 uçtan uca', () async {
      final purchases = PurchaseRepository(f.db);
      final sales = SaleRepository(f.db);
      final collections = CollectionRepository(f.db);
      final returns = ReturnRepository(f.db);
      final reversals = ReversalRepository(f.db);
      final instruments = InstrumentRepository(f.db);

      // ---------------------------------------------------------------
      // ADIM 1 — Alış A (01.09.2026), 2.930 TL/m³, nakliye 1.960,00
      // Beklenen: gerçek maliyet 3.030,0000 TL/m³, toplam 59.388,00
      // ---------------------------------------------------------------
      await purchases.create(
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

      final batchesAfterA = await f.db.select(f.db.inventoryBatches).get();
      expect(batchesAfterA.length, 2);
      for (final b in batchesAfterA) {
        expect(
          b.realUnitCostM3,
          UnitPrice.parse('3030'),
          reason: 'nakliye dağıtıldıktan sonra gerçek maliyet 3.030,0000',
        );
        expect(
          b.bareUnitCostM3,
          UnitPrice.parse('2930'),
          reason: 'çıplak fabrika fiyatı ayrı saklanır (SPEC §4)',
        );
      }
      expect(await f.db.stockCostTotal(), Money.parse('59388'));

      // ---------------------------------------------------------------
      // ADIM 2 — Alış B (15.09.2026), 3.165 TL/m³ → 26.586,00
      // ---------------------------------------------------------------
      await purchases.create(
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
      expect(
        await f.db.stockCostTotal(),
        Money.parse('85974'),
      ); // 59.388 + 26.586

      // ---------------------------------------------------------------
      // ADIM 3 — Satış (17.09.2026), 60 adet × 3.500 TL/m³
      // FIFO: A'dan 50 (42.420) + B'den 10 (8.862) = 51.282,00
      // ---------------------------------------------------------------
      final saleId = await sales.create(
        SaleInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 17),
          dueDate: DateTime.utc(2026, 10, 17),
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

      final sale = await (f.db.select(
        f.db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      expect(sale.costTotal, Money.parse('51282'), reason: 'FIFO maliyeti');
      expect(sale.subtotalNet, Money.parse('58800'), reason: 'KDV hariç satış');
      expect(sale.vatTotal, Money.parse('11760'));
      expect(sale.grandTotal, Money.parse('70560'));

      final profit = ProfitCalculator.of(
        netRevenue: sale.subtotalNet,
        cost: sale.costTotal,
      );
      expect(profit.grossProfit, Money.parse('7518'));
      expect(profit.marginPercent!.toStringAsFixed(2), '12.79');
      expect(profit.markupPercent!.toStringAsFixed(2), '14.66');

      // FIFO dağılımı: A1'den 50, B'den 10
      final allocs = await f.db
          .customSelect(
            'SELECT ca.pieces, ca.total_cost, ca.sequence_no FROM cost_allocations ca '
            'JOIN stock_movements sm ON sm.id = ca.movement_id '
            "WHERE sm.source_id = ? AND sm.type = 'SALE_OUT' ORDER BY ca.sequence_no",
            variables: [Variable.withString(saleId)],
          )
          .get();
      expect(allocs.length, 2);
      expect(allocs[0].read<int>('pieces'), 50);
      expect(
        Money.fromStored(allocs[0].read<int>('total_cost')),
        Money.parse('42420'),
      );
      expect(allocs[1].read<int>('pieces'), 10);
      expect(
        Money.fromStored(allocs[1].read<int>('total_cost')),
        Money.parse('8862'),
      );

      // Cari +70.560,00
      expect(await f.db.customerBalance(f.customerId), Money.parse('70560'));

      // Kalan stok: 140×200×10 → 20/5,6 (B) · 140×200×5 → 40/5,6 (A2)
      final stock10 = await f.db.variantStock(f.v10);
      expect(stock10.pieces, 20);
      expect(stock10.volume, Volume.parse('5.6'));
      final stock5 = await f.db.variantStock(f.v5);
      expect(stock5.pieces, 40);
      expect(stock5.volume, Volume.parse('5.6'));
      expect(await f.db.stockCostTotal(), Money.parse('34692'));

      // ---------------------------------------------------------------
      // ADIM 4 — Tahsilat 30.000,00 havale → bakiye 40.560,00
      // ---------------------------------------------------------------
      final collectionId = await collections.create(
        CollectionInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 20),
          amount: Money.parse('30000'),
          method: PaymentMethod.transfer,
          cashAccountId: f.bankAccountId,
        ),
        ctxFor('COLLECTION_CREATE'),
      );
      expect(await f.db.customerBalance(f.customerId), Money.parse('40560'));
      expect(await f.db.accountBalance(f.bankAccountId), Money.parse('30000'));

      // Satışın açık tutarı 40.560,00 (eşleştirme vadesi en erken belgeden)
      final open = await collections.openDocuments(f.customerId);
      expect(open.single.remaining, Money.parse('40560'));

      // ---------------------------------------------------------------
      // ADIM 5 — Alış C (18.09.2026): 140×200×8 × 5 adet = 1,12 m³
      // (BRIEF "10 adet" diyor; geometri 5 diyor — DECISIONS SK-06)
      // Satışın maliyeti, fiyatı ve kârı DEĞİŞMEMELİ.
      // ---------------------------------------------------------------
      await purchases.create(
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

      final stock8 = await f.db.variantStock(f.v8);
      expect(stock8.volume, Volume.parse('1.12'));

      final saleAfterNewPrice = await (f.db.select(
        f.db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      expect(
        saleAfterNewPrice.costTotal,
        Money.parse('51282'),
        reason: 'geçmiş satışın maliyeti yeni fiyattan ETKİLENMEZ (SPEC §30.3)',
      );
      expect(saleAfterNewPrice.subtotalNet, Money.parse('58800'));

      // ---------------------------------------------------------------
      // ADIM 8 — İade: 5 adet 140×200×10
      // Tüketimin TERSİNDEN → B partisine 3.165 ile (1,4 m³ = 4.431,00)
      // Cari −5.880,00 → bakiye 34.680,00
      // ---------------------------------------------------------------
      final saleItem = await (f.db.select(
        f.db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).getSingle();

      final returnId = await returns.createSaleReturn(
        SaleReturnInput(
          saleId: saleId,
          docDate: DateTime.utc(2026, 9, 25),
          lines: [SaleReturnLineInput(saleItemId: saleItem.id, pieces: 5)],
        ),
        ctxFor('SALE_RETURN_CREATE'),
      );

      final ret = await (f.db.select(
        f.db.saleReturns,
      )..where((r) => r.id.equals(returnId))).getSingle();
      expect(
        ret.costTotal,
        Money.parse('4431'),
        reason: 'B partisine 3.165 TL/m³ ile döner (1,4 m³)',
      );
      expect(ret.grandTotal, Money.parse('5880'));
      expect(await f.db.customerBalance(f.customerId), Money.parse('34680'));

      // İade B partisine döndü mü?
      final returnAllocs = await f.db
          .customSelect(
            'SELECT ca.batch_id, ca.unit_cost_m3 FROM cost_allocations ca '
            'JOIN stock_movements sm ON sm.id = ca.movement_id '
            "WHERE sm.source_id = ? AND sm.type = 'SALE_RETURN_IN'",
            variables: [Variable.withString(returnId)],
          )
          .get();
      expect(returnAllocs.length, 1);
      expect(
        UnitPrice.fromStored(returnAllocs.single.read<int>('unit_cost_m3')),
        UnitPrice.parse('3165'),
      );

      // ---------------------------------------------------------------
      // ADIM 9 — Tahsilat iptali → ters kayıt, orijinal SİLİNMEZ
      // bakiye 64.680,00
      // ---------------------------------------------------------------
      await reversals.cancelCollection(
        collectionId: collectionId,
        reason: 'Yanlış müşteriye girildi',
        ctx: ctxFor('COLLECTION_CANCEL'),
      );
      expect(await f.db.customerBalance(f.customerId), Money.parse('64680'));

      // Orijinal tahsilat kaydı duruyor, yalnızca durumu değişti.
      final cancelled = await (f.db.select(
        f.db.collections,
      )..where((c) => c.id.equals(collectionId))).getSingle();
      expect(cancelled.status, DocStatus.cancelled);
      expect(cancelled.amount, Money.parse('30000'));

      // Ters kayıt orijinale referans veriyor.
      final reversalRow = await (f.db.select(
        f.db.customerLedger,
      )..where((l) => l.docType.equals(LedgerDocType.reversal))).getSingle();
      expect(reversalRow.reversalOfId, isNotNull);
      expect(await f.db.accountBalance(f.bankAccountId), Money.zero);

      // ---------------------------------------------------------------
      // ADIM 10 — Çek 20.000,00 → bakiye 44.680,00, portföy 20.000,00
      // Karşılıksız → bakiye 64.680,00, portföy 0
      // ---------------------------------------------------------------
      final checkCollectionId = await collections.create(
        CollectionInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 28),
          amount: Money.parse('20000'),
          method: PaymentMethod.check,
          instrument: InstrumentInput(
            kind: InstrumentKind.check,
            dueDate: DateTime.utc(2026, 10, 30),
            serialNo: '0012345',
            bankName: 'Ziraat',
            drawerName: 'ABC Mobilya',
          ),
        ),
        ctxFor('COLLECTION_CREATE'),
      );
      expect(await f.db.customerBalance(f.customerId), Money.parse('44680'));
      expect(await f.db.instrumentPortfolioTotal(), Money.parse('20000'));

      final collectionRow = await (f.db.select(
        f.db.collections,
      )..where((c) => c.id.equals(checkCollectionId))).getSingle();
      final instrumentId = collectionRow.instrumentId!;

      await instruments.changeStatus(
        instrumentId: instrumentId,
        toStatus: InstrumentStatus.bounced,
        ctx: ctxFor('INSTRUMENT_STATUS'),
      );
      expect(
        await f.db.customerBalance(f.customerId),
        Money.parse('64680'),
        reason: 'karşılıksız → cariye ters kayıt',
      );
      expect(await f.db.instrumentPortfolioTotal(), Money.zero);

      // ---------------------------------------------------------------
      // ADIM 12 — Doğrulama
      // ---------------------------------------------------------------
      final report = await IntegrityService(f.db).check();
      expect(
        report.isClean,
        isTrue,
        reason:
            'checkIntegrity fark bulmamalı:\n'
            '${report.findings.join('\n')}',
      );

      // Tüm işlemler audit_logs'ta görünüyor.
      final audits = await f.db.select(f.db.auditLogs).get();
      final actions = audits.map((a) => '${a.entityType}:${a.action}').toSet();
      expect(
        actions,
        containsAll(<String>[
          'purchase:CREATE',
          'sale:CREATE',
          'collection:CREATE',
          'sale_return:CREATE',
          'collection:REVERSE',
          'instrument:STATUS_CHANGE',
        ]),
      );

      // Hareket tabloları dolu.
      expect(
        (await f.db.select(f.db.stockMovements).get()).length,
        greaterThan(0),
      );
      expect(
        (await f.db.select(f.db.customerLedger).get()).length,
        greaterThan(0),
      );
      expect((await f.db.select(f.db.commandLog).get()).length, greaterThan(0));
    });
  });

  group('EK A — Ağırlıklı ortalama (ayrı veritabanı)', () {
    late ScenarioFixture f;

    setUp(
      () async => f = await ScenarioFixture.create(
        costingMethod: CostingMethod.weightedAverage,
      ),
    );
    tearDown(() async => f.close());

    test(
      'satış maliyeti (59.388 + 26.586) / 28 m³ = 3.070,5000 → 51.584,40',
      () async {
        final purchases = PurchaseRepository(f.db);
        final sales = SaleRepository(f.db);

        // Adımlar 1–2 aynı.
        await purchases.create(
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

        await purchases.create(
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

        final saleId = await sales.create(
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

        final sale = await (f.db.select(
          f.db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        expect(
          sale.costTotal,
          Money.parse('51584.40'),
          reason: 'ürün bazlı ağırlıklı ortalama (payda 28 m³, D-11)',
        );
        expect(sale.subtotalNet, Money.parse('58800'));
      },
    );
  });

  group('EK B — KDV Dahil', () {
    late ScenarioFixture f;
    setUp(() async => f = await ScenarioFixture.create());
    tearDown(() async => f.close());

    test('INCL modda girilen tutar aynen korunur', () async {
      final purchases = PurchaseRepository(f.db);
      final sales = SaleRepository(f.db);

      await purchases.create(
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
          ],
        ),
        ctxFor('PURCHASE_CREATE'),
      );

      // 1 m³ × 4.200 TL KDV DAHİL → net 3.500,00 · KDV 700,00
      final saleId = await sales.create(
        SaleInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 17),
          priceMode: PriceMode.incl,
          lines: [
            SaleLineInput(
              variantId: f.v10,
              pieces: 1,
              volume: Volume.parse('1'),
              unitPriceM3: UnitPrice.parse('4200'),
              vatRate: vat20,
            ),
          ],
        ),
        ctxFor('SALE_CREATE'),
      );

      final sale = await (f.db.select(
        f.db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      expect(sale.subtotalNet, Money.parse('3500'));
      expect(sale.vatTotal, Money.parse('700'));
      expect(sale.grandTotal, Money.parse('4200'));
      expect(sale.subtotalNet + sale.vatTotal, sale.grandTotal);
    });
  });
}
