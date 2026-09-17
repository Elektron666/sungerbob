# Kararlar ve Gerekçeler

Her mimari karar, varsayım ve sapma burada gerekçesiyle kayıtlıdır.
Kaynak otorite sırası: `docs/BRIEF.md` → `docs/SPEC.md` → bu dosya.

Durum etiketleri: **Kesin** (müşteri kararı) · **Karar** (geliştirme kararı) ·
**Varsayım** (doğrulanmayı bekliyor).

---

## SABAH KONTROL

> Gece otonom çalışma sırasında karar gerektiren belirsizliklerde en makul seçenek uygulandı.
> Bu başlık altındakiler **onayına sunulur**; itiraz edersen ilgili karar tek tek geri alınabilir.

### SK-01 · Android SDK bu ortamda kurulamadı (Flutter kuruldu) — **✅ ÇÖZÜLDÜ**

- **Durum:** Flutter **3.47.4** (Dart **3.13.3**) `/opt/sdk/flutter` altına kuruldu ve
  çalışıyor. `flutter doctor` çıktısı aşağıda (K-01).
- **Sorun:** Android SDK `dl.google.com` üzerinden dağıtılıyor ve bu ortamın ağ politikası
  o adrese **403** veriyor (`storage.googleapis.com` açık olduğu için Flutter inebildi).
  Doğrulama: `curl "$HTTPS_PROXY/__agentproxy/status"` → `connect_rejected`, `dl.google.com:443`.
- **Uygulanan seçenek:** Faz 1 zaten arayüzsüzdür; domain ve veri katmanı testleri Dart VM'de
  koşar, Android SDK **gerektirmez**. Faz 1 bu haliyle tamamlandı.
- **Sonuç:** APK derlemesi ek karar #2'deki **GitHub Actions** ile yapılacak (runner'da
  Android SDK hazır gelir). Yerel APK derlemesi bu ortamda mümkün değil.
- **Çözüm uygulandı:** `.github/workflows/ci.yml` her push'ta testleri çalıştırıyor ve
  debug APK'yı 30 gün saklanan indirilebilir artifact olarak yüklüyor;
  `.github/workflows/release.yml` imzalı yayın APK'sını üretiyor.
- **Senin yapman gereken:** Bir şey yok. Yerelde de APK derlemek istersen ağ politikasına
  `dl.google.com` eklenmeli.

### SK-02 · `purchase_orders` tablosu v1 kapsamına alınmadı

SPEC §26 minimum tablolar arasında `purchase_orders` (satın alma siparişi) sayıyor, ancak
ne SPEC'in akış bölümlerinde ne de BRIEF'te sipariş süreci tarif edilmiyor; BRIEF §5'in
kapsam dışı listesi de siparişi kapsama almıyor. Boş bir tablo yaratmak yerine kapsam dışı
bırakıldı (D-16). Sipariş takibi istiyorsan ayrıca söyle — veri modeli engellemiyor.

### SK-03 · Fire tablosu `stock_adjustments` olarak adlandırıldı

BRIEF §6 fire için tablo adı vermiyor; SPEC §26 `stock_adjustments`, SPEC §17 ise
"Stok Düzeltme / Fire" ekranı diyor. İkisini tek tabloda birleştirdim
(`stock_adjustments` + `stock_adjustment_items`), sayım ise BRIEF'in istediği gibi ayrı
(`stock_counts`). Alternatif olan `waste_records` adı SPEC'te geçmediği için terk edildi.

### SK-04 · Teklif tablosu `sales_quotes` olarak adlandırıldı

SPEC §26 `sales_quotes` diyor; taslakta `quotes` idi. SPEC adlandırması korundu
(`sales_quotes`, `sales_quote_items`).

### SK-05 · Ürün ve müşteri kartına SPEC alanları eklendi

SPEC §1 `products` için DNS, sünger tipi, standart kalınlıklar, varsayılan satış fiyatı ve
minimum stok istiyor; SPEC §9 `customers` için **Yetkili** istiyor. Bunlar ilk taslakta
yoktu, eklendi (`dns`, `foam_type`, `standard_thicknesses`, `default_sale_price_m3`,
`min_stock_volume`, `contact_person`).

