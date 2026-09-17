# SÜNGER STOK, SATIŞ, CARİ VE KÂRLILIK YÖNETİM SİSTEMİ — MÜŞTERİ SPESİFİKASYONU

> Bu doküman müşterinin orijinal isteğidir. Müşteriyle netleşen kararlar ve değişiklikler `CLAUDE_CODE_PROMPT.md` içindedir; çelişki olursa o dosya geçerlidir (ör. web yerine Android APK, sunucu yok, tek kullanıcı).

Türkiye'de sünger toptan alım-satımı yapan bir işletme için gerçek ticari kullanım amaçlı, Türkçe, modern ve mobil uyumlu bir web uygulaması geliştir.

Bu uygulama klasik ve karmaşık bir muhasebe programı olmayacak.

Temel amaç şu sorulara anında cevap verebilmek:

- Fabrikadan ne kadar sünger aldım?
- Hangi fiyattan aldım?
- Hangi ölçülerde ürünüm var?
- Şu anda elimde kaç plaka/adet ve kaç m³ sünger var?
- Hangi müşteriye ne sattım?
- Hangi fiyattan sattım?
- Satıştan kaç TL ve yüzde kaç kâr ettim?
- Hangi müşteri bana ne kadar borçlu?
- Ne kadar tahsilat yaptım?
- Toplam stok maliyetim ne?
- Güncel satış fiyatlarıyla stoğumun satış değeri ne?
- Sermayemin ne kadarı stokta, ne kadarı müşterilerde alacak olarak duruyor?

Uygulama masaüstü bilgisayar ve Android/iPhone telefonlarda sorunsuz çalışmalıdır.

---

## 1. ÜRÜN GRUPLARI

Başlangıç ürünleri:

- Beyaz Sünger
- D22 Gri
- D28 Gri
- D32 Gri
- D35 Sert
- D35 Yumuşak
- D35 140×240
- Kuş Tüyü
- 30 Dream Soft
- HR35
- HR35 140×240
- Eko Gri D18

Yeni ürün ekleme, düzenleme ve pasife alma desteklenmeli.

Her ürün için şunlar tutulmalı:

- Ürün kodu
- Ürün adı
- DNS
- Sünger tipi
- Standart en
- Standart boy
- Standart kalınlıklar
- Varsayılan satış fiyatı
- Minimum stok
- Açıklama

---

## 2. ÖLÇÜ / PLAKA BAZLI STOK

Sadece m³ bazlı stok tutmak yeterli değildir. Aynı süngerin farklı ölçü ve kalınlıkları ayrı stok olarak izlenmelidir.

Örneğin D32 Gri:

- 140 × 200 × 5 cm → 40 adet
- 140 × 200 × 8 cm → 25 adet
- 140 × 200 × 10 cm → 12 adet

Her satırın hem adet/plaka hem m³ karşılığı gösterilmeli.

Otomatik formül:

En(m) × Boy(m) × Kalınlık(m) × Adet = Toplam m³

Örnek: 140 × 200 × 10 cm, 10 adet → 1,40 × 2,00 × 0,10 × 10 = 2,80 m³

Sistem bunu otomatik hesaplamalıdır.

---

## 3. FABRİKADAN STOK GİRİŞİ

Fabrikadan mal geldiğinde "Yeni Alış / Stok Girişi" ekranı kullanılmalı.

Başlık:

- Tedarikçi
- Tarih
- Fatura no
- İrsaliye no
- Vade
- Açıklama

Ardından tek alış belgesine birden fazla ürün eklenebilmeli. Her satır şunları içermeli:

- Sünger çeşidi
- En
- Boy
- Kalınlık
- Adet
- Otomatik m³
- TL/m³ alış fiyatı
- Toplam ürün maliyeti

Bir alışta örneğin 10 farklı ölçü aynı anda girilebilmeli.

---

## 4. NAKLİYE VE GERÇEK MALİYET

Alış belgesine şunlar eklenebilmeli:

- Nakliye
- Hamaliye
- Diğer giderler

Bu giderler toplam alınan m³ miktarına otomatik dağıtılabilmeli.

