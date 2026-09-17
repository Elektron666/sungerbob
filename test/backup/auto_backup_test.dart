import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/backup/auto_backup.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';

import 'backup_fixture.dart';

/// Otomatik yedek kuralları (BRIEF §4.3).
void main() {
  late BackupFixture f;
  late AutoBackupPolicy policy;
  late SettingsRepository settings;

  setUp(() async {
    f = await BackupFixture.create();
    settings = SettingsRepository(f.db);
    policy = AutoBackupPolicy(backup: f.service, settings: settings);
  });
  tearDown(() async => f.dispose());

  group('Açılışta yedek kontrolü', () {
    test('hiç yedek alınmamışsa açılışta alınır', () async {
      expect(await policy.shouldBackupOnStartup(), isTrue);
    });

    test('bugün alınmışsa tekrar alınmaz', () async {
      final now = DateTime(2026, 9, 17, 14);
      await settings.setLastAutoBackupDate(now);
      expect(await policy.shouldBackupOnStartup(now: now), isFalse);
    });

    test('önceki gün alınmışsa bugün alınır', () async {
      await settings.setLastAutoBackupDate(DateTime(2026, 9, 16, 20));
      expect(
        await policy.shouldBackupOnStartup(now: DateTime(2026, 9, 17, 8)),
        isTrue,
      );
    });
  });

  group('Zamanlanmış yedek (varsayılan 20:00)', () {
    test('saat gelmeden alınmaz', () async {
      expect(
        await policy.isScheduledTime(now: DateTime(2026, 9, 17, 19, 59)),
        isFalse,
      );
    });

    test('saat geçince alınır', () async {
      expect(
        await policy.isScheduledTime(now: DateTime(2026, 9, 17, 20, 1)),
        isTrue,
      );
    });

    test('aynı gün ikinci kez alınmaz', () async {
      await settings.setLastAutoBackupDate(DateTime(2026, 9, 17, 20, 5));
      expect(
        await policy.isScheduledTime(now: DateTime(2026, 9, 17, 21)),
        isFalse,
      );
    });

    test('ayarlanan saat dikkate alınır', () async {
      await settings.setBackupTime('08:30');
      expect(
        await policy.isScheduledTime(now: DateTime(2026, 9, 17, 8, 0)),
        isFalse,
      );
      expect(
        await policy.isScheduledTime(now: DateTime(2026, 9, 17, 8, 31)),
        isTrue,
      );
    });
  });

  group('Otomatik yedek çalıştırma', () {
    test('yedek alır, tarihi kaydeder ve saklama kuralını uygular', () async {
      final now = DateTime(2026, 9, 17, 20);
      final result = await policy.runAutoBackup(
        password: 'gizli-sifre',
        trigger: BackupTrigger.autoDaily,
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.file.existsSync(), isTrue);
      expect(await settings.lastAutoBackupDate(), now);
      expect(await policy.shouldBackupOnStartup(now: now), isFalse);

      final logs = await f.db.select(f.db.backupLog).get();
      expect(logs.single.trigger, BackupTrigger.autoDaily);
    });

    test('riskli işlem öncesi yedek PRE_RISK olarak işaretlenir', () async {
      await policy.backupBeforeRiskyOperation(
        password: 'gizli-sifre',
        operation: 'stock_count',
      );
      final logs = await f.db.select(f.db.backupLog).get();
      expect(logs.single.trigger, BackupTrigger.preRisk);
    });

    test('migration öncesi yedek PRE_MIGRATION olarak işaretlenir', () async {
      await policy.backupBeforeRiskyOperation(
        password: 'gizli-sifre',
        operation: 'migration',
      );
      final logs = await f.db.select(f.db.backupLog).get();
      expect(logs.single.trigger, BackupTrigger.preMigration);
    });
  });

  group('Cihaz dışı kopya kaydı', () {
    test('yeni yedek dosyası üretmeden uyarıyı kapatır', () async {
      final created = await f.service.createBackup(
        password: 'sunger2026',
        trigger: BackupTrigger.manual,
      );
      // Yerel yedek cihaz dışı sayılmaz; uyarı sürer.
      expect(await f.service.daysSinceOffsiteBackup(), isNull);
      expect(await f.service.shouldWarnAboutOffsiteBackup(), isTrue);

      final before = f.service.localBackups().length;
      await f.service.recordOffsiteCopy(
        file: created.file,
        destination: BackupDestination.share,
      );

      expect(f.service.localBackups().length, before);
      expect(await f.service.daysSinceOffsiteBackup(), 0);
      expect(await f.service.shouldWarnAboutOffsiteBackup(), isFalse);
    });

    test('dosya yoksa FAIL kaydı düşer, uyarı sürer', () async {
      final created = await f.service.createBackup(
        password: 'sunger2026',
        trigger: BackupTrigger.manual,
      );
      await created.file.delete();

      await f.service.recordOffsiteCopy(
        file: created.file,
        destination: BackupDestination.share,
      );

      expect(await f.service.daysSinceOffsiteBackup(), isNull);
      expect(await f.service.shouldWarnAboutOffsiteBackup(), isTrue);
    });
  });
}