### SK-06 · Altın Senaryo adım 5'te aritmetik uyuşmazlık — adet 10 → **5** düzeltildi

BRIEF §8 adım 5 ve adım 7 şunu diyor: **"140×200×8 × 10 adet = 1,12 m³"**.
Geometri bunu vermiyor:

```
1,40 m × 2,00 m × 0,08 m × 10 adet = 2,24 m³   (1,12 değil)
1,40 m × 2,00 m × 0,08 m ×  5 adet = 1,12 m³   ✔
1,40 m × 2,00 m × 0,04 m × 10 adet = 1,12 m³   ✔
```

Üç sayıdan (kalınlık 8, adet 10, hacim 1,12) ancak ikisi aynı anda doğru olabilir.

**1,12 m³ üç bağımsız türetilmiş rakamla doğrulanıyor:**

| Kontrol | Hesap | BRIEF'teki değer |
|---|---|---|
| Adım 5 tutarı | 1,12 × 3.300 | **3.696,00** ✔ |
| Adım 7 toplam m³ | 5,32 + 5,32 + 1,12 | **11,76** ✔ |
| Adım 7 toplam maliyet | 16.837,80 + 16.119,60 + 3.696,00 | **36.653,40** ✔ |

Kalınlık 8 cm + 10 adet kabul edilseydi bu **üç toplam birden** bozulurdu. Dolayısıyla hatalı
olan ya kalınlık ya adettir.

**Seçim: adet 10 → 5.** Gerekçe: SPEC §2'nin örnek kalınlık kümesi **{5, 8, 10} cm**;
4 cm ne SPEC'te ne BRIEF'te hiçbir yerde geçmiyor, 8 cm ise işletmenin standart ölçüsü.
Adet hiçbir para hesabına girmediği için bu düzeltmenin başka hiçbir rakama etkisi yok.

**Etki:** Yok. 1,12 m³ · 3.696,00 TL · 11,76 m³ · 36.653,40 TL değerlerinin hepsi korunur.
Yalnızca adım 5 ve adım 7'deki "10 adet" ifadesi "5 adet" olur.

**Senin yapman gereken:** Onayla ya da düzelt. Eğer asıl niyet "140×200×**4** × 10 adet" idiyse
söyle — o durumda yalnızca varyant etiketi değişir, rakamlar yine aynı kalır.

### SK-07 · SQLCipher paketleri değişti — şifreleme Faz 2'ye kaldı

