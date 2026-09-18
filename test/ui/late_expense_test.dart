import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/documents/documents_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';

import '../data/test_db.dart';

/// **Nakliye faturası sonradan geldiğinde ne oluyor?**
///
/// `addLateExpense` Faz 1'den beri yazılıydı ve maliyet motoru testliydi;
/// ama hiçbir ekrandan çağrılmıyordu (SK-22). Fabrikadan mal gelir, fatura
/// bir hafta sonra gelir — bu, toptancının haftalık gerçeği.
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

  testWidgets('sonradan gelen nakliye parti maliyetini artırır', (
    tester,
  ) async {
    // 10 plaka × 2.500 TL/m³ → 2,8 m³, çıplak maliyet 2.500 TL/m³.
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

    final before = await db.select(db.inventoryBatches).getSingle();
    expect(before.realUnitCostM3.perM3.toString(), '2500');

    // Alışlar → belge → masraf ekle: 280 TL nakliye.
    await pump(tester, const DocumentsScreen(sales: false));
    await tester.tap(find.text('Öz Sünger'));
    await tester.pumpAndSettle();
    await tapAndSettle(
      tester,
      find.text('Masraf ekle (sonradan gelen fatura)'),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Tutar (TL)'), '280');
    await tester.pump();
    await tapAndSettle(tester, find.text('Masrafı ekle'));

    // 280 TL / 2,8 m³ = 100 TL/m³ → gerçek maliyet 2.600 TL/m³.
    final after = await db.select(db.inventoryBatches).getSingle();
    expect(
      after.realUnitCostM3.perM3.toString(),
      '2600',
      reason: 'masraf parti maliyetine dağıtılmadı',
    );

    // Masraf belgeye "sonradan" işaretiyle yazıldı.
    final expense = await db.select(db.purchaseExpenses).getSingle();
    expect(expense.kind, PurchaseExpenseKind.freight);
    expect(expense.addedLater, isTrue);

    // Çıplak maliyet DEĞİŞMEZ: fabrikaya ödenen para o kadardı.
    expect(after.bareUnitCostM3.perM3.toString(), '2500');
  });
}
