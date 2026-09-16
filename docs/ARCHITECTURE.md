# Mimari — Sünger Stok & Cari

Faz 0 çıktısı. Kod yok; bu doküman Faz 1'in sözleşmesidir.
Kesin kararların kaynağı `docs/BRIEF.md`; gerekçeler `docs/DECISIONS.md`.

---

## 1. Sistem sınırları

Tek bir Android APK. Sunucu yok, ağ çağrısı gerektiren hiçbir iş akışı yok.
Uygulama uçak modunda **eksiksiz** çalışır. İnternet yalnızca iki isteğe bağlı yerde kullanılır:

| Yetenek | İnternet | Başarısız olursa |
|---|---|---|
| Tüm iş akışları (satış, alış, cari, stok, evrak, rapor) | Hayır | — |
| Google Drive'a yedek yükleme | Evet | Yedek yerelde kalır, "paylaş" seçeneği sunulur |
| Yedeği WhatsApp/e-posta ile paylaşma | Hayır (uygulamalar arası) | — |

Minimum Android 8 (API 26). Kod iOS ve Windows derlemesini engellemeyecek şekilde yazılır;
platforma özel API'ler `data` katmanında arayüz arkasına alınır.

---

## 2. Katmanlar

```
┌──────────────────────────────────────────────┐
│ ui/      Material 3 ekranları, Riverpod,     │
│          go_router. Türkçe metinler.         │
└───────────────┬──────────────────────────────┘
                │ sadece repository arayüzleri ve domain tipleri
┌───────────────▼──────────────────────────────┐
│ data/    Drift (SQLCipher), TypeConverter,   │
│          repository'ler, yedekleme, Drive    │
└───────────────┬──────────────────────────────┘
                │ saf Dart tipleri (Decimal, value object)
┌───────────────▼──────────────────────────────┐
│ domain/  İş kuralları. Flutter importu YOK.  │
│          Maliyet motoru, KDV, m³, eşleştirme │
└──────────────────────────────────────────────┘
```

Kural: `domain` katmanı `package:flutter`, `package:drift` veya herhangi bir I/O paketine
bağımlı olamaz. Bu bir test ile zorlanır (`test/domain/no_flutter_import_test.dart`:
`lib/domain/**` içindeki importları tarar).

**Neden:** maliyet motoru işletmenin en değerli parçası. Saf Dart kalırsa hem hızlı test edilir
hem de ileride sunucuya olduğu gibi taşınabilir (bkz. `docs/FUTURE_SYNC.md`).

### 2.1 domain/

| Modül | Sorumluluk |
|---|---|
| `core/money.dart` | Kuruş ↔ `Decimal`, para aritmetiği, ROUND_HALF_UP yuvarlama |
| `core/quantity.dart` | m³, ölçü, adet ölçekleri; m³ hesabı |
| `core/rounding.dart` | Tek yuvarlama fonksiyonu (tüm sistemde tek kaynak) |
| `core/allocation.dart` | Bir tutarı satırlara dağıtma; kuruş farkı son satıra |
| `costing/fifo.dart` | Parti tüketim sırası ve dağılımı |
| `costing/weighted_average.dart` | Ürün bazlı ağırlıklı ortalama birim maliyet |
| `costing/expense_allocation.dart` | Alış masrafının partilere ve sonradan gelen masrafın stok/satılmış ayrımına dağıtımı |
| `costing/cutting_costing.dart` | Kaynak maliyeti + kesim ücreti + nakliyenin hedeflere m³ oranında aktarımı |
| `service/vat.dart` | EXCL/INCL satır hesabı |
| `service/settlement.dart` | Tahsilat/ödeme eşleştirme, vade, gecikme |
| `service/instrument_rules.dart` | Çek/senet durum geçiş tablosu |
| `service/integrity.dart` | `checkIntegrity()` karşılaştırma mantığı (veriyi `data` besler) |

### 2.2 data/

Drift veritabanı, tablo tanımları, migration'lar, trigger'lar, TypeConverter'lar,
repository'ler, yedekleme servisi ve Drive istemcisi. Her iş işlemi burada **tek bir
`transaction`** içinde yürütülür.

