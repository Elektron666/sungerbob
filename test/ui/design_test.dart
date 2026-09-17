import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/ui/content/daily_quote.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/theme/app_theme.dart';
import 'package:sungerbob/ui/widgets/common.dart';
import 'package:sungerbob/ui/widgets/signature.dart';

/// Tasarım dilinin sabitleri (BRIEF §7).
///
/// Bu testler "güzel mi" demiyor — **kural bozuldu mu** diyor: kontrast,
/// dokunma alanı, tek vurgu rengi, imzanın yerinde durması.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  /// WCAG bağıl parlaklık.
  double luminance(Color c) => c.computeLuminance();

  double contrast(Color a, Color b) {
    final l1 = luminance(a), l2 = luminance(b);
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('Palet', () {
    for (final entry in {
      'açık': AppTheme.light(),
      'koyu': AppTheme.dark(),
    }.entries) {
      test('${entry.key} temada metin kontrastı yeterli', () {
        final s = entry.value.colorScheme;
        // Gövde metni için WCAG AA: 4.5.
        expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onError, s.error), greaterThanOrEqualTo(4.5));
        expect(
          contrast(s.onSecondaryContainer, s.secondaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        // İkincil metin daha soluk ama yine okunur olmalı (AA large: 3.0).
        expect(
          contrast(s.onSurfaceVariant, s.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('${entry.key} temada zemin sıcak nötr, saf gri değil', () {
        final surface = entry.value.colorScheme.surface;
        // Sıcaklık: kırmızı kanal maviden yüksek olmalı.
        expect(
          (surface.r * 255).round(),
          greaterThan((surface.b * 255).round()),
          reason: 'zemin soğuk görünüyor',
        );
      });
    }

    test('tek vurgu rengi: ceviz', () {
      expect(AppTheme.light().colorScheme.primary, AppTheme.accent);
    });
  });

  group('Tipografi', () {
    test('başlıklar serif, gövde ve etiketler sans', () {
      final t = AppTheme.light().textTheme;
      expect(t.displayMedium?.fontFamily, AppTheme.serifFamily);
      expect(t.headlineMedium?.fontFamily, AppTheme.serifFamily);
      expect(t.bodyLarge?.fontFamily, AppTheme.sansFamily);
      expect(t.labelSmall?.fontFamily, AppTheme.sansFamily);
    });

    testWidgets('rakamlar tabular figür kullanır', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final style in [ctx.numberStyle, ctx.bigNumberStyle]) {
        expect(style.fontFeatures, contains(AppTheme.tabularFigures));
      }
    });
  });

  group('Dokunma alanı', () {
    testWidgets('düğmeler en az 48 dp', (tester) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Kaydet')),
              OutlinedButton(onPressed: () {}, child: const Text('Vazgeç')),
            ],
          ),
        ),
      );
      for (final type in [FilledButton, OutlinedButton]) {
        expect(
          tester.getSize(find.byType(type)).height,
          greaterThanOrEqualTo(AppTheme.minTouchTarget),
        );
      }
    });
  });

  group('Günün Sözü kartı', () {
    testWidgets('sözü, kaynağını ve başlığını gösterir', (tester) async {
      final day = DateTime(2026, 4, 23);
      final quote = DailyQuote.of(day);

      await tester.pumpWidget(wrap(DailyQuoteCard(now: day)));

      expect(find.text('GÜNÜN SÖZÜ'), findsOneWidget);
      expect(find.text(quote.text), findsOneWidget);
      expect(find.text('— ${quote.source}'), findsOneWidget);
    });

    testWidgets('söz serif ile dizilir', (tester) async {
      final day = DateTime(2026, 4, 23);
      await tester.pumpWidget(wrap(DailyQuoteCard(now: day)));

      final text = tester.widget<Text>(find.text(DailyQuote.of(day).text));
      expect(text.style?.fontFamily, AppTheme.serifFamily);
    });

    testWidgets('koyu temada da okunur', (tester) async {
      final day = DateTime(2026, 4, 23);
      await tester.pumpWidget(
        wrap(DailyQuoteCard(now: day), brightness: Brightness.dark),
      );
      expect(find.text(DailyQuote.of(day).text), findsOneWidget);
    });
  });

  group('Karşılama', () {
    testWidgets('isim varsa selama eklenir', (tester) async {
      await tester.pumpWidget(
        wrap(GreetingHeader(userName: 'Fatih', now: DateTime(2026, 4, 23, 9))),
      );
      expect(find.text('Günaydın, Fatih'), findsOneWidget);
      expect(find.text('23 Nisan 2026, Perşembe'), findsOneWidget);
    });

    testWidgets('isim yoksa yalnızca selam', (tester) async {
      await tester.pumpWidget(
        wrap(GreetingHeader(now: DateTime(2026, 4, 23, 20))),
      );
      expect(find.text('İyi akşamlar'), findsOneWidget);
    });

    testWidgets('boş isim selamı bozmaz', (tester) async {
      await tester.pumpWidget(
        wrap(GreetingHeader(userName: '   ', now: DateTime(2026, 4, 23, 14))),
      );
      expect(find.text('İyi günler'), findsOneWidget);
    });
  });

  group('İmza', () {
    testWidgets('tasarımcı adı görünür', (tester) async {
      await tester.pumpWidget(wrap(const DesignSignature()));
      expect(find.textContaining(DesignSignature.designer), findsOneWidget);
    });

    test('imza adı sabit', () {
      expect(DesignSignature.designer, 'Fatih Özdemir');
    });
  });

  group('Ortak parçalar', () {
    testWidgets('bölüm başlığı büyük harfe çevirir', (tester) async {
      await tester.pumpWidget(wrap(const SectionHeader(title: 'Yedekleme')));
      expect(find.text('YEDEKLEME'), findsOneWidget);
    });

    testWidgets('kart etiketi büyük harf, değer olduğu gibi', (tester) async {
      await tester.pumpWidget(
        wrap(const StatCard(label: 'Toplam stok', value: '11,76 m³')),
      );
      expect(find.text('TOPLAM STOK'), findsOneWidget);
      expect(find.text('11,76 m³'), findsOneWidget);
    });

    testWidgets('boş durum başlığı ve açıklaması görünür', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            height: 400,
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Stokta ürün yok',
              description: 'Önce stok girişi yapın.',
            ),
          ),
        ),
      );
      expect(find.text('Stokta ürün yok'), findsOneWidget);
      expect(find.text('Önce stok girişi yapın.'), findsOneWidget);
    });
  });
}
