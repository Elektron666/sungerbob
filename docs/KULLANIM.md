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

### Nakliye faturası sonradan geldiğinde

Fabrikadan mal gelir, nakliye faturası bir hafta sonra gelir. O fatura
malın maliyetinin bir parçasıdır.

*Alışlar → belgeye dokun → **Masraf ekle*** deyip tutarı girin. Nakliye,
hamaliye veya diğer; hacme göre ya da tutara göre dağıtılır.

Ne olur:

- **Stokta duran mala düşen pay** o partinin maliyetini artırır. Bundan
  sonraki satışların kârı doğru hesaplanır.
- **Zaten satılmış mala düşen pay** dönem maliyet farkı olur.
  **Geçmiş satışın kârı değişmez** — o satış o günkü maliyetle kapandı.

---

## Tahsilat

Ana sayfa → **+ TAHSİLAT**

Müşteri, tutar, yöntem (nakit / havale / kart / çek / senet). Nakit ve havalede
hangi kasaya girdiğini seçersiniz.

Tahsilat **vadesi en erken açık satıştan** başlayarak otomatik eşleştirilir.
Böylece "hangi fatura kapandı", "kaç gün gecikti" ve "ortalama ödeme süresi"
doğru hesaplanır.

**Çek aldıysanız:** Çek bilgilerini girin. Çek müşterinin borcundan düşer ve
**portföye** girer — ama para henüz kasaya girmemiştir. Çek tahsil edilince
bankaya giriş yazarsınız. Karşılıksız çıkarsa borç müşteriye **geri yazılır**.

### Yanlış tahsilat girdiyseniz

*Müşteriler → müşteri → Cari Ekstre* açın, tahsilat satırındaki **⋮**
menüsünden **Tahsilatı iptal et** deyin. Sebep yazmanız istenir; o sebep
ekstrede görünür, böylece "bu neden iptal edilmiş?" sorusunun cevabı
defterin içinde kalır.

Tahsilat silinmez: ters bir kayıt oluşur, kasadan da geri çıkar, ikisi de
ekstrede yan yana durur.

---

## Önemli kurallar

### Hiçbir kayıt silinemez

Yanlış giriş yaptıysanız kaydı silmezsiniz; **ters bir kayıt** oluşturursunuz.
Orijinal kayıt yerinde kalır ve geçmişte görünür. Bu, muhasebe açısından
doğrudur ve denetlenebilir bir geçmiş bırakır.

**Satışta bunun adı iadedir.** Müşteri malı geri getirdiğinde satışı iptal
etmezsiniz: *Satışlar → belge → İade al* deyip kaç adet geri geldiğini
girersiniz. Satış olduğu gibi durur, mal aynı maliyetle stoğa döner, müşterinin
borcu azalır. Böylece ciro ve kâr raporları gerçeği anlatmaya devam eder —
iptal edilmiş bir satış, hiç olmamış gibi görünürdü.

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

## Ürünler ve ince malzeme

*Menü → Depo → Ürünler*

Uygulama 12 sünger çeşidiyle kurulur. Kendi çeşidinizi ekleyebilir, yanında
sattığınız **çivi, yapıştırıcı, zikzak yay** gibi malzemeleri de
tanımlayabilirsiniz.

Ürün kartı açarken **birim** seçersiniz:

| Birim | Ne zaman |
|---|---|
| **m³ (sünger)** | Ölçüye göre satılan sünger. En, boy, kalınlık sorulur. |
| adet, kg, kutu, litre, metre | İnce malzeme. **Ölçü sorulmaz**, miktarı kendi biriminden girersiniz. |

Birim ürün kartında sabittir; sonradan değiştirilemez, çünkü geçmiş
hareketlerin maliyeti o birime göre hesaplanmıştır.

Ana sayfadaki "Toplam Stok m³" yalnızca süngeri sayar: 50 kg tutkal o rakama
karışmaz.

---

## Fiyat listesi (zam yapmak)

*Menü → Depo → Fiyat Listeleri → Yeni fiyat listesi*

1. **Baz fiyatı** girin — beyaz süngerin metreküp fiyatı. Diğer çeşitler kendi
   katsayılarıyla hesaplanır.
2. İsterseniz **yuvarlama** seçin (en yakın 1, 5 veya 10 TL).
3. **Önizle** deyin. Her çeşidin eski fiyatı, yeni fiyatı ve değişim yüzdesi
   yan yana çıkar. Düşen bir fiyat varsa kırmızı görünür.