### 2.3 ui/

Riverpod ile durum yönetimi, `go_router` ile yönlendirme. Ekran listesi `docs/SCREENS.md`.
Ekranlar repository'lere doğrudan değil, Riverpod provider'ları üzerinden erişir.

---

## 3. Sayısal saklama (kritik)

SQLite'ta kesin ondalık tip yoktur; `NUMERIC`/`REAL` kolonları sessizce kayan noktaya döner.
Bu yüzden **veritabanında ondalık sayı yoktur.** Her sayısal değer sabit ölçekli `INTEGER`'dır.

| Büyüklük | Ölçek | Örnek | Saklanan |
|---|---|---|---|
| Para | ×100 (kuruş) | 59.388,00 TL | `5938800` |
| Birim fiyat (TL/m³, TL/plaka) | ×10.000 | 3.030,0000 TL/m³ | `30300000` |
| Hacim (m³) | ×1.000.000 | 14,000000 m³ | `14000000` |
| Ölçü (cm) | ×100 | 2,5 cm | `250` |
| Oran (%) | ×100 | %20 | `2000` |
| Adet | 1 | 50 | `50` |

Kurallar:

- Dart tarafında bu değerler Drift `TypeConverter` ile **`Decimal`**'e çevrilir. Ölçek
  sabitleri ve dönüştürücüler yalnızca `domain/core/money.dart` ve
  `domain/core/quantity.dart` içinde tanımlanır; başka yerde ölçek katsayısı yazılmaz.
- SQL içinde yalnızca **toplama ve çıkarma** yapılabilir (tamsayı olduğu için kesin).
  `SUM(pieces)`, `SUM(volume)`, `SUM(amount)` serbesttir.
- **Çarpma, bölme, yüzde ve ortalama SQL'de yapılmaz.** Dart'ta `Decimal` ile yapılır.
- Para ve m³ hesabında `double`/`num` kullanmak yasaktır. İki katmanlı koruma:
  1. `custom_lint` kuralı: `domain/` ve `data/` içinde para/miktar tiplerine `double` ataması.
  2. Kaynak tarayan test: `lib/domain/**` ve `lib/data/**` içinde `double`, `toDouble()`,
     `.toStringAsFixed(` kullanımını arar; izin verilen tek yer grafik/gösterim yardımcılarıdır
     ve açık bir `// ignore: allowed-double` yorumu gerektirir.

`int64` sınırı: en büyük ölçek m³ (×10⁶) ve birim fiyat (×10⁴). 9,2×10¹⁸ tavanına karşı
gerçekçi tutarlar 10¹² mertebesinde kalır; taşma riski yoktur. Yine de dönüştürücülerde
uç değer testi yazılır.

---

## 4. Hesap kuralları

### 4.1 m³

```
m³(bir parça) = (en/100) × (boy/100) × (kalınlık/100)      // cm → m
m³(satır)     = m³(bir parça) × adet
```

Örnek: 140×200×10 → 1,4 × 2,0 × 0,1 = 0,28 m³; 50 adet → 14,000000 m³.

### 4.2 Yuvarlama

Tek kural: **ROUND_HALF_UP**, tek bir yardımcı fonksiyonda (`core/rounding.dart`).
Satır toplamı yuvarlanmamış ara değerlerden **tek seferde** yuvarlanır — ara yuvarlama yapılmaz.

### 4.3 Dağıtım

Bir tutar birden çok satıra dağıtılırken (nakliye, kesim ücreti, tahsilat eşleştirme):

1. Her satırın payı anahtar (m³ veya tutar) oranında `Decimal` ile hesaplanır.
2. Her pay ROUND_HALF_UP ile kuruşa yuvarlanır.
3. Yuvarlanmış payların toplamı ile orijinal tutar arasındaki kuruş farkı **son satıra** eklenir.

**Değişmez:** `Σ dağıtılan = orijinal tutar`. Bu bir property testidir (rastgele tutar ve
ağırlıklarla doğrulanır).

### 4.4 KDV

