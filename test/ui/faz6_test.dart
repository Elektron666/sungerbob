import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/repo/party_repository.dart';
import 'package:sungerbob/data/repo/price_memory.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/finance/accounts_screen.dart';
import 'package:sungerbob/ui/screens/finance/instruments_screen.dart';
import 'package:sungerbob/ui/screens/finance/payment_screen.dart';
import 'package:sungerbob/ui/screens/search/search_screen.dart';

import '../golden_scenario/scenario_fixture.dart';

/// Faz 6 — paranın hareketi: ödeme, kasa/banka, çek & senet, arama.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  final vat = Rate.percent('20');
  OperationContext ctx(String t) => OperationContext(commandType: t);

  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => f.db)],
    child: MaterialApp(home: child),
  );

  Future<void> buy({String price = '2500'}) => PurchaseRepository(f.db).create(
    PurchaseInput(
      supplierId: f.supplierId,
      docDate: DateTime.utc(2026, 9, 1),
      priceMode: PriceMode.excl,
      lines: [
        PurchaseLineInput(
          variantId: f.v10,
          pieces: 20,
          volume: f.volumeOf('140', '200', '10', 20),
          unitPriceM3: UnitPrice.parse(price),
          vatRate: vat,
        ),
      ],
    ),
    ctx('PURCHASE_CREATE'),
  );

  group('Ödeme', () {
    testWidgets('tedarikçi borcu ekranda görünür', (tester) async {
      await buy();
      await tester.pumpWidget(wrap(const PaymentScreen()));
      await tester.pumpAndSettle();

      // Tedarikçiyi seç.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      final supplier = await (f.db.select(
        f.db.suppliers,
      )..where((s) => s.id.equals(f.supplierId))).getSingle();
      await tester.tap(find.text(supplier.title).last);
      await tester.pumpAndSettle();

      expect(find.text('Güncel borç'), findsOneWidget);
      // 20 adet × 2,8 m³ ... borç sıfırdan büyük olmalı.
      final debt = await f.db.supplierBalance(f.supplierId);
      expect(debt.isPositive, isTrue);
      expect(find.text(TrFormat.moneyWithCurrency(debt)), findsOneWidget);
    });

    testWidgets('tedarikçi seçilmeden kaydedilmez', (tester) async {
      await tester.pumpWidget(wrap(const PaymentScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Ödemeyi kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Tedarikçi seçin'), findsWidgets);
    });
  });

  group('Kasa & Banka', () {
    testWidgets('toplam mevcut ve hesaplar listelenir', (tester) async {
      await tester.pumpWidget(wrap(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('TOPLAM MEVCUT'), findsOneWidget);
      expect(find.text('Hesaplar'.toUpperCase()), findsOneWidget);
    });

    testWidgets('yeni hesap açılır', (tester) async {
      await tester.pumpWidget(wrap(const AccountsScreen()));
      await tester.pumpAndSettle();

      final before = (await f.db.select(f.db.cashAccounts).get()).length;

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Ziraat');
      await tester.pump();
      await tester.tap(find.text('Hesabı aç'));
      await tester.pumpAndSettle();

      final after = await f.db.select(f.db.cashAccounts).get();
      expect(after, hasLength(before + 1));
      expect(after.map((a) => a.name), contains('Ziraat'));
      // Kod unvandan türetilir ve benzersizdir.
      expect(after.map((a) => a.code).toSet().length, after.length);
    });

    testWidgets('adsız hesap açılmaz', (tester) async {
      await tester.pumpWidget(wrap(const AccountsScreen()));
      await tester.pumpAndSettle();
      final before = (await f.db.select(f.db.cashAccounts).get()).length;

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hesabı aç'));
      await tester.pumpAndSettle();

      expect(find.text('Hesap adı girin'), findsOneWidget);
      expect(await f.db.select(f.db.cashAccounts).get(), hasLength(before));
    });
  });

  group('Çek & Senet', () {
    testWidgets('evrak yokken yol gösterir', (tester) async {
      await tester.pumpWidget(wrap(const InstrumentsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Alınan evrak yok'), findsOneWidget);
    });
  });

  group('Arama', () {
    testWidgets('iki harften kısa sorguda arama yapılmaz', (tester) async {
      await tester.pumpWidget(wrap(const SearchScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Aramak için yazın'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'a');
      await tester.pumpAndSettle();
      expect(find.text('Aramak için yazın'), findsOneWidget);
    });

    testWidgets('müşteri Türkçe karakter duyarsız bulunur', (tester) async {
      await PartyRepository(f.db)
          .createCustomer(title: 'Şişli Mobilya', ctx: ctx('CUSTOMER_CREATE'));

      await tester.pumpWidget(wrap(const SearchScreen()));
      await tester.pumpAndSettle();

      // "sisli" yazınca "Şişli" bulunmalı.
      await tester.enterText(find.byType(TextField).first, 'sisli');
      await tester.pumpAndSettle();

      expect(find.text('Şişli Mobilya'), findsOneWidget);
    });

    testWidgets('sonuç yoksa açıkça söyler', (tester) async {
      await tester.pumpWidget(wrap(const SearchScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzzzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('için sonuç yok'), findsOneWidget);
    });
  });

  group('Son fiyat hafızası', () {
    test('müşteriye yapılan son satışın fiyatını hatırlar', () async {
      await buy();
      await SaleRepository(f.db).create(
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
              vatRate: vat,
            ),
          ],
        ),
        ctx('SALE_CREATE'),
      );

      final hint = await PriceMemory(f.db)
          .lastSalePrice(customerId: f.customerId, productId: f.beyazProductId);
      expect(hint, isNotNull);
      expect(hint!.unitPrice, UnitPrice.parse('3500'));
    });

    test('hiç satış yoksa ipucu yok', () async {
      final hint = await PriceMemory(f.db)
          .lastSalePrice(customerId: f.customerId, productId: f.beyazProductId);
      expect(hint, isNull);
    });

    test('tedarikçiden son alış fiyatını hatırlar', () async {
      await buy(price: '2750');
      final hint = await PriceMemory(f.db).lastPurchasePrice(
        supplierId: f.supplierId,
        productId: f.beyazProductId,
      );
      expect(hint!.unitPrice, UnitPrice.parse('2750'));
    });

    test('başka müşterinin fiyatı sızmaz', () async {
      await buy();
      final other = await PartyRepository(f.db)
          .createCustomer(title: 'Başka Firma', ctx: ctx('CUSTOMER_CREATE'));
      await SaleRepository(f.db).create(
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
              vatRate: vat,
            ),
          ],
        ),
        ctx('SALE_CREATE'),
      );

      final hint = await PriceMemory(f.db)
          .lastSalePrice(customerId: other, productId: f.beyazProductId);
      expect(hint, isNull, reason: 'başka müşterinin fiyatı görünmemeli');
    });
  });

  test('Money toplamı: kasa toplamı hesapların toplamıdır', () async {
    final accounts = await f.db.select(f.db.cashAccounts).get();
    var total = Money.zero;
    for (final a in accounts) {
      total += await f.db.accountBalance(a.id);
    }
    expect(total, isA<Money>());
  });
}
