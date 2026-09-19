import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../db/app_database.dart';
import '../repo/settings_repository.dart';
import '../db/connection.dart';
import '../db/database_key.dart';
import '../db/enums.dart';
import '../repo/integrity_service.dart';
import '../repo/unit_of_work.dart';
import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'backup_models.dart';

/// Yedekleme ve geri yükleme (BRIEF §4, docs/BACKUP.md).
///
/// Sözleşme: **yedek dosyası + yedek şifresi elindeyse, başka bir telefonda
/// veriyi son haline getirebilirsin.** Cihazın kendisine ait hiçbir şeye
/// ihtiyaç yoktur — bu yüzden anlık görüntü SQLCipher şifresi olmadan alınır
/// ve dosyanın tamamı yedek şifresiyle şifrelenir (D-13).
final class BackupService {
  final AppDatabase db;
  final File databaseFile;
  final Directory backupDirectory;
  final DatabaseKeyStore keyStore;
  final String appVersion;
  final int appBuild;
  final String deviceId;
  final String deviceName;

  BackupService({
    required this.db,
    required this.databaseFile,
    required this.backupDirectory,
    required this.keyStore,
    this.appVersion = '0.1.0',
    this.appBuild = 1,
    this.deviceId = 'device',
    this.deviceName = 'Cihaz',
  });

  static const fileExtension = '.sbk';
  static const _dbEntry = 'database.db';
  static const _manifestEntry = 'manifest.json';

  // ------------------------------------------------------------------ AL