Örnek:

- 100 m³ ürün = 300.000 TL
- Nakliye = 10.000 TL
- Gerçek toplam maliyet = 310.000 TL
- Gerçek ortalama maliyet = 3.100 TL/m³

Hem fabrika çıplak fiyatı hem gerçek maliyet ayrı ayrı saklanmalıdır.

---

## 5. PARTİ BAZLI STOK

Bu bölüm kritik önemdedir. Aynı sünger farklı tarihlerde farklı fiyatlardan alınabilir.

Örnek:

- 01.09.2026 — Beyaz Sünger — 100 m³ — 2.930 TL/m³
- 15.09.2026 — Beyaz Sünger — 50 m³ — 3.165 TL/m³

Bu iki alış birbirine karıştırılmamalıdır. Her fabrika alımı ayrı parti/lot olarak tutulmalıdır.

Her parti için şunlar görülebilmeli:

- Alış tarihi
- Tedarikçi
- Alış fiyatı
- Gerçek maliyet
- Giren m³
- Kalan m³
- Giren adet
- Kalan adet

---

## 6. MALİYET YÖNTEMİ

Varsayılan stok çıkış yöntemi **FIFO – İlk Giren İlk Çıkar** olmalıdır. Alternatif olarak **Ağırlıklı Ortalama Maliyet** seçilebilmelidir.

Satış gerçekleştirildiği anda hesaplanan maliyet satış kaydına sabitlenmelidir. Gelecekte fabrika fiyatı değişse bile geçmiş satışların kârı değişmemelidir.

---

## 7. SATIŞ EKRANI

"Yeni Satış" ekranı çok hızlı kullanılmalıdır. Önce müşteri seçilsin, ardından ürünler eklensin.

Her satır şunları içersin:

- Sünger çeşidi
- En
- Boy
- Kalınlık
- Adet
- m³
- Liste fiyatı
- TL/m³ satış fiyatı
- İskonto %
- Net satış fiyatı
- Toplam tutar

Satış sırasında mevcut stok anlık gösterilsin. Örnek:

D32 Gri – 140×200×10 → Mevcut: 32 adet, 8,96 m³

Stokta olmayan ürün satılmaya çalışılırsa uyarı ver ve yetkisiz kullanıcının negatif stoğa düşmesine izin verme.

---

## 8. SATIŞ KÂRLILIĞI

Her satış için sistem şunları otomatik hesaplasın:

- Satış tutarı
- Mal maliyeti
- Brüt kâr TL
- Kâr marjı %
- Maliyet üzerine kâr oranı %

Bu iki yüzde birbirine karıştırılmamalıdır. Örnek:

- Maliyet = 2.930 TL
- Satış = 3.200 TL
- Kâr = 270 TL
- Maliyet üzerine getiri = 270 / 2.930 × 100
- Satış kâr marjı = 270 / 3.200 × 100

İkisini ayrı ayrı göster.

---

## 9. CARİ HESAP

Her müşteri için cari hesap tutulmalıdır.

Müşteri kartı şunları içermelidir:

- Firma adı
- Yetkili
- Telefon
- Vergi dairesi
- Vergi numarası
- Adres
- Özel iskonto oranı
- Ödeme vadesi
- Cari bakiye
- Açıklama

Müşteri hesabında kronolojik hareketler gösterilsin:

- 01.09 – Satış → +120.000 TL
- 05.09 – Tahsilat → -50.000 TL
- 12.09 – Satış → +80.000 TL

Güncel bakiye "150.000 TL BORÇ" şeklinde otomatik hesaplanmalıdır.

---

## 10. TAHSİLAT

Müşteriden ödeme geldiğinde "Yeni Tahsilat" ekranı kullanılmalı.

Alanlar:

- Müşteri
- Tarih
- Tutar
- Ödeme yöntemi: Nakit, Havale/EFT, Kredi kartı, Çek, Diğer
- Açıklama

Tahsilat otomatik olarak cari bakiyeden düşmelidir. Satış yapılması stok ve cari hesabı aynı anda güncellemelidir.

---

