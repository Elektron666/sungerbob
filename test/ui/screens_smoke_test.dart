import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/backup/backup_screen.dart';
import 'package:sungerbob/ui/screens/backup/restore_screen.dart';
import 'package:sungerbob/ui/screens/documents/documents_screen.dart';
import 'package:sungerbob/ui/screens/finance/accounts_screen.dart';
import 'package:sungerbob/ui/screens/finance/collection_screen.dart';
import 'package:sungerbob/ui/screens/finance/customers_screen.dart';
import 'package:sungerbob/ui/screens/finance/instruments_screen.dart';
import 'package:sungerbob/ui/screens/finance/payment_screen.dart';
import 'package:sungerbob/ui/screens/master/parties_screen.dart';
import 'package:sungerbob/ui/screens/master/price_lists_screen.dart';
import 'package:sungerbob/ui/screens/master/products_screen.dart';
import 'package:sungerbob/ui/screens/ops/count_screen.dart';
import 'package:sungerbob/ui/screens/ops/cutting_screen.dart';
import 'package:sungerbob/ui/screens/ops/quote_form_screen.dart';
import 'package:sungerbob/ui/screens/ops/quotes_screen.dart';
import 'package:sungerbob/ui/screens/ops/waste_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';
import 'package:sungerbob/ui/screens/reports/reports_screen.dart';
import 'package:sungerbob/ui/screens/sale/quick_sale_screen.dart';
import 'package:sungerbob/ui/screens/opening/opening_screen.dart';
import 'package:sungerbob/ui/screens/search/search_screen.dart';
import 'package:sungerbob/ui/screens/settings/settings_screen.dart';
import 'package:sungerbob/ui/screens/stock/stock_screen.dart';
import 'package:sungerbob/ui/shell.dart';

import '../data/test_db.dart';

/// **Her ekran dar telefonda taşmadan açılıyor mu?**
///
/// Bugüne kadar bulunan taşmaların hepsi tesadüfen çıktı: biri alış
/// ekranında 66 px, biri satış özetinde 14 px, biri teklif listesinde
/// 16 px. Üçü de kullanıcının gördüğü ekranı bozuyordu ve hiçbiri bir
/// testin konusu değildi.
///
/// Flutter, `RenderFlex overflowed` durumunu test sırasında hata sayar;
/// dolayısıyla ekranı küçük bir telefon boyutunda çizmek tek başına
/// yeterli bir bekçidir.
///
/// Boş veritabanıyla çalışır — "ekranlar boş durumla açılır" kuralının da
/// sınandığı yer burasıdır (CLAUDE.md: mock veri yok).
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  /// Küçük bir Android telefon (360×640) ile normal bir telefon (411×891).
  const sizes = [Size(360, 640), Size(411, 891)];

  final screens = <String, Widget Function()>{
    'Ana menü': MenuScreen.new,
    'Stok': StockScreen.new,
    'Ürünler': ProductsScreen.new,
    'Ürün kartı': ProductFormScreen.new,
    'Fiyat listeleri': PriceListsScreen.new,
    'Fiyat listesi formu': PriceListFormScreen.new,
    'Müşteriler': CustomersScreen.new,
    'Tedarikçiler': SuppliersScreen.new,
    'Stok girişi': PurchaseScreen.new,
    'Hızlı satış': QuickSaleScreen.new,
    'Satışlar': () => const DocumentsScreen(sales: true),
    'Alışlar': () => const DocumentsScreen(sales: false),
    'Teklifler': QuotesScreen.new,
    'Teklif formu': QuoteFormScreen.new,
    'Tahsilat': CollectionScreen.new,
    'Ödeme': PaymentScreen.new,
    'Kasa & Banka': AccountsScreen.new,
    'Çek & Senet': InstrumentsScreen.new,
    'Kesim': CuttingScreen.new,
    'Sayım': CountScreen.new,
    'Fire': WasteScreen.new,
    'Raporlar': ReportsScreen.new,
    'Arama': SearchScreen.new,
    'Açılış işlemleri': OpeningScreen.new,
    'Ayarlar': SettingsScreen.new,
    'Yedek al': BackupScreen.new,
    'Yedekler': BackupListScreen.new,
    'Yedekten yükle': RestoreScreen.new,
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} boş veritabanında taşmadan açılıyor', (
      tester,
    ) async {
      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => db)],
            child: MaterialApp(home: entry.value()),
          ),
        );
        // Bazı ekranlar dosya sistemine bakar; testte o çağrı hiç
        // tamamlanmadığı için yükleme göstergesi dönmeye devam eder ve
        // `pumpAndSettle` zaman aşımına uğrar. Yükleme durumu da çizilen
        // bir durumdur: birkaç kare çizmek taşmayı görmeye yeter.
        try {
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
        } on FlutterError {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Taşma olsaydı çizim sırasında hata fırlardı; buraya gelinmişse
        // ekran çiziliyor demektir.
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${entry.key} ekranı ${size.width.toInt()} px genişlikte '
              'hata verdi',
        );
      }
    });
  }
}
