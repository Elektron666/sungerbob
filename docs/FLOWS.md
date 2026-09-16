# İş Akışları

Her akış **tek bir Drift transaction**'ıdır ve form açılışında üretilen UUID ile
`command_log`'a yazılır (idempotency, `docs/ARCHITECTURE.md` §7).
Ortak ön koşul: işlem sürerken Kaydet butonu devre dışıdır.

Gösterim kısaltmaları: **SM** = `stock_movements`, **CA** = `cost_allocations`,
**CL** = `customer_ledger`, **SL** = `supplier_ledger`, **AM** = `account_movements`.

---

## 1. Alış (stok girişi)

```mermaid
flowchart TD
    A[Tedarikçi, tarih, vade, fatura/irsaliye no, KDV modu] --> B[Satırlar: varyant, adet, TL/m3]
    B --> C[m3 ve satır tutarları Decimal ile hesaplanır]
    C --> D[Masraflar: nakliye, hamaliye, diğer + dağıtım anahtarı]
    D --> E{Kaydet}
    E --> T[TRANSACTION]
    T --> T1[document_sequences: ALS-YYYY-NNNNNN]
    T1 --> T2[purchases + purchase_items]
    T2 --> T3[Her satır için inventory_batches: çıplak TL/m3]
    T3 --> T4[Masraf m3 veya tutar oranında dağıtılır → gerçek TL/m3]
    T4 --> T5[SM: PURCHASE_IN, pozitif adet/m3]
    T5 --> T6[SL: + brüt tutar, vade ile]
    T6 --> T7[command_log + audit_logs]
    T7 --> OK[COMMIT]
```

**Kurallar**

- Masraf dağıtımında kuruş farkı **son partiye** eklenir; `Σ pay = masraf` değişmezi.
- Çıplak fabrika fiyatı ve gerçek maliyet ayrı saklanır (SPEC §4).
- Cariye **brüt**, partiye **KDV hariç** tutar gider.

### 1.1 Sonradan gelen masraf

```mermaid
flowchart LR
    A[Masraf, partinin toplam GİRİŞ m3'üne bölünür] --> B{Partinin durumu}
    B -->|stokta kalan m3| C[real_unit_cost_m3'e eklenir]
    B -->|satılmış / firelenmiş m3| D[cost_adjustments: dönem maliyet farkı]
    C --> E[purchase_expense_allocations'a denetim izi]
    D --> E
```

Geçmiş satış satırları **değişmez** (BRIEF §3.7, SPEC §30.3).

---

## 2. Hızlı satış

Hedef: tipik satış **30 saniyenin altında**.

```mermaid
flowchart TD
    A[Müşteri ara: son müşteriler üstte, bakiye + limit + KDV modu rozeti] --> B[Sünger çeşidi çipleri]
    B --> C[Ölçü seçimi: stokta olanlar önce, adet ve m3 ile]
    C --> D[Adet stepper → m3, liste fiyatı, iskonto, net TL/m3, TL/plaka otomatik]
    D --> E{Risk limiti aşılıyor mu}
    E -->|Evet| E1[Uyarı + açık onay]
    E -->|Hayır| F
    E1 --> F[Özet: KDV hariç, KDV, genel toplam, vade, maliyet ve kâr]
    F --> G[Peşin tahsilat: nakit/havale/kart/çek/senet - opsiyonel]
    G --> H{Kaydet}
    H --> T[TRANSACTION]
    T --> T1[document_sequences: STS-YYYY-NNNNNN]
    T1 --> T2[sales + sale_items]
    T2 --> T3{Negatif stok kontrolü}
    T3 -->|Yetersiz| X[ABORT: satış kaydedilmez]
    T3 -->|Yeterli| T4[FIFO: parti tüketimi sırayla]
    T4 --> T5[CA: her parti için maliyet satırı + sequence_no]
    T5 --> T6[sale_items.cost_total SABİTLENİR]
    T6 --> T7[SM: SALE_OUT, negatif adet/m3]
    T7 --> T8[inventory_batches.remaining_* güncellenir]
    T8 --> T9[CL: + brüt tutar, vade ile]
    T9 --> T10{Peşin tahsilat var mı}
    T10 -->|Evet| T11[collections + CL alacak + AM giriş + varsa instruments]
    T10 -->|Hayır| T12
    T11 --> T12[command_log + audit_logs]
    T12 --> OK[COMMIT → WhatsApp'a fiş paylaşma seçeneği]
```

