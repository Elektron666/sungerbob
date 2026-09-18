import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';

import '../data/test_db.dart';

/// **Çekirdek döngü: boş veritabanından gerçek stoğa.**
///
/// Bu testin var olma sebebi: iş kuralları ve onların testleri hazırdı ama
/// kullanıcı hiçbirine erişemiyordu (SK-21). İş mantığının testten geçmesi,
/// ekranın kullanılabilir olduğunu göstermez.
///
/// Burada hiçbir veri hazırlanmaz, hiçbir repository doğrudan çağrılmaz —
/// her şey **ekranlara dokunarak** yapılır. Kullanıcının yaptığı neyse o.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(home: child),
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

  testWidgets('sıfırdan stok girişi: tedarikçi aç, malı gir, stoğa düşsün', (
    tester,
  ) async {
    await pump(tester, const PurchaseScreen());

    // Başlangıç: hiçbir şey yok.
    expect(await db.select(db.suppliers).get(), isEmpty);

    // 1) Tedarikçi kartını açılır listeden aç.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni tedarikçi ekle').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Öz Sünger');
    await tester.pump();
    await tester.tap(find.text('Tedarikçi kartını aç'));
    await tester.pumpAndSettle();

    // 2) Sünger çeşidi (seed'den gelen 12 üründen biri).
    final productPicker = find.byType(DropdownButtonFormField<String>).last;
    await tester.scrollUntilVisible(
      productPicker,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(productPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyaz Sünger').last);
    await tester.pumpAndSettle();

    // 3) Ölçü, adet, fiyat. (En/boy/kalınlık varsayılan geliyor.)
    await fill(tester, 'Adet', '10');
    await fill(tester, 'TL/m³', '2500');

    // 4) Kaydet.
    final save = find.widgetWithText(FilledButton, 'Kaydet');
    await tester.scrollUntilVisible(
      save,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    // Gerçekten stok oluştu mu?
    final purchases = await db.select(db.purchases).get();
    expect(purchases, hasLength(1), reason: 'alış kaydedilmedi');

    final variant = await db.select(db.productVariants).getSingle();
    final stock = await db.variantStock(variant.id);
    expect(stock.pieces, 10, reason: 'stoğa düşmedi');

    // 140 × 200 × 10 cm × 10 adet = 2,8 m³
    expect(stock.volume.m3.toString(), '2.8');

    final batches = await db.select(db.inventoryBatches).get();
    expect(batches, hasLength(1), reason: 'parti açılmadı');
    expect(batches.single.remainingPieces, 10);
  });

  testWidgets('tedarikçi seçilmeden kaydedilmez', (tester) async {
    await pump(tester, const PurchaseScreen());

    await fill(tester, 'Adet', '5');
    await fill(tester, 'TL/m³', '1000');

    final save = find.widgetWithText(FilledButton, 'Kaydet');
    await tester.scrollUntilVisible(
      save,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(await db.select(db.purchases).get(), isEmpty);
    // Eksik olan adıyla söylenmeli.
    // İpucu metni ve hata kartı: ikisi de aynı cümleyi söyler.
    expect(find.text('Tedarikçi seçin'), findsWidgets);
  });
}
