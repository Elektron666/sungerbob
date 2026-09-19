import 'package:local_auth/local_auth.dart';

/// Parmak izi / yüz ile kilit açma (BRIEF §5: "local_auth + PIN").
///
/// Paket bağımlılık listesindeydi ama hiçbir yerden çağrılmıyordu; kilit
/// yalnızca PIN'di. Toptancı uygulamayı günde onlarca kez açar — her
/// seferinde dört hane girmek, kullanılmama sebebidir.
///
/// **PIN her zaman açık kalır.** Parmak izi bir kolaylıktır, tek faktör
/// değil: parmak okunmazsa, cihazda kayıtlı parmak kalmazsa veya donanım
/// bozulursa kullanıcı defterine erişemez duruma düşmemeli.
///
/// Arayüz `local_auth`'a doğrudan dokunmasın diye arada bu sınıf var;
/// testte sahte bir uygulamayla değiştirilebiliyor.
abstract interface class BiometricAuth {
  /// Cihazda kullanılabilir bir biyometri var mı?
  Future<bool> isAvailable();

  /// Kullanıcıyı doğrular. Başarısızlıkta, iptalde ve hatada `false`.
  Future<bool> authenticate();
}

final class LocalBiometricAuth implements BiometricAuth {
  final LocalAuthentication _auth;

  LocalBiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      // `isDeviceSupported` cihaz PIN'ine düşebilmeyi de sayar; biz
      // yalnızca gerçekten biyometri varsa düğmeyi gösteriyoruz.
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      // Eklenti yoksa ya da platform desteklemiyorsa kilit PIN'le açılır.
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Defteri açmak için parmak izinizi okutun',
        // Yalnızca biyometri: cihaz PIN'i sorulursa kullanıcı iki farklı
        // PIN arasında kafası karışır (uygulamanın kendi PIN'i ayrıdır).
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}