- Belge başlığında `price_mode` = `EXCL` | `INCL`. Varsayılan Ayarlar'dan; müşteri kartında
  müşteriye özel varsayılan ezilebilir.
- Her satırda kendi KDV oranı (varsayılan %20; seçilebilir oranlar Ayarlar'da).
- `EXCL`: `net = yuvarla(miktar × birim fiyat × (1 − iskonto))`, `kdv = yuvarla(net × oran)`,
  `brüt = net + kdv`.
- `INCL`: girilen **brüt aynen korunur**.
  `kdv = yuvarla(brüt − brüt / (1 + oran))`, `net = brüt − kdv`.
  Doğrulama: 1.000,00 dahil %20 → kdv 166,67, net 833,33, toplam tam 1.000,00.
- Satırda net, KDV ve brüt **ayrı** saklanır.
- **Maliyet, kâr ve ciro her zaman KDV hariç.** Cari hesaplara **brüt** yazılır.
  Parti maliyeti her zaman KDV hariçtir. Fiyat listesi fiyatları KDV hariç saklanır.

### 4.5 Kâr

```
brüt kâr   = net satış (KDV hariç) − sabitlenmiş maliyet
kâr marjı  = brüt kâr / net satış          → %12,79
maliyet üzerine kâr = brüt kâr / maliyet   → %14,66
```

Yüzdeler saklanmaz, `Decimal` ile anlık hesaplanır ve gösterimde 2 haneye yuvarlanır.

---

## 5. Maliyet motoru

### 5.1 Parti (batch)

Her alış satırı, her açılış stok satırı ve her kesim dönüşü bir **parti** yaratır:
varyant, konum, tedarikçi, giriş tarihi, **çıplak** TL/m³, **gerçek (masraflı)** TL/m³,
giren adet/m³, kalan adet/m³. Çıplak fabrika fiyatı ve gerçek maliyet her zaman ayrı saklanır.

### 5.2 FIFO (varsayılan)

Aynı varyantın **ana depodaki** partileri `(received_at, id)` sırasıyla tüketilir.
Kesimdeki mal satılamaz, bu yüzden FIFO sırasına girmez.

### 5.3 Ağırlıklı ortalama

Çıkış anında, **ürün (çeşit) bazında**, ana depodaki tüm kalan partilerin gerçek TL/m³'ünün
m³ ağırlıklı ortalaması alınır. Fiziksel tüketim yine FIFO ile yapılır — yani hangi partinin
kalanı düştüğü değişmez, yalnızca yazılan birim maliyet değişir.

> Doğrulama (Altın Senaryo eki): (59.388 + 26.586) / 28 m³ = 3.070,5000 TL/m³.
> Payda 28 m³, Beyaz Sünger'in ana depodaki **tüm** varyantlarının kalanıdır — ortalamanın
> varyant değil ürün bazında olduğunu bu sayı doğrular.

### 5.4 Yöntem kilidi

Yöntem kurulumda seçilir. **İlk stok hareketinden sonra kilitlenir.** Değişiklik yalnızca
yeni bir dönem başlangıç tarihi verilerek ve audit kaydıyla yapılabilir; değişiklik öncesi
otomatik yedek alınır. Geçmiş dönemin maliyetleri yeniden hesaplanmaz.

### 5.5 Maliyetin sabitlenmesi

Her çıkışın parti bazlı maliyeti `cost_allocations`'a yazılır (append-only).
`sale_items.cost_total` satış anında sabitlenir ve **bir daha değişmez** — sonradan gelen
nakliye faturası, yeni fiyat listesi veya yöntem değişikliği geçmiş satışı etkilemez.

### 5.6 Masraf dağıtımı

Alışa nakliye, hamaliye ve diğer masraflar eklenir. Varsayılan anahtar **m³**, alternatif
**tutar**. Masraf KDV hariç tutarıyla maliyete girer.

**Sonradan gelen masraf** (fatura maldan günler sonra gelir, mal kısmen satılmış olabilir):

1. Masraf, partinin **toplam giriş m³**'üne bölünür → m³ başına ek maliyet.
2. Partinin **stokta kalan** m³'üne düşen pay → partinin `real_unit_cost_m3` değerine eklenir.
3. **Satılmış veya firelenmiş** m³'e düşen pay → `cost_adjustments`'a dönem maliyet farkı
   olarak yazılır. Geçmiş satış satırları değişmez, kârlılık raporunda ayrı satır olarak görünür.

### 5.7 Fason kesim maliyeti

Kaynak partinin maliyeti + kesim ücreti (KDV hariç) + nakliye, hedeflere **m³ oranında**
dağıtılır. Hedef toplam m³ kaynağı aşamaz (CHECK + domain kuralı). Aradaki fark **kesim
firesi**dir; ayrı bir maliyet yazılmaz, hedeflerin birim maliyetine yedirilir ve fire
raporunda miktarıyla "kesim firesi" olarak görünür.

> Doğrulama: 4 m³ kaynak (11.600,00) + 1.000,00 kesim ücreti = 12.600,00; hedef 3,6 m³
> → 3.500,0000 TL/m³. 140×200×10 (2,52 m³) → 8.820,00; 60×200×10 (1,08 m³) → 3.780,00.
> Kesim firesi 0,4 m³.

### 5.8 Negatif stok

İlk sürümde **yasak** (hem CHECK kısıtı hem domain kuralı). Stokta olmayan malın FIFO
maliyeti bilinemez, dolayısıyla o satışın kârı da bilinemez. Mal gelmeden satış gerekiyorsa
önce hızlı stok girişi yapılır.

---

## 6. Değiştirilemezlik (append-only)

Şu tablolara yalnızca **INSERT** yapılabilir:

`stock_movements`, `customer_ledger`, `supplier_ledger`, `account_movements`,
`instrument_events`, `cost_allocations`, `cost_adjustments`, `command_log`, `audit_logs`,
`payment_allocations`, `supplier_payment_allocations`, `backup_log`

Her biri için iki SQLite trigger'ı üretilir:

```sql
CREATE TRIGGER trg_<tablo>_no_update BEFORE UPDATE ON <tablo>
BEGIN SELECT RAISE(ABORT, 'append-only: <tablo>'); END;

CREATE TRIGGER trg_<tablo>_no_delete BEFORE DELETE ON <tablo>
BEGIN SELECT RAISE(ABORT, 'append-only: <tablo>'); END;
```

- Belge başlıklarında (`sales`, `purchases`, `collections`, …) yalnızca **durum alanları**
  (`status`, `cancelled_at`, `cancel_reason`) güncellenebilir; bu da trigger ile zorlanır
  (diğer kolonlardan biri değişirse ABORT).
- Hatalı kayıt silinmez; orijinale `reversal_of_id` ile referans veren **ters hareketle**
  iptal edilir. Bir hareket yalnızca bir kez ters çevrilebilir (benzersiz indeks).
- Stok ve cari bakiye **hareketlerden türetilir**. `inventory_batches.remaining_pieces` ve
  `remaining_volume` yalnızca **önbellektir** ve bu yüzden güncellenebilir.

### 6.1 checkIntegrity()

Parti kalanlarını ve cari bakiyeleri hareketlerden yeniden hesaplayıp saklanan değerlerle
karşılaştırır. Kontrol ettikleri:

| Kontrol | Karşılaştırma |
|---|---|
| Parti kalanı | `Σ cost_allocations` ve `Σ stock_movements` → `inventory_batches.remaining_*` |
| Varyant stoğu | `Σ stock_movements(pieces, volume)` → parti kalanları toplamı |
| Müşteri bakiyesi | `Σ customer_ledger.amount` → ekranda gösterilen bakiye |
| Tedarikçi bakiyesi | `Σ supplier_ledger.amount` |
| Kasa/banka bakiyesi | `Σ account_movements` |
| Evrak portföyü | `instrument_events` son durumları → portföy toplamı |
| Negatif kalan | hiçbir partide `remaining_* < 0` olmamalı |
| Yetim kayıt | FK bütünlüğü, ters kaydı olmayan iptal, iki kez ters çevrilmiş hareket |

Ayarlar'dan elle çalıştırılır; **her yedek yüklemesinden sonra otomatik** çalışır.
Fark bulursa rapor eder — kendiliğinden düzeltmez (düzeltme ters hareketle ve kullanıcı
onayıyla yapılır).

---

## 7. Transaction ve çift kayıt koruması

Her iş işlemi **tek bir Drift transaction**'ıdır. Herhangi bir adım başarısız olursa hiçbir
şey yazılmaz.

| İşlem | Aynı transaction içinde yazılanlar |
|---|---|
| Satış | belge + satırlar + stok hareketleri + maliyet dağıtımı + parti kalanları + müşteri carisi + (varsa) tahsilat, kasa hareketi, alınan evrak + audit |
| Alış | belge + satırlar + partiler + masraf dağıtımı + stok hareketleri + tedarikçi carisi + audit |
| İade / iptal / tahsilat / ödeme / evrak durumu / fire / sayım / kesim emri | aynı prensip |

**Çift kayıt (idempotency):** form açıldığında bir UUID v7 üretilir. İşlem, `command_log`'a
bu UUID **birincil anahtar** olacak şekilde, iş kayıtlarıyla **aynı transaction içinde**
yazılır. Aynı UUID ikinci kez gelirse (çift dokunma, geri tuşu, yeniden deneme) INSERT
birincil anahtar çakışmasıyla düşer ve işlem tekrarlanmaz; kullanıcıya ilk işlemin sonucu
gösterilir. Kaydet butonu işlem sürerken devre dışıdır.

> `command_log` append-only olduğu için "işleniyor" durumu tutulamaz. Kayıt transaction
> içinde yazıldığından **yalnızca başarıyla tamamlanmış** komutlar loglanır; başarısız işlem
> geri alınır ve UUID yeniden kullanılabilir. Gerekçe: `docs/DECISIONS.md` D-09.

---

## 8. Belge numaraları

Yıl bazlı, boşluksuz: `STS-2026-000123`. Ön ekler:

| Ön ek | Belge |
|---|---|
| `STS` | Satış |
| `ALS` | Alış |
| `THS` | Tahsilat |
| `TKL` | Teklif |
| `IAD` | İade (satış ve alış iadesi) |
| `KSM` | Kesim emri |
| `ODM` | Tedarikçi ödemesi |
| `SYM` | Stok sayımı |
| `FIR` | Fire |
| `VRM` | Virman |
| `GDR` | Gider |

Numara `document_sequences` tablosundan **aynı transaction içinde** atanır
(`UPDATE ... SET last_number = last_number + 1` → oku). İşlem geri alınırsa numara da geri
alınır, boşluk oluşmaz.

---

## 9. Güvenlik

- Veritabanı **SQLCipher** ile şifreli. Veritabanı anahtarı kurulumda rastgele üretilir ve
  `flutter_secure_storage` (Android Keystore destekli) içinde saklanır.
- Uygulama kilidi: PIN (zorunlu) + parmak izi (opsiyonel, `local_auth`).
- **Yedek şifresi veritabanı anahtarından bağımsızdır** — yedek başka bir telefonda yalnızca
  yedek şifresiyle açılabilmelidir. Ayrıntı `docs/BACKUP.md`.
- "Maliyeti gizle" modu: üst çubuktaki göz ikonu. Açıkken maliyet, kâr ve alış fiyatları
  ekranda gizlenir; kapatmak için PIN gerekir. v1'de bu bir **gösterim** kontrolüdür (tek
  kullanıcı, tek cihaz); ikinci kullanıcı eklendiğinde veri katmanında filtrelemeye dönüşür
  (`docs/FUTURE_SYNC.md`).
