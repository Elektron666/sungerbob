import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';
import 'database_key.dart';

/// Şifreli veritabanı bağlantısı (BRIEF §2).
///
/// SQLCipher, `sqlite3` 3.x'in build-hook'u ile devreye girer
/// (`pubspec.yaml` → `hooks.user_defines.sqlite3.source: sqlcipher`).
/// Eski `sqlcipher_flutter_libs` paketi artık kullanılmıyor (DECISIONS SK-07).
abstract final class AppDatabaseFactory {
  static const databaseFileName = 'sungerbob.db';

  /// Cihazdaki veritabanı dosyasının yolu.
  static Future<File> databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, databaseFileName));
  }

  /// Uygulamanın kullandığı şifreli veritabanını açar.
  static Future<AppDatabase> open(DatabaseKeyStore keyStore) async {
    final file = await databaseFile();
    final key = await keyStore.getOrCreate();
    return AppDatabase(encryptedExecutor(file, key));
  }

  /// Belirli bir dosyayı verilen anahtarla açan çalıştırıcı.
  ///
  /// Geri yüklemede geçici dosyayı açmak için de kullanılır (BACKUP.md §5.3).
  static QueryExecutor encryptedExecutor(File file, String key) =>
      NativeDatabase.createInBackground(
        file,
        setup: (db) => applyEncryption(db, key),
      );

  /// Açılan her bağlantıya uygulanan ayarlar.
  ///
  /// `PRAGMA key` **ilk** ifade olmalıdır; sonrasında veritabanı normal
  /// şekilde kullanılır.
  static void applyEncryption(Database db, String key) {
    db.execute("PRAGMA key = '${_escape(key)}'");
    // Anahtarın doğru olduğunu hemen doğrula: yanlışsa bu sorgu patlar.
    db.execute('SELECT count(*) FROM sqlite_master');
    db.execute('PRAGMA foreign_keys = ON');
  }

  /// SQLCipher'ın yüklü olduğunu ve şifrelemenin gerçekten çalıştığını
  /// doğrular. Kurulumda bir kez çağrılır.
  static bool isEncryptionAvailable() {
    final db = sqlite3.openInMemory();
    try {
      final rows = db.select('PRAGMA cipher_version');
      return rows.isNotEmpty &&
          rows.first.values.first.toString().trim().isNotEmpty;
    } on SqliteException {
      return false;
    } finally {
      db.close();
    }
  }

  static String _escape(String value) => value.replaceAll("'", "''");
}