## 11. VADE TAKİBİ

Vadeli satışlar ayrıca takip edilmelidir. Dashboard üzerinde "Vadesi Geçen Alacaklar" kartı bulunmalı. Örnek:

- ABC Mobilya — 125.000 TL — 7 gün gecikmiş
- XYZ Mobilya — 82.500 TL — 2 gün gecikmiş

---

## 12. TEDARİKÇİ / FABRİKA CARİSİ

Sadece müşterileri değil fabrikaya olan borçları da takip et. Tedarikçi kartında şunlar gösterilsin:

- Toplam alış
- Yapılan ödeme
- Kalan borç
- Vadesi yaklaşan ödeme
- Geçmiş alışlar

Böylece sistem hem ALACAKLAR hem BORÇLAR tarafını takip edebilsin.

---

## 13. FİYAT LİSTESİ SİSTEMİ

Beyaz Sünger ana baz fiyat olarak kullanılabilsin.

Başlangıç katsayıları:

| Ürün | Katsayı |
|---|---|
| Beyaz Sünger | 1,00 |
| D22 Gri | 1,40 |
| D28 Gri | 1,71 |
| D32 Gri | 1,91 |
| D35 Sert | 2,24 |
| D35 Yumuşak | 2,24 |
| D35 140×240 | 2,24 |
| Kuş Tüyü | 1,56 |
| 30 Dream Soft | 1,83 |
| HR35 | 2,56 |
| HR35 140×240 | 2,56 |
| Eko Gri D18 | 1,23 |

Bu katsayılar yönetici tarafından değiştirilebilsin.

Yönetici sadece "Beyaz Sünger Baz Fiyatı = 3.500 TL/m³" girdiğinde diğer süngerlerin fiyatları otomatik hesaplanabilsin.

Formül: Ürün m³ fiyatı = Beyaz Sünger Baz Fiyatı × Ürün Katsayısı

Fiyat değişikliğinde geçmiş satışların ve geçmiş alışların fiyatlarını değiştirme. Yeni fiyat listesi versiyonu oluştur.

---

## 14. OTOMATİK PLAKA FİYATI

m³ fiyatından plaka fiyatını otomatik hesapla.

Formül: En(m) × Boy(m) × Kalınlık(m) × m³ fiyatı

Örneğin kullanıcı D32 Gri 140×200×10 seçtiğinde sistem hem TL/m³ hem TL/plaka fiyatını gösterebilmeli.

---

## 15. FİYAT TEKLİFİ

Müşteriye satış yapılmadan önce teklif hazırlanabilsin. Teklif şunları içersin:

- Müşteri
- Ürün
- Ölçü
- Adet
- m³
- Birim fiyat
- İskonto
- Toplam
- KDV
- Genel toplam
- Teklif geçerlilik tarihi

Teklif tek butonla satışa dönüştürülebilsin. Teklif oluşturulması stoktan ürün düşmemelidir.

---

## 16. STOK SAYIMI

Fiziksel depo sayımı yapılabilmeli. Sistem stoğu şöyle gösterebilmeli:

D32 140×200×10 — Sistem: 32 adet — Fiziksel: 30 adet — Fark: -2 adet

Sayım farkı için ayrı stok düzeltme hareketi oluşturulmalı. Geçmiş kayıt doğrudan değiştirilmemelidir.

---

## 17. FİRE / HASAR

Sünger hasarlı, kirlenmiş, kesilmiş, numune verilmiş veya fire olabilir. Bunlar satış olarak gösterilmemelidir.

"Stok Düzeltme / Fire" ekranı oluştur. Her fire işleminde neden belirtilmesi zorunlu olsun.

---

## 18. DASHBOARD

Ana ekran işletmenin durumunu birkaç saniyede anlatmalıdır.

Üst kartlar:

- TOPLAM STOK (m³)
- STOK MALİYETİ (TL)
- STOK SATIŞ DEĞERİ (TL)
- BU AY SATIŞ (TL)
- BU AY BRÜT KÂR (TL)
- MÜŞTERİLERDEN ALACAK (TL)
- TEDARİKÇİ BORCU (TL)
- VADESİ GEÇEN (TL)

