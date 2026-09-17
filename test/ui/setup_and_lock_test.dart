import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/screens/setup/setup_wizard_screen.dart';
import 'package:sungerbob/ui/widgets/pin_pad.dart';

/// Kurulum sihirbazı ve PIN tuş takımı (BRIEF §7).
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  Future<void> openPinStep(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SetupWizardScreen())),
    );
    await tester.pump();
    await tester.tap(find.text('Yeni başla'), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  bool continueEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Devam'))
          .onPressed !=
      null;

  group('PIN tuş takımı', () {
    testWidgets('basılan tuşu bildirir, değeri kendisi biriktirmez', (
      tester,
    ) async {
      final pressed = <String>[];
      var backspaces = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinPad(
              title: 'PIN',
              value: '12',
              onDigit: pressed.add,
              onBackspace: () => backspaces++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('7'));
      await tester.tap(find.text('0'));
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      // Widget "127" gibi bir değer üretmez; yalnızca haneyi iletir.
      expect(pressed, ['7', '0']);
      expect(backspaces, 1);
    });

    testWidgets('dolu PIN görünse de tuşlar yine bildirilir', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinPad(
              title: 'PIN',
              value: '1234',
              onDigit: pressed.add,
              onBackspace: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('9'));
      await tester.pump();
      // Sınır kontrolü çağırana ait; widget basışı yutmaz.
      expect(pressed, ['9']);
    });

    testWidgets('0 ve geri silme kısa ekranda da ekrana sığar', (tester) async {
      // Yatay / kısa ekran: ekran görüntüsündeki durum.
      tester.view.physicalSize = const Size(1058, 564);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinPad(
              title: 'PIN',
              value: '',
              onDigit: (_) {},
              onBackspace: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      for (final finder in [
        find.text('0'),
        find.byIcon(Icons.backspace_outlined),
      ]) {
        expect(finder, findsOneWidget);
        expect(
          tester.getRect(finder).bottom,
          lessThanOrEqualTo(564),
          reason: 'tuş ekran dışında kalıyor',
        );
      }
    });
  });

  group('Kurulum sihirbazı — PIN adımı', () {
    testWidgets('ilk adımda yeni başla ve geri yükleme seçenekleri var', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SetupWizardScreen())),
      );
      await tester.pump();

      expect(find.text('Yeni başla'), findsOneWidget);
      expect(find.text('Yedekten geri yükle'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('kullanıcı adı ve eşleşen PIN girilince devam açılır', (
      tester,
    ) async {
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (var round = 0; round < 2; round++) {
        for (final digit in ['1', '2', '3', '4']) {
          await tester.tap(find.text(digit), warnIfMissed: false);
          await tester.pump();
        }
      }
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('HIZLI basışta hiçbir hane kaybolmaz', (tester) async {
      // Gerçek kullanım: kullanıcı tuşlara art arda basar, iki dokunuş
      // arasında kare çizilmez. Eski sürüm burada kilitleniyordu.
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '1', '2', '3', '4']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      expect(find.text("PIN'ler aynı değil"), findsNothing);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('sıfır içeren PIN girilebilir', (tester) async {
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['0', '0', '4', '7', '0', '0', '4', '7']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('geri silme yalnızca son haneyi siler', (tester) async {
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '9']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      // Doğrulamada tek hane var; bir geri silme onu siler, ikincisi ilk
      // PIN'e döner — tamamını silmez.
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(find.text('4 haneli PIN belirleyin'), findsOneWidget);
      await tester.tap(find.text('4'), warnIfMissed: false);
      await tester.pump();
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('PIN tekrarı tutmazsa uyarı çıkar ve devam kapalı kalır', (
      tester,
    ) async {
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '9', '9', '9', '9']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      expect(find.text("PIN'ler aynı değil"), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
    });

    testWidgets('sıfırla düğmesi çıkmazdan kurtarır', (tester) async {
      await openPinStep(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '9', '9', '9', '9']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      await tester.tap(find.text("PIN'i sıfırla"));
      await tester.pump();

      expect(find.text('4 haneli PIN belirleyin'), findsOneWidget);
      expect(find.text("PIN'ler aynı değil"), findsNothing);
    });

    testWidgets('devam kapalıyken nedeni ekranda yazar', (tester) async {
      await openPinStep(tester);

      // Kullanıcı adı yok.
      expect(find.text('Kullanıcı adı girin'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Ahmet');
      await tester.pump();
      expect(find.text('PIN 4 haneli olmalı'), findsOneWidget);

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit), warnIfMissed: false);
        await tester.pump();
      }
      expect(find.text("PIN'i bir kez daha girin"), findsOneWidget);
    });
  });
}
