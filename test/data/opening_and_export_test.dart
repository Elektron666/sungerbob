import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/backup/backup_password_store.dart';
import 'package:sungerbob/data/documents/csv_export.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';
import 'package:sungerbob/data/repo/variant_helper.dart';
import 'package:sungerbob/domain/core/quantity.dart';

import '../golden_scenario/scenario_fixture.dart';

void main() {
  group('yedek şifresi kuralları', () {
    test('kısa şifre reddedilir', () {
      expect(BackupPasswordRules.isValid('Ab1'), isFalse);
      expect(BackupPasswordRules.validate('Ab1'), contains('en az 8 karakter'));
    });

    test('yalnızca harf veya yalnızca rakam yetmez', () {
      expect(BackupPasswordRules.isValid('abcdefghij'), isFalse);
      expect(BackupPasswordRules.isValid('1234567890'), isFalse);
      expect(
        BackupPasswordRules.validate('abcdefghij'),
        contains('harf ve bir rakam'),
      );
    });

    test('harf + rakam ve 8 karakter geçerli', () {
      expect(BackupPasswordRules.isValid('sunger2026'), isTrue);
    });

    test('Türkçe karakter harf sayılır', () {
      expect(BackupPasswordRules.isValid('şüngerç1'), isTrue);
    });
  });

  group('yedek şifresi deposu', () {
    test('yazılan şifre geri okunur', () async {
      final store = InMemoryBackupPasswordStore();
      expect(await store.exists(), isFalse);
      await store.write('sunger2026');
      expect(await store.exists(), isTrue);
      expect(await store.read(), 'sunger2026');
    });
  });

  group('varyant yardımcısı', () {
    late ScenarioFixture f;

    setUp(() async => f = await ScenarioFixture.create());
    tearDown(() async => f.close());

    test('aynı ölçü ikinci kez varyant açmaz', () async {
      final first = await f.db.ensureVariant(
        productId: f.beyazProductId,
        width: Dimension.cm('120'),
        height: Dimension.cm('180'),
        thickness: Dimension.cm('6'),
      );
      final second = await f.db.ensureVariant(
        productId: f.beyazProductId,
        width: Dimension.cm('120'),
        height: Dimension.cm('180'),
        thickness: Dimension.cm('6'),
      );
      expect(second, first);
    });

    test('farklı kalınlık ayrı varyanttır', () async {
      final a = await f.db.ensureVariant(
        productId: f.beyazProductId,
        width: Dimension.cm('120'),
        height: Dimension.cm('180'),
        thickness: Dimension.cm('6'),
      );
      final b = await f.db.ensureVariant(
        productId: f.beyazProductId,
        width: Dimension.cm('120'),
        height: Dimension.cm('180'),
        thickness: Dimension.cm('8'),
      );
      expect(b, isNot(a));
    });

    test('birim hacim 1 adet üzerinden hesaplanır', () async {
      final id = await f.db.ensureVariant(
        productId: f.beyazProductId,
        width: Dimension.cm('100'),
        height: Dimension.cm('200'),
        thickness: Dimension.cm('10'),
      );
      final variant = await (f.db.select(
        f.db.productVariants,
      )..where((v) => v.id.equals(id))).getSingle();

      // 1,00 × 2,00 × 0,10 = 0,2 m³
      expect(
        variant.unitVolume,
        Volume.fromDimensions(
          width: Dimension.cm('100'),
          height: Dimension.cm('200'),
          thickness: Dimension.cm('10'),
          pieces: 1,
        ),
      );
    });
  });

  group('ayar yazıcıları', () {
    late ScenarioFixture f;
    late SettingsRepository settings;

    setUp(() async {
      f = await ScenarioFixture.create();
      settings = SettingsRepository(f.db);
    });
    tearDown(() async => f.close());

    test('KDV oranı ve fiyat modu kaydedilir', () async {
      await settings.setDefaultVatRate(1000);
      await settings.setDefaultPriceMode('INCL');

      expect((await settings.defaultVatRate()).stored, 1000);
      expect(await settings.defaultPriceMode(), 'INCL');
    });

    test('kullanıcı adı boşken boş metin döner', () async {
      expect(await settings.userName(), '');
      await settings.saveUserName('Ahmet');
      expect(await settings.userName(), 'Ahmet');
    });
  });

  group('CSV dışa aktarma', () {
    test('noktalı virgül içeren alan tırnaklanır', () {
      final csv = CsvExport.build(
        headers: const ['Ad', 'Tutar'],
        rows: [
          ['Beyaz; sert', '1.234,56'],
        ],
      );
      expect(csv, startsWith(CsvExport.bom));
      expect(csv, contains('"Beyaz; sert";1.234,56'));
    });

    test('tırnak iki tırnağa kaçırılır', () {
      expect(CsvExport.escape('12" plaka'), '"12"" plaka"');
    });
  });
}