Alt bölüm:

- Son satışlar
- Son alışlar
- Son tahsilatlar
- Kritik stoklar
- En çok satılan süngerler
- En yüksek ciro yapan müşteriler
- Aylık ciro grafiği
- Aylık brüt kâr grafiği
- Stok dağılımı

---

## 19. MÜŞTERİ ANALİZİ

Her müşterinin detay ekranında şunlar gösterilsin:

- Toplam satış
- Toplam m³
- Toplam tahsilat
- Güncel borç
- Ortalama ödeme süresi
- Son satış
- En çok aldığı sünger
- Bu müşteriden elde edilen brüt kâr

---

## 20. ÜRÜN ANALİZİ

Her sünger çeşidi için şunlar gösterilsin:

- Toplam alınan m³
- Toplam satılan m³
- Mevcut m³
- Mevcut adet
- Ortalama maliyet
- Ortalama satış fiyatı
- Toplam ciro
- Toplam brüt kâr
- Son alış fiyatı
- Son satış fiyatı

---

## 21. HIZLI ARAMA

Uygulamanın üst kısmında global arama alanı olsun.

"D32" yazıldığında D32 stokları, alışları ve satışları bulunabilsin.

Müşteri adı yazıldığında müşterinin cari hesabı, satışları ve tahsilatları bulunabilsin.

---

## 22. MOBİL KULLANIM

Uygulamanın telefon versiyonu özellikle önemlidir. Telefondan birkaç dokunuşla şunlar yapılabilsin:

- Stok kontrolü
- Satış girişi
- Fabrika girişi
- Tahsilat girişi
- Müşteri borç kontrolü
- Fiyat kontrolü

Ana mobil ekranda büyük hızlı işlem butonları bulunsun:

- + SATIŞ
- + STOK GİRİŞİ
- + TAHSİLAT
- STOK SORGULA
- CARİ SORGULA

---

## 23. YETKİLENDİRME

İki temel kullanıcı tipi: YÖNETİCİ ve PERSONEL.

Yönetici her şeyi görebilir.

Personel için ayrı ayrı yetkilendirilebilecek alanlar:

- Alış fiyatını görebilir
- Maliyeti görebilir
- Kârı görebilir
- Satış fiyatını değiştirebilir
- Stok girişi yapabilir
- Satış yapabilir
- Tahsilat girebilir
- Cari bakiyeyi görebilir
- İşlem iptal edebilir

---

## 24. İŞLEM GÜVENLİĞİ

Finansal ve stok kayıtları doğrudan silinmemelidir. Hatalı kayıt İPTAL / TERS HAREKET oluşturularak düzeltilmelidir.

Audit log tutulmalıdır. Örnek:

17.09.2026 – 14:32 — Ahmet — D32 satış fiyatını 3.200 TL → 3.250 TL değiştirdi.

---

## 25. RAPORLAR

Şu raporlar hazırlanabilsin:

- Günlük satış
- Haftalık satış
- Aylık satış
- Yıllık satış
- Alış raporu
- Stok raporu
- Stok hareket raporu
- Fire raporu
- Kârlılık raporu
- Müşteri raporu
- Cari raporu
- Tahsilat raporu
- Tedarikçi borç raporu
- Vadesi geçen alacaklar
- Ürün bazlı kârlılık

Excel ve PDF dışa aktarımı desteklensin.

---

## 26. VERİTABANI MİMARİSİ

Profesyonel ilişkisel veritabanı kullan.

Minimum tablolar:

- users, roles, permissions
- products, product_variants, price_lists, price_list_items
- suppliers, customers
- purchase_orders, purchases, purchase_items, inventory_batches
- sales_quotes, sales, sale_items
- stock_movements, stock_adjustments
- customer_ledger, supplier_ledger, collections, supplier_payments
- expenses, audit_logs

Veritabanında para için FLOAT kullanma. DECIMAL / NUMERIC veri tipi kullan. m³ miktarlarında yüksek hassasiyet kullan.

---

## 27. TRANSACTION GÜVENLİĞİ

