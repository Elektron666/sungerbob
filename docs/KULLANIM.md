# Kullanım Kılavuzu

Günlük kullanım için kısa kılavuz. Teknik kurulum için `docs/KURULUM.md`.

---

## ⚠️ Önce şunu okuyun: Telefon kaybolursa / değişirse

**Tüm işletme veriniz yalnızca bu telefonda duruyor.** Sunucu yok. Telefon
kaybolur, çalınır, bozulur veya sıfırlanırsa **tek kurtuluşunuz yedektir.**

### Bugün yapmanız gerekenler

1. **Yedek şifrenizi bir kâğıda yazın** ve güvenli bir yerde saklayın
   (kasa, cüzdan, evdeki dosya). Bu şifre unutulursa yedekleriniz **açılamaz** —
   kimse açamaz, biz de açamayız.
2. **Yedeği telefon dışına çıkarın.** Telefonun içindeki yedek, telefon
   kaybolduğunda onunla birlikte gider. Ana sayfadaki **Yedek Al** → **Paylaş**
   ile WhatsApp'tan kendinize veya muhasebecinize gönderin. Google Drive
   bağlıysa otomatik yüklenir.
3. Ana sayfada **kırmızı uyarı bandı** görürseniz ciddiye alın: son cihaz dışı
   yedeğinizin üzerinden 3 günden fazla geçmiş demektir.

### Telefon kaybolduysa / değiştiyseniz

1. Yeni telefona uygulamayı kurun (`docs/KURULUM.md` Bölüm 1).
2. Açılıştaki ilk ekranda **"Yedekten geri yükle"** seçin.
3. Yedek dosyanızı bulun (WhatsApp'taki, e-postadaki veya Drive'daki).
4. **Yedek şifrenizi** girin.
5. Önizleme ekranında tarihe ve rakamlara bakın, doğruysa **Geri Yükle**.

Verileriniz son yedek anındaki haline döner. Yedekten sonra yaptığınız
işlemler kaybolur — bu yüzden günlük yedek önemlidir.

> Yedek dosyası şifrelidir. WhatsApp'a göndermeniz güvenlidir; şifreyi bilmeyen
> içindeki hiçbir veriyi göremez.

---

## Günlük akış

### Satış (hedef: 30 saniye)

Ana sayfa → **+ SATIŞ**

1. **Müşteriyi seçin.** Yanında bakiyesi görünür.
2. **Sünger çeşidini** seçin (çipler).
3. **Ölçüyü** seçin. Stokta olanlar listelenir, her birinde kaç adet ve kaç m³
   olduğu yazar.
4. **Adedi** artı/eksi ile ayarlayın.
5. **TL/m³** fiyatını girin. Virgül de nokta da kullanabilirsiniz (`3500` veya
   `3.500,00`).
6. Özet bölümünde KDV hariç tutar, KDV ve genel toplam görünür.
7. **Kaydet**.

Üst köşedeki **KDV Hariç / Dahil** anahtarı, girdiğiniz fiyatın hangisi olduğunu
belirler. "Dahil" seçerseniz girdiğiniz tutar **aynen korunur**, KDV içinden
ayrıştırılır.

**Risk limiti:** Müşterinin limiti aşılıyorsa uyarı çıkar. Bakiyesi, portföydeki
çekleri ve bu satış toplanarak hesaplanır. Yine de satmak isterseniz onaylarsınız.

**Stokta olmayan mal satılamaz.** Önce stok girişi yapın.

### Stok girişi (fabrikadan mal geldiğinde)

Ana sayfa → **+ STOK GİRİŞİ**

1. Tedarikçi ve sünger çeşidi.
2. En, boy, kalınlık, adet. (Bu ölçü daha önce hiç girilmemişse otomatik oluşur.)
3. **TL/m³** alış fiyatı.
4. **Nakliye** varsa girin — m³ oranında dağıtılıp maliyete eklenir.
5. Kaydet.

Sistem hem **çıplak fabrika fiyatını** hem **nakliyeli gerçek maliyeti** ayrı
tutar. Kâr hesabında gerçek maliyet kullanılır.

> **Nakliye faturası sonradan geldiyse:** Alış belgesini açıp masraf ekleyin.
> Sistem, malın stokta kalan kısmına düşen payı partinin maliyetine ekler;
> satılmış kısma düşen payı ayrı bir "maliyet farkı" olarak döneme yazar.
> **Geçmiş satışlarınızın kârı değişmez.**

### Tahsilat

Ana sayfa → **+ TAHSİLAT**

Müşteri, tutar, yöntem (nakit / havale / kart / çek / senet). Nakit ve havalede
hangi kasaya girdiğini seçersiniz.

Tahsilat **vadesi en erken açık satıştan** başlayarak otomatik eşleştirilir.
Böylece "hangi fatura kapandı", "kaç gün gecikti" ve "ortalama ödeme süresi"
doğru hesaplanır.