- Loglara şifre veya iş verisi yazılmaz.

---

## 10. Teknoloji

| Alan | Seçim |
|---|---|
| Uygulama | Flutter (Dart, null-safety), min Android 8 / API 26 |
| Durum yönetimi | Riverpod |
| Yönlendirme | go_router |
| Veritabanı | Drift (SQLite) + SQLCipher |
| Anahtar saklama | flutter_secure_storage |
| Ondalık | decimal |
| Kriptografi | cryptography (AES-256-GCM; anahtar türetme Argon2id, yoksa PBKDF2-HMAC-SHA256 ≥ 600.000 iterasyon) |
| Drive | google_sign_in + googleapis (`drive.file` kapsamı) |
| Dosya / paylaşım | file_picker, share_plus |
| Belge | pdf + printing (Türkçe karakterli gömülü font: Inter veya Noto Sans) |
| Excel | excel |
| Grafik | fl_chart |
| Kilit | local_auth |
| Arka plan | workmanager |
| QR (opsiyonel faz) | mobile_scanner |
| Kimlik | UUID v7 |

**Sürümler bu dokümanda yazılmaz.** Faz 1'in ilk adımı her paketin `pub.dev`'deki güncel
kararlı sürümünü, Android 8 ve mevcut Flutter sürümüyle uyumunu doğrulamak ve seçilen
sürümleri `docs/DECISIONS.md`'ye yazmaktır.

