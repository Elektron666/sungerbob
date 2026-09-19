import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/documents/documents_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';
import 'package:sungerbob/ui/screens/sale/quick_sale_screen.dart';

import '../data/test_db.dart';

/// **Müşteri malı geri getirdi.**
///
/// İade iş kuralı Faz 1'den beri hazırdı ve testleri geçiyordu; ekranı
/// yoktu. SK-21'in dersi: iş mantığının testten geçmesi, kullanıcının o işi
/// yapabildiğini göstermez. Bu test boş veritabanından başlar ve yalnızca
/// ekranlara dokunur.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  /// Ekranı **boş bir ana rotanın üstüne** iter.
  ///
  /// Kaydettikten sonra kendini kapatan ekranlar (satış, iade) doğrudan
  /// `home:` olarak verilince Navigator'ın geçmişini boşaltıyor. Gerçek
  /// uygulamada da altlarında bir sayfa var.
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextField, label);
    await tester.scrollUntilVisible(
      field,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('satış → iade: mal stoğa döner, orijinal satış durur', (
    tester,
  ) async {
    // 1) Stok girişi: 10 plaka Beyaz Sünger.
    await pump(tester, const PurchaseScreen());
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni tedarikçi ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Öz Sünger');
    await tester.pump();
    await tester.tap(find.text('Tedarikçi kartını aç'));
    await tester.pumpAndSettle();

    await tapAndSettle(
      tester,
      find.byType(DropdownButtonFormField<String>).last,
    );
    await tester.tap(find.text('Beyaz Sünger').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Adet', '10');
    await fill(tester, 'TL/m³', '2500');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Kaydet'));

    final variant = await db.select(db.productVariants).getSingle();
    expect((await db.variantStock(variant.id)).pieces, 10);

    // 2) Satış: 4 plaka.
    await pump(tester, const QuickSaleScreen());
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni müşteri ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mobilyacı Ahmet');
    await tester.pump();
    await tester.tap(find.text('Müşteri kartını aç'));
    await tester.pumpAndSettle();

    // Önce çeşit, sonra ölçü: varyantlar çeşit seçilmeden görünmez.
    await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Beyaz Sünger'));
    await tapAndSettle(tester, find.byType(RadioListTile<String>).first);
    // Varsayılan 1 adet; 4'e çıkar.
    for (var i = 0; i < 3; i++) {
      await tapAndSettle(tester, find.byIcon(Icons.add));
    }
    await fill(tester, 'TL/m³', '3500');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Kaydet'));

    final sale = await db.select(db.sales).getSingle();
    expect(
      (await db.variantStock(variant.id)).pieces,
      6,
      reason: 'satış çıkmadı',
    );

    // 3) Müşteri 2 plakayı geri getirdi: satışlar listesi → detay → İade al.
    await pump(tester, const DocumentsScreen(sales: true));
    await tester.tap(find.text('Mobilyacı Ahmet'));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.text('İade al'));

    expect(find.text('/ 4'), findsOneWidget, reason: 'iade tavanı 4 olmalı');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'İadeyi kaydet'),
    );

    // Mal geri döndü.
    expect(
      (await db.variantStock(variant.id)).pieces,
      8,
      reason: '2 plaka stoğa dönmedi',
    );

    // İade belgesi açıldı, orijinal satış DEĞİŞMEDİ (D-12).
    final ret = await db.select(db.saleReturns).getSingle();
    expect(ret.saleId, sale.id);
    final saleAfter = await db.select(db.sales).getSingle();
    expect(saleAfter.grandTotal, sale.grandTotal);
    expect(saleAfter.status, 'ACTIVE');

    // Cari alacak azaldı: satış artı, iade eksi yazar.
    final ledger = await db.select(db.customerLedger).get();
    expect(ledger, hasLength(2));
    expect(
      ledger.map((l) => l.amount.stored).reduce((a, b) => a + b) <
          sale.grandTotal.stored,
      isTrue,
      reason: 'iade cariden düşmedi',
    );
  });

  testWidgets('iade satılandan fazla olamaz — artı tuşu tavanda kilitlenir', (
    tester,
  ) async {
    await pump(tester, const PurchaseScreen());
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni tedarikçi ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Öz Sünger');
    await tester.pump();
    await tester.tap(find.text('Tedarikçi kartını aç'));
    await tester.pumpAndSettle();
    await tapAndSettle(
      tester,
      find.byType(DropdownButtonFormField<String>).last,
    );
    await tester.tap(find.text('Beyaz Sünger').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Adet', '5');
    await fill(tester, 'TL/m³', '2500');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Kaydet'));

    await pump(tester, const QuickSaleScreen());
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni müşteri ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mobilyacı Ahmet');
    await tester.pump();
    await tester.tap(find.text('Müşteri kartını aç'));
    await tester.pumpAndSettle();
    // Önce çeşit, sonra ölçü: varyantlar çeşit seçilmeden görünmez.
    await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Beyaz Sünger'));
    await tapAndSettle(tester, find.byType(RadioListTile<String>).first);
    await fill(tester, 'TL/m³', '3500');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Kaydet'));

    await pump(tester, const DocumentsScreen(sales: true));
    await tester.tap(find.text('Mobilyacı Ahmet'));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.text('İade al'));

    // 1 adet satıldı; bir kez artırınca tavan dolar.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final plus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
    );
    expect(plus.onPressed, isNull, reason: 'tavanda artı tuşu açık kalmış');
  });
}