**Çek aldıysanız:** Çek bilgilerini girin. Çek müşterinin borcundan düşer ve
**portföye** girer — ama para henüz kasaya girmemiştir. Çek tahsil edilince
bankaya giriş yazarsınız. Karşılıksız çıkarsa borç müşteriye **geri yazılır**.

---

## Önemli kurallar

### Hiçbir kayıt silinemez

Yanlış giriş yaptıysanız **iptal** edersiniz. Sistem ters bir kayıt oluşturur;
orijinal kayıt yerinde kalır ve geçmişte görünür. Bu, muhasebe açısından
doğrudur ve denetlenebilir bir geçmiş bırakır.

### Geçmiş kâr değişmez

Bir satışın maliyeti **satış anında sabitlenir**. Sonradan fabrika fiyatı
artsa, yeni fiyat listesi çıksa veya nakliye faturası gelse bile o satışın kârı
**aynı kalır**.

### Maliyet yöntemi kilitlenir

FIFO (ilk giren ilk çıkar) varsayılandır. İlk stok hareketinden sonra
değiştirilemez — değiştirilirse geçmiş raporlar tutarsızlaşırdı.

### Maliyeti gizleme

Telefonu müşteriye gösterirken üst çubuktaki **göz** ikonuna dokunun. Maliyet,
kâr ve alış fiyatları gizlenir. Tekrar göstermek için **PIN** gerekir.

---

## Ana sayfadaki kartlar

| Kart | Ne demek |
|---|---|
| **Toplam Stok** | Depodaki toplam m³ |
| **Stok Maliyeti** | Depodaki malın size kaça mal olduğu |
| **Stok Satış Değeri** | Güncel fiyat listesiyle satarsanız ne eder |
| **Bu Ay Satış** | KDV hariç ciro |
| **Bu Ay Brüt Kâr** | Satış − maliyet |
| **Müşterilerden Alacak** | Toplam cari bakiye |
| **Tedarikçi Borcu** | Fabrikaya borcunuz |
| **Vadesi Geçen** | Zamanında ödenmemiş alacak |
| **Kasa & Banka** | Eldeki nakit ve banka bakiyesi |
| **Çek/Senet Portföyü** | Elinizdeki, henüz tahsil edilmemiş evrak |
| **Kesimdeki Mal** | Kesimhanede olan malın değeri |
| **Sermaye Dağılımı** | Stok + Kesimde + Alacak + Portföy + Kasa − Borç − Verilen evrak |

---

## Stok ekranı

Çeşidi seçtiğinizde **ölçü satır, kalınlık sütun** olan bir tablo çıkar. Her
hücrede kaç adet ve kaç m³ olduğu yazar. Kritik seviyenin altındakiler
**kırmızı** görünür.

**"Kesimde"** sekmesi, kesimhaneye gönderdiğiniz malı gösterir. Bu mal
satılamaz; geri döndüğünde yeni ölçülerde stoğa girer.

---

## Fason kesim

Blok alıp özel ölçü satıyorsanız:

1. **Kesime gönder:** Hangi bloktan kaç adet gittiğini girin. Mal "Kesimde"
   konumuna geçer, maliyetini yanında taşır.
2. **Kesimden dönüş:** Hangi ölçüde kaç adet geldiğini ve kesim ücretini girin.
   Kaynak maliyeti + kesim ücreti + nakliye, çıkan ölçülere m³ oranında
   dağıtılır. Aradaki kayıp **kesim firesi** olarak görünür.

Kısmi dönüş olabilir; kalan mal "Kesimde" görünmeye devam eder.

---

## Sayım ve fire

**Sayım:** Depoyu fiziksel sayarsınız, sistem farkı gösterir. Onayladığınızda
düzeltme hareketi oluşur. Geçmiş kayıtlar değişmez. Onaydan önce otomatik
yedek alınır.

**Fire:** Hasarlı, nemlenmiş veya numune verilen mal. **Neden belirtmek
zorunludur.** Fire satış olarak görünmez, kârlılık raporunda ayrı kalem olur.

---

## Yedekleme alışkanlığı

| Ne zaman | Ne yapın |
|---|---|
| Her gün (otomatik, 20:00) | Bir şey yapmanız gerekmez |
| Haftada en az bir | **Yedek Al → Paylaş** ile telefon dışına çıkarın |
| Kırmızı uyarı bandı çıkınca | Hemen cihaz dışına yedek alın |
| Telefon değiştirmeden önce | Yedek alın, dosyanın ulaştığını **doğrulayın** |
| Büyük bir işlemden önce | Yedek Al (sayım onayı gibi işlemlerde otomatik alınır) |

**Yedek şifresini unutmayın.** Kâğıda yazın.