`sqlite3_flutter_libs` ve `sqlcipher_flutter_libs` **artık kullanılmıyor**
(pub.dev'de `0.6.0+eol` / `0.7.0+eol`, açıklama: *"Not used anymore, update to version 3.x
of package:sqlite3 instead"*). Yerlerini `sqlite3` 3.x aldı; SQLCipher artık paketin
**build-hook** ayarıyla devreye giriyor.

**✅ Faz 2'de çözüldü.** `pubspec.yaml`'a eklenen

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlcipher
```

ile SQLCipher **4.19.0 community** devreye girdi (SQLite 3.53.4). Doğrulaması
`test/data/encryption_test.dart`'ta: `PRAGMA cipher_version` dolu dönüyor, dosya anahtarsız
ve yanlış anahtarla açılamıyor, ham baytlarında `SQLite format 3` başlığı görünmüyor.

Alternatif olarak `source: sqlite3mc` (SQLite3MultipleCiphers) da vardı; BRIEF §2 doğrudan
"SQLCipher" dediği için o seçildi. sqlite3mc daha güncel bir SQLite taşıyor, ileride
gerekirse tek satırlık bir değişiklik.

Veritabanı anahtarı `flutter_secure_storage` v11 ile saklanıyor (varsayılanı zaten
Android Keystore destekli AES-GCM + RSA OAEP; v11'de `encryptedSharedPreferences`
parametresi kaldırılmış). Yedek dosyasının şifrelemesi bu anahtardan **bağımsızdır**
(D-13), bu yüzden telefon kaybolsa bile yedek açılabilir.

### SK-08 · Faz 1'de doğrulanan paket sürümleri

Ezberden yazılmadı, pub.dev'den doğrulandı (BRIEF §0):

| Paket | Sürüm |
|---|---|
| Flutter / Dart | 3.47.4 / 3.13.3 |
| decimal | ^3.2.6 |
| drift / drift_dev | ^2.35.0 |
| sqlite3 | ^3.6.0 |
| uuid | ^4.6.0 (v7 desteği doğrulandı) |
| build_runner | ^2.16.1 |
| crypto / path / collection / meta | ^3.0.7 / ^1.9.1 / ^1.19.1 / ^1.17.0 |

Riverpod, go_router, cryptography, googleapis, pdf, excel, fl_chart, local_auth,
workmanager ve flutter_secure_storage **henüz eklenmedi** — Faz 2 ve sonrasının işi.
Kullanılmayan bağımlılık eklemek yerine sırası gelince sürümü yeniden doğrulanacak.

### SK-09 · Faz 1'de testin yakaladığı iki hata (düzeltildi, bilgi amaçlı)

1. **`checkIntegrity` evrak zincirini yanlış sıralıyordu.** Zincirin sonu `occurred_at`'e
   göre okunuyordu; vadesi ileri tarihli bir çek bugün karşılıksız çıkınca "son durum"
   yanlış bulunuyordu. Zincirin sırası **kayıt sırasıdır** — `created_at` + UUID v7 id ile
   düzeltildi. Altın Senaryo adım 10 bunu yakaladı.
2. **Fiyat katsayısı 100 katına çıkıyordu.** `Rate.fraction` zaten çarpanı veriyor
   (10000 → 1,0); formülde fazladan `×100` vardı. Fiyat listesi testi yakaladı.

Her ikisi de kural gereği **önce yazılan testler** sayesinde koda değil teste düştü.

### SK-10 · Excel yerine CSV — paket çakışması

SPEC §25 "Excel ve PDF dışa aktarımı desteklensin" diyor. `excel` paketi
eklenemedi çünkü iki ayrı çakışma var:

```
excel 4.0.6  →  archive ^3.6.1   ama yedekleme archive ^4.x kullanıyor
excel 4.0.6  →  xml >=5.0.0 <7   ama pdf ^3.13.0 xml ^7.0.1 istiyor
```

`pdf` BRIEF §5'te açıkça isteniyor (teklif, sevk fişi, cari ekstre, kesim emri)
ve önceliklidir. Bu yüzden **Excel yerine CSV** seçildi:

- Excel `.csv` dosyalarını doğrudan açar — muhasebeciye göndermek için yeterli.
- Türkçe Excel ayraç olarak **noktalı virgül** bekler (virgül ondalık ayırıcı
  olduğu için alan ayracı olamaz); `CsvExport.separator` bu yüzden `;`.
- Dosya **UTF-8 BOM** ile başlar, yoksa Excel Türkçe karakterleri bozuk gösterir.

`archive` ayrıca `^4.0.9`'a sabitlendi (`pdf` `<4.1.0` istiyor). Yedekleme
testlerinin tamamı bu sürümle de geçiyor.

**Senin yapman gereken:** Gerçek `.xlsx` şartsa söyle; `syncfusion_flutter_xlsio`
gibi bağımsız bir paketle eklenebilir, ama lisans koşullarına bakmak gerekir.

### SK-11 · PDF için gömülü Noto Sans

BRIEF §2 "Türkçe karakter destekli gömülü font: Inter veya Noto Sans" diyor —
bu bir tercih değil, zorunluluk: `pdf` paketinin varsayılan Helvetica'sı
**ş, ğ, İ, ı karakterlerini basmıyor** (test çalıştırırken
`Unable to find a font to draw "ş"` uyarısı veriyordu).

`assets/fonts/` altına **Noto Sans Regular ve Bold** (toplam ~1,1 MB) gömüldü ve
`main()` içinde yükleniyor. Test de fontun yüklü olduğunu doğruluyor.

---

## K-01 · Ortam kaydı

```
Flutter 3.47.4 • channel stable
Framework revision 9584c6713b (2026-09-10) • Engine 06a2e2a110
Tools • Dart 3.13.3 • DevTools 2.60.0

[✓] Flutter (Channel stable, 3.47.4, on Ubuntu 24.04.4 LTS, locale en_US)
[✗] Android toolchain — Unable to locate Android SDK   (SK-01: dl.google.com ağ politikasıyla engelli)
[✗] Chrome — web hedefi kullanılmıyor, önemsiz
[✗] Linux toolchain — GTK3 dev kütüphaneleri yok, Android hedefi için önemsiz
[✓] Connected device (1 available) • Linux (desktop)
[✓] Network resources
```

---

## Kullanıcının ek kararları

### D-K1 · SDK kurulumu (ek karar #1) — **Kesim**
Faz 1'e başlamadan Flutter ve Android SDK kurulacak, `flutter doctor` gösterilecekti.
Flutter kuruldu ve doğrulandı (K-01). Android SDK kurulamadı; gerekçe ve etkisi **SK-01**'de.

### D-K2 · APK derlemesi GitHub Actions ile (ek karar #2) — **Kesim**
Faz 2'de eklenecek workflow: her push'ta testleri çalıştırır ve debug APK'yı indirilebilir
**artifact** olarak yükler. **Release imzalama anahtarı yalnızca GitHub Secrets'ta durur,
asla repoya girmez.** Bu karar SK-01'i de çözer: derleme, Android SDK'sı hazır gelen
runner'da yapılır.
> Faz 2 işi olduğu için bu fazda workflow **yazılmadı**; `.gitignore` tarafı şimdiden hazır (D-K3).

### D-K3 · `.gitignore` (ek karar #3) — **Kesim**
`*.jks`, `*.keystore`, `key.properties`, `.env`, `google-services.json`, `*.sbk` depoya
girmez. `.sbk` özellikle kritik: yedek dosyası tüm işletme verisidir, halka açık bir depoda
asla bulunmamalıdır.

---

## SPEC ile BRIEF arasındaki çelişkiler

BRIEF çelişkide üstündür (BRIEF girişi). Sapmalar:

### D-01 · Platform: web değil, Android APK — **Kesin**
SPEC "mobil uyumlu web uygulaması, masaüstü + iPhone" diyor. Müşteri kararı: tek kullanıcılı,
sunucusuz, offline **Android APK**. Kod ileride iOS/Windows derlemesini engellemeyecek
şekilde yazılır (`domain` saf Dart, platform API'leri arayüz arkasında).

### D-02 · Para tipi: DECIMAL değil, sabit ölçekli INTEGER — **Karar**
SPEC §26 "para için FLOAT kullanma, DECIMAL/NUMERIC kullan" diyor. Ancak hedef veritabanı
**SQLite** ve SQLite'ta gerçek bir ondalık tip yoktur: `NUMERIC`/`DECIMAL` kolonları
saklama sınıfı olarak `REAL`'e (IEEE-754 double) düşebilir. Bu, SPEC §30.8'in
("para hesaplamalarında floating-point hatası olmamalı") tam tersini üretirdi.

Bu yüzden her sayısal değer **sabit ölçekli tamsayı** olarak saklanır (para ×100, birim
fiyat ×10.000, m³ ×10⁶, ölçü ×100, oran ×100) ve Dart'ta `Decimal` ile işlenir. Böylece
SPEC'in **amacı** (kuruş hatası olmasın) daha güçlü biçimde sağlanır. SQL'de yalnızca
toplama/çıkarma yapılır; çarpma/bölme Dart'a taşınır.

### D-03 · Yetkilendirme: v1'de tek kullanıcı — **Kesin**
SPEC §23 YÖNETİCİ/PERSONEL yetkilendirmesi istiyor. Müşteri kararı v1'de tek kullanıcı
(Patron). `users`, `roles`, `permissions` tabloları **şimdiden var**, tek `ADMIN` kullanıcı
seed'lenir, yönetim arayüzü gizlidir. SPEC §23'teki yetki listesi `permissions` tablosuna
kod olarak girilir ki ikinci kullanıcı eklendiğinde şema değişmesin.

### D-04 · "Maliyeti gizle" v1'de gösterim kontrolüdür — **Karar**
SPEC §23 ve ANALİZ §2.13 "personel maliyeti göremiyorsa veri hiç gönderilmemeli" diyor. Bu
doğru kural **sunucu-istemci** mimarisi içindir. v1'de sunucu yok, tek cihaz ve tek kullanıcı
var; veri zaten kullanıcının kendi cihazında ve kendi şifresiyle duruyor. Bu yüzden
"maliyeti gizle" bir **gösterim** modudur (telefonu müşteriye gösterirken), güvenlik sınırı
değildir. İkinci kullanıcı eklendiğinde veri katmanı filtresine dönüşür — `docs/FUTURE_SYNC.md`.

### D-05 · Eşzamanlı satış kilidi gerekmiyor — **Karar**
ANALİZ §2.11 iki personelin aynı anda son 5 plakayı satmasına karşı satır kilidi istiyor.
v1 tek kullanıcı ve tek cihaz olduğu için eşzamanlılık yok; Drift transaction'ı (tek yazar)
yeterli. İkinci kullanıcı/sunucu geldiğinde bu yeniden gündeme gelir (FUTURE_SYNC).

### D-06 · Excel'den içe aktarma yok — **Kesin**
ANALİZ §3 öneriyor, BRIEF §1.11 kapsam dışı bırakıyor: veriler elle girilir, bunun yerine
**açılış ekranları** zorunludur (stok, cari, kasa/banka, portföydeki evrak).

---

## Mimari kararlar

### D-07 · Kesimdeki mal ayrı konum, ayrı parti — **Karar**
`KESIMDE` sanal bir `location`'dır ve `is_sellable = false` taşır. Mal kesime giderken ana
depodaki parti **silinmez**: kalanı düşülür, aynı birim maliyeti taşıyan bir **çocuk parti**
(`parent_batch_id`) `KESIMDE` konumunda açılır.
**Neden:** (a) satılamaz olması tek bir kolondan zorlanır, (b) kesimdeki malın değeri stok
değerinde ayrıca görünür, (c) maliyet zinciri parti soyağacından izlenebilir kalır.

### D-08 · Kesim hedefleri kaynağın tarihini taşır — **Karar (BRIEF §5.4)**
Hedef partilerin `received_at` değeri kaynak partininkidir. Aksi halde kesimden dönen mal
FIFO kuyruğunun **sonuna** düşer ve daha yeni alınmış mal ondan önce satılır — kesim, malın
yaşını değiştirmez.

### D-09 · `command_log` işlemle aynı transaction'da yazılır — **Karar**
`command_log` append-only olduğu için "işleniyor → başarılı" gibi bir durum güncellemesi
yapılamaz. Bu yüzden kayıt, iş kayıtlarıyla **aynı transaction içinde** yazılır:
- İşlem başarılıysa komut loglanmış olur.
- İşlem başarısızsa log da geri alınır, aynı UUID yeniden denenebilir.
- Aynı UUID ikinci kez gelirse birincil anahtar çakışır → çift kayıt engellenir.

**Alternatif ve neden seçilmedi:** komutu önce `PENDING` yazıp sonra güncellemek append-only
kuralını delerdi ve yarıda kalan işlemler "hayalet komut" bırakırdı.

### D-10 · Bakiye kolonu tutulmaz, hareketlerden toplanır — **Karar**
`customers.balance` gibi bir önbellek kolonu **yoktur**; bakiye `SUM(customer_ledger.amount)`
ile bulunur. Tamsayı toplaması olduğu için kesindir ve sessiz bozulma üretmez. Tek önbellek
`inventory_batches.remaining_*`'tır (FIFO taraması her seferinde tüm geçmişi okumasın diye)
ve `checkIntegrity()` bunu hareketlerle karşılaştırır.

### D-11 · Ağırlıklı ortalama ürün (çeşit) bazındadır — **Karar (BRIEF §3.6)**
Varyant bazında değil. Altın Senaryo eki bunu doğruluyor: (59.388 + 26.586) / **28 m³**
= 3.070,50 TL/m³ — paydadaki 28 m³, Beyaz Sünger'in ana depodaki *tüm* varyantlarının
kalanıdır (19,6 + 8,4). Varyant bazlı olsaydı payda 22,4 m³ olurdu.

### D-12 · İade, tüketimin tersinden döner — **Karar (BRIEF §5)**
Satış iadesinde mal, orijinal satışın tükettiği partilere `cost_allocations.sequence_no`
**tersinden** (son tüketilenden başlayarak) döner. Altın Senaryo 8 bunu doğruluyor: satış
A'dan 50 + B'den 10 tüketmişti; 5 adetlik iade **B**'ye 3.165 TL/m³ ile döner.

### D-13 · Yedek şifresi cihaz anahtarından bağımsızdır — **Karar (BRIEF §4.1)**
Yedeğin içindeki veritabanı anlık görüntüsü **SQLCipher şifresiz** alınır, dosyanın tamamı
yedek şifresinden türetilen anahtarla AES-256-GCM ile şifrelenir.
**Neden:** SQLCipher anahtarı Android Keystore'da durur ve telefon kaybolduğunda o anahtar
da kaybolur. Yedek ona bağlı olsaydı, yedek dosyası elde olsa bile açılamazdı — yani
yedeklemenin tek amacı boşa çıkardı. Şifresiz anlık görüntü diskte kalmaz (`docs/BACKUP.md` §1.2).

### D-14 · Geri yükleme atomik dosya değişimiyle yapılır — **Karar**
Yeni veritabanı geçici dosyaya açılır, migration ve `checkIntegrity()` **geçici dosyada**
çalışır, ancak hepsi başarılıysa `rename()` ile yerine konur. Herhangi bir adımda hata
olursa mevcut `app.db` dosyasına hiç dokunulmamış olur. Öncesinde güvenlik yedeği alınır.

### D-15 · Belge numarası transaction içinde atanır — **Karar**
`document_sequences` üzerinden aynı transaction'da artırılır; işlem geri alınırsa numara da
geri alınır. Böylece SPEC'in istediği **boşluksuz** numaralandırma sağlanır.

### D-16 · `purchase_orders` kapsam dışı — **Karar** → bkz. **SK-02**

### D-17 · Enum'lar veritabanında TEXT — **Karar**
Tamsayı kod yerine okunabilir metin (`'PURCHASE_IN'`) saklanır, `CHECK (col IN (...))` ile
kısıtlanır. **Neden:** yedek dosyası ileride elle incelenebilir olmalı; tamsayı kodlar
şema bilgisi olmadan anlamsızdır. Maliyeti ihmal edilebilir.

### D-18 · Türkçe arama için normalize kolon — **Karar (BRIEF §6)**
Aranabilir her ad kolonunun yanında `*_normalized` kolonu tutulur (İ/i, I/ı, ş/s, ğ/g, ü/u,
ö/o, ç/c eşlenmiş, küçük harfli). SQLite'ın `LIKE`'ı Türkçe harfleri doğru katlamaz.
FTS5'e veri büyüyene kadar gerek yok.

### D-19 · `double` yasağı iki katmanlı zorlanır — **Karar (BRIEF §2)**
(a) `custom_lint` kuralı, (b) `lib/domain` ve `lib/data` kaynaklarını tarayan bir test.
Tek başına lint yeterli değil çünkü lint kuralları CI'da sessizce atlanabilir; test
`flutter test` ile her koşuda çalışır.

---

## Varsayımlar (doğrulanmayı bekliyor)

### V-01 · `D35 140×240` ve `HR35 140×240` katsayıları kopya
SPEC §13'te bu iki ürünün katsayısı, `D35 Sert/Yumuşak` (2,24) ve `HR35` (2,56) ile
birebir aynı. Müşteri bunları **ayrı ürün** olarak istedi (BRIEF §1.6), o yüzden aynen
seed'leniyor. Katsayıların farklılaşması gerekiyorsa fiyat listesi versiyonundan
düzeltilebilir.

### V-02 · KDV oranı varsayılanı %20
BRIEF §3.4 varsayılanı %20 veriyor, seçilebilir oranlar Ayarlar'da. Seed'lenen oran
listesi: %0, %1, %10, %20.

### V-03 · Açılış partisi tedarikçisi boş bırakılabilir
Açılış stoğu girilirken malın hangi tedarikçiden geldiği bilinmeyebilir;
`inventory_batches.supplier_id` bu durumda `NULL` olur ve `source_type = OPENING` taşır.
