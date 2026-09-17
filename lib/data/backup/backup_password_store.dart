import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Yedek şifresinin cihaz üzerindeki saklanması.
///
/// Otomatik yedek kullanıcı etkileşimi olmadan çalışır; bu yüzden şifreye
/// arka planda erişebilmelidir (D-22). Şifre **yalnızca** güvenli depoda
/// (Android Keystore destekli) tutulur, veritabanına veya yedek dosyasına
/// yazılmaz.
///
/// Bu, yedeğin cihaz bağımsızlığını bozmaz: `.sbk` dosyası hâlâ yalnızca
/// yedek şifresiyle açılır. Burada saklanan kopya kaybolursa yedekler
/// okunabilir kalır — yeter ki kullanıcı şifreyi bir yere not etmiş olsun.
/// Kurulum sihirbazı bunu açıkça uyarır.
abstract interface class BackupPasswordStore {
  Future<String?> read();
  Future<void> write(String password);
  Future<bool> exists();
}

const _passwordKey = 'sungerbob_backup_password';

final class SecureBackupPasswordStore implements BackupPasswordStore {
  final FlutterSecureStorage _storage;

  SecureBackupPasswordStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _passwordKey);

  @override
  Future<void> write(String password) =>
      _storage.write(key: _passwordKey, value: password);

  @override
  Future<bool> exists() async => await _storage.read(key: _passwordKey) != null;
}

final class InMemoryBackupPasswordStore implements BackupPasswordStore {
  String? _password;

  InMemoryBackupPasswordStore([this._password]);

  @override
  Future<String?> read() async => _password;

  @override
  Future<void> write(String password) async => _password = password;

  @override
  Future<bool> exists() async => _password != null;
}

/// Yedek şifresi kuralları (BRIEF §4.2): en az 8 karakter, harf ve rakam.
final class BackupPasswordRules {
  static const minLength = 8;

  /// Hata mesajı döndürür; geçerliyse `null`.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'Yedek şifresi en az $minLength karakter olmalı';
    }
    final hasLetter = password.contains(RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) {
      return 'Yedek şifresi en az bir harf ve bir rakam içermeli';
    }
    return null;
  }

  static bool isValid(String password) => validate(password) == null;
}
