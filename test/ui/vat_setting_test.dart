import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';
import 'package:sungerbob/ui/screens/sale/quick_sale_screen.dart';

import '../data/test_db.dart';

/// **Ayarlardaki KDV oranı belgelere gerçekten uygulanıyor mu?**
///
/// Satış, alış ve teklif ekranları oranı koda gömülü %20 tutuyordu.
/// Kullanıcı Ayarlar'da %10 seçse bile her belge %20 hesaplıyordu — ve bu
/// sessizce oluyordu, hiçbir ekran yanlış olduğunu söylemiyordu. Para
/// hesabının ayarı görmezden gelmesi kabul edilemez (D-32).
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

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
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('KDV %10 seçilince satış da alış da %10 hesaplar', (
    tester,
  ) async {
    // Ayar: %10 (×100 ölçeğinde 1000).
    await SettingsRepository(db).setDefaultVatRate(1000);

    // Alış: 10 plaka × 2.500 TL/m³ = 2,8 m³ × 2500 = 7.000 TL net.
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

    final purchase = await db.select(db.purchases).getSingle();
    expect(purchase.subtotalNet, Money.parse('7000'));
    expect(
      purchase.vatTotal,
      Money.parse('700'),
      reason: 'alışta KDV %20 hesaplanmış — ayar görmezden gelinmiş',
    );

    // Satış: 1 plaka = 0,28 m³ × 3.500 = 980 TL net, %10 KDV = 98 TL.
    await pump(tester, const QuickSaleScreen());
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni müşteri ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mobilyacı Ahmet');
    await tester.pump();
    await tester.tap(find.text('Müşteri kartını aç'));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Beyaz Sünger'));
    await tapAndSettle(tester, find.byType(RadioListTile<String>).first);
    await fill(tester, 'TL/m³', '3500');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Kaydet'));

    final sale = await db.select(db.sales).getSingle();
    expect(sale.subtotalNet, Money.parse('980'));
    expect(
      sale.vatTotal,
      Money.parse('98'),
      reason: 'satışta KDV %20 hesaplanmış — ayar görmezden gelinmiş',
    );
  });

  testWidgets('ayar yoksa %20 varsayılır', (tester) async {
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

    final purchase = await db.select(db.purchases).getSingle();
    expect(purchase.vatTotal, Money.parse('1400'));
  });
}
