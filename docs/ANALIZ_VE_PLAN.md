# Sünger Stok & Cari Sistemi — Analiz ve Geliştirilmiş Plan

## 1. Genel Değerlendirme

Müşterinin dokümanı ortalamanın çok üstünde. Parti bazlı stok, FIFO, maliyetin satışa sabitlenmesi, DECIMAL kullanımı, transaction güvenliği, ters kayıtla düzeltme ve audit log gibi çoğu yazılımcının atladığı konular zaten yazılmış. Sorun eksik düşünce değil, **gerçek hayatta ilk ay içinde patlayacak birkaç boşluk** ve **kapsamın tek seferde yapılamayacak kadar büyük olması**.

Güncelleme: Müşteriyle yapılan görüşmeden sonra platform **tek kullanıcılı, sunucusuz, çevrimdışı Android uygulaması (APK)** olarak netleşti. Kararlar ve etkileri 4. bölümde. Bu yapıda 2.11 (eşzamanlı satış) ve 2.13 (sunucu tarafı yetki) şimdilik geçerli değil; ikinci kullanıcı eklendiğinde tekrar gündeme gelecek.

---

## 2. Kritik Eksikler ve Riskler

**2.1 KDV hiç tanımlanmamış (sadece teklifte geçiyor).** Satış ve alışta KDV yoksa cari bakiye yanlış çıkar, kâr da KDV'li tutardan hesaplanırsa şişer. Karar: fiyatlar KDV hariç girilir, kâr ve maliyet KDV hariç hesaplanır, cariye KDV dahil tutar yazılır.

**2.2 İade yok.** Müşteri 5 plaka geri getirdiğinde ya da fabrikaya hasarlı mal iade edildiğinde sistemin yapacağı bir şey yok. İptal/ters kayıt bunun yerini tutmaz, çünkü satışın tamamı değil bir kısmı geri gelir. Satış iadesi ve alış iadesi ilk fazda olmalı; iade edilen mal, çıktığı partiye aynı maliyetle geri dönmeli.

**2.3 Kesim / dönüştürme yok.** Spesifikasyonda "kesilmiş" sadece fire nedeni olarak geçiyor. Oysa 140×240 plakadan 140×200 kesmek ya da müşteriye özel ölçü çıkarmak bu sektörde günlük iş. Bunun için ayrı bir hareket gerekiyor: kaynak ölçüden stok düşer, hedef ölçüler oluşur, maliyet m³ oranında aktarılır, artan kısım fire yazılır. Yoksa personel ya satışı yanlış ölçüden girer ya da sayım her ay tutmaz.

**2.4 Ürün ile ölçü karışmış.** "D35 140×240" ve "HR35 140×240" ayrı ürün olarak listelenmiş ama katsayıları D35 ve HR35 ile birebir aynı. Müşterinin kendi kuralı da "aynı ürünün farklı ölçüleri ayrı stoklanmalı" diyor. Bunlar ayrı ürün değil, ölçü varyantı olmalı. Ayrı tutulursa raporlarda D35 toplamı yanlış çıkar. (Müşteriye teyit ettirilecek.)

**2.5 Tahsilat hangi faturayı kapatıyor, belli değil.** "Vadesi geçen alacak" ve "ortalama ödeme süresi" ancak tahsilatın hangi satışlara karşılık geldiği biliniyorsa hesaplanabilir. Karar: tahsilat otomatik olarak en eski açık satışlardan kapatılır, istenirse elle eşleştirilir. Aynısı tedarikçi ödemeleri için de geçerli.

**2.6 Sisteme geçiş (açılış) düşünülmemiş.** İşletme sıfırdan başlamıyor. Depoda mal var, müşterilerin eski borçları var, fabrikaya borç var. Açılış stoğu (maliyetiyle) ve açılış cari bakiyeleri girilemezse sistem ilk günden yanlış rakam gösterir.

**2.7 "Sermayem nerede?" sorusu yarım kalıyor.** Stok ve alacak var ama kasa ve banka yok. Tahsilat "nakit" diye girilip bir hesaba bağlanmazsa paranın nerede olduğu görünmez. Basit kasa/banka hesapları eklenmeli. Böylece dashboard'da gerçek tablo çıkar: Stok + Alacak + Kasa/Banka − Tedarikçi Borcu.