**Maliyet yöntemi ağırlıklı ortalama ise:** fiziksel tüketim yine FIFO'dur, ancak `CA`'ya
yazılan birim maliyet, **ürün bazında** ana depodaki tüm kalan partilerin m³ ağırlıklı
ortalamasıdır (D-11).

---

## 3. Satış iadesi

```mermaid
flowchart TD
    A[Orijinal satış seçilir] --> B[İade edilecek satırlar ve adetler]
    B --> C{Adet kontrolü}
    C -->|Satılanı aşıyor| X[ABORT]
    C -->|Geçerli| T[TRANSACTION]
    T --> T1[IAD-YYYY-NNNNNN]
    T1 --> T2[sale_returns + sale_return_items]
    T2 --> T3[CA sequence_no TERSİNDEN okunur]
    T3 --> T4[Mal, çıktığı partilere AYNI maliyetle döner]
    T4 --> T5[SM: SALE_RETURN_IN, pozitif]
    T5 --> T6[remaining_* geri artar]
    T6 --> T7[CL: − brüt tutar]
    T7 --> T8[command_log + audit_logs]
    T8 --> OK[COMMIT]
```

Orijinal satış **değişmez**; kâr raporunda iade ayrı görünür.
Alış iadesi aynı mantıkla ters yönde çalışır (`PURCHASE_RETURN_OUT`, `SL` alacak).

---

## 4. İptal (ters hareket)

```mermaid
flowchart LR
    A[İptal edilecek belge] --> B{Zaten iptal mi}
    B -->|Evet| X[ABORT: bir hareket iki kez ters çevrilemez]
    B -->|Hayır| T[TRANSACTION]
    T --> T1[Belgenin her hareketi için ters kayıt: reversal_of_id]
    T1 --> T2[Stok, cari, kasa ve portföy etkileri geri alınır]
    T2 --> T3[Belge başlığı: status=CANCELLED, cancelled_at, cancel_reason]
    T3 --> T4[audit_logs]
    T4 --> OK[COMMIT]
```

**Hiçbir kayıt silinmez** (SPEC §24, §30.10). Orijinal satırlar yerinde kalır.

---

## 5. Tahsilat ve eşleştirme

```mermaid
flowchart TD
    A[Müşteri, tarih, tutar, yöntem] --> B{Yöntem}
    B -->|Nakit/Havale/Kart| C[Kasa veya banka hesabı seçilir]
    B -->|Çek/Senet| D[Evrak bilgileri: no, banka, keşideci, vade]
    C --> E[Eşleştirme]
    D --> E
    E --> E1[Varsayılan: vadesi en erken açık belgeler kapatılır]
    E --> E2[Elle eşleştirme: is_manual]
    E1 --> T[TRANSACTION]
    E2 --> T
    T --> T1[THS-YYYY-NNNNNN]
    T1 --> T2[collections]
    T2 --> T3[payment_allocations: belge bazında]
    T3 --> T4[CL: − tutar]
    T4 --> T5{Nakit/havale/kart mı}
    T5 -->|Evet| T6[AM: hesaba giriş]
    T5 -->|Hayır| T7[instruments: PORTFOLIO + instrument_events]
    T6 --> T8[command_log + audit_logs]
    T7 --> T8
    T8 --> OK[COMMIT]
```

Vadesi geçen alacak, gecikme günü ve **ortalama ödeme süresi** `payment_allocations`
üzerinden hesaplanır (SPEC §11, §19). Tedarikçi ödemesi birebir aynı mantıktadır.

---

## 6. Çek / senet durum değişikliği

