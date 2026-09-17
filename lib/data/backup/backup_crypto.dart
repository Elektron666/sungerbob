import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// `.sbk` dosyasının şifrelenmesi (BACKUP.md §1.3).
///
/// AES-256-GCM. Anahtar, yedek şifresinden Argon2id ile türetilir; platform
/// desteklemezse PBKDF2-HMAC-SHA256 (≥ 600.000 iterasyon) kullanılır.
///
/// Dosya düzeni — ilk 38 bayt başlıktır ve GCM'e **AAD** olarak verilir,
/// böylece başlıktaki tek bir baytın değişmesi çözmeyi başarısız kılar:
///
/// ```
/// offset  uzunluk  alan
/// 0       4        sihirli sayı "SBK1"
/// 4       1        format sürümü
/// 5       1        KDF kimliği (1 = Argon2id, 2 = PBKDF2-HMAC-SHA256)
/// 6       4        KDF parametresi (big-endian)
/// 10      16       salt
/// 26      12       nonce
/// 38      N        şifreli içerik
/// 38+N    16       GCM etiketi
/// ```

/// Yedek dosyası bozuk, kesilmiş veya bu uygulamaya ait değil.
final class CorruptBackupException implements Exception {
  final String reason;
  const CorruptBackupException(this.reason);
  @override
  String toString() => 'Yedek dosyası okunamadı: $reason';
}

/// Yedek şifresi yanlış.
final class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() =>
      'Yedek şifresi yanlış. Yedek açılamadı, mevcut veriniz değişmedi.';
}

enum KdfKind {
  argon2id(1),
  pbkdf2(2);

  final int id;
  const KdfKind(this.id);

  static KdfKind fromId(int id) => switch (id) {
    1 => KdfKind.argon2id,
    2 => KdfKind.pbkdf2,
    _ => throw CorruptBackupException(
      'bilinmeyen anahtar türetme yöntemi: $id',
    ),
  };
}

abstract final class BackupCrypto {
  static const magic = [0x53, 0x42, 0x4B, 0x31]; // "SBK1"
  static const formatVersion = 1;
  static const headerLength = 38;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const macLength = 16;

  /// Argon2id: 64 MiB, 3 geçiş, 1 paralellik (BACKUP.md §1.3).
  static const argon2Memory = 65536; // 1 kB blok sayısı
  static const argon2Iterations = 3;
  static const argon2Parallelism = 1;

  /// PBKDF2 yedek yolu — en az 600.000 iterasyon.
  static const pbkdf2Iterations = 600000;

  static final _random = Random.secure();

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  /// Şifreden 256 bit anahtar türetir.
  static Future<SecretKey> deriveKey({
    required String password,
    required Uint8List salt,
    required KdfKind kdf,
    required int parameter,
  }) async {
    final bytes = Uint8List.fromList(password.codeUnits);
    switch (kdf) {
      case KdfKind.argon2id:
        final algorithm = Argon2id(
          parallelism: argon2Parallelism,
          memory: parameter,
          iterations: argon2Iterations,
          hashLength: 32,
        );
        return algorithm.deriveKey(secretKey: SecretKey(bytes), nonce: salt);
      case KdfKind.pbkdf2:
        final algorithm = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: parameter,
          bits: 256,
        );
        return algorithm.deriveKey(secretKey: SecretKey(bytes), nonce: salt);
    }
  }

  /// Düz içeriği şifreleyip tam `.sbk` baytlarını üretir.
  static Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required String password,
    KdfKind kdf = KdfKind.argon2id,
  }) async {
    final salt = _randomBytes(saltLength);
    final nonce = _randomBytes(nonceLength);
    final parameter = kdf == KdfKind.argon2id ? argon2Memory : pbkdf2Iterations;

    final header = _buildHeader(
      kdf: kdf,
      parameter: parameter,
      salt: salt,
      nonce: nonce,
    );
    final key = await deriveKey(
      password: password,
      salt: salt,
      kdf: kdf,
      parameter: parameter,
    );

    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      // Başlık kimlik doğrulamaya dahil: değiştirilirse çözme başarısız olur.
      aad: header,
    );

    return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
  }

  /// `.sbk` baytlarını çözer. Şifre yanlışsa [WrongPasswordException],
  /// dosya bozuksa [CorruptBackupException] fırlatır.
  static Future<Uint8List> decrypt({
    required Uint8List fileBytes,
    required String password,
  }) async {
    final header = readHeader(fileBytes);

    if (fileBytes.length < headerLength + macLength) {
      throw const CorruptBackupException('dosya eksik veya kesilmiş');
    }

    final cipherText = fileBytes.sublist(
      headerLength,
      fileBytes.length - macLength,
    );
    final mac = fileBytes.sublist(fileBytes.length - macLength);

    final key = await deriveKey(
      password: password,
      salt: header.salt,
      kdf: header.kdf,
      parameter: header.parameter,
    );

    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: header.nonce, mac: Mac(mac)),
        secretKey: key,
        aad: fileBytes.sublist(0, headerLength),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      // GCM etiketi tutmadı: ya şifre yanlış ya da dosya değiştirilmiş.
      // İkisini ayırt etmek kriptografik olarak mümkün değil; kullanıcıya
      // önce şifreyi kontrol etmesi söylenir.
      throw const WrongPasswordException();
    }
  }

  static Uint8List _buildHeader({
    required KdfKind kdf,
    required int parameter,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final header = Uint8List(headerLength);
    header.setRange(0, 4, magic);
    header[4] = formatVersion;
    header[5] = kdf.id;
    ByteData.view(header.buffer).setUint32(6, parameter, Endian.big);
    header.setRange(10, 26, salt);
    header.setRange(26, 38, nonce);
    return header;
  }

  /// Başlığı okur ve doğrular. Dosyanın tamamını çözmeden hızlı kontrol sağlar.
  static BackupHeader readHeader(Uint8List fileBytes) {
    if (fileBytes.length < headerLength) {
      throw const CorruptBackupException('dosya çok küçük');
    }
    for (var i = 0; i < magic.length; i++) {
      if (fileBytes[i] != magic[i]) {
        throw const CorruptBackupException(
          'bu bir Sünger yedek dosyası (.sbk) değil',
        );
      }
    }
    final version = fileBytes[4];
    if (version != formatVersion) {
      throw CorruptBackupException(
        'desteklenmeyen yedek format sürümü: $version',
      );
    }
    return BackupHeader(
      formatVersion: version,
      kdf: KdfKind.fromId(fileBytes[5]),
      parameter: ByteData.view(
        fileBytes.buffer,
        fileBytes.offsetInBytes,
      ).getUint32(6, Endian.big),
      salt: Uint8List.fromList(fileBytes.sublist(10, 26)),
      nonce: Uint8List.fromList(fileBytes.sublist(26, 38)),
    );
  }
}

final class BackupHeader {
  final int formatVersion;
  final KdfKind kdf;
  final int parameter;
  final Uint8List salt;
  final Uint8List nonce;

  const BackupHeader({
    required this.formatVersion,
    required this.kdf,
    required this.parameter,
    required this.salt,
    required this.nonce,
  });
}
