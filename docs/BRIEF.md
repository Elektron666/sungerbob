# GÖREV

Kıdemli bir mobil mühendis olarak, Türkiye'de toptan sünger alım-satımı yapan bir işletme için **gerçek ticari kullanımda çalışacak**, **tamamen cihaz üzerinde çalışan bir Android uygulaması (APK)** geliştireceksin. Uygulama stok, satış, cari, çek/senet ve kârlılık yönetimi yapar. Demo değil, her gün kullanılacak üretim yazılımı.

Müşterinin tam spesifikasyonu `docs/SPEC.md` dosyasında. Bu prompt o dokümanı tamamlar ve müşteriyle netleşen kararları içerir. **Bu prompt ile SPEC.md çelişirse bu prompt geçerlidir.** Özellikle: SPEC "web uygulaması, veritabanı sunucusu, çok kullanıcı" diyor; müşteri kararı **tek kullanıcılı, sunucusuz, offline Android APK**'dır.

---

## 0. ÇALIŞMA KURALLARI

- Plan modunda başla. Kod yazmadan önce `docs/SPEC.md`'yi ve bu promptu tamamen oku.
- Proje köküne `CLAUDE.md` oluştur: komutlar, klasör yapısı, iş kurallarının kısa özeti, test çalıştırma.
- İş fazlara bölünmüştür (Bölüm 9). **Her faz sonunda dur:** testler geçiyor, `flutter analyze` temiz, migration'lar sıfırdan çalışıyor olmalı. Kısa bir özet yaz ve onayımı bekle.
- Her varsayımı ve mimari kararı `docs/DECISIONS.md` dosyasına gerekçesiyle yaz.
- Mock veriyle doldurulmuş ekran yok. Test/demo verisi yalnızca geliştirici menüsünden yüklenir.
- Arayüz metinleri Türkçe. Kod, tablo, kolon ve değişken adları İngilizce.
- Bir iş kuralını uygulamadan önce testini yaz (özellikle maliyet, stok, cari ve yedekleme).
- Paket sürümlerini ezbere yazma; güncel kararlı sürümleri kontrol et.

---

## 1. MÜŞTERİ KARARLARI (KESİN)

1. **Platform:** Android APK. Web sitesi yok. Kod ileride iOS ve Windows derlemesine engel olmamalı.
2. **Sunucu yok (v1):** Tüm veri telefonda, şifreli yerel veritabanında durur. Uygulama internet olmadan tam çalışır. İnternet yalnızca Google Drive yedeği ve paylaşım için kullanılır.
3. **Tek kullanıcı (v1):** Kurulumda tek bir kullanıcı (Patron) tanımlanır. Veri modeli ileride ikinci kullanıcı (Muhasebeci), yetkiler ve sunucu senkronizasyonu eklenebilecek şekilde tasarlanır (Bölüm 3.12), ancak bu özellikler şimdi yapılmaz.
4. **Tek tuşla yedek alma ve yedekten yükleme** zorunludur (Bölüm 4).
5. **Depo:** Tek depo, ek olarak kesime gönderilen mal için sanal "Kesimde" konumu (Bölüm 5).
6. **Ürünler:** "D35 140×240" ve "HR35 140×240" **ayrı ürünlerdir**; SPEC'teki 12 ürün katsayılarıyla aynen seed'lenir. Bu iki ürünün kartında standart en/boy 140×240 gelir.
7. **Kesim:** İşletme blok alır ve özel ölçü satar. **Kesim işletme dışında (fason kesimhanede) yapılır.** Kesim Emri akışı zorunludur.
8. **KDV:** Her belgede fiyat giriş modu **KDV Hariç / KDV Dahil** seçilebilir.
9. **e-Fatura / e-İrsaliye:** Kapsam dışı. Yalnızca opsiyonel "fatura no" ve "irsaliye no" metin alanları.
10. **Çek ve senet:** Aktif kullanılıyor; alınan ve verilen evrak takibi çekirdek kapsamdadır.
11. **Geçmiş veri:** İçe aktarma yok, veriler elle girilecek. Açılış stoğu, açılış cari bakiyeleri, açılış kasa/banka bakiyeleri ve portföydeki mevcut evrak için giriş ekranları zorunludur.

---

## 2. TEKNOLOJİ