### 10.1 Yerelleştirme

`tr_TR`: tarih `dd.MM.yyyy`, saat 24 saat, sayı `1.234,56`. Girişte **hem virgül hem nokta**
ondalık ayırıcı kabul edilir (`3,5` = `3.5`). Saat dilimi `Europe/Istanbul`; tüm zaman
damgaları UTC epoch olarak saklanır, gösterimde yerel saate çevrilir.

### 10.2 Türkçe arama

Aranabilir her ad kolonunun yanında `*_normalized` kolonu tutulur: küçük harfe çevrilmiş ve
`İ/i`, `I/ı`, `ş/s`, `ğ/g`, `ü/u`, `ö/o`, `ç/c` eşlenmiş hali. Arama bu kolonda yapılır,
böylece "sunger" → "Sünger" bulur. Normalizasyon `domain/core/text_normalize.dart` içinde
tek yerde tanımlanır ve test edilir. Hacim büyürse (müşteri/ürün sayısı) FTS5 eklenir.

---

## 11. Migration

- Şema sürümü Drift `schemaVersion` ile yönetilir.
- Her sürüm için `drift_dev schema dump` ile anlık görüntü `drift_schemas/` altına alınır;
  üretilen doğrulama testleri `test/data/generated_migrations/` altında çalışır.
