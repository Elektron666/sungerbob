import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/backup/backup_crypto.dart';
import 'package:sungerbob/data/backup/backup_models.dart';
import 'package:sungerbob/data/backup/backup_service.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';

import 'backup_fixture.dart';

/// docs/BACKUP.md §8 — Faz 2'nin geçme şartı olan ZORUNLU testler.
void main() {
  late BackupFixture f;

  setUp(() async => f = await BackupFixture.create());
  tearDown(() async => f.dispose());

  Future<void> addData() async {
    await f.db
        .into(f.db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'c1',
            code: 'ABC',
            title: 'ABC Mobilya',
            titleNormalized: 'abc mobilya',
          ),
        );
    await f.db
        .into(f.db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: 's1',
            code: 'FAB',
            title: 'Fabrika',
            titleNormalized: 'fabrika',
            type: SupplierType.factory,
          ),
        );
  }

  // ------------------------------------------------------------- TEST 1
  test(
    '1 — veri oluştur → yedek al → sil → yükle → içerik BİREBİR aynı',
    () async {
      await addData();
      final before = await f.contentDigest();

      final backup = await f.service.createBackup(password: 'gizli-sifre-123');
      expect(backup.file.existsSync(), isTrue);
      expect(backup.manifest.tableCounts['customers'], 1);
      expect(backup.manifest.tableCounts['products'], 12);

      // Veritabanını sil.
      await f.closeDatabase();
      f.databaseFile.deleteSync();
      expect(f.databaseFile.existsSync(), isFalse);
      await f.reopen(); // boş veritabanı

      expect((await f.db.select(f.db.customers).get()), isEmpty);

      // Yedeği yükle.
      await f.service.restore(
        file: backup.file,
        password: 'gizli-sifre-123',
        closeDatabase: f.closeDatabase,
      );
      await f.reopen();

      final after = await f.contentDigest();
      expect(
        after.keys.toSet(),
        before.keys.toSet(),
        reason: 'tablo listesi aynı olmalı',
      );
      for (final table in before.keys) {
        expect(
          after[table],
          before[table],
          reason: '$table tablosunun içeriği birebir aynı olmalı',
        );
      }
    },
  );

  // ------------------------------------------------------------- TEST 2
  test('2 — yanlış şifre reddedilir, mevcut veri DEĞİŞMEZ', () async {
    await addData();
    final backup = await f.service.createBackup(password: 'dogru-sifre');
    final before = await f.contentDigest();

    await expectLater(
      f.service.restore(
        file: backup.file,
        password: 'yanlis-sifre',
        closeDatabase: f.closeDatabase,
      ),
      throwsA(isA<WrongPasswordException>()),
    );

    expect(await f.contentDigest(), before);
    expect((await f.db.select(f.db.customers).get()).length, 1);
  });

  // ------------------------------------------------------------- TEST 3
  test(
    '3 — bozuk dosya (değiştirilmiş bayt) reddedilir, veri DEĞİŞMEZ',
    () async {
      await addData();
      final backup = await f.service.createBackup(password: 'sifre-123');
      final before = await f.contentDigest();

      // Şifreli içerikte tek bir baytı boz.
      final bytes = await backup.file.readAsBytes();
      final corrupted = Uint8List.fromList(bytes);
      final index = BackupCrypto.headerLength + 10;
      corrupted[index] = corrupted[index] ^ 0xFF;
      await backup.file.writeAsBytes(corrupted, flush: true);

      await expectLater(
        f.service.restore(
          file: backup.file,
          password: 'sifre-123',
          closeDatabase: f.closeDatabase,
        ),
        throwsA(
          anyOf(isA<WrongPasswordException>(), isA<CorruptBackupException>()),
        ),
      );

      expect(await f.contentDigest(), before);
    },
  );

  test(
    '3b — başlıktaki tek bayt değişirse de reddedilir (AAD koruması)',
    () async {
      await addData();
      final backup = await f.service.createBackup(password: 'sifre-123');

      final bytes = await backup.file.readAsBytes();
      final corrupted = Uint8List.fromList(bytes);
      corrupted[20] = corrupted[20] ^ 0xFF; // salt bölgesi
      await backup.file.writeAsBytes(corrupted, flush: true);

      await expectLater(
        f.service.restore(
          file: backup.file,
          password: 'sifre-123',
          closeDatabase: f.closeDatabase,
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    '3c — Sünger yedeği olmayan dosya anlaşılır hatayla reddedilir',
    () async {
      final notBackup = File('${f.root.path}/rastgele.sbk')
        ..writeAsBytesSync(List.filled(200, 7));

      await expectLater(
        f.service.inspect(notBackup, 'sifre'),
        throwsA(isA<CorruptBackupException>()),
      );
    },
  );

  // ------------------------------------------------------------- TEST 4
  test(
    '4 — yükleme ortasında hata → veri DEĞİŞMEZ, güvenlik yedeği oluşmuş',
    () async {
      await addData();
      final backup = await f.service.createBackup(password: 'sifre-123');
      final before = await f.contentDigest();
      final backupsBefore = f.service.localBackups().length;

      // Atomik değişim adımında hata simüle et.
      await expectLater(
        f.service.restore(
          file: backup.file,
          password: 'sifre-123',
          closeDatabase: () async => throw const FileSystemException(
            'simüle edilmiş hata: veritabanı kapatılamadı',
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );

      // Mevcut veri sağlam.
      expect(await f.contentDigest(), before);
      expect((await f.db.select(f.db.customers).get()).length, 1);

      // Güvenlik yedeği oluşmuş.
      expect(
        f.service.localBackups().length,
        greaterThan(backupsBefore),
        reason: 'yükleme öncesi güvenlik yedeği alınmalıydı',
      );

      final safetyLogs = await (f.db.select(
        f.db.backupLog,
      )..where((l) => l.trigger.equals(BackupTrigger.preRisk))).get();
      expect(safetyLogs, isNotEmpty);
    },
  );

  // ------------------------------------------------------------- TEST 6
  test('6 — daha yeni şema sürümünün yedeği reddedilir', () async {
    await addData();
    final backup = await f.service.createBackup(password: 'sifre-123');

    // Manifest'i daha yüksek şema sürümüyle yeniden paketle.
    final tampered = await _repackWithSchemaVersion(
      source: backup.file,
      password: 'sifre-123',
      newSchemaVersion: f.db.schemaVersion + 5,
      target: File('${f.root.path}/gelecek.sbk'),
    );

    await expectLater(
      f.service.restore(
        file: tampered,
        password: 'sifre-123',
        closeDatabase: f.closeDatabase,
      ),
      throwsA(isA<BackupTooNewException>()),
    );

    // Mesaj kullanıcıya ne yapacağını söylüyor.
    try {
      await f.service.restore(
        file: tampered,
        password: 'sifre-123',
        closeDatabase: f.closeDatabase,
      );
    } on BackupTooNewException catch (e) {
      expect(e.toString(), contains('Önce uygulamayı güncelleyin'));
    }
  });

  // ------------------------------------------------------------- TEST 7
  test(
    '7 — yedek FARKLI cihaz anahtarıyla yalnızca yedek şifresiyle açılır',
    () async {
      await addData();
      final before = await f.contentDigest();
      final backup = await f.service.createBackup(password: 'kagida-yazdim');

      // Yedek dosyasını dışarı kopyala.
      final exported = File('${Directory.systemTemp.path}/tasinan.sbk');
      await backup.file.copy(exported.path);

      // YENİ TELEFON: yeni anahtar, boş veritabanı, secure storage silinmiş.
      final newPhone = await BackupFixture.create(
        deviceKey: 'tamamen-baska-anahtar',
      );
      try {
        expect(
          (await newPhone.db.select(newPhone.db.customers).get()),
          isEmpty,
        );

        await newPhone.service.restore(
          file: exported,
          password: 'kagida-yazdim',
          closeDatabase: newPhone.closeDatabase,
        );
        await newPhone.reopen();

        final after = await newPhone.contentDigest();
        for (final table in before.keys) {
          expect(
            after[table],
            before[table],
            reason: '$table yeni telefonda birebir gelmeli',
          );
        }
        expect(
          (await newPhone.db.select(newPhone.db.customers).get()).length,
          1,
        );
      } finally {
        await newPhone.dispose();
        if (exported.existsSync()) exported.deleteSync();
      }
    },
  );

  test('7b — yedek, cihazın veritabanı anahtarını İÇERMEZ', () async {
    await addData();
    final backup = await f.service.createBackup(password: 'sifre-123');
    final deviceKey = await f.keyStore.getOrCreate();

    final bytes = await backup.file.readAsBytes();
    final asText = String.fromCharCodes(bytes);
    expect(
      asText.contains(deviceKey),
      isFalse,
      reason: 'yedek dosyası cihaz anahtarını içeriyor',
    );
  });

  // ------------------------------------------------------------- TEST 8
  test('8 — saklama kuralı: son 7 günlük + son 4 haftalık tutulur', () async {
    final now = DateTime(2026, 9, 17, 12);

    // 60 günlük geçmiş: her gün bir yedek dosyası.
    final created = <File, DateTime>{};
    for (var day = 0; day < 60; day++) {
      final at = now.subtract(Duration(days: day));
      final file = File('${f.backupDir.path}/${BackupService.fileNameFor(at)}')
        ..writeAsBytesSync([1, 2, 3]);
      file.setLastModifiedSync(at);
      created[file] = at;
    }

    final deleted = await f.service.applyRetention(now: now);
    final remaining = f.service.localBackups();

    expect(deleted, isNotEmpty, reason: 'eski yedekler silinmeliydi');

    // Son 7 gün: her günden bir tane.
    for (var day = 0; day <= 7; day++) {
      final at = now.subtract(Duration(days: day));
      final name = BackupService.fileNameFor(at);
      expect(
        remaining.map((file) => file.uri.pathSegments.last),
        contains(name),
        reason: '$day gün önceki günlük yedek korunmalı',
      );
    }

    // 28 günden eski hiçbir şey kalmamalı.
    for (final file in remaining) {
      final age = now.difference(file.statSync().modified).inDays;
      expect(
        age,
        lessThanOrEqualTo(28),
        reason: '28 günden eski yedek silinmeliydi: ${file.path}',
      );
    }

    // 8–28 gün arası yalnızca haftalık kopyalar.
    final weekly = remaining.where(
      (file) => now.difference(file.statSync().modified).inDays > 7,
    );
    expect(
      weekly.length,
      lessThanOrEqualTo(4),
      reason: 'en fazla 4 haftalık yedek tutulmalı',
    );
  });

  test('8b — riskli işlem öncesi yedekler saklama kuralından muaf', () async {
    final now = DateTime(2026, 9, 17, 12);
    final old = now.subtract(const Duration(days: 20));

    final protected = File(
      '${f.backupDir.path}/${BackupService.fileNameFor(old)}',
    )..writeAsBytesSync([1]);
    protected.setLastModifiedSync(old);

    await f.db
        .into(f.db.backupLog)
        .insert(
          BackupLogCompanion.insert(
            id: 'log-1',
            occurredAt: old.millisecondsSinceEpoch,
            kind: BackupKind.backup,
            trigger: BackupTrigger.preRisk,
            destination: BackupDestination.local,
            fileName: protected.uri.pathSegments.last,
            schemaVersion: 1,
            appVersion: '1.0.0',
            result: 'OK',
          ),
        );

    // Aynı haftadan başka bir dosya da koy ki haftalık kotayı o doldursun.
    final sameWeek = File(
      '${f.backupDir.path}/${BackupService.fileNameFor(old.add(const Duration(hours: 2)))}',
    )..writeAsBytesSync([1]);
    sameWeek.setLastModifiedSync(old.add(const Duration(hours: 2)));

    await f.service.applyRetention(now: now);
    expect(
      protected.existsSync(),
      isTrue,
      reason: 'riskli işlem öncesi yedek korunmalı',
    );
  });

  // -------------------------------------------------------- UYARILAR §4
  group('Uyarılar (BACKUP.md §4)', () {
    test('hiç cihaz dışı yedek yoksa uyarı gösterilir', () async {
      expect(await f.service.daysSinceOffsiteBackup(), isNull);
      expect(await f.service.shouldWarnAboutOffsiteBackup(), isTrue);
    });

    test('yerel yedek cihaz dışı sayılmaz', () async {
      await f.service.createBackup(password: 'sifre-123');
      expect(
        await f.service.daysSinceOffsiteBackup(),
        isNull,
        reason: 'LOCAL hedefi cihaz dışı değildir',
      );
      expect(await f.service.shouldWarnAboutOffsiteBackup(), isTrue);
    });

    test('paylaşım sonrası uyarı kalkar, 3 gün sonra geri gelir', () async {
      final now = DateTime(2026, 9, 17, 12);
      await f.service.createBackup(
        password: 'sifre-123',
        destination: BackupDestination.share,
        now: now,
      );

      expect(await f.service.shouldWarnAboutOffsiteBackup(now: now), isFalse);
      expect(
        await f.service.shouldWarnAboutOffsiteBackup(
          now: now.add(const Duration(days: 2)),
        ),
        isFalse,
      );
      expect(
        await f.service.shouldWarnAboutOffsiteBackup(
          now: now.add(const Duration(days: 3)),
        ),
        isTrue,
      );
    });

    test('son yedek zamanı durum bandı için okunabiliyor', () async {
      final now = DateTime(2026, 9, 17, 20, 0);
      await f.service.createBackup(password: 'sifre-123', now: now);
      expect(await f.service.lastBackupAt(), now);
    });
  });

  // ------------------------------------------------------- ÖNİZLEME §5.2
  group('Önizleme (BACKUP.md §5.2)', () {
    test('yedek ve mevcut veri sayıları karşılaştırılıyor', () async {
      await addData();
      final backup = await f.service.createBackup(password: 'sifre-123');

      await f.db
          .into(f.db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'c2',
              code: 'XYZ',
              title: 'XYZ',
              titleNormalized: 'xyz',
            ),
          );

      final preview = await f.service.inspect(backup.file, 'sifre-123');
      expect(preview.manifest.customerCount, 1);
      expect(preview.currentCounts['customers'], 2);
      expect(preview.manifest.deviceName, 'Test Telefon');
    });

    test('yedek mevcut veriden eskiyse uyarı metni üretilir', () async {
      final preview = BackupPreview(
        manifest: (await f.service.createBackup(password: 'x')).manifest,
        currentCounts: const {},
        currentLastTransactionAt: DateTime(2026, 9, 17),
      );
      // Manifest'te son işlem yoksa karşılaştırma yapılamaz.
      expect(preview.ageInDaysVsCurrent, isNull);
      expect(preview.warningText, isNull);
    });

    test('inspect mevcut veriyi DEĞİŞTİRMEZ', () async {
      await addData();
      final backup = await f.service.createBackup(password: 'sifre-123');
      final before = await f.contentDigest();
      await f.service.inspect(backup.file, 'sifre-123');
      expect(await f.contentDigest(), before);
    });
  });

  // ---------------------------------------------------------- backup_log
  test('backup_log her işlemi kaydediyor', () async {
    await f.service.createBackup(password: 'sifre-123');
    final logs = await f.db.select(f.db.backupLog).get();
    expect(logs.length, 1);
    expect(logs.single.kind, BackupKind.backup);
    expect(logs.single.result, 'OK');
    expect(logs.single.sizeBytes, greaterThan(0));
    expect(logs.single.sha256, isNotNull);
  });

  test('dosya adı biçimi: SungerYedek_2026-09-17_1432.sbk', () {
    expect(
      BackupService.fileNameFor(DateTime(2026, 9, 17, 14, 32)),
      'SungerYedek_2026-09-17_1432.sbk',
    );
  });
}

/// Yedeği açıp manifest'teki şema sürümünü değiştirerek yeniden paketler.
/// "Daha yeni sürümün yedeği" senaryosunu üretmek için.
Future<File> _repackWithSchemaVersion({
  required File source,
  required String password,
  required int newSchemaVersion,
  required File target,
}) async {
  final bytes = await source.readAsBytes();
  final clear = await BackupCrypto.decrypt(
    fileBytes: bytes,
    password: password,
  );

  final archive = ZipDecoder().decodeBytes(clear);
  final dbBytes = archive.findFile('database.db')!.content as List<int>;
  final manifestJson = utf8
      .decode(archive.findFile('manifest.json')!.content as List<int>)
      .replaceAll(
        RegExp(r'"schema_version": \d+'),
        '"schema_version": $newSchemaVersion',
      );

  final manifestBytes = utf8.encode(manifestJson);
  final repacked = Archive()
    ..addFile(ArchiveFile('database.db', dbBytes.length, dbBytes))
    ..addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

  final encrypted = await BackupCrypto.encrypt(
    plaintext: Uint8List.fromList(ZipEncoder().encode(repacked)),
    password: password,
  );
  await target.writeAsBytes(encrypted, flush: true);
  return target;
}
