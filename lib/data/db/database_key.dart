import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Veritabanı şifreleme anahtarının yönetimi (BRIEF §2, ARCHITECTURE §9).
///
/// Anahtar kurulumda rastgele üretilir ve **yalnızca** güvenli depoda
/// (Android Keystore destekli `flutter_secure_storage`) saklanır.
///
/// ÖNEMLİ: Bu anahtar telefona bağlıdır ve telefon kaybolursa kaybolur.
/// Yedek dosyası bu anahtara **bağlı değildir** — yedek kendi şifresiyle
/// şifrelenir ve başka bir telefonda yalnızca o şifreyle açılır (D-13).
abstract interface class DatabaseKeyStore {
  /// Anahtarı döndürür; yoksa üretip saklar.
  Future<String> getOrCreate();

  /// Anahtar daha önce üretilmiş mi? Kurulum sihirbazı bunu sorar.
  Future<bool> exists();

  /// Yedekten geri yüklemede veritabanı cihazın KENDİ anahtarıyla yeniden
  /// şifrelenir; bu yüzden anahtar orada da lazımdır.
  Future<void> overwrite(String key);
}

const _keyName = 'sungerbob_db_key';

final class SecureStorageKeyStore implements DatabaseKeyStore {
  final FlutterSecureStorage _storage;

  SecureStorageKeyStore([FlutterSecureStorage? storage])
    // v11 varsayılanı zaten AES-GCM + RSA OAEP anahtar sarmalaması
    // kullanıyor (Android Keystore destekli).
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<bool> exists() async => await _storage.read(key: _keyName) != null;

  @override
  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return existing;

    final generated = generateKey();
    await _storage.write(key: _keyName, value: generated);
    return generated;
  }

  @override
  Future<void> overwrite(String key) =>
      _storage.write(key: _keyName, value: key);

  /// 256 bit rastgele anahtar, base64 olarak.
  static String generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}

/// Test ve geliştirici menüsü için bellek içi anahtar deposu.
final class InMemoryKeyStore implements DatabaseKeyStore {
  String? _key;

  InMemoryKeyStore([this._key]);

  @override
  Future<bool> exists() async => _key != null;

  @override
  Future<String> getOrCreate() async =>
      _key ??= SecureStorageKeyStore.generateKey();

  @override
  Future<void> overwrite(String key) async => _key = key;
}