- **Flutter** (Dart, null-safety), minimum Android 8 (API 26)
- Mimari: `domain` (saf Dart iş kuralları, Flutter bağımlılığı yok) · `data` (Drift, repository'ler) · `ui` katmanları. Durum yönetimi **Riverpod**, yönlendirme **go_router**.
- Yerel veritabanı **Drift (SQLite)**, **SQLCipher** ile şifreli. Veritabanı anahtarı **flutter_secure_storage**'da.
- **decimal** paketi: para ve m³ hesabında `double` kullanmak YASAK. Bunu kontrol eden özel bir lint kuralı veya test ekle.
- Kriptografi (yedek şifreleme): **cryptography** paketi (AES-256-GCM, anahtar türetme Argon2id; desteklenmiyorsa PBKDF2-HMAC-SHA256, en az 600.000 iterasyon).
- Google Drive yedeği: **google_sign_in** + **googleapis** (Drive API, `drive.file` kapsamı). Dosya seçimi: **file_picker**. Paylaşım: **share_plus**.
- PDF: **pdf + printing** (Türkçe karakter destekli gömülü font: Inter veya Noto Sans). Excel dışa aktarma: **excel**. Grafikler: **fl_chart**.
- Uygulama kilidi: **local_auth** (parmak izi) + PIN.
- Arka plan görevi (otomatik yedek): **workmanager**.
- QR (opsiyonel faz): **mobile_scanner**.
- Yerelleştirme `tr_TR`: tarih `dd.MM.yyyy`, sayı `1.234,56`. Girişlerde virgül ve nokta ondalık ayırıcı kabul edilir. Saat dilimi `Europe/Istanbul`.

---

## 3. DEĞİŞMEZ MİMARİ KARARLAR

**3.1 Ürün ve varyant.** `products` = sünger çeşidi (fiyat katsayısı burada). `product_variants` = en × boy × kalınlık, `kind` = `PLAKA` veya `BLOK`. Bloklar da stoklanır, kesime gönderilir ve istenirse doğrudan m³ olarak satılabilir.

**3.2 Sayısal saklama (SQLite'a özel, kritik).** SQLite'ta kesin ondalık tipi yoktur; `NUMERIC`/`REAL` kolonları kayan noktaya dönüşebilir. Bu yüzden **tüm sayısal değerler sabit ölçekli tamsayı (INTEGER) olarak saklanır** ve Drift `TypeConverter` ile `Decimal`'e çevrilir:
- Para: kuruş (×100)
- Birim fiyatlar (TL/m³, TL/plaka): ×10.000
- m³: ×1.000.000
- Ölçüler (cm, kalınlık 2,5 olabilir): ×100
- Oranlar (%): ×100
- Adet: tamsayı

SQL içinde yalnızca toplama/çıkarma yapılabilir (tamsayı olduğu için kesin). Çarpma, bölme ve oran hesapları Dart'ta `Decimal` ile yapılır. Tüm bunlar tek bir `money.dart` / `quantity.dart` modülünde toplanır.

**3.3 Hesap kuralları.**
- m³ = (en/100) × (boy/100) × (kalınlık/100) × adet.
- Yuvarlama `ROUND_HALF_UP`, tek bir yardımcı fonksiyonda. Satır toplamı yuvarlanmamış ara değerlerden tek seferde yuvarlanır.
- Bir tutar birden çok satıra dağıtılırken kuruş farkı son satıra eklenir; dağıtım toplamı her zaman orijinal tutara eşittir.

**3.4 KDV.**
- Belge başlığında `price_mode` = `EXCL` veya `INCL`. Varsayılan Ayarlar'dan gelir; müşteri kartında müşteriye özel varsayılan seçilebilir.
- Her satırda KDV oranı bulunur (varsayılan %20; seçilebilir oranlar Ayarlar'da).
- `INCL` modunda girilen KDV dahil satır toplamı **aynen korunur**: `KDV = yuvarla(toplam − toplam / (1 + oran))`, `net = toplam − KDV`.
- Her satırda net, KDV ve brüt tutar ayrı saklanır.
- Maliyet, kâr ve ciro **her zaman KDV hariç** hesaplanır. Cari hesaplara brüt tutar yazılır. Parti maliyeti her zaman KDV hariçtir.
- Fiyat listesi fiyatları KDV hariç saklanır; ekranlarda seçili moda göre gösterilir.

**3.5 Değiştirilemez kayıtlar.**
- `stock_movements`, `customer_ledger`, `supplier_ledger`, `account_movements`, `instrument_events`, `cost_allocations`, `command_log` ve `audit_logs` **append-only**'dir. SQLite trigger'ları ile (`BEFORE UPDATE/DELETE ... RAISE(ABORT)`) UPDATE ve DELETE engellenir.
- Belge başlıklarında yalnızca durum alanları (`status`, `cancelled_at`, `cancel_reason`) güncellenebilir.
- Hatalı kayıt, orijinale referans veren **ters hareketlerle** iptal edilir (`reversal_of_id`).
- Stok ve cari bakiye hareketlerden türetilir. `inventory_batches.remaining_*` önbellektir.
- `checkIntegrity()` servisi parti kalanlarını ve cari bakiyeleri hareketlerden yeniden hesaplayıp karşılaştırır. Ayarlar'dan çalıştırılabilir; her yedek yüklemesinden sonra otomatik çalışır.

**3.6 Maliyet motoru (`domain/costing`, saf Dart).**
- Her alış satırı bir **parti** (`inventory_batches`) oluşturur: varyant, konum, tedarikçi, giriş tarihi, çıplak TL/m³, gerçek (masraflı) TL/m³, giren/kalan adet ve m³.
- **FIFO (varsayılan):** Aynı varyantın ana depodaki partileri `(received_at, id)` sırasıyla tüketilir.
- **Ağırlıklı Ortalama:** Çıkış anında ürün (çeşit) bazında, ana depodaki tüm kalan partilerin ağırlıklı ortalama gerçek TL/m³'ü. Fiziksel olarak partiler yine FIFO ile düşülür.
- Yöntem ilk stok hareketinden sonra **kilitlenir**; değişiklik yalnızca yeni dönem başlangıç tarihiyle ve audit kaydıyla yapılabilir.
- Her çıkışın parti bazlı maliyeti `cost_allocations`'a yazılır. `sale_items.cost_total` satış anında sabitlenir ve bir daha değişmez.

**3.7 Masraf dağıtımı.**
- Alışa nakliye, hamaliye ve diğer masraflar eklenebilir. Varsayılan anahtar m³, alternatif tutar.
- Masraf **sonradan** da eklenebilir: partinin toplam giriş m³'üne göre bölünür. Stokta kalan kısma düşen pay partinin birim maliyetine eklenir; satılmış veya firelenmiş kısma düşen pay `cost_adjustments`'a maliyet farkı olarak yazılır. Geçmiş satış satırları değişmez.
- Çıplak fabrika fiyatı ve gerçek maliyet her zaman ayrı saklanır.

**3.8 Negatif stok.** İlk sürümde **yasak**. Gerekçe DECISIONS.md'ye: stokta olmayan malın FIFO maliyeti bilinmez.

**3.9 Transaction ve çift kayıt koruması.**
- Her iş işlemi tek bir Drift transaction'ıdır; herhangi bir adım başarısız olursa hiçbir şey yazılmaz.
  - Satış: belge + satırlar + stok hareketleri + maliyet dağıtımı + parti kalanları + müşteri carisi + (varsa) tahsilat, kasa hareketi, alınan evrak + audit.
  - Alış: belge + satırlar + partiler + masraf dağıtımı + stok hareketleri + tedarikçi carisi + audit.
  - İade, iptal, tahsilat, ödeme, evrak durum değişikliği, fire, sayım, kesim emri: aynı prensip.
- Her işlem, form açıldığında üretilen bir UUID ile `command_log`'a yazılır. Aynı UUID ikinci kez gelirse (çift dokunma, geri tuşu) işlem tekrarlanmaz. Kaydet butonu işlem sürerken devre dışıdır.

**3.10 Tahsilat ve ödeme eşleştirme.** Tahsilat varsayılan olarak müşterinin vadesi en erken açık belgelerini kapatır (`payment_allocations`); elle eşleştirme de yapılabilir. Vadesi geçen alacak, gecikme günü ve ortalama ödeme süresi buradan hesaplanır. Tedarikçi ödemeleri için aynı mantık geçerlidir.

**3.11 Belge numaraları.** Yıl bazlı ve boşluksuz (`STS-2026-000123`, `ALS-`, `THS-`, `TKL-`, `IAD-`, `KSM-`), `document_sequences` tablosundan aynı transaction içinde atanır.

**3.12 Geleceğe hazırlık (şimdi yapılmayacak ama engellenmeyecek).**
- Tüm kimlikler **UUID v7**.
- `users`, `roles`, `permissions` tabloları şimdiden var; v1'de tek ADMIN kullanıcı bulunur ve kullanıcı yönetimi arayüzü gizlidir.
- Her kayıtta `created_by` ve `device_id` bulunur.
- Tüm yazma işlemleri zaten `command_log`'a komut olarak düşer; ileride sunucu eklendiğinde bu log senkronizasyonun temeli olacak.
- `docs/FUTURE_SYNC.md` içinde, ikinci kullanıcı ve sunucu senkronizasyonunun bu yapı üzerine nasıl ekleneceğini kısaca yaz (komut kuyruğu, sunucuda yeniden işlenen maliyet, yetki bazlı veri filtreleme, çakışan satışların reddi).

---

## 4. YEDEKLEME VE GERİ YÜKLEME (KRİTİK)

Veri yalnızca telefonda durduğu için telefonun kaybolması, bozulması veya sıfırlanması tüm işletme verisinin kaybı demektir. Bu bölüm en az maliyet motoru kadar önemlidir ve **Faz 2'de** eksiksiz tamamlanır.

**4.1 Yedek dosyası.**
- Uzantı `.sbk`, adı `SungerYedek_2026-09-17_1432.sbk`.
- İçerik: veritabanının tutarlı anlık görüntüsü (açık transaction yokken alınmış; `VACUUM INTO` veya SQLCipher `sqlcipher_export` ile) + `manifest.json` (uygulama sürümü, şema sürümü, oluşturulma zamanı, cihaz adı, tablo bazında kayıt sayıları, son işlem tarihi, içerik SHA-256 özeti).
- Dosyanın tamamı **yedek şifresiyle** AES-256-GCM ile şifrelenir.
- **Önemli:** Yedek, cihazın Keystore'undaki veritabanı anahtarına bağlı olmamalıdır. Yalnızca yedek şifresi bilinerek **başka bir telefonda** açılabilmelidir.
- Yedek şifresi ilk kurulumda belirlenir (en az 8 karakter, iki kez girilir). Açık bir uyarı gösterilir: *"Bu şifreyi unutursanız yedekleriniz açılamaz. Bir kâğıda yazıp güvenli yerde saklayın."* Şifre Ayarlar'dan değiştirilebilir; değişiklikten sonraki yedekler yeni şifreyi kullanır.

**4.2 Tek tuşla yedek al.**
- Ana sayfada ve Menü'de belirgin **"Yedek Al"** butonu.
- Dokununca dosya oluşturulur ve iki seçenek sunulur:
  1. **Google Drive'a yükle** (hesap bağlıysa tek dokunuşla, ilerleme göstergesiyle)
  2. **Paylaş / Kaydet** (Android paylaşım menüsü: WhatsApp, e-posta, Dosyalar vb.)
- Google Drive bağlantısı Ayarlar'dan bir kez yapılır. Yedekler kullanıcının Drive'ında görünür bir **"Sünger Yedekleri"** klasörüne yüklenir. Drive'da son 30 yedek tutulur, eskiler silinir.

**4.3 Otomatik yedek.**
- Her gün (varsayılan 20:00, ayarlanabilir) ve günün ilk açılışında önceki gün yedeği alınmamışsa otomatik yedek alınır.
- Yerel kopya: cihazda son 7 günlük + son 4 haftalık yedek saklanır.
- Drive bağlıysa otomatik yedek Drive'a da yüklenir (yalnızca Wi-Fi seçeneği ayarlanabilir).
- **Riskli işlemlerden önce otomatik yedek:** yedekten geri yükleme, uygulama güncellemesi sonrası şema migration'ı, stok sayımı onayı, maliyet yöntemi değişikliği.

**4.4 Uyarılar.**
- Ana sayfanın üstünde yedek durumu: "Son yedek: bugün 20:00 · Drive ✓".
- Son **cihaz dışı** yedek (Drive'a yükleme veya paylaşım) 3 günden eskiyse ana sayfada kırmızı uyarı bandı ve "Şimdi yedekle" butonu. Eşik ayarlanabilir.
- Otomatik yedek başarısız olursa bildirim gösterilir.

**4.5 Tek tuşla yedekten yükle.**
- Menü → **"Yedekten Yükle"**. Ayrıca ilk kurulum sihirbazının ilk ekranında **"Yeni başla / Yedekten geri yükle"** seçimi (telefon değişikliği için).
- Kaynak seçimi: Google Drive'daki yedekler listesi (tarih ve boyutla), cihazdaki otomatik yedekler veya dosya seç.
- Yedek şifresi istenir.
- Doğrulama: şifre çözme, SHA-256 kontrolü, manifest okunması, şema sürümü kontrolü.
  - Yedek daha eski şemadaysa yükleme sonrası migration çalıştırılır.
  - Yedek daha yeni bir uygulama sürümündense "Önce uygulamayı güncelleyin" mesajıyla durdurulur.
- **Önizleme ekranı:** yedek tarihi, cihaz, son işlem tarihi, müşteri/ürün/satış/tahsilat sayıları ve mevcut verilerle karşılaştırması. Yedek mevcut veriden eskiyse uyarı: *"Bu yedek, telefondaki verilerden X gün eski. Sonraki işlemler kaybolacak."*
- Tek bir **"Geri Yükle"** onayı.
- Yükleme öncesi mevcut veritabanının **güvenlik yedeği** otomatik alınır.
- Yeni veritabanı geçici dosyaya açılır, `checkIntegrity()` çalıştırılır, ancak başarılıysa mevcut dosyayla değiştirilir. Herhangi bir adımda hata olursa mevcut veri **hiç değişmemiş** olarak kalır.
- Sonrasında uygulama kendini yeniden başlatır ve "Geri yükleme tamamlandı" özeti gösterir.
- Güvenlik yedeğine Menü → Yedekler ekranından dönülebilir.

**4.6 Yedekler ekranı.** Tüm yerel ve Drive yedeklerinin listesi (tarih, boyut, konum, otomatik/manuel), paylaşma, geri yükleme ve silme (yerel otomatik yedekler için). Son yedek durumu ve Drive bağlantı durumu.

**4.7 Güvenlik.** Yedek şifresi hiçbir yerde düz metin olarak saklanmaz. Otomatik yedek için gereken şifreli anahtar materyali yalnızca secure storage'da tutulur. Loglara şifre veya veri yazılmaz.

---

## 5. SPESİFİKASYONA EK ÖZELLİKLER

- **Kesim Emri — fason kesim:**
  1. *Kesime gönder:* Kaynak blok/plaka partileri ve adetleri, kesimhane (tedarikçi tipi `KESIMHANE`), planlanan hedef ölçüler ve istenirse bağlı teklif/müşteri girilir. Mal ana depodan sanal **"Kesimde"** konumuna transfer edilir; satılamaz, stok değerinde ayrıca görünür, maliyeti aynen taşınır.
  2. *Kesimden dönüş:* Gerçekleşen hedef varyantlar ve adetleri, kesim ücreti ve nakliye girilir. Kesim ücreti kesimhane carisine borç yazılır.
  3. *Maliyet:* Kaynak maliyeti + kesim ücreti + nakliye hedeflere m³ oranında dağıtılır. Hedef toplam m³ kaynağı aşamaz. Normal kesim firesi hedef maliyetine yedirilir ve fire raporunda "kesim firesi" olarak miktarıyla görünür. Artık parçalar (ör. 60×200) ayrı varyant olarak stoğa girebilir.
  4. Hedefler kaynak partinin tarihini taşıyan yeni partiler olarak ana depoya girer.
  5. Kısmi dönüş desteklenir. Durumlar: Hazırlanıyor, Kesimde, Kısmen Döndü, Tamamlandı, İptal.
  6. Teklife bağlı emir tamamlanınca "Satışa dönüştür" kısayolu.
- **Çek ve senet:**
  - Tek model `instruments`: tür (ÇEK / SENET), yön (ALINAN / VERİLEN), numara, banka/şube, keşideci veya borçlu, vade, tutar, bağlı cari. Durum değişiklikleri `instrument_events`'e yazılır.
  - Alınan: Portföyde, Bankaya Tahsile Verildi, Tahsil Edildi, Tedarikçiye Ciro Edildi, Karşılıksız/Protestolu, İade Edildi.
  - Verilen: Verildi, Ödendi, İade Alındı.
  - Alınan evrak müşteri carisinden düşer, portföye girer. Karşılıksız/protestolu → müşteri carisine ters kayıt. Ciro → tedarikçi ödemesi. Tahsil → seçilen banka hesabına giriş. Verilen evrak tedarikçi borcundan düşer; ödendiğinde banka hesabından çıkar.
  - Ana sayfada: bu hafta vadesi gelen alınan ve ödenecek verilen evrak, portföy toplamı. Vade gününden bir gün önce yerel bildirim.
- **Satış iadesi ve alış iadesi:** Orijinal belge satırına referans verir, satılan miktarı aşamaz. Satış iadesinde stok, orijinal satışın tükettiği partilere son tüketilenden başlayarak aynı maliyetle döner. Cariye alacak yazılır; kâr raporunda iade ayrı görünür.
- **Açılış işlemleri:** Açılış stoğu (maliyetli açılış partisi), müşteri/tedarikçi açılış bakiyeleri (vadeli), kasa/banka açılış bakiyeleri, portföydeki evrak.
- **Kasa ve banka hesapları:** `cash_accounts` (kasa, banka, POS) ve `account_movements`, virman.
- **Müşteri risk limiti:** Bakiye + vadesi gelmemiş alınan evrak limiti aşarsa uyarı ve onay.
- **Maliyeti gizle:** Üst çubukta göz ikonu. Açıkken maliyet, kâr ve alış fiyatları ekranda gizlenir (telefonu müşteriye gösterirken). PIN olmadan tekrar açılamaz.
- **Fiyat listesi yuvarlama:** Her versiyonda yuvarlama kuralı (yok / en yakın 1, 5, 10 TL) ve ürün bazlı elle fiyat. Yeni versiyon öncesi eski/yeni karşılaştırma önizlemesi.
- **PDF ve paylaşım:** Teklif, satış/sevk fişi, cari ekstre, kesim emri (kesimhaneye ölçü listesi). Firma logosu ve bilgileri Ayarlar'dan. WhatsApp'a doğrudan paylaşım.
- **Genel giderler:** Kategorili giderler; kârlılık raporunda brüt kâr, fire, maliyet farkları, giderler ve net kâr.
- **QR etiket (opsiyonel):** Varyant için yazdırılabilir QR; okutunca stok kartı açılır veya aktif satışa eklenir.

**Kapsam dışı (v1):** Sunucu, senkronizasyon, ikinci kullanıcı ve yetki arayüzü, e-Fatura/e-İrsaliye, web, Excel içe aktarma, çoklu fiziksel depo, döviz, iOS derlemesi.

---

## 6. VERİ MODELİ

SPEC Bölüm 26'daki tablolara ek olarak en az şunlar:

`locations` (ANA_DEPO, KESIMDE), `settings`, `document_sequences`, `command_log`, `cash_accounts`, `account_movements`, `cost_allocations`, `payment_allocations`, `supplier_payment_allocations`, `sale_returns`, `sale_return_items`, `purchase_returns`, `purchase_return_items`, `purchase_expenses`, `cost_adjustments`, `stock_counts`, `stock_count_items`, `cutting_orders`, `cutting_order_sources`, `cutting_order_results`, `instruments`, `instrument_events`, `expense_categories`, `opening_balances`, `backup_log` (yedek alma/yükleme geçmişi: zaman, tür, hedef, boyut, sonuç).

`stock_movements` en az: `id`, `occurred_at`, `type` (PURCHASE_IN, SALE_OUT, SALE_RETURN_IN, PURCHASE_RETURN_OUT, COUNT_IN, COUNT_OUT, WASTE_OUT, TRANSFER_OUT, TRANSFER_IN, CUTTING_OUT, CUTTING_IN, OPENING_IN, REVERSAL), `location_id`, `variant_id`, `batch_id`, `pieces` (işaretli), `volume` (işaretli, ×10⁶), `unit_cost_m3`, `total_cost`, `source_type`, `source_id`, `reversal_of_id`, `created_by`, `device_id`, `note`.

CHECK kısıtları (adet > 0, kalan ≥ 0, oranlar 0–100), yabancı anahtarlar (`PRAGMA foreign_keys = ON`) ve benzersiz indeksler kullan. Aramada Türkçe karakterleri normalize eden bir kolon tut (İ/i, I/ı, ş/s, ğ/g, ü/u, ö/o, ç/c eşleşmeli); gerekirse FTS5.

Faz 0'da tam ER diyagramını `docs/ERD.md` içinde Mermaid formatında çiz. Şema migration'ları Drift `schemaVersion` ile yönetilir ve her migration için test yazılır.

---

## 7. EKRANLAR VE KULLANICI DENEYİMİ

**Tasarım dili:** Sade, premium, kurumsal. Material 3 tabanlı, nötr tonlar, tek vurgu rengi. Rakamlar tabular. Açık/koyu tema. Dokunma alanları en az 48 dp. Boş, yükleniyor ve hata durumları Türkçe ve anlaşılır. Para/miktar alanlarında sayısal klavye.

**Kurulum sihirbazı:** Yeni başla / Yedekten geri yükle → kullanıcı adı ve PIN (parmak izi opsiyonel) → yedek şifresi → firma bilgileri ve logo → KDV ve varsayılan fiyat modu → maliyet yöntemi → Google Drive bağlama (atlanabilir) → açılış işlemleri (atlanabilir, sonra da yapılabilir).

**Alt navigasyon:** Ana Sayfa · Stok · **(+)** · Cari · Menü.
- **(+)**: Satış, Stok Girişi, Tahsilat, Ödeme, Kesime Gönder.
- **Menü:** Satışlar, Teklifler, İadeler, Alışlar, Kesim Emirleri, Sayım, Fire, Çek & Senet, Kasa & Banka, Tedarikçiler, Fiyat Listeleri, Raporlar, **Yedek Al**, **Yedekten Yükle**, **Yedekler**, Ayarlar (Firma, KDV, Maliyet Yöntemi, Yedek ve Drive, PIN, Audit Log, Tutarlılık Kontrolü, Uygulama Sürümü).
- Üstte global arama, maliyeti gizle ikonu ve yedek durumu.

**Ana Sayfa:** Yedek durum bandı; SPEC'teki büyük hızlı işlem butonları; altında SPEC Bölüm 18'deki kartlar + Kasa & Banka + Çek/Senet Portföyü + Kesimdeki Mal + Sermaye Dağılımı (Stok + Kesimde + Alacak + Portföy + Kasa/Banka − Tedarikçi Borcu − Verilen Evrak).

**Hızlı satış akışı (hedef: tipik satış 30 saniyenin altında):**
1. Müşteri ara (son müşteriler üstte; bakiye, limit ve varsayılan KDV modu rozeti).
2. Sünger çeşidi çipleri.
3. Ölçü seçimi: stokta olan varyantlar önce; her birinde mevcut adet ve m³.
4. Adet stepper; m³, liste fiyatı, müşteri iskontosu, net TL/m³ ve TL/plaka otomatik, değiştirilebilir. Üstte KDV Hariç/Dahil anahtarı.
5. Özet: KDV hariç, KDV, genel toplam, vade, maliyet ve kâr (gizle modu kapalıysa). Peşin tahsilat: nakit, havale, kart, çek, senet.
6. Kaydet → WhatsApp'a fiş paylaşma seçeneği.

**Stok ekranı:** Çeşit seçilince ölçü satır, kalınlık sütun olacak şekilde matris; hücrede adet ve m³. Kritik stok vurgulu. "Kesimde" ayrı sekmede. Hücreye dokununca partiler ve hareket geçmişi.

---

## 8. TEST

**Domain (saf Dart):** m³, yuvarlama, masraf dağıtımı (kuruş farkı dahil), FIFO ve ağırlıklı ortalama, kâr yüzdeleri, KDV dahil/hariç, tahsilat eşleştirme, vade/gecikme, kesim maliyet aktarımı, evrak durum geçişleri.

**Veri katmanı (bellek içi Drift):** Transaction geri alma (satışın ortasında hata → hiçbir kayıt yok), append-only trigger'ları, iade sınırı, negatif stok engeli, çift gönderim (aynı UUID → tek kayıt), sayısal dönüştürücüler (tamsayı ↔ Decimal, uç değerler), migration'lar, `checkIntegrity`.

**Yedekleme (zorunlu):**
- Veri oluştur → yedek al → veritabanını sil → yedeği yükle → **tüm tabloların içerik özeti birebir aynı**.
- Yanlış şifre reddedilir, mevcut veri değişmez.
- Bozuk dosya (değiştirilmiş bayt) reddedilir, mevcut veri değişmez.
- Yükleme ortasında hata simülasyonu → mevcut veri değişmez, güvenlik yedeği oluşmuş.
- Eski şema sürümündeki yedek yüklenir ve migration sonrası doğru çalışır.
- Daha yeni sürümün yedeği reddedilir.
- Yedek farklı bir cihaz anahtarıyla (yeni kurulum simülasyonu) yalnızca yedek şifresiyle açılır.
- Otomatik yedek saklama kuralı (7 günlük + 4 haftalık) doğru eski dosyaları siler.

**Widget/E2E (integration_test):** Kurulum sihirbazı, hızlı satış, stok girişi, tahsilat, yedek al, yedekten yükle.

### Altın Senaryo (kesin rakamlarla, otomatik test)

Ayarlar: FIFO, KDV %20, KDV Hariç mod.

1. **Alış A — 01.09.2026:** Beyaz Sünger, 2.930 TL/m³.
   - 140×200×10 cm × 50 adet → 14,000000 m³
   - 140×200×5 cm × 40 adet → 5,600000 m³
   - Toplam 19,6 m³, çıplak 57.428,00 TL. Nakliye 1.960,00 TL (m³ bazlı).
   - **Beklenen:** Gerçek maliyet 3.030,0000 TL/m³, toplam 59.388,00 TL.
2. **Alış B — 15.09.2026:** Beyaz 140×200×10 × 30 adet = 8,4 m³, 3.165 TL/m³ → 26.586,00 TL.
3. **Satış — 17.09.2026:** ABC Mobilya, vade 30 gün. Beyaz 140×200×10 × 60 adet = 16,8 m³, 3.500 TL/m³.
   - **FIFO:** A'dan 50 adet (14 m³ × 3.030 = 42.420,00) + B'den 10 adet (2,8 m³ × 3.165 = 8.862,00) → maliyet **51.282,00 TL**.
   - Satış (KDV hariç) **58.800,00**, brüt kâr **7.518,00**, kâr marjı **%12,79**, maliyet üzerine kâr **%14,66**.
   - KDV 11.760,00 → müşteri carisi **+70.560,00 TL**.
   - Kalan: 140×200×10 → 20 / 5,6 m³ (B); 140×200×5 → 40 / 5,6 m³ (A). Toplam 11,2 m³, maliyet **34.692,00 TL**.
4. **Tahsilat:** 30.000,00 TL havale → bakiye **40.560,00**, satışın açık tutarı 40.560,00.
5. **Yeni fiyat:** Alış C — 18.09.2026, Beyaz 140×200×8 × 10 = 1,12 m³, **3.300 TL/m³** → 3.696,00 TL. Ardından yeni fiyat listesi versiyonu (baz 3.700). → 3. adımdaki satışın maliyeti, fiyatı ve kârı **değişmemeli**; eski versiyon erişilebilir olmalı.
6. **Sayım:** 140×200×10 sistem 20, fiziksel 19 → −1 adet, −0,28 m³, maliyet **886,20 TL** (B).
7. **Fire:** 140×200×5 × 2 adet, "Hasarlı" → −0,28 m³, maliyet **848,40 TL** (A).
   - **Son stok:** 140×200×10 → 19 / 5,32 m³; 140×200×5 → 38 / 5,32 m³; 140×200×8 → 10 / 1,12 m³. Toplam **11,76 m³**, maliyet **36.653,40 TL**.
8. **İade:** 3. adımdaki satıştan 5 adet 140×200×10 iade → B partisine 3.165 ile döner (1,4 m³, 4.431,00 TL). Cari **−5.880,00** → bakiye **34.680,00**.
9. **İptal:** 4. adımdaki tahsilat iptal → ters kayıt, orijinal silinmez, bakiye **64.680,00**.
10. **Çek:** ABC'den 20.000,00 TL çek (vade 30.10.2026) → bakiye **44.680,00**, portföy 20.000,00. Karşılıksız → bakiye **64.680,00**, portföy 0.
11. **Yedek:** Bu noktada yedek al → veritabanını sil → yedeği yükle → 1–10. adımlardaki tüm bakiyeler, stoklar ve maliyetler birebir aynı.
12. **Doğrulama:** Tüm işlemler hareket tablolarında ve `audit_logs`'ta görünür; `checkIntegrity()` fark bulmaz.

**Ek — Ağırlıklı Ortalama (ayrı veritabanı):** 1–3. adımlar aynı. Satış maliyeti (59.388 + 26.586) / 28 = 3.070,5000 TL/m³ üzerinden **51.584,40 TL**.

**Ek — KDV Dahil:** 4.200,00 dahil %20 → net **3.500,00**, KDV **700,00**. 1.000,00 dahil %20 → KDV **166,67**, net **833,33**; toplam tam 1.000,00.

**Ek — Fason kesim (ayrı veritabanı):**
- Alış: Beyaz blok 200×200×100 × 2 = 8 m³, 2.900 TL/m³ → 23.200,00.
- Kesime gönder: 1 blok (4 m³, 11.600,00) → ana depo 1 blok / 4 m³, "Kesimde" 1 blok / 4 m³.
- Dönüş: 140×200×10 × 9 (2,52 m³) + 60×200×10 × 9 (1,08 m³) = 3,6 m³; kesim ücreti 1.000,00 (KDV hariç).
- **Beklenen:** Toplam maliyet 12.600,00 → **3.500,0000 TL/m³**. 140×200×10 partisi **8.820,00**, 60×200×10 partisi **3.780,00**. Kesim firesi 0,4 m³. Kesimhane carisi +1.200,00. "Kesimde" boş, emir Tamamlandı.

Rakamlardan biri tutmazsa testi değiştirme; önce hesabı kontrol et. Test gerçekten hatalıysa gerekçesini DECISIONS.md'ye yazıp bana sor.

---

## 9. FAZLAR

**Faz 0 — Mimari (kod yok):**
`docs/ARCHITECTURE.md`, `docs/ERD.md` (Mermaid), `docs/BACKUP.md` (dosya formatı, şifreleme, yükleme adımları, hata senaryoları), `docs/DECISIONS.md`, `docs/FLOWS.md` (satış, alış, iade, tahsilat, evrak, sayım, fire, kesim emri, yedek al/yükle), `docs/FUTURE_SYNC.md`, ekran listesi. **DUR, onay bekle.**

**Faz 1 — Domain ve veri katmanı (arayüz yok):**
Flutter projesi ve katman yapısı, Drift şeması + SQLCipher + trigger'lar + sayısal dönüştürücüler, 12 ürün ve katsayıların seed'i, maliyet motoru, fiyat listesi, açılış işlemleri, alış + parti + masraf, satış, iadeler, iptal, tahsilat + eşleştirme, tedarikçi ödemesi, kasa/banka, çek/senet, risk limiti, audit, `checkIntegrity`. Altın senaryonun 1–5, 8–10 ve 12. adımları, ağırlıklı ortalama ve KDV dahil senaryoları geçmeli. **DUR.**

**Faz 2 — Mobil çekirdek + yedekleme:**
Tema, kurulum sihirbazı, PIN/parmak izi kilidi, ana sayfa, stok ekranı, müşteri/tedarikçi kartları ve cari ekstre, alış, hızlı satış, iade, tahsilat, ödeme, çek/senet, kasa/banka, açılış ekranları, maliyeti gizle, ayarlar. **Bölüm 4'ün tamamı:** yedek al, Drive'a yükle, paylaş, otomatik yedek, uyarılar, yedekten yükle, yedekler ekranı. Yedekleme testleri ve altın senaryonun 11. adımı geçmeli. Test için imzalı debug APK üret. **DUR.**

**Faz 3 — Operasyon:**
Teklif ve satışa dönüştürme (stok düşmeden), stok sayımı, fire, kesim emri (gönder, dönüş, kısmi dönüş, teklife bağlama), vade takibi ve bildirimler, PDF belgeler ve WhatsApp paylaşımı, global arama. Altın senaryonun tamamı ve fason kesim senaryosu geçmeli. **DUR.**

**Faz 4 — Analiz ve rapor:**
Müşteri analizi (SPEC 19), ürün analizi (SPEC 20), SPEC 25'teki raporlar (tarih/müşteri/ürün filtreli), Excel ve PDF dışa aktarma + paylaşım, grafikler, giderler ve net kâr, evrak vade raporu, kesim raporu, QR etiket (opsiyonel). **DUR.**

**Faz 5 — Yayına alma:**
- **Release APK:** İmzalama anahtarı oluşturma talimatı. `docs/KURULUM.md`'de uyarı: *anahtar kaybolursa uygulama güncellenemez, en az iki güvenli yere yedeklenmeli.*
- **Güncelleme:** APK elden dağıtılır. Güncellemede veri korunur (aynı imza, aynı paket adı). Migration öncesi otomatik yedek alınır, migration başarısızsa o yedekten dönülür. Ayarlar'da sürüm bilgisi ve değişiklik notları.
- Google Drive için Google Cloud OAuth istemcisi kurulum adımları (paket adı ve SHA-1 parmak izi dahil) `docs/KURULUM.md`'de.
- Performans: 50.000 satış satırıyla ana sayfa ve raporların makul sürede açıldığını ölç ve DECISIONS.md'ye yaz.
- `docs/KULLANIM.md`: ekran görüntülü kısa kılavuz; **"Telefon kaybolursa / değişirse ne yapılır"** bölümü ayrıca.

**Gelecek (şimdi yapılmayacak):** Sunucu, ikinci kullanıcı (Muhasebeci), yetkiler ve senkronizasyon. Yalnızca `docs/FUTURE_SYNC.md` hazırlanır.

---

## 10. TAMAMLANMA KRİTERİ

- Tüm testler geçiyor, `flutter analyze` temiz.
- Altın senaryo ve tüm ek senaryolar otomatik testte geçiyor.
- Uygulama internetsiz eksiksiz çalışıyor.
- Tek dokunuşla yedek alınıyor, Drive'a yükleniyor veya paylaşılıyor; otomatik yedek çalışıyor.
- Tek akışla yedek yükleniyor; yanlış şifre, bozuk dosya ve yarıda kesilen yüklemede mevcut veri hiç bozulmuyor.
- Yedek, yeni bir telefonda yalnızca yedek şifresiyle açılabiliyor.
- Hiçbir finansal veya stok kaydı silinemiyor ya da değiştirilemiyor; düzeltmeler ters hareketle.
- İmzalı release APK üretiliyor, güncellemede veri korunuyor.

Şimdi Faz 0 ile başla.