**2.8 Çek sadece bir ödeme yöntemi olarak geçiyor.** Türkiye'de mobilya sektöründe çek çok yaygın. Çekin vadesi, bankası, durumu (portföyde, tahsil edildi, ciro edildi, karşılıksız) izlenmezse "tahsilat yaptım" sanılan para aslında henüz gelmemiş olur. Karşılıksız çıkarsa cariye geri yazılmalı.

**2.9 FIFO ↔ Ağırlıklı Ortalama geçişi tehlikeli.** Yöntem işletme ortasında değiştirilirse raporlar tutarsızlaşır. Karar: yöntem kurulumda seçilir, ilk stok hareketinden sonra kilitlenir. Fiziksel parti takibi her iki yöntemde de devam eder.

**2.10 Sonradan gelen nakliye faturası.** Nakliye faturası çoğu zaman maldan günler sonra gelir; bu arada partinin bir kısmı satılmış olabilir. Karar: masrafın hâlâ stokta kalan kısma düşen payı partinin maliyetine eklenir, satılmış kısma düşen payı ayrı bir "maliyet farkı" kaydı olarak döneme yazılır. Geçmiş satışlar değişmez.

**2.11 Aynı anda iki satış.** İki personel aynı anda son 5 plakayı satarsa stok eksiye düşer. Veritabanında satır kilitleme şart.

**2.12 "Yetkiliye negatif stok izni".** FIFO'da stokta olmayan malın maliyeti bilinmez, dolayısıyla o satışın kârı da bilinmez. İlk sürümde negatif stok herkes için kapalı olmalı; mal gelmeden satış gerekiyorsa önce hızlı stok girişi yapılır.

**2.13 Yetki sadece ekranda gizlenirse işe yaramaz.** Personel maliyeti göremiyorsa, sunucu bu veriyi hiç göndermemeli. Aksi halde tarayıcıdan okunabilir.

**2.14 Kuruş farkları.** Nakliye dağıtımında ve iskontolu plaka fiyatında yuvarlama kuralı tanımlı değil. Kural koyulmazsa toplamlar 1-2 kuruş tutmaz ve muhasebeci ile tartışma çıkar.

---

## 3. Önerilen Ek Özellikler

Müşterinin istemediği ama kullanımda fark yaratacak eklemeler:

- **Müşteri risk limiti:** Limiti aşan satışta uyarı; aşmak için yönetici yetkisi.
- **PDF belgeler + WhatsApp paylaşımı:** Teklif, satış/sevk fişi ve cari ekstre telefondan tek dokunuşla WhatsApp'a gönderilir. Müşterilerle iletişim zaten orada.
- **Fiyat yuvarlama kuralı:** Baz × katsayı sonucu 6.685,00 yerine 6.690 gibi yuvarlanabilsin; ürün bazlı elle düzeltme yapılabilsin.
- **Excel'den içe aktarma:** Müşteri listesi ve açılış bakiyeleri toplu yüklensin.
- **Genel gider girişi:** Kira, maaş, yakıt girilirse brüt kârın yanında net kâr da görülür.
- **QR etiket (opsiyonel):** Raf/plaka etiketi okutulunca stok sorgusu açılır ya da ürün satışa eklenir.
- **Tutarlılık kontrolü:** Stok ve cari bakiyelerini hareketlerden yeniden hesaplayıp karşılaştıran bir kontrol. Sessiz veri bozulmasını erken yakalar.
- **Geleceğe hazırlık:** Tek depo ile başlanır ama veri modeli çoklu depoya hazır olur; e-Fatura için alanlar şimdiden bulunur.

---

## 4. Müşteri Kararları ve Etkileri

