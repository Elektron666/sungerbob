import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/theme/app_theme.dart';
import 'package:sungerbob/ui/widgets/common.dart';

void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  group('Tema (BRIEF §7)', () {
    test('açık ve koyu tema üretilir, Material 3', () {
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().useMaterial3, isTrue);
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });

    test('tek vurgu rengi her iki temada da tohum', () {
      expect(AppTheme.light().colorScheme.primary, isNotNull);
      expect(AppTheme.dark().colorScheme.primary, isNotNull);
    });

    test('dokunma alanları en az 48 dp', () {
      final style = AppTheme.light().filledButtonTheme.style;
      final size = style?.minimumSize?.resolve({});
      expect(size!.height, greaterThanOrEqualTo(AppTheme.minTouchTarget));
    });
  });

  group('Boş durumlar — mock veri yok (BRIEF §0)', () {
    testWidgets('EmptyState başlık ve açıklamayı gösterir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Bu çeşitten stok yok',
              description: 'Stok girişi yaparak ekleyebilirsiniz.',
            ),
          ),
        ),
      );

      expect(find.text('Bu çeşitten stok yok'), findsOneWidget);
      expect(
        find.text('Stok girişi yaparak ekleyebilirsiniz.'),
        findsOneWidget,
      );
    });

    testWidgets('ErrorState Türkçe mesaj ve tekrar dene gösterir', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              error: 'Yetersiz stok',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Bir sorun oluştu'), findsOneWidget);
      expect(find.text('Yetersiz stok'), findsOneWidget);

      await tester.tap(find.text('Tekrar dene'));
      expect(retried, isTrue);
    });
  });

  group('Maliyeti gizle (BRIEF §5)', () {
    testWidgets('gizli modda değer görünmez', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SensitiveValue(hidden: true, value: '51.282,00 TL'),
          ),
        ),
      );
      expect(find.text('51.282,00 TL'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });

    testWidgets('açık modda değer görünür', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SensitiveValue(hidden: false, value: '51.282,00 TL'),
          ),
        ),
      );
      expect(find.text('51.282,00 TL'), findsOneWidget);
    });
  });

  group('StatCard', () {
    testWidgets('etiket ve rakamı gösterir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'STOK MALİYETİ',
              value: '34.692,00 TL',
              secondary: 'KDV hariç',
            ),
          ),
        ),
      );

      expect(find.text('STOK MALİYETİ'), findsOneWidget);
      expect(find.text('34.692,00 TL'), findsOneWidget);
      expect(find.text('KDV hariç'), findsOneWidget);
    });
  });
}