  /// Tek tuşla yedek al (BACKUP.md §2).
  Future<BackupResult> createBackup({
    required String password,
    String trigger = BackupTrigger.manual,
    String destination = BackupDestination.local,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final tempDir = await Directory.systemTemp.createTemp('sbk_create_');
    final plainSnapshot = File(p.join(tempDir.path, _dbEntry));

    try {
      await _writeSnapshot(plainSnapshot);

      final snapshotBytes = await plainSnapshot.readAsBytes();
      final manifest = BackupManifest(
        appVersion: appVersion,
        appBuild: appBuild,
        schemaVersion: db.schemaVersion,
        createdAt: timestamp,
        deviceId: deviceId,
        deviceName: deviceName,
        costingMethod:
            await _settingValue('costing_method') ?? CostingMethod.fifo,
        lastTransactionAt: await _lastTransactionAt(),
        tableCounts: await _tableCounts(),
        contentSha256: sha256.convert(snapshotBytes).toString(),
      );

      final archive = Archive()
        ..addFile(ArchiveFile(_dbEntry, snapshotBytes.length, snapshotBytes))
        ..addFile(_textEntry(_manifestEntry, manifest.encode()));

      final payload = Uint8List.fromList(ZipEncoder().encode(archive));
      final encrypted = await BackupCrypto.encrypt(
        plaintext: payload,
        password: password,
      );

      if (!backupDirectory.existsSync()) {
        backupDirectory.createSync(recursive: true);
      }
      final outFile = _uniqueFile(fileNameFor(timestamp));
      await outFile.writeAsBytes(encrypted, flush: true);

      await _log(
        kind: BackupKind.backup,
        trigger: trigger,
        destination: destination,
        fileName: p.basename(outFile.path),
        sizeBytes: encrypted.length,
        sha256Value: manifest.contentSha256,
        result: 'OK',
        now: timestamp,
      );

      return BackupResult(
        file: outFile,
        manifest: manifest,
        sizeBytes: encrypted.length,
      );
    } catch (e) {
      await _log(
        kind: BackupKind.backup,
        trigger: trigger,
        destination: destination,
        fileName: fileNameFor(timestamp),
        sizeBytes: 0,
        result: 'FAIL',
        errorMessage: e.toString(),
        now: timestamp,
      );
      rethrow;
    } finally {
      // Şifresiz anlık görüntü diskte KALMAZ (BACKUP.md §9).
      await _shred(plainSnapshot);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  /// Aynı ada sahip bir dosya varsa `_2`, `_3` ... ekler.
  ///
  /// Dosya adı dakika hassasiyetinde olduğu için (BACKUP.md §1) aynı dakika
  /// içinde alınan iki yedek aynı ada sahip olur. Örneğin elle yedek alıp
  /// hemen geri yükleme başlatıldığında güvenlik yedeği manuel yedeğin
  /// üzerine yazardı. Yedek dosyası asla sessizce kaybolmamalıdır.
  File _uniqueFile(String preferredName) {
    var candidate = File(p.join(backupDirectory.path, preferredName));
    if (!candidate.existsSync()) return candidate;

    final base = preferredName.substring(
      0,
      preferredName.length - fileExtension.length,
    );
    for (var i = 2; i < 1000; i++) {
      candidate = File(
        p.join(backupDirectory.path, '${base}_$i$fileExtension'),
      );
      if (!candidate.existsSync()) return candidate;
    }
    throw StateError('Aynı dakikada çok fazla yedek alındı: $preferredName');
  }

  /// `SungerYedek_2026-09-17_1432.sbk`
  static String fileNameFor(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'SungerYedek_${at.year}-${two(at.month)}-${two(at.day)}'
        '_${two(at.hour)}${two(at.minute)}$fileExtension';
  }

  /// Tutarlı anlık görüntü: açık transaction yokken, şifresiz (BACKUP.md §1.2).
  Future<void> _writeSnapshot(File target) async {
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

    final escaped = target.path.replaceAll("'", "''");
    // sqlcipher_export şifreli veritabanını şifresiz bir kopyaya aktarır.
    // Boş KEY '' hedefin şifresiz olması demektir — yedek, cihaz anahtarına
    // bağlı OLMAMALIDIR (D-13).
    await db.customStatement("ATTACH DATABASE '$escaped' AS plaintext KEY ''");
    try {
      await db.customStatement("SELECT sqlcipher_export('plaintext')");
      // sqlcipher_export şemayı ve veriyi kopyalar ama `user_version`'ı
      // KOPYALAMAZ. Taşınmazsa Drift geri yüklenen veritabanını yeni sanıp
      // tabloları yeniden oluşturmaya çalışır ve yükleme patlar.
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      await db.customStatement(
        'PRAGMA plaintext.user_version = ${version.read<int>('user_version')}',
      );
    } finally {
      await db.customStatement('DETACH DATABASE plaintext');
    }
  }

  // --------------------------------------------------------------- İNCELE

  /// Yedeği çözer ve önizleme bilgisi döndürür — **hiçbir şeyi değiştirmez**.
  Future<BackupPreview> inspect(File file, String password) async {
    final manifest = (await _openPayload(file, password)).manifest;
    return BackupPreview(
      manifest: manifest,
      currentCounts: await _tableCounts(),
      currentLastTransactionAt: await _lastTransactionAt(),
    );
  }

  /// Dosyayı çözer, bütünlüğünü doğrular ve içeriğini döndürür.
  Future<({BackupManifest manifest, Uint8List database})> _openPayload(
    File file,
    String password,
  ) async {
    if (!file.existsSync()) {
      throw const CorruptBackupException('dosya bulunamadı');
    }

    final bytes = await file.readAsBytes();
    final clear = await BackupCrypto.decrypt(
      fileBytes: bytes,
      password: password,
    );

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(clear);
    } catch (_) {
      throw const CorruptBackupException('arşiv açılamadı');
    }

    final dbEntry = archive.findFile(_dbEntry);
    final manifestEntry = archive.findFile(_manifestEntry);
    if (dbEntry == null || manifestEntry == null) {
      throw const CorruptBackupException('yedek içeriği eksik');
    }

    final manifest = BackupManifest.decode(
      utf8.decode(manifestEntry.content as List<int>),
    );
    final database = Uint8List.fromList(dbEntry.content as List<int>);

    // SHA-256 kontrolü (BACKUP.md §5.1 adım 4).
    final actual = sha256.convert(database).toString();
    if (actual != manifest.contentSha256) {
      throw BackupIntegrityException(
        expected: manifest.contentSha256,
        actual: actual,
      );
    }

    return (manifest: manifest, database: database);
  }

  // ----------------------------------------------------------- GERİ YÜKLE

  /// Tek tuşla yedekten yükle (BACKUP.md §5).
  ///
  /// **Değişmez:** atomik değişime gelinmediği sürece mevcut `app.db`
  /// dosyasına hiç dokunulmaz. Herhangi bir adımda hata olursa veri
  /// değişmemiş olarak kalır ve güvenlik yedeği yerinde durur.
  Future<RestoreResult> restore({
    required File file,
    required String password,
    required Future<void> Function() closeDatabase,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();

    // 1) Doğrulama — mevcut veriye dokunmadan.
    final payload = await _openPayload(file, password);
    final manifest = payload.manifest;

    if (manifest.schemaVersion > db.schemaVersion) {
      throw BackupTooNewException(
        backupSchemaVersion: manifest.schemaVersion,
        appSchemaVersion: db.schemaVersion,
      );
    }

    // 2) Güvenlik yedeği — mevcut veritabanının tam kopyası.
    final safety = await createBackup(
      password: password,
      trigger: BackupTrigger.preRisk,
      now: timestamp,
    );

    // 3) Geçici dosyaya aç.
    final tempDir = await Directory.systemTemp.createTemp('sbk_restore_');
    final tempPlain = File(p.join(tempDir.path, 'restore_plain.db'));
    final tempEncrypted = File(p.join(tempDir.path, 'restore_tmp.db'));
    var migrationApplied = false;

    try {
      await tempPlain.writeAsBytes(payload.database, flush: true);

      // Cihazın KENDİ anahtarıyla yeniden şifrele: yeni telefonda kendi
      // Keystore anahtarı geçerli olmalı (BACKUP.md §5.3).
      final deviceKey = await keyStore.getOrCreate();
      _encryptInto(source: tempPlain, target: tempEncrypted, key: deviceKey);

      // 4) Migration ve checkIntegrity GEÇİCİ dosyada çalışır.
      final candidate = AppDatabase(
        AppDatabaseFactory.encryptedExecutor(tempEncrypted, deviceKey),
      );
      try {
        await candidate.customSelect('SELECT 1').get();
        migrationApplied = manifest.schemaVersion < db.schemaVersion;

        final report = await IntegrityService(candidate).check();
        if (!report.isClean) {
          throw RestoreIntegrityException(
            report.findings.map((f) => f.toString()).toList(),
          );
        }
      } finally {
        await candidate.close();
      }

      // 5) Yalnızca buraya gelindiyse atomik değişim.
      await closeDatabase();
      await tempEncrypted.rename(databaseFile.path);
      _removeWalArtifacts(databaseFile);

      return RestoreResult(
        manifest: manifest,
        safetyBackup: safety.file,
        migrationApplied: migrationApplied,
      );
    } finally {
      await _shred(tempPlain);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  /// Şifresiz kopyayı verilen anahtarla şifreli bir dosyaya aktarır.
  void _encryptInto({
    required File source,
    required File target,
    required String key,
  }) {
    final plain = sql.sqlite3.open(source.path);
    try {
      final escaped = target.path.replaceAll("'", "''");
      final escapedKey = key.replaceAll("'", "''");
      plain.execute(
        "ATTACH DATABASE '$escaped' AS encrypted KEY '$escapedKey'",
      );
      plain.execute("SELECT sqlcipher_export('encrypted')");
      // user_version elle taşınmalı (yukarıdaki notun aynısı).
      final version = plain.select('PRAGMA user_version').first.values.first;
      plain.execute('PRAGMA encrypted.user_version = $version');
      plain.execute('DETACH DATABASE encrypted');
    } finally {
      plain.close();
    }
  }

  // -------------------------------------------------------------- SAKLAMA

  /// Yerel saklama kuralı: son **7 günlük** + son **4 haftalık** (BACKUP.md §3).
  ///
  /// Riskli işlem ve migration öncesi yedekler bu kuraldan **muaftır**
  /// (en az 30 gün tutulur).
  Future<List<File>> applyRetention({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    if (!backupDirectory.existsSync()) return const [];

    final protectedNames = await _protectedFileNames(reference);

    final files =
        backupDirectory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(fileExtension))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    final keep = <String>{};
    final dailyDays = <int>{};
    final weeklyWeeks = <int>{};

    for (final file in files) {
      final name = p.basename(file.path);
      if (protectedNames.contains(name)) {
        keep.add(file.path);
        continue;
      }

      final modified = file.statSync().modified;
      final ageDays = reference.difference(modified).inDays;

      if (ageDays <= 7) {
        // Her günden bir tanesi (en yenisi).
        if (dailyDays.add(_dayKey(modified))) keep.add(file.path);
      } else if (ageDays <= 28) {
        // Her haftadan bir tanesi.
        if (weeklyWeeks.add(_weekKey(modified))) keep.add(file.path);
      }
    }

    final deleted = <File>[];
    for (final file in files) {
      if (!keep.contains(file.path)) {
        file.deleteSync();
        deleted.add(file);
      }
    }
    return deleted;
  }

  Future<Set<String>> _protectedFileNames(DateTime reference) async {
    final rows =
        await (db.select(db.backupLog)..where(
              (l) => l.trigger.isIn([
                BackupTrigger.preRisk,
                BackupTrigger.preMigration,
              ]),
            ))
            .get();
    final cutoff = reference.subtract(const Duration(days: 30));
    return rows
        .where(
          (r) =>
              DateTime.fromMillisecondsSinceEpoch(r.occurredAt).isAfter(cutoff),
        )
        .map((r) => r.fileName)
        .toSet();
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static int _weekKey(DateTime d) {
    final startOfYear = DateTime(d.year);
    return d.year * 100 + (d.difference(startOfYear).inDays ~/ 7);
  }

  /// Cihazdaki yedeklerin listesi (Yedekler ekranı, BACKUP.md §6).
  List<File> localBackups() {
    if (!backupDirectory.existsSync()) return const [];
    return backupDirectory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(fileExtension))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }

  // --------------------------------------------------------------- UYARI

  /// Son **cihaz dışı** yedek (Drive veya paylaşım) kaç gün önce alındı?
  /// null ise hiç alınmamış (BACKUP.md §4).
  Future<int?> daysSinceOffsiteBackup({DateTime? now}) async {
    final row =
        await (db.select(db.backupLog)
              ..where(
                (l) =>
                    l.kind.equals(BackupKind.backup) &
                    l.result.equals('OK') &
                    l.destination.isIn([
                      BackupDestination.drive,
                      BackupDestination.share,
                    ]),
              )
              ..orderBy([(l) => OrderingTerm.desc(l.occurredAt)])
              ..limit(1))
            .getSingleOrNull();

    if (row == null) return null;
    return (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(row.occurredAt))
        .inDays;
  }

  /// Var olan bir yedek dosyasının **cihaz dışına** çıkarıldığını kaydeder.
  ///
  /// Paylaşım veya Drive yüklemesi yeni bir yedek üretmez; aynı dosya başka
  /// bir yere kopyalanır. Yeniden yedek almak hem gereksiz şifreleme yapar
  /// hem de saklama kuralını boş yere tüketir (BACKUP.md §4).
  Future<void> recordOffsiteCopy({
    required File file,
    required String destination,
    DateTime? now,
  }) async {
    final exists = await file.exists();
    await _log(
      kind: BackupKind.backup,
      trigger: BackupTrigger.manual,
      destination: destination,
      fileName: p.basename(file.path),
      sizeBytes: exists ? await file.length() : 0,
      result: exists ? 'OK' : 'FAIL',
      errorMessage: exists ? null : 'Yedek dosyası bulunamadı',
      now: now,
    );
  }

  /// Ana sayfada kırmızı uyarı bandı gösterilmeli mi?
  ///
  /// Eşik `SettingsRepository`'den okunur: ayarın anahtarını iki yerde
  /// yazmak, ikisinin ayrışmasının başlangıcıdır.
  Future<bool> shouldWarnAboutOffsiteBackup({DateTime? now}) async {
    final threshold = await SettingsRepository(db).offsiteWarnDays();
    final days = await daysSinceOffsiteBackup(now: now);
    return days == null || days >= threshold;
  }

  /// Son yedek durumu bandı için.
  Future<DateTime?> lastBackupAt() async {
    final row =
        await (db.select(db.backupLog)
              ..where(
                (l) => l.kind.equals(BackupKind.backup) & l.result.equals('OK'),
              )
              ..orderBy([(l) => OrderingTerm.desc(l.occurredAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.occurredAt);
  }

  // -------------------------------------------------------------- YARDIM

  Future<String?> _settingValue(String key) async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<Map<String, int>> _tableCounts() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();

    final counts = <String, int>{};
    for (final row in tables) {
      final name = row.read<String>('name');
      final result = await db
          .customSelect('SELECT count(*) AS c FROM "$name"')
          .getSingle();
      counts[name] = result.read<int>('c');
    }
    return counts;
  }

  Future<DateTime?> _lastTransactionAt() async {
    final row = await db
        .customSelect('SELECT MAX(created_at) AS last FROM command_log')
        .getSingle();
    final value = row.read<int?>('last');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> _log({
    required String kind,
    required String trigger,
    required String destination,
    required String fileName,
    required int sizeBytes,
    required String result,
    String? sha256Value,
    String? errorMessage,
    DateTime? now,
  }) => db
      .into(db.backupLog)
      .insert(
        BackupLogCompanion.insert(
          id: uuid.v7(),
          occurredAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
          kind: kind,
          trigger: trigger,
          destination: destination,
          fileName: fileName,
          sizeBytes: Value(sizeBytes),
          sha256: Value(sha256Value),
          schemaVersion: db.schemaVersion,
          appVersion: appVersion,
          result: result,
          errorMessage: Value(errorMessage),
          deviceId: Value(deviceId),
        ),
      );

  static ArchiveFile _textEntry(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }

  /// Şifresiz geçici dosyayı üzerine yazarak siler.
  static Future<void> _shred(File file) async {
    if (!file.existsSync()) return;
    try {
      final length = file.lengthSync();
      await file.writeAsBytes(List.filled(length, 0), flush: true);
    } catch (_) {
      // Üzerine yazamasak bile silmeyi dene.
    }
    try {
      file.deleteSync();
    } catch (_) {}
  }

  static void _removeWalArtifacts(File dbFile) {
    for (final suffix in ['-wal', '-shm']) {
      final artifact = File('${dbFile.path}$suffix');
      if (artifact.existsSync()) artifact.deleteSync();
    }
  }
}