```mermaid
flowchart TD
    A[Evrak seçilir] --> B{Hedef durum geçerli mi}
    B -->|Hayır| X[ABORT: geçersiz geçiş]
    B -->|Evet| T[TRANSACTION]
    T --> T1[instrument_events: from_status → to_status]
    T1 --> T2{Geçiş türü}
    T2 -->|Tahsil edildi| C1[AM: banka hesabına giriş]
    T2 -->|Karşılıksız| C2[CL: ters kayıt, bakiye geri artar]
    T2 -->|Ciro| C3[SL: tedarikçi borcu azalır]
    T2 -->|İade| C4[CL: ters kayıt]
    T2 -->|Verilen ödendi| C5[AM: bankadan çıkış]
    C1 --> T3[instruments.current_status önbelleği]
    C2 --> T3
    C3 --> T3
    C4 --> T3
    C5 --> T3
    T3 --> T4[audit_logs]
    T4 --> OK[COMMIT]
```

Geçerli geçişler `docs/ERD.md` §9'daki iki durum makinesindedir. Ana sayfada bu hafta
vadesi gelen evrak listelenir; vade gününden **bir gün önce** yerel bildirim gider.

---

## 7. Stok sayımı

```mermaid
flowchart TD
    A[Konum seçilir, sistem stoğu listelenir] --> B[Fiziksel adetler girilir - DRAFT]
    B --> C[Fark raporu: varyant bazında +/− adet ve m3]
    C --> D{Onayla}
    D --> R[RİSKLİ İŞLEM: önce otomatik yedek]
    R --> T[TRANSACTION]
    T --> T1[SYM-YYYY-NNNNNN, status=APPLIED]
    T1 --> T2{Fark yönü}
    T2 -->|Eksik| T3[FIFO sırasıyla partilerden düş: COUNT_OUT + CA]
    T2 -->|Fazla| T4[COUNT_IN: son partinin birim maliyetiyle]
    T3 --> T5[remaining_* güncellenir]
    T4 --> T5
    T5 --> T6[audit_logs]
    T6 --> OK[COMMIT]
```

`DRAFT` iken stok **etkilenmez**. Geçmiş kayıt doğrudan değiştirilmez (SPEC §16).

---

## 8. Fire / hasar

```mermaid
flowchart LR
    A[Varyant, adet, ZORUNLU neden] --> T[TRANSACTION]
    T --> T1[FIR-YYYY-NNNNNN: stock_adjustments + items]
    T1 --> T2[FIFO sırasıyla partilerden düş: WASTE_OUT + CA]
    T2 --> T3[remaining_* güncellenir]
    T3 --> T4[audit_logs]
    T4 --> OK[COMMIT → kârlılık raporunda ayrı kalem]
```

Neden zorunludur (SPEC §17): `HASARLI`, `KESIM_FIRESI`, `NEM`, `DIGER`.

---

## 9. Kesim emri (fason)

### 9.1 Kesime gönder

```mermaid
flowchart TD
    A[Kesimhane, kaynak partiler ve adetler] --> B[Planlanan hedef ölçüler]
    B --> C[İsteğe bağlı: bağlı teklif/müşteri]
    C --> T[TRANSACTION]
    T --> T1[KSM-YYYY-NNNNNN, status=AT_CUTTER]
    T1 --> T2[SM: TRANSFER_OUT ana depodan]
    T2 --> T3[KESIMDE konumunda çocuk parti: aynı birim maliyet, parent_batch_id]
    T3 --> T4[SM: TRANSFER_IN Kesimde konumuna]
    T4 --> T5[cutting_order_sources]
    T5 --> T6[audit_logs]
    T6 --> OK[COMMIT]
```

Kesimdeki mal **satılamaz** (`locations.is_sellable = false`), stok değerinde ayrıca
görünür, maliyetini aynen taşır.

### 9.2 Kesimden dönüş

