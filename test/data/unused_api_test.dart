@Tags(['guard'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Yazılmış ama hiç çağrılmamış iş kuralı bekçisi.**
///
/// Bu projede en pahalı hata türü bu oldu ve hep aynı biçimde çıktı: bir
/// iş kuralı yazılır, testi de yazılır, testler geçer — ama hiçbir ekran
/// onu çağırmaz. Kullanıcı için o özellik **yoktur**, üstelik testler yeşil
/// olduğu için kimse fark etmez.
///
/// İki gerçek örnek:
///
/// - `PdfDocuments` — dört belge yazılmış ve testliydi, hiçbir ekrandan
///   çağrılmıyordu (K-11). BRIEF §5'in "WhatsApp'a paylaşılır" sözü boştaydı.
/// - `SettingsRepository.defaultVatRate` — yazılmıştı, kurulum sihirbazı
///   oranı soruyordu, ama belge ekranları %20'yi koda gömülü tutuyordu.
///   Kullanıcı %10 seçse bile her belge %20 hesaplıyordu (D-32). Bu bir
///   arayüz eksiği değil, **yanlış rakam** üretmekti.
///
/// İkisini de elle tarayarak buldum. Elle tarama ölçeklenmez; bu test aynı
/// taramayı her koşuda yapar.
///
/// **Kapsam:** `lib/data/repo` ve `lib/data/documents` — iş kuralının ve
/// belgelerin durduğu yerler.
///
/// **Ölçüt:** metodun `lib/` içinde *herhangi bir yerden* çağrılması yeter.
/// Yalnızca `lib/data` içinden çağrılan bir metot (ör. `writeAudit`) altyapı
/// olarak kullanılıyordur; aranan, **hiçbir yerden** çağrılmayandır — iki
/// gerçek hatanın ikisi de öyleydi.
void main() {
  /// Bilerek arayüzden çağrılmayanlar. Her satırın **gerekçesi** var;
  /// gerekçe yazılamıyorsa muhtemelen eksik bir ekran vardır.
  const allowed = <String, String>{
    'useFonts':
        'testlerin fontu elle yüklemesi için; uygulama '
        'loadBundledFonts kullanır',
    'platePrice':
        'SPEC §14 yardımcı hesabı; plaka fiyatı henüz hiçbir '
        'ekranda gösterilmiyor (bilinen eksik)',
    'expireOverdue':
        'süresi geçen teklifleri işaretler; açılış görevinden '
        'çağrılacak (bilinen eksik)',
    'recomputeCustomerBalance':
        'tutarlılık kontrolünün düzeltme adımı; '
        'rapor gösteriliyor, otomatik düzeltme bilerek yapılmıyor',
    'costingMethod':
        'ayar okuma; SaleRepository aynı ayarı kendi sorgusuyla '
        'okuyor, ekran settingsMapProvider üzerinden gösteriyor',
    'isCostingMethodLocked':
        'maliyet yöntemi ilk stok hareketinden sonra '
        'kilitlenir; yöntemi değiştiren ekran yok (kurulum sihirbazında '
        'seçiliyor), bu yüzden kilit sorgusu da çağrılmıyor',
    'backupWifiOnly':
        'Drive otomatik yüklemesinin ayarı; Drive istemcisi '
        'OAuth kimliği beklediği için bağlanmadı (SK-12)',
    'setBackupWifiOnly': 'aynı — SK-12 bekliyor',
    'driveFolderId': 'aynı — SK-12 bekliyor',
    'setDriveFolderId': 'aynı — SK-12 bekliyor',
  };

  test('lib/data/repo ve documents içindeki her genel metodun çağıranı var', () {
    // Bütün kaynak, dosya dosya. Bir metodun çağıranı aranırken **kendi
    // dosyası hariç** her yere bakılır: kendi dosyasında geçmesi tanımın
    // kendisi olabilir, başka bir dosyada geçmesi gerçek kullanımdır.
    final sources = <String, String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      sources[file.path] = file.readAsStringSync();
    }
    expect(sources, isNotEmpty, reason: 'kaynak boş okundu — tarama bozuk');

    /// `  Future<X> name(` / `  static X name(` biçimindeki genel metotlar.
    final method = RegExp(
      r'^\s{2}(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|[A-Z]\w*\??|void)'
      r'\s+(\w+)\s*\(',
      multiLine: true,
    );

    final orphans = <String>[];
    for (final dir in const ['lib/data/repo', 'lib/data/documents']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();

        for (final m in method.allMatches(source)) {
          final name = m.group(1)!;
          if (name.startsWith('_') || allowed.containsKey(name)) continue;

          final call = RegExp('\\b$name\\s*\\(');
          final calledElsewhere = sources.entries.any(
            (e) => e.key != file.path && call.hasMatch(e.value),
          );
          if (calledElsewhere) continue;
          orphans.add('${file.path}: $name');
        }
      }
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'Bu iş kuralları yazılmış ama uygulamada hiçbir yerden '
          'çağrılmıyor — kullanıcı için YOKLAR:\n  ${orphans.join('\n  ')}\n\n'
          'Ya bir ekrana bağlayın, ya da testteki `allowed` listesine '
          'gerekçesiyle ekleyin.',
    );
  });
}
