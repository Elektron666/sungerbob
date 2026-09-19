import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/master/price_lists_screen.dart';

import '../data/test_db.dart';

/// **Zam yapmak.**
///
/// Fiyat listesi iş mantığı (baz × katsayı, yuvarlama, eski versiyonu
/// arşivleme) Faz 1'den beri hazırdı; ekranı yoktu, yani fiyat listesi hiç
/// oluşturulamıyordu.
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

  /// Uzun listede düğmeye basar.
  ///
  /// İki ayrı sorun var: (1) `ListView` görüş alanının dışındaki çocuğu
  /// henüz KURMAMIŞ olabilir — `scrollUntilVisible` onu kurar; (2) kurulmuş
  /// ama ekranın altında kalmış olabilir — `ensureVisible` onu görünür
  /// kılar. İkisi de gerekiyor.
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

  testWidgets('baz fiyat girilir, katsayıyla hesaplanır, yürürlüğe alınır', (
    tester,
  ) async {
    await pump(tester, const PriceListsScreen());
    expect(find.text('Henüz fiyat listesi yok'), findsOneWidget);

    await tester.tap(find.text('Yeni fiyat listesi'));
    await tester.pumpAndSettle();

    // Önizleme görülmeden kaydedilemez.
    expect(find.text('Baz metreküp fiyatını girin'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Baz fiyat (TL/m³)'),
      '1000',
    );
    await tester.pump();
    expect(find.text('Önce önizlemeyi görün'), findsOneWidget);

    await tapAndSettle(tester, find.text('Önizle'));

    // Beyaz Sünger katsayısı 1,00 → baz fiyatın kendisi.
    expect(find.text('Beyaz Sünger'), findsOneWidget);
    expect(find.text('İlk fiyat'), findsWidgets);

    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Listeyi yürürlüğe al'),
    );

    final list = await db.select(db.priceLists).getSingle();
    expect(list.versionNo, 1);
    expect(list.status, 'ACTIVE');

    // Seed'deki 12 ürünün hepsine fiyat yazıldı.
    final items = await db.select(db.priceListItems).get();
    expect(items, hasLength(12));

    final white = await (db.select(
      db.products,
    )..where((p) => p.name.equals('Beyaz Sünger'))).getSingle();
    final whiteItem = items.firstWhere((i) => i.productId == white.id);
    expect(
      whiteItem.effectivePriceM3.perM3.toString(),
      '1000',
      reason: 'katsayı 1,00 olan ürün baz fiyatı almalı',
    );
  });

  testWidgets('ikinci versiyon öncekini arşivler, eskiyi silmez', (
    tester,
  ) async {
    Future<void> createVersion(String base) async {
      await tester.tap(find.text('Yeni fiyat listesi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Baz fiyat (TL/m³)'),
        base,
      );
      await tester.pump();
      await tapAndSettle(tester, find.text('Önizle'));
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Listeyi yürürlüğe al'),
      );
    }

    await pump(tester, const PriceListsScreen());
    await createVersion('1000');
    await createVersion('1200');

    final lists = await db.select(db.priceLists).get();
    expect(lists, hasLength(2), reason: 'eski versiyon silinmiş');

    final active = lists.where((l) => l.status == 'ACTIVE').toList();
    expect(active, hasLength(1));
    expect(active.single.versionNo, 2);
    expect(
      lists.firstWhere((l) => l.versionNo == 1).status,
      'ARCHIVED',
      reason: 'önceki versiyon arşivlenmedi',
    );

    // İkinci versiyonda artık "eski fiyat" görünmeli.
    await tester.tap(find.text('Yeni fiyat listesi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Baz fiyat (TL/m³)'),
      '1200',
    );
    await tester.pump();
    await tapAndSettle(tester, find.text('Önizle'));
    expect(find.textContaining('Eski '), findsWidgets);
  });
}
