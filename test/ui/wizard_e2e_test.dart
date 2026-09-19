import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/backup/backup_password_store.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/setup/setup_wizard_screen.dart';

import '../data/test_db.dart';

/// Kurulum sihirbazını **baştan sona** sürer.
///
/// Adım adım test etmek yetmiyordu: kullanıcı sihirbazı bitiremediğini
/// bildirdi, oysa tek tek adım testleri geçiyordu. Burada sekiz adımın
/// tamamı gerçek bir veritabanıyla sürülüyor ve sonunda ayarların
/// gerçekten yazıldığı doğrulanıyor.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  late InMemoryBackupPasswordStore passwords;

  setUp(() {
    db = newTestDatabase();
    passwords = InMemoryBackupPasswordStore();
  });
  tearDown(() async => db.close());

  Future<void> pumpWizard(WidgetTester tester, {Size? screen}) async {
    tester.view.physicalSize = screen ?? const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          backupPasswordStoreProvider.overrideWithValue(passwords),
        ],
        child: const MaterialApp(home: SetupWizardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapContinue(WidgetTester tester, String step) async {
    final finder = find.widgetWithText(FilledButton, 'Devam');
    final button = tester.widget<FilledButton>(finder);
    expect(
      button.onPressed,
      isNotNull,
      reason: '"$step" adımında Devam kapalı kaldı',
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Tuşlara **gerçekten basılabildiğini** doğrular.
  ///
  /// `warnIfMissed: false` ile ıskalayan dokunuş sessizce yutuluyordu ve
  /// ekranın altında kalan tuş sırası testten kaçmıştı. Artık ıskalama
  /// testi düşürür.
  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
  }

  /// Kullanıcının hata bildirdiği ekran yatay ve kısaydı; dikey telefonda
  /// çalışan akış orada kırılabilir.
  for (final screen in const [
    (name: 'dikey telefon', size: Size(411, 891)),
    (name: 'yatay / kısa ekran', size: Size(1058, 564)),
    (name: 'dar telefon', size: Size(360, 640)),
    (name: 'çok küçük ekran', size: Size(320, 568)),
  ]) {
    testWidgets('${screen.name}: dokuz adım tamamlanır ve ayarlar yazılır', (
      tester,
    ) async {
      await pumpWizard(tester, screen: screen.size);

      // 1 — Başlangıç
      await tester.tap(find.text('Yeni başla'));
      await tester.pumpAndSettle();

      // 2 — Kullanıcı adı
      await tester.enterText(find.byType(TextFormField).first, 'Fatih');
      await tester.pump();
      await tapContinue(tester, 'Kullanıcı adı');

      // 3 — PIN (kendi ekranında; tuş takımı tam görünür)
      await enterPin(tester, '1907');
      await enterPin(tester, '1907');
      await tapContinue(tester, 'PIN');

      // 4 — Yedek şifresi
      final passwordFields = find.byType(TextFormField);
      await tester.enterText(passwordFields.at(0), 'sunger2026');
      await tester.pump();
      await tester.enterText(passwordFields.at(1), 'sunger2026');
      await tester.pump();
      await tapContinue(tester, 'Yedek şifresi');

      // 5 — Firma bilgileri
      await tester.enterText(
        find.byType(TextFormField).first,
        'Özdemir Sünger',
      );
      await tester.pump();
      await tapContinue(tester, 'Firma bilgileri');

      // 6 — KDV ve fiyat modu
      await tapContinue(tester, 'KDV ve fiyat modu');

      // 7 — Maliyet yöntemi
      await tapContinue(tester, 'Maliyet yöntemi');

      // 8 — Google Drive (atlanabilir)
      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();

      // 9 — Açılış işlemleri → Bitir
      await tester.tap(find.widgetWithText(FilledButton, 'Bitir'));
      await tester.pumpAndSettle();

      // Ayarlar gerçekten yazıldı mı?
      final settings = SettingsRepository(db);
      expect(
        await settings.isSetupCompleted(),
        isTrue,
        reason: 'kurulum bitmedi',
      );
      expect(await settings.userName(), 'Fatih');
      expect(await settings.hasPin(), isTrue);
      expect(await settings.verifyPin('1907'), isTrue);
      expect((await settings.company()).name, 'Özdemir Sünger');
      expect(await passwords.read(), 'sunger2026');
    });
  }

  testWidgets('demo giriş kurulumu atlayıp uygulamayı açar', (tester) async {
    await pumpWizard(tester);

    await tester.tap(find.text('Demo ile hızlı gir'));
    await tester.pumpAndSettle();

    final settings = SettingsRepository(db);
    expect(await settings.isSetupCompleted(), isTrue);
    expect(await settings.hasPin(), isTrue);
    expect(await settings.verifyPin(SetupWizardScreen.demoPin), isTrue);
    expect(await settings.userName(), 'Demo');
    expect(await passwords.read(), SetupWizardScreen.demoBackupPassword);
  });

  testWidgets('demo giriş sahte kayıt üretmez', (tester) async {
    await pumpWizard(tester);
    await tester.tap(find.text('Demo ile hızlı gir'));
    await tester.pumpAndSettle();

    // Kayıt defteri boş açılmalı: uydurma satış/cari sonradan gerçek
    // kayıtlarla karışır.
    for (final table in [
      'sales',
      'purchases',
      'customer_ledger',
      'stock_movements',
      'inventory_batches',
    ]) {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle();
      expect(row.read<int>('c'), 0, reason: '$table boş değil');
    }
  });
}
