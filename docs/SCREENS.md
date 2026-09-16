# Ekran Listesi

Tasarım dili: sade, premium, kurumsal. Material 3, nötr tonlar, **tek vurgu rengi**.
Rakamlar tabular. Açık/koyu tema. Dokunma alanı ≥ 48 dp. Para/miktar alanlarında sayısal
klavye. Boş, yükleniyor ve hata durumları Türkçe ve anlaşılır.

Arayüz metinleri **Türkçe**; kod ve rota adları İngilizce.

Faz sütunu: hangi fazda hayata geçtiğini gösterir.

---

## 1. Kurulum ve güvenlik

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| Karşılama · **Yeni başla / Yedekten geri yükle** | `/setup` | 2 | Telefon değişikliği buradan |
| Kullanıcı adı ve PIN (parmak izi opsiyonel) | `/setup/user` | 2 | |
| **Yedek şifresi** belirleme | `/setup/backup-password` | 2 | En az 8 karakter, iki kez; unutma uyarısı |
| Firma bilgileri ve logo | `/setup/company` | 2 | PDF başlığında kullanılır |
| KDV ve varsayılan fiyat modu | `/setup/vat` | 2 | |
| **Maliyet yöntemi** seçimi | `/setup/costing` | 2 | İlk stok hareketinden sonra kilitlenir |
| Google Drive bağlama | `/setup/drive` | 2 | Atlanabilir |
| Açılış işlemleri | `/setup/opening` | 2 | Atlanabilir, sonra da yapılabilir |
| Uygulama kilidi (PIN / parmak izi) | `/lock` | 2 | Her açılışta |

## 2. Ana kabuk

Alt navigasyon: **Ana Sayfa · Stok · (+) · Cari · Menü**
Üst çubuk: **global arama · maliyeti gizle (göz) · yedek durumu**

| Ekran | Rota | Faz | İçerik |
|---|---|---|---|
| **Ana Sayfa** | `/` | 2 | Yedek durum bandı · büyük hızlı işlem butonları (SPEC §22) · kartlar (SPEC §18): Toplam stok m³, Stok maliyeti, Stok satış değeri, Bu ay satış, Bu ay brüt kâr, Müşterilerden alacak, Tedarikçi borcu, Vadesi geçen · **+ Kasa & Banka · Çek/Senet Portföyü · Kesimdeki Mal · Sermaye Dağılımı** |
| **(+) hızlı işlem** | modal | 2 | Satış · Stok Girişi · Tahsilat · Ödeme · Kesime Gönder |
| **Menü** | `/menu` | 2 | Aşağıdaki tüm bölümler |
| Global arama | `/search` | 3 | "D32" → stok/alış/satış; müşteri adı → cari/satış/tahsilat (SPEC §21) |

**Sermaye Dağılımı** = Stok + Kesimde + Alacak + Portföy + Kasa/Banka − Tedarikçi Borcu − Verilen Evrak

**Ana sayfa alt bölümü (SPEC §18):** son satışlar, son alışlar, son tahsilatlar, kritik
stoklar, en çok satılan süngerler, en yüksek ciro yapan müşteriler, aylık ciro grafiği,
aylık brüt kâr grafiği, stok dağılımı. *(Grafikler Faz 4)*

## 3. Stok

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| **Stok matrisi** | `/stock` | 2 | Çeşit seçilince **ölçü satır × kalınlık sütun**; hücrede adet ve m³. Kritik stok vurgulu |
| "Kesimde" sekmesi | `/stock?loc=KESIMDE` | 3 | Ayrı sekme |
| Varyant detayı: partiler ve hareket geçmişi | `/stock/variant/:id` | 2 | Hücreye dokununca |
| Parti detayı | `/stock/batch/:id` | 2 | Giren/kalan adet-m³, çıplak ve gerçek maliyet |
| Ürün kartları | `/products` · `/products/:id` | 2 | SPEC §1 alanları |
| Stok sayımı | `/stock-count` | 3 | DRAFT → onay (riskli işlem) |
| Fire / hasar | `/adjustments` | 3 | Neden zorunlu |

## 4. Satış tarafı

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| **Hızlı satış** | `/sale/new` | 2 | Hedef < 30 saniye (`docs/FLOWS.md` §2) |
| Satışlar listesi | `/sales` | 2 | Tarih/müşteri filtresi |
| Satış detayı | `/sales/:id` | 2 | Satırlar, maliyet ve kâr (gizle modu kapalıysa), iptal, iade |
| Satış iadesi | `/sales/:id/return` | 2 | Satılanı aşamaz |
| Teklifler | `/quotes` · `/quotes/new` | 3 | Stok düşmez |
| Teklifi satışa dönüştür | `/quotes/:id/convert` | 3 | Tek buton |
| İadeler | `/returns` | 2 | Satış ve alış iadeleri |

## 5. Alış tarafı

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| **Stok girişi (alış)** | `/purchase/new` | 2 | Çok satırlı; masraflar ve dağıtım anahtarı |
| Alışlar listesi / detayı | `/purchases` · `/purchases/:id` | 2 | |
| Sonradan masraf ekle | `/purchases/:id/expense` | 2 | Stok/satılmış ayrımı otomatik |
| Alış iadesi | `/purchases/:id/return` | 2 | |
| Tedarikçiler | `/suppliers` · `/suppliers/:id` | 2 | Toplam alış, ödeme, kalan borç, vadesi yaklaşan (SPEC §12) |