| Konu | Karar | Plana etkisi |
|---|---|---|
| D35/HR35 140×240 | Ayrı ürün | SPEC'teki 12 ürün aynen kalır |
| Blok ve özel ölçü | Var, kesim dışarıda | **Fason Kesim Emri**: mal "Kesimde" konumuna gider, dönüşte kesim ücreti maliyete eklenir |
| KDV | Hariç/dahil seçilebilsin | Her belgede anahtar; kâr her zaman KDV hariç |
| e-Fatura | İstenmiyor | Sadece opsiyonel fatura/irsaliye no |
| Çek/senet | Aktif | Alınan ve verilen evrak çekirdek kapsamda |
| Kullanıcı | Başlangıçta tek kullanıcı | Kullanıcı/yetki arayüzü yok; veri modeli ikinci kullanıcıya hazır |
| Depo | Tek depo | + sanal "Kesimde" konumu |
| Mevcut veri | Sıfırdan girilecek | İçe aktarma yok; açılış ekranları var |
| İnternet | Offline | Uygulama tamamen cihazda çalışır |
| Sunucu | Başlangıçta yok | Veri telefonda şifreli; yedekleme kritik hale geldi |
| Yedek | Tek tuşla al/yükle | Şifreli yedek dosyası, Google Drive, otomatik günlük yedek |

**Dikkat edilmesi gereken noktalar:**

1. **Telefon = tüm işletme verisi.** Sunucu olmadığı için telefon kaybolur, bozulur veya sıfırlanırsa tek kurtuluş yedektir. Bu yüzden günlük otomatik yedek, Google Drive'a otomatik yükleme ve 3 gün cihaz dışı yedek alınmazsa kırmızı uyarı eklendi.
2. **Yedek şifresi unutulmamalı.** Yedekler şifreli; şifre olmadan yeni telefonda açılamaz. Kurulumda kâğıda yazıp saklanması istenecek.
3. **Google Drive bağlantısı bir kerelik kurulum ister.** Ücretsiz bir Google Cloud projesi ve OAuth ayarı gerekir; adımlar kurulum dokümanında olacak. Drive bağlanmazsa yedek WhatsApp/e-posta ile paylaşılarak dışarı alınabilir.
4. **İkinci kullanıcı gelince sunucu gerekecek.** Muhasebeci ayrı cihazdan kullanmak isterse sunucu ve senkronizasyon eklenmeli. Veri modeli buna hazır kuruluyor, ama bu ayrı bir iş ve ayrı bir bütçe.
5. **SPEC'teki masaüstü ve iPhone desteği bu sürümde yok.** Flutter sayesinde kod buna hazır.

---

## 5. Teknoloji Kararı

| Katman | Seçim | Neden |
|---|---|---|
| Uygulama | Flutter | Android APK; ileride iOS/Windows aynı koddan |
| Veritabanı | Drift (SQLite) + SQLCipher | Tamamen cihazda, şifreli |
| Sayısal saklama | Sabit ölçekli tamsayı | SQLite'ta kuruş hatası olmaması için |
| İş mantığı | Saf Dart domain katmanı | Test edilebilir, ileride sunucuya taşınabilir |
| Yedek | AES-256 şifreli dosya + Google Drive | Telefon değişse bile şifreyle geri yüklenir |
| Belgeler | pdf + share_plus | WhatsApp'a doğrudan paylaşım |
| Test | flutter_test + integration_test | İş kuralları ve yedek senaryoları |

---

## 6. Faz Planı

**Faz 0 — Mimari:** Veri modeli, yedekleme tasarımı, ER diyagramı, kararlar dokümanı.

**Faz 1 — Domain ve veri katmanı:** Tüm iş kuralları, maliyet motoru, cari, çek/senet ve testleri. Arayüz yok.

**Faz 2 — Mobil çekirdek + yedekleme:** Uygulama ekranları, satış, alış, iade, tahsilat, çek/senet, kasa/banka, açılış ekranları, **tek tuşla yedek al/yükle, otomatik yedek, Drive**.

**Faz 3 — Operasyon:** Teklif, sayım, fire, fason kesim emri, vade takibi, PDF ve paylaşım, arama.

**Faz 4 — Analiz:** Müşteri/ürün analizleri, raporlar, Excel/PDF, grafikler, net kâr.

**Faz 5 — Yayına alma:** İmzalı APK, güvenli güncelleme, Drive kurulumu, kılavuz.

**Gelecek:** Sunucu + Muhasebeci kullanıcısı + senkronizasyon (ayrı iş).
