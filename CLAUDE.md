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
| **Faz 2 — Mobil çekirdek + yedekleme** | ✅ tamam |
| **Faz 3 — Operasyon** | ✅ sayım, fire, kesim, teklif, arama, PDF |
| **Faz 4 — Analiz ve raporlar** | ✅ müşteri/ürün analizi, kârlılık, CSV |
| **Faz 5 — Yayına alma** | ✅ kılavuzlar, imzalama, performans ölçümü |

**399 test geçiyor**, `flutter analyze` temiz, `dart format` uygulandı.
Şema sürümü **2** (ürün birimi); `drift_schemas/` altında v1 ve v2 anlık
görüntüsü, `test/data/generated_migrations/` altında üretilmiş yardımcı var.

Faz 1'de hazır olanlar:

- `domain/core` — ölçekler, ROUND_HALF_UP, Money/Volume/UnitPrice/Rate, dağıtım
- `domain/costing` — FIFO, ağırlıklı ortalama, masraf, fason kesim, iade tersine çevirme
- `domain/service/vat.dart` — EXCL/INCL, kâr marjı ve maliyet üzerine kâr
- `data/db` — 49 tablo, append-only trigger'ları, CHECK kısıtları, seed, migration
- `data/repo` — alış, satış, iade, iptal, tahsilat, ödeme, virman, evrak, açılış,
  fiyat listesi, `checkIntegrity`

Faz 2'de eklenenler:

- `data/backup` — `.sbk` formatı, AES-256-GCM + Argon2id, atomik geri yükleme,
  saklama kuralı, cihaz dışı yedek uyarısı
- `data/db/connection.dart` + `database_key.dart` — SQLCipher 4.19.0, anahtar
  `flutter_secure_storage`'da
- `data/repo/dashboard_queries.dart` — SPEC §18 kartları + Sermaye Dağılımı
- `ui/` — tema, Türkçe biçimlendirme, Riverpod, go_router, 10 ekran
- `.github/workflows/` — CI (test + debug APK artifact) ve release (imzalı APK)

**Derleme:** Android SDK yerelde yok; APK GitHub Actions'ta üretiliyor.
Actions sekmesindeki son koşunun **`sungerbob-debug-apk`** artifact'i telefona
kurulabilir.

Faz 3–5'te eklenenler:

- `data/repo/stock_ops_repository.dart` — sayım (DRAFT → onay) ve fire
- `data/repo/cutting_repository.dart` — fason kesim, kısmi dönüş
- `data/repo/quote_repository.dart` — teklif, satışa dönüştürme
- `data/repo/search_queries.dart` — global arama (Türkçe normalize)
- `data/repo/analytics_queries.dart` — müşteri/ürün analizi, kârlılık, dönemsel satış
- `data/documents/` — PDF belgeler (gömülü Noto Sans) ve CSV dışa aktarma
- `docs/KURULUM.md`, `docs/KULLANIM.md`
- `test/performance/` — 50.000 satırla ölçüm (ana sayfa 11 ms)

Faz 5 sonrası eklenenler:

- `ui/screens/setup/` — 8 adımlı kurulum sihirbazı (BRIEF §7)
- `ui/screens/lock/` — PIN kilit ekranı, tuş takımı, "maliyeti gizle" PIN sorgusu
- `ui/screens/reports/` — kârlılık, dönemsel satış grafiği (fl_chart), ürün
  analizi, vade raporu; üçü de CSV olarak paylaşılabiliyor
- `ui/screens/opening/` — açılış stoğu, cari ve kasa/banka bakiyeleri
- `ui/screens/ops/` — teklifler (satışa çevirme), kesim emirleri (gönder /
  dönüş al), sayım (taslak → onay), fire
- `ui/widgets/variant_picker.dart` — stoktaki varyantı seçtiren ortak sayfa
- `data/repo/party_repository.dart` + `ui/screens/master/` — müşteri ve
  tedarikçi kartı açma; seçiciler boşken bile kart açtırır (SK-21)
- `ui/theme/app_theme.dart` — sıcak minimalist palet (elle yazılmış, tohumdan
  türetilmiyor), Inter + Lora tipografi, kontrast testli (K-03)
- `ui/content/daily_quote.dart` — **Günün Sözü** (imza öğesi), gün bazında
  sabit, tamamı Türk atasözü
- `ui/widgets/signature.dart` — Günün Sözü kartı, karşılama satırı, tasarım
  imzası