## 6. Cari ve finans

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| **Cari listesi** | `/customers` | 2 | Bakiye, vadesi geçen rozeti |
| Müşteri kartı | `/customers/:id` | 2 | SPEC §9 alanları + risk limiti |
| **Cari ekstre** | `/customers/:id/ledger` | 2 | Kronolojik hareketler, PDF |
| Tahsilat | `/collections/new` | 2 | Eşleştirme: otomatik veya elle |
| Tedarikçi ödemesi | `/payments/new` | 2 | |
| **Çek & Senet** | `/instruments` | 2 | Alınan/verilen, vade takvimi, portföy toplamı |
| Evrak detayı ve durum değişikliği | `/instruments/:id` | 2 | Durum makinesi |
| **Kasa & Banka** | `/accounts` · `/accounts/:id` | 2 | Hesap hareketleri |
| Virman | `/accounts/transfer` | 2 | |
| Giderler | `/expenses` | 4 | Kategorili |
| Vade takibi ve bildirimler | `/due` | 3 | Vadeden bir gün önce yerel bildirim |

## 7. Kesim

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| Kesim emirleri | `/cutting` | 3 | Durum filtreli |
| Kesime gönder | `/cutting/new` | 3 | Kaynak partiler, planlanan hedefler |
| Kesimden dönüş | `/cutting/:id/return` | 3 | Kısmi dönüş destekli |
| Kesim emri PDF (kesimhaneye ölçü listesi) | — | 3 | Paylaşılabilir |

## 8. Fiyat listeleri

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| Fiyat listeleri | `/price-lists` | 2 | Versiyon geçmişi, arşiv erişilebilir |
| Yeni versiyon | `/price-lists/new` | 2 | Baz fiyat + katsayı + yuvarlama kuralı |
| **Eski/yeni karşılaştırma önizlemesi** | `/price-lists/new/preview` | 2 | Onaydan önce |

## 9. Yedekleme

| Ekran | Rota | Faz | Not |
|---|---|---|---|
| **Yedek Al** | `/backup` | 2 | Ana sayfada + Menü'de belirgin buton |
| **Yedekten Yükle** | `/restore` | 2 | Kaynak → şifre → doğrulama → önizleme → tek onay |
| **Yedekler** | `/backups` | 2 | Yerel + Drive listesi; paylaş, geri yükle, sil |

## 10. Raporlar *(Faz 4)*

SPEC §25'in tamamı, tarih/müşteri/ürün filtreli, Excel ve PDF dışa aktarımlı:

Günlük · Haftalık · Aylık · Yıllık satış · Alış raporu · Stok raporu · Stok hareket raporu ·
Fire raporu · **Kârlılık raporu** (brüt kâr, fire, maliyet farkları, giderler, net kâr) ·
Müşteri raporu · Cari raporu · Tahsilat raporu · Tedarikçi borç raporu ·
Vadesi geçen alacaklar · Ürün bazlı kârlılık

Ek olarak: **Müşteri analizi** (SPEC §19), **Ürün analizi** (SPEC §20), evrak vade raporu,
kesim raporu.

## 11. Ayarlar

| Bölüm | Faz | İçerik |
|---|---|---|
| Firma | 2 | Ad, adres, vergi bilgileri, logo |
| KDV | 2 | Varsayılan oran, seçilebilir oranlar, varsayılan fiyat modu |
| Maliyet yöntemi | 2 | Kilitliyse gerekçe gösterilir; değişiklik riskli işlem |
| **Yedek ve Drive** | 2 | Yedek şifresi değiştir, otomatik yedek saati, Wi-Fi seçeneği, uyarı eşiği, Drive bağla |
| PIN / parmak izi | 2 | |
| Audit Log | 2 | Kronolojik, filtreli |
| **Tutarlılık Kontrolü** | 2 | `checkIntegrity()` elle çalıştırma ve rapor |
| Uygulama sürümü ve değişiklik notları | 5 | |
| Geliştirici menüsü (gizli) | 1 | **Tek** demo veri kaynağı; üretimde erişilemez |

---

## Çapraz kesen davranışlar

- **Maliyeti gizle:** üst çubukta göz ikonu. Açıkken maliyet, kâr ve alış fiyatları tüm
  ekranlarda gizlenir; kapatmak için **PIN** gerekir.
- **Yedek durum bandı:** ana sayfanın üstünde sürekli. Cihaz dışı yedek 3 günden eskiyse
  kırmızı uyarı + "Şimdi yedekle".
- **Risk limiti:** bakiye + vadesi gelmemiş alınan evrak limiti aşarsa satışta uyarı ve onay.
- **PDF ve paylaşım:** teklif, satış/sevk fişi, cari ekstre, kesim emri → WhatsApp'a doğrudan.
- **Mock veri yok:** hiçbir ekran örnek veriyle doldurulmaz; boş durum gösterilir.