4. Doğruysa **Listeyi yürürlüğe al**.

Önizlemeyi görmeden kaydedemezsiniz: tek bir sayı girerek bütün ürünlerin
fiyatını aynı anda değiştiriyorsunuz.

Eski liste **silinmez**, arşivlenir. Geçmiş satışlar kendi listesine bağlı
kalır.

Satış ekranında fiyat alanının altında iki ipucu çıkar: **son satış** (bu
müşteriye ne demiştiniz) ve **liste fiyatı** (bugünkü fiyatınız). İkisi de
dokununca alanı doldurur; kendiliğinden doldurmaz.

---

## Teklif

*Menü → Kayıtlar → Teklifler → Yeni teklif*

Müşteri, geçerlilik tarihi ve kalemler. Teklifte ölçü serbesttir: elinizde
olmayan bir ölçüye de fiyat verebilirsiniz, çünkü teklif **stoğa dokunmaz**.

Teklifi gönderdikten sonra satırdaki **⋮** menüsünden durumunu
işaretleyin: *Gönderildi* → *Kabul edildi* / *Reddedildi*. Menü yalnızca o
an yapılabilecekleri gösterir.

Müşteri kabul edince **Satışa çevir** deyin; stok o anda düşer, cariye borç
yazılır. Aynı teklif ikinci kez çevrilemez. "Satışa çevrildi" durumu elle
işaretlenemez — çünkü o, stok ve cari hareketi üreten gerçek bir işlemdir.

---

## Belgeleri müşteriye gönderme

Dört belge PDF olarak üretilir ve doğrudan WhatsApp'a (ya da e-postaya)
paylaşılır:

| Belge | Nereden |
|---|---|
| **Satış fişi** | Satışlar → belgeye dokun → *Fişi paylaş* |
| **Fiyat teklifi** | Teklifler → *PDF paylaş* |
| **Kesim emri** | Kesim Emirleri → paylaş simgesi |
| **Cari ekstre** | Müşteriler → müşteri → başlıktaki paylaş simgesi |

Belgelerde firma adınız, adresiniz ve logonuz görünür — bunları *Ayarlar →
İşletme* bölümünden girersiniz.

**Kesim emrinde fiyat yazmaz.** Kesimhanenin görmesi gereken yalnızca ölçü ve
adettir.

**Cari ekstre tahsilatın ilk adımıdır:** "sana şu kadar borcun var" demenin en
kibar yolu belgedir.

---

## Raporlar

| Sekme | Ne söyler |
|---|---|
| **Kârlılık** | Seçili dönemde ciro, maliyet, brüt kâr |
| **Satış grafiği** | Dönem dönem satış eğrisi |
| **Ürünler** | Hangi çeşit ne kadar döndü, ortalama maliyet ve satış |
| **Müşteriler** | Hangi müşteri ne kadar aldı, ne kadar kâr bıraktı, **kaç günde ödüyor** |
| **Vadeler** | Yaklaşan ve geçmiş vadeler |

Dördü de **CSV olarak paylaşılabilir** — muhasebeciye göndermenin en kolay
yolu.

"Ortalama ödeme süresi" vade değil, **gerçekleşen** ödeme süresidir: 30 gün
vadeli satan ama parasını 55 günde alan bir müşteriyi burada görürsünüz.

---

## Ayarlar

*Menü → Kurulum → Ayarlar*

| Ayar | Ne yapar |
|---|---|
| **KDV oranı** | Yeni satış, alış ve tekliflerde kullanılan varsayılan oran. Değiştirdiğinizde bundan sonraki belgeler yeni oranla hesaplanır; **geçmiş belgeler değişmez.** |
| **Varsayılan fiyat modu** | Satış ekranının KDV hariç mi dahil mi açılacağı |
| **Maliyet yöntemi** | FIFO veya ağırlıklı ortalama. İlk stok hareketinden sonra kilitlenir. |
| **Parmak izi ile aç** | Kilidi parmak iziyle açar. **PIN her zaman çalışmaya devam eder**; parmağınız okunmazsa PIN girersiniz. Açarken bir kez parmağınız okutulur. |
| **Otomatik yedek saati** | Her gün yedeğin alınacağı saat |
| **Cihaz dışı yedek uyarı eşiği** | Kaç gün yedek çıkarmazsanız kırmızı uyarı çıkacağı (1/3/7/14 gün) |
| **Tutarlılık kontrolü** | Stok ve cari bakiyeleri hareketlerden yeniden hesaplar; fark varsa gösterir |

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
