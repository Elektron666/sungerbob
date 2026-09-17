import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/connection.dart';
import 'package:sungerbob/data/db/database_key.dart';

/// Veritabanı şifreleme testleri (BRIEF §2, DECISIONS SK-07).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sungerbob_crypt_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('SQLCipher yüklü ve kullanılabilir', () {
    expect(
      AppDatabaseFactory.isEncryptionAvailable(),
      isTrue,
      reason: 'pubspec hooks.user_defines.sqlite3.source: sqlcipher olmalı',
    );
  });

  test('anahtar üretimi 256 bit ve her seferinde farklı', () {
    final a = SecureStorageKeyStore.generateKey();
    final b = SecureStorageKeyStore.generateKey();
    expect(a, isNot(b));
    expect(a.length, greaterThanOrEqualTo(43)); // base64url(32 bayt)
  });

  test('şifreli veritabanı doğru anahtarla açılır ve veri korunur', () async {
    final file = File('${tempDir.path}/enc.db');
    const key = 'test-anahtari-123';

    var db = AppDatabase(AppDatabaseFactory.encryptedExecutor(file, key));
    await db.customSelect('SELECT 1').get();
    final productCount = (await db.select(db.products).get()).length;
    await db.close();

    expect(file.existsSync(), isTrue);

    // Aynı anahtarla yeniden açıldığında veri yerinde.
    db = AppDatabase(AppDatabaseFactory.encryptedExecutor(file, key));
    expect((await db.select(db.products).get()).length, productCount);
    await db.close();
  });

  test('dosya gerçekten şifreli — anahtarsız açılamaz', () async {
    final file = File('${tempDir.path}/enc2.db');
    final db = AppDatabase(
      AppDatabaseFactory.encryptedExecutor(file, 'gizli-anahtar'),
    );
    await db.customSelect('SELECT 1').get();
    await db.close();

    // Anahtarsız açmaya çalış: SQLCipher dosyayı okuyamaz.
    final raw = sqlite3.open(file.path);
    expect(
      () => raw.select('SELECT count(*) FROM sqlite_master'),
      throwsA(isA<SqliteException>()),
      reason: 'şifreli dosya anahtarsız okunabiliyor — şifreleme çalışmıyor',
    );
    raw.close();
  });

  test('yanlış anahtarla açılamaz', () async {
    final file = File('${tempDir.path}/enc3.db');
    final db = AppDatabase(
      AppDatabaseFactory.encryptedExecutor(file, 'dogru-anahtar'),
    );
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sqlite3.open(file.path);
    raw.execute("PRAGMA key = 'yanlis-anahtar'");
    expect(
      () => raw.select('SELECT count(*) FROM sqlite_master'),
      throwsA(isA<SqliteException>()),
    );
    raw.close();
  });

  test('dosyanın ham baytlarında düz metin SQLite başlığı YOK', () async {
    final file = File('${tempDir.path}/enc4.db');
    final db = AppDatabase(
      AppDatabaseFactory.encryptedExecutor(file, 'anahtar'),
    );
    await db.customSelect('SELECT 1').get();
    await db.close();

    final header = file.readAsBytesSync().take(16).toList();
    final asText = String.fromCharCodes(header);
    expect(
      asText.startsWith('SQLite format 3'),
      isFalse,
      reason: 'şifresiz veritabanı başlığı görünüyor',
    );
  });

  group('InMemoryKeyStore (test ve geliştirici menüsü)', () {
    test('yoksa üretir, sonra aynısını döndürür', () async {
      final store = InMemoryKeyStore();
      expect(await store.exists(), isFalse);
      final first = await store.getOrCreate();
      expect(await store.exists(), isTrue);
      expect(await store.getOrCreate(), first);
    });

    test('overwrite anahtarı değiştirir (geri yükleme senaryosu)', () async {
      final store = InMemoryKeyStore('eski');
      await store.overwrite('yeni');
      expect(await store.getOrCreate(), 'yeni');
    });
  });
}
