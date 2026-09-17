# CLAUDE.md — Sünger Stok & Cari (Android, offline)

Toptan sünger alım-satımı yapan işletme için **tek kullanıcılı, sunucusuz, tamamen cihaz
üzerinde çalışan Android uygulaması**. Üretim yazılımı, demo değil.

## Otorite sırası

1. `docs/BRIEF.md` — müşteriyle netleşen kesin kararlar. **Çelişkide bu kazanır.**
2. `docs/SPEC.md` — müşterinin orijinal spesifikasyonu.
3. `docs/DECISIONS.md` — geliştirme sırasında alınan kararlar ve gerekçeleri.

## Çalışma kuralları

- **Faz sonunda dur.** Her fazın sonunda testler geçmeli, `flutter analyze` temiz olmalı,
  migration'lar sıfırdan çalışmalı. Kısa özet yaz, onay bekle. Fazlar: `docs/BRIEF.md` Bölüm 9.
- **Önce test.** Maliyet, stok, cari ve yedekleme kurallarında test kod'dan önce yazılır.
- **Mock veri yok.** Ekranlar boş durumla açılır; demo verisi yalnızca geliştirici menüsünden.
- **Dil:** Arayüz metinleri Türkçe; kod, tablo, kolon, değişken adları İngilizce.
- **Paket sürümü ezberden yazılmaz** — `pub.dev`'den güncel kararlı sürüm doğrulanır.
- Her mimari karar gerekçesiyle `docs/DECISIONS.md`'ye yazılır.

## Komutlar

Flutter `/opt/sdk/flutter/bin` altında; PATH'e ekle:
`export PATH=/opt/sdk/flutter/bin:$PATH`

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift + Riverpod kod üretimi
flutter analyze                                            # uyarısız olmalı
dart format --set-exit-if-changed .

flutter test                                  # domain + data katmanı
flutter test test/domain                      # saf Dart iş kuralları (hızlı)
flutter test test/golden_scenario              # Altın Senaryo (docs/GOLDEN_SCENARIO.md)
flutter test test/backup                      # yedekleme senaryoları (zorunlu)
flutter test integration_test                 # cihaz/emülatör gerektirir

flutter build apk --debug                     # Faz 2 test APK'sı
flutter build apk --release                   # Faz 5 yayın APK'sı
```

Migration testleri için şema anlık görüntüleri `drift_schemas/` altında tutulur:

```bash
dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

## Klasör yapısı

```
lib/
  domain/     # saf Dart. Flutter importu YASAK. İş kuralları, maliyet motoru, KDV, m³.
    core/     # money.dart, quantity.dart, rounding.dart, allocation.dart
    costing/  # FIFO, ağırlıklı ortalama, masraf dağıtımı, kesim maliyeti
    model/    # değer nesneleri ve saf domain entity'leri
    service/  # iş akışı kuralları (satış, iade, tahsilat eşleştirme, evrak durumları)
  data/       # Drift şeması, TypeConverter'lar, trigger'lar, repository'ler, yedekleme
    db/       # tablolar, migration'lar, seed
    repo/
    backup/   # .sbk üretimi, şifreleme, geri yükleme, Drive
  ui/         # Material 3 ekranlar, Riverpod provider'ları, go_router
  l10n/       # tr_TR
test/
  domain/ data/ backup/ golden_scenario/
integration_test/
docs/
```

Bağımlılık yönü tek yönlüdür: `ui → data → domain`. `domain` hiçbir şeye bağlı değildir.

## İş kurallarının kısa özeti

Tamamı `docs/ARCHITECTURE.md` ve `docs/BRIEF.md` Bölüm 3'te.

- **Sayısal saklama:** her şey sabit ölçekli **INTEGER**. Para ×100 (kuruş), birim fiyat
  ×10.000, m³ ×1.000.000, ölçü (cm) ×100, oran ×100, adet tamsayı. SQL'de yalnızca
  toplama/çıkarma; çarpma/bölme **Dart'ta `Decimal` ile**. Para ve m³ hesabında `double` YASAK.
- **m³** = (en/100) × (boy/100) × (kalınlık/100) × adet. Yuvarlama `ROUND_HALF_UP`, tek
  yardımcı fonksiyonda. Bir tutar satırlara dağıtılırken kuruş farkı **son satıra** eklenir.
