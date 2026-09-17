import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/main.dart';
import 'package:sungerbob/ui/app_router.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/shell.dart';

/// Duman testi: uygulamanın tamamının derlendiğini ve açıldığını doğrular.
///
/// `main.dart`, yönlendirici ve tüm ekranlar buradan import edildiği için
/// derleme hataları `flutter test` ile yakalanır — Android SDK gerekmez.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  testWidgets('uygulama açılıyor ve ana sayfa kabuğu görünüyor', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SungerApp()));
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
    await tester.pumpWidget(const ProviderScope(child: SungerApp()));
    await tester.pump();

    expect(find.text('+ SATIŞ'), findsOneWidget);
    expect(find.text('+ STOK GİRİŞİ'), findsOneWidget);
    expect(find.text('+ TAHSİLAT'), findsOneWidget);
    expect(find.text('STOK SORGULA'), findsOneWidget);
    expect(find.text('CARİ SORGULA'), findsOneWidget);
  });

  testWidgets('menü ekranı yedekleme girişlerini içeriyor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pump();

    expect(find.text('Yedek Al'), findsOneWidget);
    expect(find.text('Yedekten Yükle'), findsOneWidget);
    expect(find.text('Yedekler'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
  });

  test('yönlendirici kurulabiliyor ve rotalar tanımlı', () {
    final router = buildRouter();
    expect(router.configuration.routes, isNotEmpty);
  });
}
