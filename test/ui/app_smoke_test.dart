import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sungerbob/main.dart';
import 'package:sungerbob/ui/app_router.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/shell.dart';

/// Duman testi: uygulamanın tamamının derlendiğini ve açıldığını doğrular.
///
/// `main.dart`, yönlendirici ve tüm ekranlar buradan import edildiği için
/// derleme hataları `flutter test` ile yakalanır — Android SDK gerekmez.

/// Kilidi açılmış uygulama. Gerçek kapı veritabanını açmaya çalışır; testte
/// şifreli dosya yoktur, o yüzden durum doğrudan verilir.
class _UnlockedGate extends AppLockNotifier {
  @override
  AppGate build() => AppGate.ready;
}

Widget _unlockedApp() => ProviderScope(
  overrides: [appLockProvider.overrideWith(_UnlockedGate.new)],
  child: const SungerApp(),
);

void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  testWidgets('uygulama açılıyor ve ana sayfa kabuğu görünüyor', (
    tester,
  ) async {
    await tester.pumpWidget(_unlockedApp());
    await tester.pump();

    // Alt navigasyonun beş bölümü yerinde.
    expect(find.text('Ana Sayfa'), findsOneWidget);
    expect(find.text('Stok'), findsOneWidget);
    expect(find.text('Cari'), findsOneWidget);
    expect(find.text('Menü'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('hızlı işlem sayfası SPEC §22 butonlarını gösteriyor', (
    tester,
  ) async {
    await tester.pumpWidget(_unlockedApp());
    await tester.pump();

    expect(find.text('+ SATIŞ'), findsOneWidget);
    expect(find.text('+ STOK GİRİŞİ'), findsOneWidget);
    expect(find.text('+ TAHSİLAT'), findsOneWidget);
    expect(find.text('STOK SORGULA'), findsOneWidget);
    expect(find.text('CARİ SORGULA'), findsOneWidget);
  });

  testWidgets('kurulum bitmeden ana sayfa gösterilmez', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SungerApp()));
    await tester.pump();

    // Kapı çözülene kadar yükleniyor; ana sayfa sızmıyor (BRIEF §5).
    expect(find.text('Ana Sayfa'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('menü ekranı yedekleme ve rapor girişlerini içeriyor', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pump();

    expect(find.text('Teklifler'), findsOneWidget);
    expect(find.text('Kesim Emirleri'), findsOneWidget);
    expect(find.text('Sayım'), findsOneWidget);
    expect(find.text('Fire'), findsOneWidget);
    expect(find.text('Raporlar'), findsOneWidget);
    expect(find.text('Açılış İşlemleri'), findsOneWidget);
    expect(find.text('Yedek Al'), findsOneWidget);
    expect(find.text('Yedekten Yükle'), findsOneWidget);
    expect(find.text('Yedekler'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
  });

  test('yönlendirici kurulabiliyor ve rotalar tanımlı', () {
    final router = buildRouter();
    expect(router.configuration.routes, isNotEmpty);
  });

  test('menüdeki ve sihirbazdaki her rota tanımlı', () {
    final router = buildRouter();
    final defined = <String>{};

    void collect(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) defined.add(route.path);
        collect(route.routes);
      }
    }

    collect(router.configuration.routes);

    // Menüden, hızlı işlemlerden ve kurulum sihirbazından çağrılan rotalar.
    // Tanımsız bir rota çalışma anında "page not found" ekranı verir.
    for (final route in const [
      '/',
      '/stock',
      '/customers',
      '/menu',
      '/sale/new',
      '/purchase/new',
      '/collection/new',
      '/quotes',
      '/cutting',
      '/cutting/new',
      '/count',
      '/waste',
      '/reports',
      '/opening',
      '/backup',
      '/backups',
      '/restore',
      '/settings',
      '/settings/drive',
    ]) {
      expect(defined, contains(route), reason: '$route tanımlı değil');
    }
  });
}