- **KDV:** belge başlığında `price_mode` = `EXCL`/`INCL`. `INCL`'de girilen tutar aynen korunur
  (`KDV = yuvarla(toplam − toplam/(1+oran))`, `net = toplam − KDV`). Maliyet, kâr ve ciro
  **her zaman KDV hariç**; cariye **brüt** yazılır.
- **Değiştirilemezlik:** hareket ve log tabloları append-only, SQLite trigger'ı ile UPDATE/DELETE
  engellenir. Düzeltme yalnızca `reversal_of_id` ile **ters hareket**. Belge başlığında sadece
  durum alanları güncellenir.
- **Maliyet:** her alış satırı bir parti. FIFO varsayılan; ağırlıklı ortalama ürün (çeşit)
  bazında. Yöntem ilk stok hareketinden sonra kilitlenir. `sale_items.cost_total` satış anında
  sabitlenir, bir daha değişmez. Her çıkış `cost_allocations`'a parti bazlı yazılır.
- **Negatif stok yasak.**
- **Transaction:** her iş işlemi tek Drift transaction'ı. Her işlem form açılışında üretilen
  UUID ile `command_log`'a yazılır; aynı UUID ikinci kez gelirse işlem tekrarlanmaz.
- **Yedekleme kritik:** veri yalnızca telefonda. `.sbk` dosyası yedek şifresiyle AES-256-GCM
  ile şifrelenir ve **cihaz anahtarına bağlı olmamalıdır**. Ayrıntı: `docs/BACKUP.md`.

## Faz 0 çıktıları

| Doküman | İçerik |
|---|---|
| `docs/ARCHITECTURE.md` | Katmanlar, sayısal saklama, KDV/yuvarlama, maliyet motoru, append-only, transaction |
| `docs/ERD.md` | Mermaid ER diyagramları, kısıtlar, trigger listesi, enum sözlüğü, SPEC §26 uyumu, 12 ürün seed'i |
| `docs/BACKUP.md` | `.sbk` formatı, AES-256-GCM, otomatik yedek, atomik geri yükleme, zorunlu testler |
| `docs/FLOWS.md` | 12 iş akışı, transaction adımlarıyla |
| `docs/SCREENS.md` | Ekran listesi, rotalar, faz dağılımı |
| `docs/GOLDEN_SCENARIO.md` | Doğrulanmış rakamlar — testlerin birebir kaynağı |
| `docs/FUTURE_SYNC.md` | İkinci kullanıcı ve sunucu senkronizasyonu (şimdi yapılmayacak) |
| `docs/DECISIONS.md` | Kararlar, gerekçeler, varsayımlar, **SABAH KONTROL** |

## Ortam

- Flutter **3.47.4** / Dart **3.13.3** → `/opt/sdk/flutter/bin` (PATH'e ekle).
- **Android SDK kurulu değil** — `dl.google.com` bu ortamın ağ politikasıyla engelli.
  Faz 1 bunu gerektirmedi; APK derlemesi GitHub Actions ile yapılacak (`DECISIONS.md` SK-01, D-K2).

## Durum

| Faz | Durum |
|---|---|
| Faz 0 — Mimari | ✅ tamam |
| **Faz 1 — Domain ve veri katmanı** | ✅ **tamam — 124 test geçiyor, analyze temiz** |
| Faz 2 — Mobil çekirdek + yedekleme | ⏳ sırada |
| Faz 3–5 | ⏳ |

Faz 1'de hazır olanlar:

- `domain/core` — ölçekler, ROUND_HALF_UP, Money/Volume/UnitPrice/Rate, dağıtım
- `domain/costing` — FIFO, ağırlıklı ortalama, masraf, fason kesim, iade tersine çevirme
- `domain/service/vat.dart` — EXCL/INCL, kâr marjı ve maliyet üzerine kâr
- `data/db` — 49 tablo, append-only trigger'ları, CHECK kısıtları, seed, migration
- `data/repo` — alış, satış, iade, iptal, tahsilat, ödeme, virman, evrak, açılış,
  fiyat listesi, `checkIntegrity`

**Faz 2'nin ilk iki işi:** (1) SQLCipher'ı `sqlite3` 3.x build-hook'u ile devreye almak
(SK-07), (2) GitHub Actions workflow'u (D-K2).
