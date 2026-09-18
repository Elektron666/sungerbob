import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/documents/documents_screen.dart';
import 'package:sungerbob/ui/widgets/first_steps.dart';

import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../data/test_db.dart';
import '../golden_scenario/scenario_fixture.dart';

final _vat = Rate.percent('20');
OperationContext _ctx(String t) => OperationContext(commandType: t);

/// Fixture'a bir alış ve istenirse bir satış yazar.
Future<void> seedPurchase(ScenarioFixture f) => PurchaseRepository(f.db).create(
  PurchaseInput(
    supplierId: f.supplierId,
    docDate: DateTime.utc(2026, 9, 1),
    priceMode: PriceMode.excl,
    lines: [
      PurchaseLineInput(
        variantId: f.v10,
        pieces: 20,
        volume: f.volumeOf('140', '200', '10', 20),
        unitPriceM3: UnitPrice.parse('2500'),
        vatRate: _vat,
      ),
    ],
  ),
  _ctx('PURCHASE_CREATE'),
);

Future<void> seedSale(ScenarioFixture f) => SaleRepository(f.db).create(
  SaleInput(
    customerId: f.customerId,
    docDate: DateTime.utc(2026, 9, 17),
    priceMode: PriceMode.excl,
    lines: [
      SaleLineInput(
        variantId: f.v10,
        pieces: 5,
        volume: f.volumeOf('140', '200', '10', 5),
        unitPriceM3: UnitPrice.parse('3500'),
        vatRate: _vat,
      ),
    ],
  ),
  _ctx('SALE_CREATE'),
);

/// Kaydedilen belgeyi **görebilmek**. En büyük eksik buydu: satış
/// kaydediliyor, bir daha bulunamıyordu.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  Widget wrap(AppDatabase db, Widget child) => ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: MaterialApp(home: child),
  );

  group('Belgeler', () {
    testWidgets('boş defterde yol gösterir', (tester) async {
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(wrap(db, const DocumentsScreen(sales: true)));
      await tester.pumpAndSettle();

      expect(find.text('Henüz satış yok'), findsOneWidget);
    });

    testWidgets('satış listelenir ve detayı açılır', (tester) async {
      final f = await ScenarioFixture.create();
      addTearDown(f.close);
      await seedPurchase(f);
      await seedSale(f);

      await tester.pumpWidget(wrap(f.db, const DocumentsScreen(sales: true)));
      await tester.pumpAndSettle();

      // Müşteri adı ve tutar listede.
      final customer = await (f.db.select(
        f.db.customers,
      )..where((c) => c.id.equals(f.customerId))).getSingle();
      expect(find.text(customer.title), findsOneWidget);

      // Detay: kalemler görünüyor.
      await tester.tap(find.text(customer.title));
      await tester.pumpAndSettle();
      expect(find.text('Genel toplam'), findsOneWidget);
      expect(find.textContaining('Beyaz Sünger'), findsWidgets);
    });

    testWidgets('alışlar da listelenir', (tester) async {
      final f = await ScenarioFixture.create();
      addTearDown(f.close);
      await seedPurchase(f);

      await tester.pumpWidget(wrap(f.db, const DocumentsScreen(sales: false)));
      await tester.pumpAndSettle();

      expect(find.text('Henüz alış yok'), findsNothing);
      expect(find.byType(ListTile), findsWidgets);
    });
  });

  // Kart bir ekran değil; Scaffold'u test veriyor (ListTile Material ister).
  Widget wrapCard(AppDatabase db, Widget child) => ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  group('İlk adımlar', () {
    testWidgets('boş defterde dört adım da açık', (tester) async {
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(wrapCard(db, const FirstStepsCard()));
      await tester.pumpAndSettle();

      expect(find.text('İLK ADIMLAR'), findsOneWidget);
      expect(find.text('0/4'), findsOneWidget);
      expect(find.text('Tedarikçi ekle'), findsOneWidget);
      expect(find.text('İlk satışını gir'), findsOneWidget);
    });

    testWidgets('adımlar ilerledikçe sayaç artar', (tester) async {
      final f = await ScenarioFixture.create();
      addTearDown(f.close);
      await seedPurchase(f);

      await tester.pumpWidget(wrapCard(f.db, const FirstStepsCard()));
      await tester.pumpAndSettle();

      // Tedarikçi, stok ve müşteri hazır; satış henüz yok.
      expect(find.text('3/4'), findsOneWidget);
      expect(find.text('İlk satışını gir'), findsOneWidget);
    });

    testWidgets('hepsi bitince kart tamamen kaybolur', (tester) async {
      final f = await ScenarioFixture.create();
      addTearDown(f.close);
      await seedPurchase(f);
      await seedSale(f);

      await tester.pumpWidget(wrapCard(f.db, const FirstStepsCard()));
      await tester.pumpAndSettle();

      expect(find.text('İLK ADIMLAR'), findsNothing);
    });
  });
}
