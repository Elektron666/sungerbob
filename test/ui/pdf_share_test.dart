import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/documents/pdf_documents.dart';
import 'package:sungerbob/ui/documents/pdf_share.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/documents/documents_screen.dart';
import 'package:sungerbob/ui/screens/ops/quotes_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';
import 'package:sungerbob/ui/screens/sale/quick_sale_screen.dart';

import '../data/test_db.dart';

/// **Belgeler arayüzden gerçekten üretilebiliyor mu?**
///
/// `PdfDocuments` Faz 3'te yazılmış ve test edilmişti — ama hiçbir ekrandan
/// çağrılmıyordu. BRIEF §5'in "WhatsApp'a doğrudan paylaşılır" sözü boşta
/// duruyordu. Burada belgeler **veritabanındaki gerçek kayıttan** üretilir;
/// paylaşım sayfasının kendisi platform işi olduğu için çağrılmaz.
void main() {
  setUpAll(() async {
    await TrFormat.ensureInitialized();
    PdfDocuments.useFonts(
      regular: pw.Font.ttf(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
      bold: pw.Font.ttf(
        File('assets/fonts/NotoSans-Bold.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
    );
  });

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  /// Ekranı boş bir ana rotanın üstüne iter: kaydettikten sonra kendini
  /// kapatan ekranlar doğrudan `home:` verilince Navigator'ı boşaltıyor.
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

  /// PDF dosyaları `%PDF-` ile başlar; bozuk çıktı burada yakalanır.
  void expectPdf(List<int> bytes, {required String reason}) {
    expect(bytes.length, greaterThan(1000), reason: reason);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: reason);
  }

  testWidgets('satış fişi ve cari ekstre gerçek kayıttan üretiliyor', (
    tester,
  ) async {
    // Stok girişi.
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

    // Satış.
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
    final customer = await db.select(db.customers).getSingle();

    expectPdf(
      await buildSaleReceipt(db, sale.id),
      reason: 'satış fişi üretilemedi',
    );
    expectPdf(
      await buildCustomerStatement(db, customer.id),
      reason: 'cari ekstre üretilemedi',
    );

    // Paylaş düğmesi satış detayında görünüyor mu?
    await pump(tester, const DocumentsScreen(sales: true));
    await tester.tap(find.text('Mobilyacı Ahmet'));
    await tester.pumpAndSettle();
    expect(find.text('Fişi paylaş'), findsOneWidget);
  });

  testWidgets('teklif PDF\'i üretiliyor ve düğmesi listede duruyor', (
    tester,
  ) async {
    await pump(tester, const QuotesScreen());
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
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Teklifi kaydet'),
    );

    final quote = await db.select(db.salesQuotes).getSingle();
    expectPdf(await buildQuotePdf(db, quote.id), reason: 'teklif üretilemedi');

    expect(find.text('PDF paylaş'), findsOneWidget);
  });
}
