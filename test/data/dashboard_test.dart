import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/repo/dashboard_queries.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
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

  test('boş sistemde tüm kartlar sıfır — mock veri yok', () async {
    final s = await f.db.dashboardSnapshot();
    expect(s.totalStockVolume, Volume.zero);
    expect(s.stockCost, Money.zero);
    expect(s.receivables, Money.zero);
    expect(s.supplierDebt, Money.zero);
    expect(s.capital, Money.zero);
  });

  test('Altın Senaryo 3 sonrası kartlar doğru', () async {
    final now = DateTime.utc(2026, 9, 30);

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
        dueDate: DateTime.utc(2026, 9, 20), // vadesi geçmiş olsun
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

    final s = await f.db.dashboardSnapshot(now: now);

    expect(s.totalStockVolume, Volume.parse('11.2'));
    expect(s.stockCost, Money.parse('34692'));
    expect(s.monthSales, Money.parse('58800'), reason: 'KDV hariç ciro');
    expect(s.monthGrossProfit, Money.parse('7518'));
    expect(s.receivables, Money.parse('70560'), reason: 'cariye brüt yazılır');
    expect(s.overdue, Money.parse('70560'), reason: 'vadesi geçmiş');
    expect(s.cashAndBank, Money.zero);

    // Sermaye = stok + alacak − tedarikçi borcu
    final supplierDebt = s.supplierDebt;
    expect(
      s.capital,
      Money.parse('34692') + Money.parse('70560') - supplierDebt,
    );
  });

  test('vadesi geçen müşteriler listesi gecikme günüyle', () async {
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
    await SaleRepository(f.db).create(
      SaleInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 1),
        dueDate: DateTime.utc(2026, 9, 10),
        priceMode: PriceMode.excl,
        lines: [
          SaleLineInput(
            variantId: f.v10,
            pieces: 10,
            volume: f.volumeOf('140', '200', '10', 10),
            unitPriceM3: UnitPrice.parse('3500'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('SALE_CREATE'),
    );

    final overdue = await f.db.overdueCustomers(now: DateTime.utc(2026, 9, 17));
    expect(overdue.length, 1);
    expect(overdue.single.title, 'ABC Mobilya');
    expect(overdue.single.daysLate, 7);
  });

  test('kritik stok eşiğin altındaki varyantları listeler', () async {
    // Eşik belirle.
    await f.db.customStatement(
      'UPDATE product_variants SET critical_stock_pieces = 20 WHERE id = ?',
      [f.v10],
    );

    await PurchaseRepository(f.db).create(
      PurchaseInput(
        supplierId: f.supplierId,
        docDate: DateTime.utc(2026, 9, 1),
        priceMode: PriceMode.excl,
        lines: [
          PurchaseLineInput(
            variantId: f.v10,
            pieces: 15,
            volume: f.volumeOf('140', '200', '10', 15),
            unitPriceM3: UnitPrice.parse('3000'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('PURCHASE_CREATE'),
    );

    final critical = await f.db.criticalStock();
    expect(critical.any((c) => c.variantId == f.v10), isTrue);
    expect(critical.firstWhere((c) => c.variantId == f.v10).pieces, 15);
  });
}
