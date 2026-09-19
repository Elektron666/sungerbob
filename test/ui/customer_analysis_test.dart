import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';
import 'package:sungerbob/ui/screens/reports/reports_screen.dart';
import 'package:sungerbob/ui/screens/sale/quick_sale_screen.dart';

import '../data/test_db.dart';

/// **"Hangi müşteri ne kadar kâr bıraktı?"**
///
/// `customerAnalysis` Faz 4'te yazılmıştı ama hiçbir ekrandan
/// çağrılmıyordu (SK-22). Rapor artık Raporlar → Müşteriler sekmesinde.
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

  testWidgets('satış sonrası müşteri raporda ciro ve kârıyla görünür', (
    tester,
  ) async {
    // Boşken rapor boş durumla açılmalı (mock veri yok kuralı).
    await pump(tester, const ReportsScreen());
    await tapAndSettle(tester, find.text('Müşteriler'));
    expect(find.text('Henüz müşteri hareketi yok'), findsOneWidget);

    // 10 plaka al (2.500 TL/m³), 1 plaka sat (3.500 TL/m³).
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

    // 0,28 m³ × 3.500 = 980 TL ciro; maliyet 0,28 × 2.500 = 700 TL.
    await pump(tester, const ReportsScreen());
    await tapAndSettle(tester, find.text('Müşteriler'));

    expect(find.text('Mobilyacı Ahmet'), findsOneWidget);
    expect(find.text('980,00 TL'), findsWidgets, reason: 'ciro yok');
    expect(find.text('280,00 TL'), findsWidgets, reason: 'brüt kâr yanlış');

    // Henüz tahsilat yok: borç ciro + KDV kadar.
    expect(find.text('Güncel borç'), findsOneWidget);
    expect(find.text('Ort. ödeme süresi'), findsOneWidget);
    expect(find.text('henüz kapanmış belge yok'), findsOneWidget);
  });
}