Bir satış gerçekleştiğinde şu adımlar tek database transaction içerisinde gerçekleşsin:

1. Satış kaydı
2. Sale items
3. Stok çıkışı
4. FIFO maliyet tüketimi
5. Müşteri cari borcu
6. Kâr kaydı

Herhangi biri başarısız olursa hiçbir kayıt tamamlanmış sayılmasın.

Aynı şekilde alış işleminde alış + stok + parti + tedarikçi carisi tek transaction içerisinde işlensin.

---

## 28. YEDEKLEME

Veritabanı otomatik yedeklenmeli. Günlük yedek oluştur. Yanlış işlem veya teknik problem nedeniyle ticari verilerin kaybolmasını engelle.

---

## 29. TASARIM

Arayüz klasik muhasebe programları gibi karmaşık görünmesin.

Tasarım dili: modern, minimal, premium, kurumsal, hızlı, temiz.

Masaüstünde sol menü: Dashboard, Satış, Alış, Stok, Cari Hesaplar, Müşteriler, Tedarikçiler, Tahsilatlar, Fiyat Listeleri, Raporlar, Ayarlar.

Telefon kullanımında alt navigasyon ve büyük hızlı işlem butonları kullan.

---

## 30. ÖNEMLİ İŞ KURALLARI

1. Geçmiş alış fiyatı sonradan değişmemeli.
2. Geçmiş satış fiyatı sonradan değişmemeli.
3. Geçmiş satış kârı yeni fabrika fiyatından etkilenmemeli.
4. Stok hareketlerinin tamamı izlenebilir olmalı.
5. Stok hem adet/plaka hem m³ olarak tutulmalı.
6. Aynı ürünün farklı ölçüleri ayrı stoklanmalı.
7. Negatif stok varsayılan olarak yasak olmalı.
8. Para hesaplamalarında floating-point hatası olmamalı.
9. Satış ve stok hareketleri transaction ile güvence altına alınmalı.
10. Finansal kayıtlar doğrudan silinmemeli.
11. Fiyat listelerinin geçmiş versiyonları korunmalı.
12. Kullanıcıların yaptığı kritik değişiklikler audit log'a kaydedilmeli.

---

## 31. GELİŞTİRME SIRASI

Kodlamaya doğrudan rastgele başlama. Önce:

1. Sistem mimarisini tasarla.
2. Veritabanı ER diyagramını oluştur.
3. Tablo ve ilişkileri oluştur.
4. Kullanıcı akışlarını belirle.
5. Dashboard tasarla.
6. Stok giriş modülünü geliştir.
7. Stok yönetimini geliştir.
8. Satış modülünü geliştir.
9. FIFO maliyet sistemini geliştir.
10. Cari hesap ve tahsilatı geliştir.
11. Fiyat listesi modülünü geliştir.
12. Raporlamayı geliştir.
13. Yetkilendirmeyi geliştir.
14. Mobil arayüzü optimize et.
15. Test verileri oluştur.
16. Sistemi uçtan uca test et.

Test senaryosu:

- Fabrikadan farklı fiyatlarla iki ayrı Beyaz Sünger partisi satın al.
- Bunları farklı ölçü ve kalınlıklarda stoğa ekle.
- Bir müşteriye vadeli satış yap.
- FIFO maliyetinin doğru hesaplandığını doğrula.
- Satış sonrası stoğun doğru düştüğünü doğrula.
- Müşteri cari borcunun arttığını doğrula.
- Kısmi tahsilat gir.
- Cari bakiyenin doğru düştüğünü doğrula.
- Yeni fabrika fiyatı gir.
- Geçmiş satışın maliyet ve kâr rakamlarının değişmediğini doğrula.
- Stok sayımı yap ve fire oluştur.
- Tüm hareketlerin audit log ve stok hareket geçmişinde bulunduğunu doğrula.

Sonuç olarak ortaya demo ekranlardan oluşan bir prototip değil, gerçek ticari verilerin güvenli şekilde saklanabildiği ve günlük kullanılabilecek çalışan bir uygulama çıkar.