```mermaid
flowchart TD
    A[Gerçekleşen hedef varyantlar ve adetler] --> B[Kesim ücreti + nakliye]
    B --> C{Hedef toplam m3 ≤ kaynak m3}
    C -->|Hayır| X[ABORT]
    C -->|Evet| T[TRANSACTION]
    T --> T1[Toplam maliyet = kaynak + kesim ücreti + nakliye]
    T1 --> T2[Hedeflere m3 oranında dağıtılır, kuruş farkı son satıra]
    T2 --> T3[SM: CUTTING_OUT Kesimde konumundan]
    T3 --> T4[Hedef partiler ana depoya: received_at = KAYNAĞIN tarihi]
    T4 --> T5[SM: CUTTING_IN]
    T5 --> T6[Kesim firesi = kaynak m3 − hedef m3, ayrı maliyet YAZILMAZ]
    T6 --> T7[SL: kesimhane carisine brüt kesim ücreti]
    T7 --> T8[status: PARTIAL veya COMPLETED]
    T8 --> T9[audit_logs]
    T9 --> OK[COMMIT]
```

Kısmi dönüş desteklenir. Bağlı teklif varsa tamamlanınca **"Satışa dönüştür"** kısayolu çıkar.

---

## 10. Açılış işlemleri

```mermaid
flowchart TD
    A{Açılış türü} --> B[Stok: varyant, adet, birim maliyet]
    A --> C[Müşteri/tedarikçi bakiyesi: tutar + vade]
    A --> D[Kasa/banka bakiyesi]
    A --> E[Portföydeki evrak]
    B --> T[TRANSACTION]
    C --> T
    D --> T
    E --> T
    T --> T1[opening_balances kaydı]
    T1 --> T2[Stok: OPENING partisi + SM OPENING_IN]
    T2 --> T3[Cari: CL/SL doc_type=OPENING, vade ile]
    T3 --> T4[Kasa: AM type=OPENING]
    T4 --> T5[Evrak: instruments PORTFOLIO + instrument_events]
    T5 --> T6[audit_logs]
    T6 --> OK[COMMIT]
```

Açılış cari satırları tahsilat eşleştirmesinde **hedef olabilir** (`target_type = OPENING`).

---

## 11. Fiyat listesi versiyonu

```mermaid
flowchart LR
    A[Yeni baz TL/m3] --> B[Katsayılarla ürün fiyatları hesaplanır]
    B --> C[Yuvarlama kuralı: yok / 1 / 5 / 10 TL]
    C --> D[Ürün bazlı elle ezme]
    D --> E[ÖNİZLEME: eski ↔ yeni karşılaştırma]
    E --> F{Onayla}
    F --> T[TRANSACTION]
    T --> T1[Yeni price_lists versiyonu: ACTIVE]
    T1 --> T2[Önceki versiyon: ARCHIVED, SİLİNMEZ]
    T2 --> T3[audit_logs]
    T3 --> OK[COMMIT]
```

Geçmiş satışlar kendi versiyonuna referans verir (`sale_items.price_list_id`), bu yüzden
fiyat değişikliği geçmiş kârı **etkilemez** (SPEC §13, §30.11 · Altın Senaryo adım 5).

---

## 12. Yedek al / yedekten yükle

Ayrıntılı akış, dosya formatı ve hata senaryoları: **`docs/BACKUP.md`**.

```mermaid
flowchart LR
    subgraph AL[Yedek Al]
        A1[Yazma kilidi + checkpoint] --> A2[Tutarlı anlık görüntü + manifest]
        A2 --> A3[AES-256-GCM]
        A3 --> A4[Drive'a yükle veya Paylaş]
        A4 --> A5[backup_log]
    end
    subgraph YUKLE[Yedekten Yükle]
        B1[Kaynak + şifre] --> B2[Doğrula: şifre, SHA-256, şema]
        B2 --> B3[Önizleme + karşılaştırma]
        B3 --> B4[Güvenlik yedeği]
        B4 --> B5[Geçici dosyada aç + migration + checkIntegrity]
        B5 --> B6[ATOMİK değişim]
        B6 --> B7[Yeniden başlat]
    end
```

**Değişmez:** atomik değişime gelinmediği sürece mevcut veriye hiç dokunulmaz.
