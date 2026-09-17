import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/repo/analytics_queries.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_ops_repository.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

void main() {
  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  /// Altın Senaryo adım 1–3.
  Future<void> setUpSales() async {
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
  }

  group('Müşteri analizi (SPEC §19)', () {
    test('boş müşteride tüm değerler sıfır', () async {
      final a = await f.db.customerAnalysis(f.customerId);
      expect(a.totalSales, Money.zero);
      expect(a.grossProfit, Money.zero);
      expect(a.lastSaleAt, isNull);
      expect(a.averagePaymentDays, isNull);
    });

    test('Altın Senaryo 3 sonrası doğru', () async {
      await setUpSales();
      final a = await f.db.customerAnalysis(f.customerId);

      expect(a.title, 'ABC Mobilya');
      expect(a.totalSales, Money.parse('58800'), reason: 'KDV hariç');
      expect(a.totalVolume, Volume.parse('16.8'));
      expect(a.grossProfit, Money.parse('7518'));
      expect(
        a.currentDebt,
        Money.parse('70560'),
        reason: 'cariye brüt yazılır',
      );
      expect(a.topProductName, 'Beyaz Sünger');
      // Zaman damgaları epoch saklanır, gösterimde yerele çevrilir
      // (ARCHITECTURE §10.1) — karşılaştırma epoch üzerinden yapılır.
      expect(
        a.lastSaleAt!.millisecondsSinceEpoch,
        DateTime.utc(2026, 9, 17).millisecondsSinceEpoch,
      );
    });

    test('ortalama ödeme süresi tahsilattan hesaplanıyor', () async {
      await setUpSales();
      // Satış 17.09, tahsilat 27.09 → 10 gün
      await CollectionRepository(f.db).create(
        CollectionInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 27),
          amount: Money.parse('30000'),
          method: PaymentMethod.transfer,
          cashAccountId: f.bankAccountId,
        ),
        ctxFor('COLLECTION_CREATE'),
      );

      final a = await f.db.customerAnalysis(f.customerId);
      expect(a.averagePaymentDays, 10);
      expect(a.totalCollected, Money.parse('30000'));
    });
  });

  group('Ürün analizi (SPEC §20)', () {
    test('alınan, satılan, mevcut ve ortalamalar', () async {
      await setUpSales();
      final list = await f.db.productAnalysis();
      final beyaz = list.firstWhere((p) => p.name == 'Beyaz Sünger');

      expect(beyaz.purchasedVolume, Volume.parse('28'), reason: '19,6 + 8,4');
      expect(beyaz.soldVolume, Volume.parse('16.8'));
      expect(beyaz.currentVolume, Volume.parse('11.2'));
      expect(beyaz.revenue, Money.parse('58800'));
      expect(beyaz.grossProfit, Money.parse('7518'));

      // Ortalama satış fiyatı = 58.800 / 16,8 = 3.500,0000
      expect(beyaz.averageSalePrice, UnitPrice.parse('3500'));
      // Ortalama maliyet = 51.282 / 16,8 = 3.052,5000
      expect(beyaz.averageCost, UnitPrice.parse('3052.5'));

      expect(beyaz.lastPurchasePrice, UnitPrice.parse('3165'));
      expect(beyaz.lastSalePrice, UnitPrice.parse('3500'));
    });

    test('hiç hareketi olmayan ürün sıfırlarla döner', () async {
      final list = await f.db.productAnalysis();
      final hr35 = list.firstWhere((p) => p.name == 'HR35');
      expect(hr35.soldVolume, Volume.zero);
      expect(hr35.averageCost, UnitPrice.zero);
      expect(hr35.lastPurchasePrice, isNull);
    });
  });

  group('Kârlılık raporu', () {
    test('brüt kâr, fire ve net kâr', () async {
      await setUpSales();

      // Fire ekle: 140×200×5 × 2 adet → 848,40
      await StockOpsRepository(f.db).recordWaste(
        occurredAt: DateTime.utc(2026, 9, 27),
        reasonCode: WasteReason.damaged,
        lines: [WasteLineInput(variantId: f.v5, pieces: 2)],
        ctx: ctxFor('WASTE_CREATE'),
      );

      final report = await f.db.profitability(
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
      );

      expect(report.revenue, Money.parse('58800'));
      expect(report.costOfGoods, Money.parse('51282'));
      expect(report.grossProfit, Money.parse('7518'));
      expect(report.waste, Money.parse('848.40'));
      expect(report.expenses, Money.zero);

      // Net kâr = 7.518,00 − 848,40 = 6.669,60
      expect(report.netProfit, Money.parse('6669.60'));
      expect(report.grossMarginPercent!.toStringAsFixed(2), '12.79');
    });

    test('dönem dışı hareketler rapora girmez', () async {
      await setUpSales();
      final report = await f.db.profitability(
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 10, 31),
      );
      expect(report.revenue, Money.zero);
      expect(report.netProfit, Money.zero);
    });
  });

  group('Dönemsel satış raporu (SPEC §25)', () {
    test('aylık gruplama', () async {
      await setUpSales();
      final rows = await f.db.salesByPeriod(
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 12, 31),
      );
      expect(rows.length, 1);
      expect(rows.single.net, Money.parse('58800'));
      expect(rows.single.profit, Money.parse('7518'));
      expect(rows.single.count, 1);
    });

    test('günlük gruplama', () async {
      await setUpSales();
      final rows = await f.db.salesByPeriod(
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
        granularity: 'day',
      );
      expect(rows.length, 1);
      expect(rows.single.period.day, 17);
    });
  });
}