- **Her migration için test yazılır:** eski sürümden yeni sürüme geçiş, veri korunumu,
  trigger'ların yeniden kurulması.
- Migration öncesi **otomatik yedek** alınır; migration başarısız olursa o yedekten dönülür.
- `PRAGMA foreign_keys = ON` her bağlantıda açılır (Drift `beforeOpen`), migration sırasında
  geçici olarak kapatılır ve sonunda `PRAGMA foreign_key_check` ile doğrulanır.

---

## 12. Test stratejisi

| Katman | Araç | Kapsam |
|---|---|---|
| Domain | `test` (saf Dart, hızlı) | m³, yuvarlama, dağıtım (kuruş farkı), FIFO, ağırlıklı ortalama, kâr yüzdeleri, KDV EXCL/INCL, tahsilat eşleştirme, vade/gecikme, kesim maliyeti, evrak durum geçişleri |
| Veri | bellek içi Drift | transaction geri alma, append-only trigger'ları, iade sınırı, negatif stok engeli, çift gönderim (aynı UUID → tek kayıt), TypeConverter uç değerleri, migration'lar, `checkIntegrity` |
| Yedekleme | bellek içi + geçici dosya | `docs/BACKUP.md` Bölüm 8'deki zorunlu senaryolar |
| Altın Senaryo | Drift + domain | `docs/GOLDEN_SCENARIO.md` — kesin rakamlarla uçtan uca |
| Widget/E2E | `integration_test` | Kurulum sihirbazı, hızlı satış, stok girişi, tahsilat, yedek al, yedekten yükle |

Bir iş kuralı uygulanmadan **önce** testi yazılır. Altın Senaryo'daki bir rakam tutmazsa
test değiştirilmez; önce hesap kontrol edilir, test gerçekten hatalıysa gerekçe
`docs/DECISIONS.md`'ye yazılıp müşteriye sorulur.
