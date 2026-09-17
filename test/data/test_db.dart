import 'package:drift/native.dart';
import 'package:sungerbob/data/db/app_database.dart';

/// Bellek içi test veritabanı. Faz 1'de SQLCipher kullanılmaz; şifreleme
/// Faz 2'de sqlite3 build-hook'u ile devreye girer (DECISIONS SK-01).
AppDatabase newTestDatabase() => AppDatabase(
  NativeDatabase.memory(
    setup: (db) {
      db.execute('PRAGMA foreign_keys = ON');
    },
  ),
);