- `ui/screens/settings/drive_screen.dart` — cihaz dışı yedek
- `ui/startup.dart` — kilit açıldıktan sonra bildirim kurulumu ve açılış yedeği
- `data/notifications/notification_service.dart` — `flutter_local_notifications`
- `data/backup/background_backup.dart` — `workmanager` saatlik görevi
- `data/backup/backup_password_store.dart` — yedek şifresi güvenli depoda
- `data/repo/settings_repository.dart` — PIN karması, maliyet yöntemi kilidi

Faz 6'da eklenenler (K-05 — paranın hareketi):

- `ui/screens/finance/payment_screen.dart` — tedarikçiye ödeme, güncel borç
  görünür
- `ui/screens/finance/accounts_screen.dart` — kasa/banka, hesap açma, virman
- `ui/screens/finance/instruments_screen.dart` — çek & senet portföyü,
  yalnızca izin verilen durum geçişleri
- `ui/screens/search/search_screen.dart` — ölü `/search` bağlantısı kapatıldı
- `data/repo/price_memory.dart` — "bu müşteriye en son kaça sattın" ipucu

Faz 7'de eklenenler (K-06 — ince malzeme):

- `products.unit` — `M3` / `ADET` / `KG` / `KUTU` / `LITRE` / `METRE` (D-22).
  Miktar süngerin m³ kolonunda durur, yalnızca anlamı değişir; **maliyet
  motoruna dokunulmadı.** m³ toplamları `unit = 'M3'` ile filtrelenir.
- `data/repo/product_repository.dart` + `ui/screens/master/products_screen.dart`
  — ürün kartı açma; ölçüsüz üründe tek varyant kendiliğinden kurulur
- Şema v2: `products` ve `product_variants` migration'da yeniden kurulur —
  `ADD COLUMN` tablo kısıtı ekleyemez (D-24)
- Tablo `CHECK` metinleri literal SQL; enum uyumunu
  `test/data/schema_constraints_test.dart` koruyor (D-23)
- Alış, satış, stok, fire, sayım ekranları birim farkındalığına açıldı:
  ölçü alanları yalnızca süngerde görünür, etiketler ürünün kendi birimini
  yazar ("Miktar (kg)", "TL/kg")

Faz 8'de eklenenler (K-07 — iade):

- `ui/screens/sale/sale_return_screen.dart` — `Satışlar → belge → İade al`.
  Kalem başına iade miktarı; artı tuşu tavanda kilitlenir (iade satılandan
  fazla olamaz), daha önce iade alınmışsa tavan kalan miktardır.
- `ReturnRepository.returnableLines` — "neyi, en fazla kaç tane" sorgusu
- Satışlar listesinde ve belge detayında iade tutarı görünüyor
- Satış iptali **eklenmedi**: düzeltmenin doğru yolu iadedir (D-25)

Faz 9'da eklenenler (K-08 — teklif yazma):

- `ui/screens/ops/quote_form_screen.dart` — çok kalemli teklif; ölçü
  serbest, teklif stoğa dokunmaz (D-26)
- `ui/widgets/product_picker.dart` — alış ve teklifin ortak ürün seçicisi

Faz 10'da eklenenler (K-09 — fiyat listesi):

- `ui/screens/master/price_lists_screen.dart` — baz TL/m³ + yuvarlama →
  **önizleme** → yürürlüğe alma. Önizleme görülmeden kaydedilemez (D-27);
  eski versiyon silinmez, arşivlenir.
- `PriceMemory.activeListPrice` + satış ekranında **liste fiyatı** ipucu;
  son satış fiyatının yanında durur, ikisi de dokununca doldurur (D-28)

Faz 11'de eklenenler (K-10 — bekçiler):

- `test/ui/routes_test.dart` — kaynağı tarayıp gidilen her rotanın tanımlı
  olduğunu doğrular (D-29). İlk koşuşta vade bildirimlerinin iki ölü
  rotasını buldu; ikisi de tanımlanıp işe yarar hâle getirildi.
- `test/ui/screens_smoke_test.dart` — 28 ekranı boş veritabanıyla 360×640 ve
  411×891'de çizer (D-30). Test yazı tipi cihazdakinden geniş olduğu için
  **temkinli** bir sınırdır; büyük yazı tipi ayarına da güvence verir.

**Kalan işler:**

- Google Drive API istemcisi (SK-12 — OAuth istemci kimliği bekleniyor)
- Ekransız iş mantığı **kalmadı**.
