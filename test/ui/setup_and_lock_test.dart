import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/screens/setup/setup_wizard_screen.dart';
import 'package:sungerbob/ui/widgets/pin_pad.dart';

/// Kurulum sihirbazı ve PIN tuş takımı (BRIEF §7).
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  Future<void> pumpWizard(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SetupWizardScreen())),
    );
    await tester.pump();
  }

  group('PIN tuş takımı', () {
    testWidgets('basılan rakamlar değeri büyütür, geri silme küçültür', (
      tester,
    ) async {
      var value = '';
      var completed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PinPad(
                title: 'PIN',
                value: value,
                onChanged: (v) => setState(() => value = v),
                onCompleted: () => completed++,
              ),
            ),
          ),
        ),
      );

      for (final digit in ['1', '2', '3']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(value, '123');
      expect(completed, 0);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(value, '12');

      for (final digit in ['7', '8']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(value, '1278');
      // 4 hane dolunca doğrulama tetiklenir.
      expect(completed, 1);
    });

    testWidgets('dolu PIN daha fazla rakam almaz', (tester) async {
      var value = '1234';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PinPad(
                title: 'PIN',
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('9'));
      await tester.pump();
      expect(value, '1234');
    });
  });

  group('Kurulum sihirbazı', () {
    testWidgets('ilk adımda yeni başla ve geri yükleme seçenekleri var', (
      tester,
    ) async {
      await pumpWizard(tester);

      expect(find.text('Yeni başla'), findsOneWidget);
      expect(find.text('Yedekten geri yükle'), findsOneWidget);
      // İlk adımda geri düğmesi yok.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('PIN adımında kullanıcı adı ve PIN olmadan devam edilemez', (
      tester,
    ) async {
      await pumpWizard(tester);
      await tester.tap(find.text('Yeni başla'));
      await tester.pumpAndSettle();

      expect(find.text('Kullanıcı adı'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Devam'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('kullanıcı adı ve eşleşen PIN girilince devam açılır', (
      tester,
    ) async {
      await pumpWizard(tester);
      await tester.tap(find.text('Yeni başla'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      // Önce PIN, sonra tekrarı.
      for (var round = 0; round < 2; round++) {
        for (final digit in ['1', '2', '3', '4']) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }
      }

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Devam'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('PIN tekrarı tutmazsa uyarı çıkar ve devam kapalı kalır', (
      tester,
    ) async {
      await pumpWizard(tester);
      await tester.tap(find.text('Yeni başla'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '9', '9', '9', '9']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }

      expect(find.text('PIN\'ler aynı değil'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Devam'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
