import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/ops/quotes_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';

import '../data/test_db.dart';

/// **Teklif: yazılabiliyor mu, satışa dönüyor mu?**
///
/// Teklif listesi ve "satışa çevir" hazırdı ama teklifi yazacak ekran
/// yoktu — yani liste hiç dolmuyordu. Bu test boş veritabanından başlar ve
/// yalnızca ekranlara dokunur.
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
    // Form uzun; düğme ağaçta olsa da görüş alanının altında kalabiliyor.
    // `ensureVisible` onu gerçekten görünür hâle getirir.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('teklif yazılır, satışa çevrilince stok düşer', (tester) async {
    // Önce stok: teklif stoğa dokunmaz ama satışa dönerken mal gerekir.
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

    // Teklif: müşteri + tek kalem.
    await pump(tester, const QuotesScreen());
    expect(find.text('Henüz teklif yok'), findsOneWidget);

    await tester.tap(find.text('Yeni teklif'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni müşteri ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mobilyacı Ahmet');
    await tester.pump();
    await tester.tap(find.text('Müşteri kartını aç'));
    await tester.pumpAndSettle();

    await tapAndSettle(tester, find.text('Kalem ekle'));
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyaz Sünger').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Adet', '3');
    await fill(tester, 'TL/m³', '3500');
    await tapAndSettle(tester, find.text('Kalemi ekle'));

    // Kalem eklenmeden kaydet düğmesi kapalıydı; şimdi açılmalı.
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Teklifi kaydet'),
    );

    final quote = await db.select(db.salesQuotes).getSingle();
    expect(quote.status, QuoteStatus.draft);
    // Teklif stoğa DOKUNMAZ.
    expect(
      (await db.variantStock(variant.id)).pieces,
      10,
      reason: 'teklif stoktan düşmüş',
    );

    // Satışa çevir.
    await tapAndSettle(tester, find.text('Satışa çevir'));

    final sale = await db.select(db.sales).getSingle();
    expect(sale.salesQuoteId, quote.id);
    expect(
      (await db.variantStock(variant.id)).pieces,
      7,
      reason: 'satışa çevrilince stok düşmedi',
    );

    final converted = await db.select(db.salesQuotes).getSingle();
    expect(converted.status, QuoteStatus.converted);
  });

  testWidgets('müşterisiz ve kalemsiz teklif kaydedilmez', (tester) async {
    await pump(tester, const QuotesScreen());
    await tester.tap(find.text('Yeni teklif'));
    await tester.pumpAndSettle();

    // Eksik olan adıyla söylenmeli.
    expect(find.text('Müşteri seçin'), findsWidgets);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Teklifi kaydet'),
    );
    expect(save.onPressed, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni müşteri ekle').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mobilyacı Ahmet');
    await tester.pump();
    await tester.tap(find.text('Müşteri kartını aç'));
    await tester.pumpAndSettle();

    // Müşteri var ama kalem yok: hâlâ kapalı ve sebebi yazılı.
    expect(find.text('En az bir kalem ekleyin'), findsOneWidget);
    expect(await db.select(db.salesQuotes).get(), isEmpty);
  });
}
