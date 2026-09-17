import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:sungerbob/data/backup/backup_service.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/connection.dart';
import 'package:sungerbob/data/db/database_key.dart';

/// Yedekleme testleri için gerçek dosya tabanlı, şifreli veritabanı.
///
/// Bellek içi veritabanı kullanılmaz: yedekleme dosya kopyalama ve atomik
/// değiştirme üzerine kurulu olduğu için gerçek dosyalarla sınanmalıdır.
class BackupFixture {
  final Directory root;
  final DatabaseKeyStore keyStore;
  late AppDatabase db;
  late BackupService service;

  BackupFixture._(this.root, this.keyStore);

  File get databaseFile => File(p.join(root.path, 'app.db'));
  Directory get backupDir => Directory(p.join(root.path, 'backups'));

  static Future<BackupFixture> create({String? deviceKey}) async {
    // Geri yükleme sırasında aday veritabanı mevcut olanla aynı anda açılır
    // (farklı dosyalar, yarış yok) — Drift'in uyarısı burada beklenen durum.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final root = await Directory.systemTemp.createTemp('sbk_test_');
    final store = InMemoryKeyStore(deviceKey);
    final fixture = BackupFixture._(root, store);
    await fixture._open();
    return fixture;
  }

  Future<void> _open() async {
    backupDir.createSync(recursive: true);
    final key = await keyStore.getOrCreate();
    db = AppDatabase(AppDatabaseFactory.encryptedExecutor(databaseFile, key));
    await db.customSelect('SELECT 1').get(); // onCreate + seed

    service = BackupService(
      db: db,
      databaseFile: databaseFile,
      backupDirectory: backupDir,
      keyStore: keyStore,
      appVersion: '1.0.0',
      appBuild: 1,
      deviceId: 'test-device',
      deviceName: 'Test Telefon',
    );
  }

  /// Geri yüklemeden sonra veritabanını yeniden açar.
  Future<void> reopen() async {
    final key = await keyStore.getOrCreate();
    db = AppDatabase(AppDatabaseFactory.encryptedExecutor(databaseFile, key));
    await db.customSelect('SELECT 1').get();
    service = BackupService(
      db: db,
      databaseFile: databaseFile,
      backupDirectory: backupDir,
      keyStore: keyStore,
      appVersion: '1.0.0',
      appBuild: 1,
      deviceId: 'test-device',
      deviceName: 'Test Telefon',
    );
  }

  Future<void> closeDatabase() => db.close();

  /// Tüm tabloların içerik özeti — yedek/geri yükleme sonrası birebir
  /// aynı olmalı (BACKUP.md §8, test 1).
  ///
  /// Yalnızca satır sayısı yeterli sayılmaz; her tablonun tüm kolonları
  /// kanonik sırayla okunup özetlenir.
  Future<Map<String, String>> contentDigest() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();

    final digests = <String, String>{};
    for (final t in tables) {
      final name = t.read<String>('name');
      // backup_log yedek alma sırasında değişir, karşılaştırmadan hariç.
      if (name == 'backup_log') continue;

      final columns = await db.customSelect('PRAGMA table_info("$name")').get();
      final columnNames = columns.map((c) => c.read<String>('name')).toList()
        ..sort();
      if (columnNames.isEmpty) continue;

      final selectList = columnNames
          .map((c) => 'COALESCE("$c", \'∅\')')
          .join("||'|'||");
      final rows = await db
          .customSelect(
            'SELECT $selectList AS row_text FROM "$name" '
            'ORDER BY row_text',
          )
          .get();

      digests[name] = rows.map((r) => r.read<String>('row_text')).join('\n');
    }
    return digests;
  }

  Future<void> dispose() async {
    try {
      await db.close();
    } catch (_) {}
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
