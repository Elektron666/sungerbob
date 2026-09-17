import 'package:drift/drift.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/payment_repository.dart';
import 'package:sungerbob/data/repo/price_list_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/return_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/costing/costing_engine.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t, {String? id}) =>
    OperationContext(commandType: t, commandId: id);

/// Her testin başında 50 adet 140×200×10 stok oluşturur.
Future<void> seedStock(ScenarioFixture f) async {
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
          unitPriceM3: UnitPrice.parse('3000'),
          vatRate: vat20,
        ),
      ],
    ),
    ctxFor('PURCHASE_CREATE'),
  );
}

SaleInput saleOf(ScenarioFixture f, int pieces, {bool approved = false}) =>
    SaleInput(
      customerId: f.customerId,
      docDate: DateTime.utc(2026, 9, 17),
      priceMode: PriceMode.excl,
      riskLimitApproved: approved,
      lines: [
        SaleLineInput(
          variantId: f.v10,
          pieces: pieces,
          volume: f.volumeOf('140', '200', '10', pieces),
          unitPriceM3: UnitPrice.parse('3500'),
          vatRate: vat20,
        ),
      ],
    );

void main() {
  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  group('Transaction geri alma (BRIEF §8)', () {
    test('satışın ortasında hata → HİÇBİR kayıt yazılmaz', () async {
      await seedStock(f);

      final salesBefore = (await f.db.select(f.db.sales).get()).length;
      final movementsBefore =
          (await f.db.select(f.db.stockMovements).get()).length;
      final ledgerBefore =
          (await f.db.select(f.db.customerLedger).get()).length;
      final commandsBefore = (await f.db.select(f.db.commandLog).get()).length;

      // 51 adet isteniyor ama 50 var → FIFO ortada patlar.
      await expectLater(
        SaleRepository(f.db).create(saleOf(f, 51), ctxFor('SALE_CREATE')),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(
        (await f.db.select(f.db.sales).get()).length,
        salesBefore,
        reason: 'satış belgesi yazılmamalı',
      );
      expect(
        (await f.db.select(f.db.stockMovements).get()).length,
        movementsBefore,
        reason: 'stok hareketi yazılmamalı',
      );
      expect(
        (await f.db.select(f.db.customerLedger).get()).length,
        ledgerBefore,
        reason: 'cari hareketi yazılmamalı',
      );
      expect(
        (await f.db.select(f.db.commandLog).get()).length,
        commandsBefore,
        reason: 'komut kaydı da geri alınmalı (D-09)',
      );

      // Parti kalanı da bozulmamış olmalı.
      final stock = await f.db.variantStock(f.v10);
      expect(stock.pieces, 50);
    });

    test(
      'başarısız işlemin belge numarası da geri alınır — boşluk olmaz',
      () async {
        await seedStock(f);

        await expectLater(
          SaleRepository(f.db).create(saleOf(f, 999), ctxFor('SALE_CREATE')),
          throwsA(isA<InsufficientStockException>()),
        );

        // Şimdi geçerli bir satış: numara 000001 olmalı, 000002 değil.
        final saleId = await SaleRepository(f.db)
            .create(saleOf(f, 10), ctxFor('SALE_CREATE'));
        final sale = await (f.db.select(
          f.db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        expect(sale.docNo, 'STS-2026-000001');
      },
    );
  });

  group('Çift gönderim — aynı UUID tek kayıt (BRIEF §3.9)', () {
    test('aynı commandId ile ikinci satış reddedilir', () async {
      await seedStock(f);
      final ctx = ctxFor('SALE_CREATE', id: 'ayni-uuid-123');

      await SaleRepository(f.db).create(saleOf(f, 10), ctx);

      await expectLater(
        SaleRepository(f.db).create(saleOf(f, 10), ctx),
        throwsA(isA<DuplicateCommandException>()),
      );

      expect((await f.db.select(f.db.sales).get()).length, 1);
      final stock = await f.db.variantStock(f.v10);
      expect(stock.pieces, 40, reason: 'stok yalnızca bir kez düşmeli');
    });

    test('farklı commandId ile ikinci satış geçer', () async {
      await seedStock(f);
      await SaleRepository(f.db).create(saleOf(f, 10), ctxFor('SALE_CREATE'));
      await SaleRepository(f.db).create(saleOf(f, 10), ctxFor('SALE_CREATE'));
      expect((await f.db.select(f.db.sales).get()).length, 2);
    });

    test('tahsilatta da çift gönderim engellenir', () async {
      final ctx = ctxFor('COLLECTION_CREATE', id: 'tahsilat-uuid');
      final input = CollectionInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 20),
        amount: Money.parse('1000'),
        method: PaymentMethod.cash,
        cashAccountId: f.bankAccountId,
      );

      await CollectionRepository(f.db).create(input, ctx);
      await expectLater(
        CollectionRepository(f.db).create(input, ctx),
        throwsA(isA<DuplicateCommandException>()),
      );
      expect(await f.db.customerBalance(f.customerId), Money.parse('-1000'));
    });
  });

  group('Negatif stok engeli (BRIEF §3.8)', () {
    test('stoktan fazla satış reddedilir', () async {
      await seedStock(f);
      await expectLater(
        SaleRepository(f.db).create(saleOf(f, 51), ctxFor('SALE_CREATE')),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('hiç stok yokken satış reddedilir', () async {
      await expectLater(
        SaleRepository(f.db).create(saleOf(f, 1), ctxFor('SALE_CREATE')),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('tam stok kadar satış geçer', () async {
      await seedStock(f);
      await SaleRepository(f.db).create(saleOf(f, 50), ctxFor('SALE_CREATE'));
      final stock = await f.db.variantStock(f.v10);
      expect(stock.pieces, 0);
      expect(stock.volume, Volume.zero);
    });
  });

  group('İade sınırı (BRIEF §5)', () {
    test('satılandan fazla iade reddedilir', () async {
      await seedStock(f);
      final saleId = await SaleRepository(f.db)
          .create(saleOf(f, 10), ctxFor('SALE_CREATE'));
      final item = await (f.db.select(
        f.db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).getSingle();

      await expectLater(
        ReturnRepository(f.db).createSaleReturn(
          SaleReturnInput(
            saleId: saleId,
            docDate: DateTime.utc(2026, 9, 25),
            lines: [SaleReturnLineInput(saleItemId: item.id, pieces: 11)],
          ),
          ctxFor('SALE_RETURN_CREATE'),
        ),
        throwsA(isA<ReturnExceedsSoldException>()),
      );
    });

    test('kısmi iadeler toplamı satılanı aşamaz', () async {
      await seedStock(f);
      final saleId = await SaleRepository(f.db)
          .create(saleOf(f, 10), ctxFor('SALE_CREATE'));
      final item = await (f.db.select(
        f.db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).getSingle();

      await ReturnRepository(f.db).createSaleReturn(
        SaleReturnInput(
          saleId: saleId,
          docDate: DateTime.utc(2026, 9, 25),
          lines: [SaleReturnLineInput(saleItemId: item.id, pieces: 6)],
        ),
        ctxFor('SALE_RETURN_CREATE'),
      );

      // 6 iade edildi, 4 kaldı; 5 istemek reddedilmeli.
      await expectLater(
        ReturnRepository(f.db).createSaleReturn(
          SaleReturnInput(
            saleId: saleId,
            docDate: DateTime.utc(2026, 9, 26),
            lines: [SaleReturnLineInput(saleItemId: item.id, pieces: 5)],
          ),
          ctxFor('SALE_RETURN_CREATE'),
        ),
        throwsA(isA<ReturnExceedsSoldException>()),
      );
    });
  });

  group('Müşteri risk limiti (BRIEF §5)', () {
    test('limiti aşan satış uyarı fırlatır', () async {
      await seedStock(f);
      await (f.db.update(f.db.customers)
            ..where((c) => c.id.equals(f.customerId)))
          .write(CustomersCompanion(riskLimit: Value(Money.parse('10000'))));

      // 10 adet × 2,8 m³ × 3.500 = 9.800 net + KDV = 11.760 brüt > 10.000
      await expectLater(
        SaleRepository(f.db).create(saleOf(f, 10), ctxFor('SALE_CREATE')),
        throwsA(isA<RiskLimitExceededException>()),
      );
      expect((await f.db.select(f.db.sales).get()), isEmpty);
    });

    test('kullanıcı onaylarsa satış geçer', () async {
      await seedStock(f);
      await (f.db.update(f.db.customers)
            ..where((c) => c.id.equals(f.customerId)))
          .write(CustomersCompanion(riskLimit: Value(Money.parse('10000'))));

      await SaleRepository(f.db)
          .create(saleOf(f, 10, approved: true), ctxFor('SALE_CREATE'));
      expect((await f.db.select(f.db.sales).get()).length, 1);
    });

    test('limit 0 ise sınırsız', () async {
      await seedStock(f);
      await SaleRepository(f.db).create(saleOf(f, 50), ctxFor('SALE_CREATE'));
      expect((await f.db.select(f.db.sales).get()).length, 1);
    });
  });

  group('Fiyat listesi (SPEC §13, §30.11)', () {
    test('baz 3.500 ile katsayılar uygulanır', () async {
      final repo = PriceListRepository(f.db);
      await repo.createVersion(
        basePrice: UnitPrice.parse('3500'),
        name: 'Eylül 2026',
        validFrom: DateTime.utc(2026, 9, 1),
        ctx: ctxFor('PRICE_LIST_CREATE'),
      );

      final list = await (f.db.select(
        f.db.priceLists,
      )..where((l) => l.status.equals('ACTIVE'))).getSingle();
      final items = await (f.db.select(
        f.db.priceListItems,
      )..where((i) => i.priceListId.equals(list.id))).get();

      final beyaz = items.firstWhere((i) => i.productId == f.beyazProductId);
      expect(beyaz.effectivePriceM3, UnitPrice.parse('3500')); // 3500 × 1,00

      // D32 Gri: 3.500 × 1,91 = 6.685,00
      final products = await f.db.select(f.db.products).get();
      final d32 = products.firstWhere((p) => p.code == 'D32GRI');
      final d32Item = items.firstWhere((i) => i.productId == d32.id);
      expect(d32Item.effectivePriceM3, UnitPrice.parse('6685'));
    });

    test('yeni versiyon öncekini arşivler, SİLMEZ', () async {
      final repo = PriceListRepository(f.db);
      await repo.createVersion(
        basePrice: UnitPrice.parse('3500'),
        name: 'v1',
        validFrom: DateTime.utc(2026, 9, 1),
        ctx: ctxFor('PRICE_LIST_CREATE'),
      );
      await repo.createVersion(
        basePrice: UnitPrice.parse('3700'),
        name: 'v2',
        validFrom: DateTime.utc(2026, 9, 18),
        ctx: ctxFor('PRICE_LIST_CREATE'),
      );

      final all = await f.db.select(f.db.priceLists).get();
      expect(all.length, 2, reason: 'eski versiyon erişilebilir kalmalı');
      expect(all.where((l) => l.status == 'ARCHIVED').length, 1);
      expect(all.where((l) => l.status == 'ACTIVE').single.versionNo, 2);
    });

    test('yuvarlama kuralı: en yakın 5 TL', () async {
      final repo = PriceListRepository(f.db);
      await repo.createVersion(
        basePrice: UnitPrice.parse('3500'),
        name: 'yuvarlanmış',
        validFrom: DateTime.utc(2026, 9, 1),
        roundingRule: RoundingRule.nearest5,
        ctx: ctxFor('PRICE_LIST_CREATE'),
      );

      final list = await (f.db.select(
        f.db.priceLists,
      )..where((l) => l.status.equals('ACTIVE'))).getSingle();
      final products = await f.db.select(f.db.products).get();
      final d28 = products.firstWhere((p) => p.code == 'D28GRI');
      final item =
          await (f.db.select(f.db.priceListItems)..where(
                (i) =>
                    i.priceListId.equals(list.id) & i.productId.equals(d28.id),
              ))
              .getSingle();

      // 3.500 × 1,71 = 5.985,00 → en yakın 5 → 5.985,00
      expect(item.effectivePriceM3, UnitPrice.parse('5985'));
    });

    test('önizleme eski/yeni karşılaştırması verir', () async {
      final repo = PriceListRepository(f.db);
      await repo.createVersion(
        basePrice: UnitPrice.parse('3500'),
        name: 'v1',
        validFrom: DateTime.utc(2026, 9, 1),
        ctx: ctxFor('PRICE_LIST_CREATE'),
      );

      final preview = await repo.preview(basePrice: UnitPrice.parse('3700'));
      final beyaz = preview.firstWhere((r) => r.productId == f.beyazProductId);
      expect(beyaz.oldPrice, UnitPrice.parse('3500'));
      expect(beyaz.newPrice, UnitPrice.parse('3700'));
      // %5,71 artış
      expect(beyaz.changePercent!.toStringAsFixed(2), '5.71');
    });

    test('SPEC §14: plaka fiyatı = m³ fiyatı × parça hacmi', () async {
      // 140×200×10 → 0,28 m³ × 6.685 TL/m³ = 1.871,80 TL/plaka
      final plate = PriceListRepository.platePrice(
        pricePerM3: UnitPrice.parse('6685'),
        unitVolume: Volume.parse('0.28'),
      );
      expect(plate, UnitPrice.parse('1871.80'));
    });
  });

  group('Kasa/banka ve tedarikçi ödemesi', () {
    test('virman iki hesap hareketi yazar, toplam korunur', () async {
      final second = uuid.v7();
      await f.db
          .into(f.db.cashAccounts)
          .insert(
            CashAccountsCompanion.insert(
              id: second,
              code: 'BANKA1',
              name: 'Ziraat',
              type: CashAccountType.bank,
            ),
          );

      // Önce kasaya para girsin.
      await CollectionRepository(f.db).create(
        CollectionInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 20),
          amount: Money.parse('5000'),
          method: PaymentMethod.cash,
          cashAccountId: f.bankAccountId,
        ),
        ctxFor('COLLECTION_CREATE'),
      );

      await PaymentRepository(f.db).transfer(
        fromAccountId: f.bankAccountId,
        toAccountId: second,
        amount: Money.parse('2000'),
        docDate: DateTime.utc(2026, 9, 21),
        ctx: ctxFor('TRANSFER_CREATE'),
      );

      expect(await f.db.accountBalance(f.bankAccountId), Money.parse('3000'));
      expect(await f.db.accountBalance(second), Money.parse('2000'));
    });

    test('tedarikçi ödemesi borcu azaltır ve açık alışı kapatır', () async {
      await seedStock(f); // 50 × 2,8 m³... alış brüt tutarı oluşur

      final purchase = await f.db
          .select(f.db.purchases)
          .get()
          .then((r) => r.single);
      expect(await f.db.supplierBalance(f.supplierId), purchase.grandTotal);

      await PaymentRepository(f.db).paySupplier(
        SupplierPaymentInput(
          supplierId: f.supplierId,
          docDate: DateTime.utc(2026, 9, 25),
          amount: Money.parse('10000'),
          method: PaymentMethod.transfer,
          cashAccountId: f.bankAccountId,
        ),
        ctxFor('SUPPLIER_PAYMENT'),
      );

      expect(
        await f.db.supplierBalance(f.supplierId),
        purchase.grandTotal - Money.parse('10000'),
      );

      final allocations = await f.db
          .select(f.db.supplierPaymentAllocations)
          .get();
      expect(allocations.single.targetId, purchase.id);
      expect(allocations.single.amount, Money.parse('10000'));
    });
  });
}
