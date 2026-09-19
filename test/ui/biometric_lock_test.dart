import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/auth/biometric_auth.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/lock/pin_lock_screen.dart';

import '../data/test_db.dart';

/// **Parmak izi ile kilit açma (BRIEF §5).**
///
/// `local_auth` bağımlılık listesindeydi, `isBiometricEnabled` ayarı
/// yazılıydı — ama hiçbir yerden çağrılmıyordu; kilit yalnızca PIN'di.
///
/// Gerçek biyometri testte çalıştırılamaz; bu yüzden doğrulayıcı arayüz
/// (`BiometricAuth`) sahtesiyle değiştiriliyor ve **karar mantığı**
/// sınanıyor: ne zaman soruluyor, başarısızlıkta ne oluyor.
class _FakeBiometric implements BiometricAuth {
  bool available;
  bool succeeds;
  int prompts = 0;

  _FakeBiometric({this.available = true, this.succeeds = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return succeeds;
  }
}

void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  Future<void> pumpLock(WidgetTester tester, _FakeBiometric fake) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          biometricAuthProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: PinLockScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ayar kapalıyken parmak izi hiç sorulmaz', (tester) async {
    final fake = _FakeBiometric();
    await pumpLock(tester, fake);

    expect(fake.prompts, 0);
    expect(find.text('Parmak izi ile aç'), findsNothing);
  });

  testWidgets('cihazda biyometri yoksa düğme görünmez', (tester) async {
    await SettingsRepository(db).setBiometricEnabled(true);
    final fake = _FakeBiometric(available: false);
    await pumpLock(tester, fake);

    // Cihazdaki parmak izi silinmiş olabilir; kullanıcı PIN'le girer.
    expect(find.text('Parmak izi ile aç'), findsNothing);
    expect(fake.prompts, 0);
    expect(find.text('PIN'), findsOneWidget);
  });

  testWidgets('ayar açıkken kendiliğinden sorulur ve kilidi açar', (
    tester,
  ) async {
    await SettingsRepository(db).setBiometricEnabled(true);
    final fake = _FakeBiometric();
    await pumpLock(tester, fake);

    expect(fake.prompts, 1, reason: 'açılışta sorulmadı');
    expect(find.text('Parmak izi ile aç'), findsOneWidget);
  });

  testWidgets('parmak okunmazsa PIN tuş takımı çalışmaya devam eder', (
    tester,
  ) async {
    await SettingsRepository(db).setBiometricEnabled(true);
    final fake = _FakeBiometric(succeeds: false);
    await pumpLock(tester, fake);

    expect(fake.prompts, 1);
    // Kilit açılmadı ama kullanıcı çıkmazda değil.
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Parmak izi ile aç'), findsOneWidget);

    // Başarısız okuma yanlış PIN sayılmaz: tuş takımı serbest.
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('PIN'), findsOneWidget);
  });

  testWidgets('düğmeye basınca tekrar sorulur', (tester) async {
    await SettingsRepository(db).setBiometricEnabled(true);
    final fake = _FakeBiometric(succeeds: false);
    await pumpLock(tester, fake);
    expect(fake.prompts, 1);

    await tester.tap(find.text('Parmak izi ile aç'));
    await tester.pumpAndSettle();
    expect(fake.prompts, 2, reason: 'elle deneme çalışmıyor');
  });
}
