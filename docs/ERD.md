# Veri Modeli (ERD)

Faz 0 çıktısı. Ölçekler, kısıtlar ve trigger kuralları `docs/ARCHITECTURE.md` Bölüm 3 ve 6'da.

**Okuma notları**

- Tüm `id` kolonları **UUID v7** (`TEXT`). Sıralanabilir olduğu için hem birincil anahtar
  hem de zaman kırıcı (tie-breaker) olarak kullanılır.
- Tüm zaman damgaları **UTC epoch milisaniye** (`INTEGER`).
- Tüm sayısal değerler **sabit ölçekli INTEGER**: `money` = kuruş ×100, `price` = ×10.000,
  `vol` = m³ ×10⁶, `dim` = cm ×100, `rate` = % ×100, `pcs` = adet.
- 🔒 ile işaretli tablolar **append-only**'dir (UPDATE/DELETE trigger ile engellenir).
- Her iş kaydında `created_at`, `created_by` (users.id) ve `device_id` bulunur; diyagramlarda
  tekrar etmemek için yalnızca ilk tabloda gösterilmiştir.

## 0. SPEC Bölüm 26 ile uyum

`docs/SPEC.md` §26 "minimum tablolar" listesinin tamamı bu modelde karşılanır:

| SPEC §26 tablosu | Bu modelde | Not |
|---|---|---|
| `users`, `roles`, `permissions` | aynı | v1'de tek ADMIN, arayüz gizli |
| `products`, `product_variants` | aynı | |
| `price_lists`, `price_list_items` | aynı | |
| `suppliers`, `customers` | aynı | |
| `purchases`, `purchase_items` | aynı | |
| `purchase_orders` | **yok** | Sipariş akışı BRIEF'te hiç geçmiyor; v1 kapsamı dışı (D-16) |
| `inventory_batches` | aynı | |
| `sales_quotes`, `sales`, `sale_items` | aynı | SPEC adlandırması korundu |
| `stock_movements` | aynı | BRIEF §6'daki genişletilmiş kolon listesiyle |
| `stock_adjustments` | aynı | Fire/hasar ve stok düzeltme (SPEC §17); başlık + `stock_adjustment_items` |
| `customer_ledger`, `supplier_ledger` | aynı | |
| `collections`, `supplier_payments` | aynı | |
| `expenses` | aynı | `expense_categories` ile |
| `audit_logs` | aynı | |

BRIEF §6'nın ek tablolarının tamamı da modeldedir (`locations`, `settings`,
`document_sequences`, `command_log`, `cash_accounts`, `account_movements`,
`cost_allocations`, `payment_allocations`, `supplier_payment_allocations`, `sale_returns`,
`sale_return_items`, `purchase_returns`, `purchase_return_items`, `purchase_expenses`,
`cost_adjustments`, `stock_counts`, `stock_count_items`, `cutting_orders`,
`cutting_order_sources`, `cutting_order_results`, `instruments`, `instrument_events`,
`expense_categories`, `opening_balances`, `backup_log`).

**Tek sapma:** SPEC §26 "para için DECIMAL/NUMERIC kullan" diyor. SQLite'ta kesin ondalık tip
olmadığı için bunun yerine sabit ölçekli INTEGER kullanılır — SPEC'in asıl amacı olan
"floating-point hatası olmasın" (SPEC §30.8) kuralı böylece daha güçlü şekilde sağlanır.
Gerekçe: `docs/DECISIONS.md` D-02.

---

## 0.1 Seed: 12 ürün ve fiyat katsayıları (SPEC §1 + §13)

Baz ürün **Beyaz Sünger = 1,00**. Fiyat = baz TL/m³ × katsayı (SPEC §13).

| # | Ürün | Katsayı | `price_coefficient` |
|---|---|---|---|
| 1 | Beyaz Sünger | 1,00 | `10000` |
| 2 | D22 Gri | 1,40 | `14000` |
| 3 | D28 Gri | 1,71 | `17100` |
| 4 | D32 Gri | 1,91 | `19100` |
| 5 | D35 Sert | 2,24 | `22400` |
| 6 | D35 Yumuşak | 2,24 | `22400` |
| 7 | D35 140×240 | 2,24 | `22400` |
| 8 | Kuş Tüyü | 1,56 | `15600` |
| 9 | 30 Dream Soft | 1,83 | `18300` |
| 10 | HR35 | 2,56 | `25600` |
| 11 | HR35 140×240 | 2,56 | `25600` |
| 12 | Eko Gri D18 | 1,23 | `12300` |

7 ve 11 numaralı ürünler katsayı olarak 5/6 ve 10 ile aynıdır ama **ayrı ürünlerdir**
(müşteri kararı, BRIEF §1.6) ve kartlarında `default_width = 14000`,
`default_height = 24000` (140×240 cm) gelir.

---

## 1. Genel bakış

```mermaid
erDiagram
    SISTEM ||--o{ ANA_VERI : "kullanıcı, ayar, log"
    ANA_VERI ||--o{ STOK_MALIYET : "ürün, varyant, konum"
    STOK_MALIYET ||--o{ ALIS : "parti üretir"
    STOK_MALIYET ||--o{ SATIS : "parti tüketir"
    STOK_MALIYET ||--o{ KESIM : "transfer ve dönüş"
    STOK_MALIYET ||--o{ SAYIM_FIRE : "düzeltme ve fire"
    SATIS ||--o{ CARI : "borç yazar"
    ALIS ||--o{ CARI : "borç yazar"
    CARI ||--o{ TAHSILAT_ODEME : "kapatılır"
    TAHSILAT_ODEME ||--o{ KASA_BANKA : "para hareketi"
    TAHSILAT_ODEME ||--o{ EVRAK : "çek / senet"
    EVRAK ||--o{ KASA_BANKA : "tahsil / ödeme"
    ACILIS ||--o{ STOK_MALIYET : "açılış partisi"
    ACILIS ||--o{ CARI : "açılış bakiyesi"
    ACILIS ||--o{ EVRAK : "portföydeki evrak"
```

---

## 2. Sistem, kimlik ve log

```mermaid
erDiagram
    roles ||--o{ users : "sahiptir"
    roles ||--o{ role_permissions : ""
    permissions ||--o{ role_permissions : ""
    users ||--o{ audit_logs : "aktör"
    users ||--o{ command_log : "aktör"
    devices ||--o{ command_log : "kaynak"

    roles {
        uuid id PK
        text code UK "ADMIN | ACCOUNTANT"
        text name
    }
    permissions {
        uuid id PK
        text code UK "SALE_CREATE | COST_VIEW | ..."
        text description
    }
    role_permissions {
        uuid role_id PK_FK
        uuid permission_id PK_FK
    }
    users {
        uuid id PK
        text username UK
        text display_name
        uuid role_id FK
        text pin_hash "Argon2id/PBKDF2"
        text pin_salt
        bool biometric_enabled
        bool is_active
        int created_at
        text created_by
        text device_id
    }
    devices {
        uuid id PK
        text name "cihaz adı, yedek manifestinde geçer"
        int first_seen_at
        int last_seen_at
    }
    settings {
        text key PK
        text value "JSON veya skaler"
        int updated_at
        uuid updated_by FK
    }
    document_sequences {
        uuid id PK
        text doc_type "STS | ALS | THS | TKL | IAD | KSM | ODM | SYM | FIR | VRM | GDR"
        int year
        int last_number
    }
    command_log {
        uuid id PK "istemcide üretilen UUID v7 = idempotency anahtarı"
        text command_type
        text payload_hash "SHA-256"
        text result_ref_type
        uuid result_ref_id
        int created_at
        uuid created_by FK
        text device_id FK
    }
    audit_logs {
        uuid id PK
        int occurred_at
        uuid actor_user_id FK
        text device_id
        text entity_type
        uuid entity_id
        text action "CREATE | STATUS_CHANGE | REVERSE | RESTORE | SETTING_CHANGE"
        text summary "Türkçe özet"
        text before_json
        text after_json
        uuid command_id FK
    }
```

🔒 `command_log`, `audit_logs`

- `document_sequences` UK: `(doc_type, year)`. Numara atama aynı transaction içinde
  `UPDATE ... last_number = last_number + 1` ile yapılır; işlem geri alınırsa numara da geri
  alınır → **boşluk oluşmaz**.
- `command_log.id` birincil anahtar olduğu için aynı UUID'nin ikinci INSERT'i çakışır →
  çift kayıt engellenir. Kayıt iş kayıtlarıyla aynı transaction'da yazılır.
- v1'de tek `ADMIN` kullanıcı vardır, kullanıcı yönetimi arayüzü gizlidir. Tablolar
  ileriye hazırlık içindir (`docs/FUTURE_SYNC.md`).

**Ayar anahtarları (`settings`)**

| key | örnek değer | açıklama |
|---|---|---|
| `costing_method` | `FIFO` \| `WEIGHTED_AVERAGE` | ilk stok hareketinden sonra kilitli |
| `costing_method_locked_at` | epoch | kilit zamanı |
| `default_price_mode` | `EXCL` \| `INCL` | belge varsayılanı |
| `default_vat_rate` | `2000` | %20 |
| `allowed_vat_rates` | `[0,100,1000,2000]` | Ayarlar'dan düzenlenir |
| `company_*` | ad, adres, vergi dairesi, logo yolu | PDF başlığı |
| `backup_auto_time` | `20:00` | otomatik yedek saati |
| `backup_offsite_warn_days` | `3` | cihaz dışı yedek uyarı eşiği |
| `backup_wifi_only` | `true` | Drive yüklemesi |
| `drive_folder_id` | Drive klasör kimliği | "Sünger Yedekleri" |
| `hide_cost_mode` | `false` | maliyeti gizle |

---

## 3. Ana veri

```mermaid
erDiagram
    products ||--o{ product_variants : "ölçüleri"
    products ||--o{ price_list_items : "fiyatlanır"
    price_lists ||--o{ price_list_items : "içerir"
    customers ||--o{ customer_product_discounts : "iskonto"
    products ||--o{ customer_product_discounts : ""

    locations {
        uuid id PK
        text code UK "ANA_DEPO | KESIMDE"
        text name
        bool is_virtual
        bool is_sellable "KESIMDE = false"
    }
    products {
        uuid id PK
        text code UK
        text name
        text name_normalized "Türkçe arama"
        int price_coefficient "rate x10000, SPEC 13 katsayısı"
        text dns "SPEC 1: DNS degeri"
        text foam_type "SPEC 1: sünger tipi"
        int default_width "dim, ör. D35 140x240"
        int default_height "dim"
        text standard_thicknesses "JSON dizi, SPEC 1: standart kalınlıklar"
        int default_sale_price_m3 "price, SPEC 1: varsayılan satış fiyatı"
        int critical_stock_pieces "SPEC 1: minimum stok"
        int min_stock_volume "vol"
        bool is_active
        text note
    }
    product_variants {
        uuid id PK
        uuid product_id FK
        int width "dim"
        int height "dim"
        int thickness "dim, 2,5 cm olabilir"
        text kind "PLAKA | BLOK"
        int unit_volume "vol, tek parçanın m3 degeri"
        text sku UK
        int critical_stock_pieces
        bool is_active
    }
    customers {
        uuid id PK
        text code UK
        text title "SPEC 9: firma adı"
        text title_normalized
        text contact_person "SPEC 9: yetkili"
        text phone
        text email
        text address
        text tax_office
        text tax_number
        text default_price_mode "EXCL | INCL | null = ayar"
        int default_discount_rate "rate"
        int risk_limit "money, 0 = limitsiz"
        int payment_term_days
        bool is_active
        text note
    }
    suppliers {
        uuid id PK
        text code UK
        text title
        text title_normalized
        text type "FABRIKA | KESIMHANE | NAKLIYE | DIGER"
        text phone
        text address
        text tax_office
        text tax_number
        int payment_term_days
        bool is_active
    }
    price_lists {
        uuid id PK
        int version_no UK
        text name
        int base_price_m3 "price, baz TL/m3"
        text rounding_rule "NONE | NEAREST_1 | NEAREST_5 | NEAREST_10"
        int valid_from
        text status "DRAFT | ACTIVE | ARCHIVED"
        int created_at
        text note
    }
    price_list_items {
        uuid id PK
        uuid price_list_id FK
        uuid product_id FK
        int coefficient "rate, versiyona kopyalanır"
        int computed_price_m3 "price, baz x katsayı, yuvarlama uygulanmış"
        int manual_price_m3 "price, elle ezme, null olabilir"
        int effective_price_m3 "price, manual varsa o"
    }
    customer_product_discounts {
        uuid id PK
        uuid customer_id FK
        uuid product_id FK
        int discount_rate "rate"
    }
```

- `product_variants` UK: `(product_id, width, height, thickness, kind)`.
- `unit_volume` Dart'ta `Decimal` ile hesaplanıp yazılır (SQL'de çarpma yapılmaz); böylece
  stok ekranındaki m³ toplamları saf `SUM()` ile alınabilir.
- Fiyat listesi fiyatları **KDV hariç** saklanır. Yeni versiyon oluşturulurken eski versiyon
  `ARCHIVED` olur ama **silinmez ve değişmez** — geçmiş satışlar kendi versiyonuna referans
  verir (`sale_items.price_list_id`).
- "D35 140×240" ve "HR35 140×240" **ayrı ürünlerdir** (müşteri kararı); kartlarında standart
  en/boy 140×240 gelir (`default_width`, `default_height`).
- **TODO(SPEC):** 12 ürün ve `price_coefficient` değerleri SPEC'ten seed'lenecek.

---

## 4. Stok ve maliyet

```mermaid
erDiagram
    product_variants ||--o{ inventory_batches : "partileri"
    locations ||--o{ inventory_batches : "konumu"
    suppliers ||--o{ inventory_batches : "tedarikçi"
    inventory_batches ||--o{ inventory_batches : "parent_batch_id"
    inventory_batches ||--o{ stock_movements : "hareketleri"
    stock_movements ||--o{ cost_allocations : "maliyet dağılımı"
    inventory_batches ||--o{ cost_allocations : "tüketilen parti"
    inventory_batches ||--o{ cost_adjustments : "maliyet farkı"
    stock_movements ||--o{ stock_movements : "reversal_of_id"

    inventory_batches {
        uuid id PK
        uuid variant_id FK
        uuid location_id FK
        uuid supplier_id FK
        text source_type "PURCHASE | OPENING | CUTTING | SALE_RETURN | TRANSFER"
        uuid source_id
        uuid parent_batch_id FK "kesim/transfer zinciri"
        int received_at "FIFO sırası; kesim hedefi kaynağın tarihini taşır"
        int bare_unit_cost_m3 "price, çıplak fabrika"
        int real_unit_cost_m3 "price, masraflı gerçek"
        int in_pieces "pcs"
        int in_volume "vol"
        int remaining_pieces "pcs, ÖNBELLEK"
        int remaining_volume "vol, ÖNBELLEK"
        int created_at
        uuid created_by FK
        text device_id
    }
    stock_movements {
        uuid id PK
        int occurred_at
        text type "PURCHASE_IN | SALE_OUT | SALE_RETURN_IN | PURCHASE_RETURN_OUT | COUNT_IN | COUNT_OUT | WASTE_OUT | TRANSFER_OUT | TRANSFER_IN | CUTTING_OUT | CUTTING_IN | OPENING_IN | REVERSAL"
        uuid location_id FK
        uuid variant_id FK
        uuid batch_id FK
        int pieces "pcs, işaretli"
        int volume "vol, işaretli"
        int unit_cost_m3 "price"
        int total_cost "money"
        text source_type "SALE | PURCHASE | CUTTING_ORDER | STOCK_COUNT | WASTE | OPENING | RETURN"
        uuid source_id
        uuid reversal_of_id FK
        uuid command_id FK
        int created_at
        uuid created_by FK
        text device_id
        text note
    }
    cost_allocations {
        uuid id PK
        uuid movement_id FK
        uuid batch_id FK
        int pieces "pcs"
        int volume "vol"
        int unit_cost_m3 "price, FIFO'da parti maliyeti, ort.'da hesaplanan ortalama"
        int total_cost "money"
        int sequence_no "tüketim sırası; iade bundan tersine döner"
        int created_at
    }
    cost_adjustments {
        uuid id PK
        int occurred_at
        uuid batch_id FK
        uuid purchase_expense_id FK
        text reason "LATE_EXPENSE | CUTTING_FEE_LATE | OTHER"
        int volume_affected "vol, satılmış veya firelenmiş kısım"
        int amount "money, döneme yazılan maliyet farkı"
        int period_date
        text note
    }
```

🔒 `stock_movements`, `cost_allocations`, `cost_adjustments`

**Kısıtlar**

- `CHECK (remaining_pieces >= 0 AND remaining_volume >= 0)` → negatif stok yasağının
  veritabanı tarafındaki güvencesi.
- `CHECK (remaining_pieces <= in_pieces AND remaining_volume <= in_volume)`.
- `CHECK (pieces <> 0)` ve `CHECK (volume <> 0)` — sıfır hareket yazılmaz.
- Hareket yönü ile tip tutarlılığı: `_IN`/`OPENING_IN` tiplerinde `pieces > 0`,
  `_OUT` tiplerinde `pieces < 0` (CHECK).
- `UNIQUE (reversal_of_id) WHERE reversal_of_id IS NOT NULL` → bir hareket **iki kez** ters
  çevrilemez.
- İndeksler: `(variant_id, location_id)`, `(batch_id)`, `(occurred_at)`,
  `(source_type, source_id)`; partide `(variant_id, location_id, received_at, id)` → FIFO
  taraması.

**Kesimdeki mal.** Ana depodaki parti kesime gönderilirken **silinmez**: kalanı düşülür ve
`KESIMDE` konumunda, aynı birim maliyeti taşıyan bir **çocuk parti** (`parent_batch_id`)
açılır. `locations.is_sellable = false` olduğu için bu parti FIFO tüketimine girmez, ama stok
değerinde ve ana sayfadaki "Kesimdeki Mal" kartında görünür.

---

## 5. Alış, masraf ve alış iadesi

```mermaid
erDiagram
    suppliers ||--o{ purchases : ""
    purchases ||--o{ purchase_items : ""
    purchases ||--o{ purchase_expenses : ""
    purchase_expenses ||--o{ purchase_expense_allocations : ""
    inventory_batches ||--o{ purchase_expense_allocations : ""
    purchase_items ||--|| inventory_batches : "parti üretir"
    purchases ||--o{ purchase_returns : ""
    purchase_returns ||--o{ purchase_return_items : ""
    purchase_items ||--o{ purchase_return_items : "referans"

    purchases {
        uuid id PK
        text doc_no UK "ALS-2026-000001"
        uuid supplier_id FK
        int doc_date
        int due_date
        text price_mode "EXCL | INCL"
        text invoice_no "opsiyonel"
        text waybill_no "opsiyonel"
        int subtotal_net "money"
        int vat_total "money"
        int grand_total "money"
        int expense_total "money, KDV hariç"
        text status "ACTIVE | CANCELLED"
        int cancelled_at
        text cancel_reason
        uuid command_id FK
        int created_at
        uuid created_by FK
        text device_id
        text note
    }
    purchase_items {
        uuid id PK
        uuid purchase_id FK
        int line_no
        uuid variant_id FK
        int pieces "pcs"
        int volume "vol"
        int unit_price_m3 "price"
        int discount_rate "rate"
        int net_total "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
        uuid batch_id FK
    }
    purchase_expenses {
        uuid id PK
        uuid purchase_id FK
        uuid supplier_id FK "nakliyeci; null = aynı tedarikçi"
        text kind "NAKLIYE | HAMALIYE | DIGER"
        int amount "money, KDV hariç"
        int vat_rate "rate"
        text allocation_key "VOLUME | AMOUNT"
        int occurred_at
        bool added_later "sonradan gelen fatura"
        text note
    }
    purchase_expense_allocations {
        uuid id PK
        uuid purchase_expense_id FK
        uuid batch_id FK
        int volume_share "vol"
        int amount_to_stock "money, parti birim maliyetine eklenen"
        int amount_to_adjustment "money, cost_adjustments'a giden"
    }
    purchase_returns {
        uuid id PK
        text doc_no UK "IAD-2026-000001"
        uuid purchase_id FK
        uuid supplier_id FK
        int doc_date
        text price_mode
        int subtotal_net "money"
        int vat_total "money"
        int grand_total "money"
        int cost_total "money"
        text status "ACTIVE | CANCELLED"
        text reason
    }
    purchase_return_items {
        uuid id PK
        uuid purchase_return_id FK
        uuid purchase_item_id FK
        uuid batch_id FK
        int pieces "pcs"
        int volume "vol"
        int unit_price_m3 "price"
        int net_total "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
        int cost_total "money"
    }
```

- Her `purchase_items` satırı **tam bir parti** üretir (`batch_id`). Çıplak birim fiyat
  partiye `bare_unit_cost_m3`, masraf dağıtıldıktan sonraki değer `real_unit_cost_m3` olur.
- `purchase_expense_allocations`, sonradan gelen masrafın **stokta kalan** ve
  **satılmış/firelenmiş** kısımlara nasıl bölündüğünün denetim izidir
  (`amount_to_stock + amount_to_adjustment = pay`).
- Alış iadesi: `Σ purchase_return_items.pieces ≤ purchase_items.pieces` (domain kuralı +
  doğrulama sorgusu). İade edilen mal ilgili partiden **aynı maliyetle** çıkar
  (`PURCHASE_RETURN_OUT`), tedarikçi carisine alacak yazılır.

---

## 6. Teklif, satış ve satış iadesi

```mermaid
erDiagram
    customers ||--o{ sales_quotes : ""
    sales_quotes ||--o{ sales_quote_items : ""
    sales_quotes ||--o| sales : "satışa dönüşür"
    customers ||--o{ sales : ""
    sales ||--o{ sale_items : ""
    sale_items ||--o{ sale_return_items : "referans"
    sales ||--o{ sale_returns : ""
    sale_returns ||--o{ sale_return_items : ""
    price_lists ||--o{ sale_items : "fiyat kaynağı"

    sales_quotes {
        uuid id PK
        text doc_no UK "TKL-2026-000001"
        uuid customer_id FK
        int doc_date
        int valid_until
        text price_mode
        int subtotal_net "money"
        int vat_total "money"
        int grand_total "money"
        text status "DRAFT | SENT | ACCEPTED | REJECTED | EXPIRED | CONVERTED"
        uuid converted_sale_id FK
        text note
    }
    sales_quote_items {
        uuid id PK
        uuid sales_quote_id FK
        int line_no
        uuid variant_id FK
        int pieces "pcs"
        int volume "vol"
        int list_price_m3 "price"
        int discount_rate "rate"
        int unit_price_m3 "price"
        int net_total "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
    }
    sales {
        uuid id PK
        text doc_no UK "STS-2026-000001"
        uuid customer_id FK
        uuid sales_quote_id FK
        int doc_date
        int due_date
        text price_mode "EXCL | INCL"
        text invoice_no
        text waybill_no
        int subtotal_net "money"
        int vat_total "money"
        int grand_total "money"
        int cost_total "money, SABİT"
        text status "ACTIVE | CANCELLED"
        int cancelled_at
        text cancel_reason
        uuid command_id FK
        int created_at
        uuid created_by FK
        text device_id
        text note
    }
    sale_items {
        uuid id PK
        uuid sale_id FK
        int line_no
        uuid variant_id FK
        int pieces "pcs"
        int volume "vol"
        uuid price_list_id FK
        int list_price_m3 "price"
        int discount_rate "rate"
        int unit_price_m3 "price, net TL/m3"
        int net_total "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
        int cost_total "money, satış anında SABİTLENİR"
    }
    sale_returns {
        uuid id PK
        text doc_no UK "IAD-2026-000002"
        uuid sale_id FK
        uuid customer_id FK
        int doc_date
        text price_mode
        int subtotal_net "money"
        int vat_total "money"
        int grand_total "money"
        int cost_total "money"
        text status "ACTIVE | CANCELLED"
        text reason
    }
    sale_return_items {
        uuid id PK
        uuid sale_return_id FK
        uuid sale_item_id FK
        int pieces "pcs"
        int volume "vol"
        int unit_price_m3 "price, orijinal satış fiyatı"
        int net_total "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
        int cost_total "money, orijinal partilere dönen maliyet"
    }
```

- `sale_items.cost_total` **satış anında sabitlenir** ve hiçbir koşulda değişmez.
- Teklif stok düşmez; `ACCEPTED` teklif "Satışa dönüştür" ile kopyalanır, `CONVERTED` olur.
- Satış iadesinde stok, orijinal satışın tükettiği partilere **`cost_allocations.sequence_no`
  tersinden** (son tüketilenden başlayarak) aynı maliyetle döner.
  > Doğrulama (Altın Senaryo 8): satış A partisinden 50, sonra B'den 10 adet tüketmişti;
  > 5 adetlik iade **B partisine** 3.165 TL/m³ ile döner (1,4 m³ → 4.431,00 TL).
- `Σ sale_return_items.pieces ≤ sale_items.pieces` (domain kuralı; iade satılan miktarı aşamaz).

---

## 7. Cari ve eşleştirme

```mermaid
erDiagram
    customers ||--o{ customer_ledger : ""
    suppliers ||--o{ supplier_ledger : ""
    customers ||--o{ collections : ""
    suppliers ||--o{ supplier_payments : ""
    collections ||--o{ payment_allocations : ""
    sales ||--o{ payment_allocations : "kapatılan belge"
    supplier_payments ||--o{ supplier_payment_allocations : ""
    purchases ||--o{ supplier_payment_allocations : ""
    customer_ledger ||--o{ customer_ledger : "reversal_of_id"

    customer_ledger {
        uuid id PK
        uuid customer_id FK
        int occurred_at
        text doc_type "SALE | SALE_RETURN | COLLECTION | INSTRUMENT_IN | INSTRUMENT_BOUNCED | OPENING | ADJUSTMENT | REVERSAL"
        uuid doc_id
        text doc_no
        int amount "money, işaretli: + borç (bize borçlu), - alacak"
        int due_date
        text description
        uuid reversal_of_id FK
        uuid command_id FK
        int created_at
        uuid created_by FK
        text device_id
    }
    supplier_ledger {
        uuid id PK
        uuid supplier_id FK
        int occurred_at
        text doc_type "PURCHASE | PURCHASE_RETURN | PAYMENT | INSTRUMENT_OUT | INSTRUMENT_ENDORSED | CUTTING_FEE | OPENING | ADJUSTMENT | REVERSAL"
        uuid doc_id
        text doc_no
        int amount "money, işaretli: + bizim borcumuz, - azalış"
        int due_date
        text description
        uuid reversal_of_id FK
    }
    collections {
        uuid id PK
        text doc_no UK "THS-2026-000001"
        uuid customer_id FK
        int doc_date
        text method "CASH | TRANSFER | CARD | CHECK | NOTE"
        uuid cash_account_id FK
        uuid instrument_id FK
        int amount "money"
        text status "ACTIVE | CANCELLED"
        int cancelled_at
        text cancel_reason
        uuid command_id FK
        text note
    }
    supplier_payments {
        uuid id PK
        text doc_no UK "ODM-2026-000001"
        uuid supplier_id FK
        int doc_date
        text method "CASH | TRANSFER | CARD | CHECK | NOTE"
        uuid cash_account_id FK
        uuid instrument_id FK
        int amount "money"
        text status "ACTIVE | CANCELLED"
    }
    payment_allocations {
        uuid id PK
        uuid collection_id FK
        text target_type "SALE | OPENING | SALE_RETURN"
        uuid target_id
        int amount "money"
        bool is_manual "elle eşleştirme"
        int created_at
    }
    supplier_payment_allocations {
        uuid id PK
        uuid supplier_payment_id FK
        text target_type "PURCHASE | OPENING | CUTTING_ORDER"
        uuid target_id
        int amount "money"
        bool is_manual
        int created_at
    }
```

🔒 `customer_ledger`, `supplier_ledger`, `payment_allocations`, `supplier_payment_allocations`

- **Bakiye = `SUM(customer_ledger.amount)`** — yalnızca toplama, kesin. Ayrı bir bakiye
  kolonu tutulmaz (`checkIntegrity` bunu doğrular).
- Cariye **brüt** (KDV dahil) tutar yazılır.
- Tahsilat varsayılan olarak **vadesi en erken açık belgeleri** kapatır; elle eşleştirme de
  yapılabilir (`is_manual`). Vadesi geçen alacak, gecikme günü ve ortalama ödeme süresi
  `payment_allocations` üzerinden hesaplanır.
- `CHECK (amount > 0)` eşleştirmelerde; `Σ allocations ≤ collection.amount` domain kuralı.

---

## 8. Kasa, banka ve gider

```mermaid
erDiagram
    cash_accounts ||--o{ account_movements : ""
    cash_accounts ||--o{ transfers : "from"
    cash_accounts ||--o{ transfers : "to"
    expense_categories ||--o{ expenses : ""
    expenses ||--o{ account_movements : "ödeme"

    cash_accounts {
        uuid id PK
        text code UK
        text name
        text type "KASA | BANKA | POS"
        text bank_name
        text iban
        bool is_active
    }
    account_movements {
        uuid id PK
        uuid cash_account_id FK
        int occurred_at
        text direction "IN | OUT"
        int amount "money, pozitif"
        text type "COLLECTION | PAYMENT | TRANSFER_IN | TRANSFER_OUT | EXPENSE | OPENING | INSTRUMENT_COLLECTED | INSTRUMENT_PAID | REVERSAL"
        text source_type
        uuid source_id
        uuid counter_account_id FK "virmanda karşı hesap"
        uuid reversal_of_id FK
        text description
        int created_at
        uuid created_by FK
        text device_id
    }
    transfers {
        uuid id PK
        text doc_no UK "VRM-2026-000001"
        uuid from_account_id FK
        uuid to_account_id FK
        int amount "money"
        int doc_date
        text status "ACTIVE | CANCELLED"
        text note
    }
    expense_categories {
        uuid id PK
        text name UK
        bool is_active
    }
    expenses {
        uuid id PK
        text doc_no UK "GDR-2026-000001"
        uuid category_id FK
        uuid supplier_id FK
        int doc_date
        int amount_net "money"
        int vat_rate "rate"
        int vat_total "money"
        int gross_total "money"
        uuid cash_account_id FK
        text status "ACTIVE | CANCELLED"
        text note
    }
```

🔒 `account_movements`

- Hesap bakiyesi = `SUM(IN) − SUM(OUT)`; ayrı bakiye kolonu yok.
- Virman tek transaction'da iki `account_movements` satırı yazar (`TRANSFER_OUT` +
  `TRANSFER_IN`), ikisi de `counter_account_id` ile birbirine bakar.
- Genel giderler kârlılık raporunda net kâr hesabına girer (KDV hariç tutarla).

---

## 9. Çek ve senet

```mermaid
erDiagram
    instruments ||--o{ instrument_events : "durum geçmişi"
    customers ||--o{ instruments : "alınan"
    suppliers ||--o{ instruments : "verilen / ciro"
    cash_accounts ||--o{ instrument_events : "tahsil / ödeme"

    instruments {
        uuid id PK
        text kind "CHECK | NOTE"
        text direction "IN | OUT"
        text serial_no
        text bank_name
        text branch
        text drawer_name "keşideci veya borçlu"
        int due_date
        int amount "money"
        uuid customer_id FK "IN ise veren müşteri"
        uuid supplier_id FK "OUT ise alan tedarikçi"
        uuid endorsed_to_supplier_id FK "ciro edildiyse"
        text current_status
        text source_type "SALE | COLLECTION | OPENING | PAYMENT"
        uuid source_id
        int created_at
        text note
    }
    instrument_events {
        uuid id PK
        uuid instrument_id FK
        int occurred_at
        text from_status
        text to_status
        uuid cash_account_id FK
        uuid counterparty_id
        int amount "money"
        uuid reversal_of_id FK
        int created_at
        uuid created_by FK
        text device_id
        text note
    }
```

🔒 `instrument_events`

**Durum makinesi — ALINAN (`direction = IN`)**

```mermaid
stateDiagram-v2
    [*] --> PORTFOLIO : müşteriden alındı
    PORTFOLIO --> AT_BANK : bankaya tahsile verildi
    AT_BANK --> COLLECTED : tahsil edildi
    AT_BANK --> BOUNCED : karşılıksız / protestolu
    PORTFOLIO --> ENDORSED : tedarikçiye ciro edildi
    PORTFOLIO --> RETURNED : müşteriye iade edildi
    PORTFOLIO --> BOUNCED : karşılıksız
    ENDORSED --> BOUNCED : karşılıksız döndü
    COLLECTED --> [*]
    RETURNED --> [*]
    BOUNCED --> [*]
```

**Durum makinesi — VERİLEN (`direction = OUT`)**

```mermaid
stateDiagram-v2
    [*] --> ISSUED : tedarikçiye verildi
    ISSUED --> PAID : ödendi
    ISSUED --> TAKEN_BACK : iade alındı
    PAID --> [*]
    TAKEN_BACK --> [*]
```

**Muhasebe etkileri**

| Geçiş | Etki |
|---|---|
| Müşteriden alınır (`→ PORTFOLIO`) | `customer_ledger` alacak (bakiye düşer), portföye girer |
| `→ COLLECTED` | Seçilen banka hesabına `account_movements` girişi |
| `→ ENDORSED` | Tedarikçi ödemesi: `supplier_ledger` borç azalır |
| `→ BOUNCED` | `customer_ledger`'a **ters kayıt** (bakiye geri artar), portföyden çıkar |
| `→ RETURNED` | `customer_ledger`'a ters kayıt |
| Verilen `→ ISSUED` | `supplier_ledger` borç azalır |
| Verilen `→ PAID` | Banka hesabından çıkış |

> Doğrulama (Altın Senaryo 10): 20.000,00 çek → bakiye 64.680 → 44.680, portföy 20.000.
> Karşılıksız → bakiye 64.680, portföy 0.

Geçerli olmayan geçişler domain katmanında reddedilir (`service/instrument_rules.dart`,
tablo testi). `instruments.current_status` bir **önbellektir**; doğrusu `instrument_events`
zincirinin sonucudur ve `checkIntegrity` bunu karşılaştırır.

---

## 10. Fason kesim

```mermaid
erDiagram
    suppliers ||--o{ cutting_orders : "kesimhane"
    sales_quotes ||--o| cutting_orders : "bağlı teklif"
    cutting_orders ||--o{ cutting_order_sources : "gönderilen"
    cutting_orders ||--o{ cutting_order_plan_items : "planlanan hedef"
    cutting_orders ||--o{ cutting_order_results : "dönen"
    inventory_batches ||--o{ cutting_order_sources : "kaynak parti"
    inventory_batches ||--o{ cutting_order_results : "hedef parti"

    cutting_orders {
        uuid id PK
        text doc_no UK "KSM-2026-000001"
        uuid cutter_supplier_id FK "type = KESIMHANE"
        uuid sales_quote_id FK
        uuid customer_id FK
        int sent_date
        int expected_return_date
        text status "PREPARING | AT_CUTTER | PARTIAL | COMPLETED | CANCELLED"
        int cutting_fee_net "money, KDV hariç"
        int cutting_fee_vat_rate "rate"
        int freight_net "money"
        int source_volume_total "vol"
        int result_volume_total "vol"
        int waste_volume "vol, kesim firesi"
        uuid command_id FK
        text note
    }
    cutting_order_sources {
        uuid id PK
        uuid cutting_order_id FK
        uuid source_batch_id FK "ana depodaki parti"
        uuid kesimde_batch_id FK "KESIMDE konumundaki çocuk parti"
        uuid variant_id FK
        int pieces "pcs"
        int volume "vol"
        int cost_total "money, taşınan maliyet"
    }
    cutting_order_plan_items {
        uuid id PK
        uuid cutting_order_id FK
        uuid variant_id FK
        int planned_pieces "pcs"
    }
    cutting_order_results {
        uuid id PK
        uuid cutting_order_id FK
        uuid variant_id FK
        uuid result_batch_id FK "ana depoya giren yeni parti"
        int pieces "pcs"
        int volume "vol"
        int allocated_cost "money, m3 oranında dağıtılmış"
        int returned_at
        bool is_remnant "artık parça (ör. 60x200)"
    }
```

- `CHECK (result_volume_total <= source_volume_total)` — hedef toplam m³ kaynağı aşamaz.
- `waste_volume = source_volume_total − result_volume_total` → fire raporunda **"kesim
  firesi"** olarak miktarıyla görünür; ayrı maliyet kaydı yazılmaz, hedeflerin birim
  maliyetine yedirilir.
- Hedef partiler **kaynak partinin `received_at` değerini** taşır → FIFO sırası bozulmaz.
- Kısmi dönüş: her dönüşte `cutting_order_results` satırları eklenir, durum `PARTIAL` olur;
  kaynak tükenince `COMPLETED`.
- Kesim ücreti kesimhane carisine **brüt** borç yazılır; maliyete **KDV hariç** girer.

---

## 11. Sayım, fire ve açılış

```mermaid
erDiagram
    locations ||--o{ stock_counts : ""
    stock_counts ||--o{ stock_count_items : ""
    product_variants ||--o{ stock_count_items : ""
    stock_adjustments ||--o{ stock_adjustment_items : ""
    product_variants ||--o{ stock_adjustment_items : ""

    stock_counts {
        uuid id PK
        text doc_no UK "SYM-2026-000001"
        uuid location_id FK
        int count_date
        text status "DRAFT | APPLIED | CANCELLED"
        int applied_at
        int cost_effect_total "money"
        uuid command_id FK
        text note
    }
    stock_count_items {
        uuid id PK
        uuid stock_count_id FK
        uuid variant_id FK
        int system_pieces "pcs"
        int counted_pieces "pcs"
        int diff_pieces "pcs, işaretli"
        int diff_volume "vol, işaretli"
        int cost_effect "money"
    }
    stock_adjustments {
        uuid id PK
        text doc_no UK "FIR-2026-000001"
        int occurred_at
        text reason_code "HASARLI | KESIM_FIRESI | NEM | DIGER"
        int cost_total "money"
        text status "ACTIVE | CANCELLED"
        text note
    }
    stock_adjustment_items {
        uuid id PK
        uuid stock_adjustment_id FK
        uuid variant_id FK
        int pieces "pcs"
        int volume "vol"
        int cost_total "money"
    }
    opening_balances {
        uuid id PK
        text kind "STOCK | CUSTOMER | SUPPLIER | CASH | INSTRUMENT"
        uuid ref_id "variant | customer | supplier | cash_account | instrument"
        int as_of_date
        int amount "money"
        int pieces "pcs, STOCK için"
        int unit_cost_m3 "price, STOCK için"
        int due_date "vadeli cari için"
        uuid created_record_id "oluşturulan parti / ledger satırı"
        int created_at
        text note
    }
```

- Sayım `DRAFT` iken stok etkilemez; **onayda** (`APPLIED`) fark kadar `COUNT_IN`/`COUNT_OUT`
  hareketi yazılır. Eksik çıkan mal FIFO sırasıyla partilerden düşülür, maliyeti
  `cost_allocations`'a yazılır. Sayım onayı **riskli işlem**tir → öncesinde otomatik yedek.
  > Doğrulama (Altın Senaryo 6): 140×200×10 sistem 20 / fiziksel 19 → −1 adet, −0,28 m³,
  > maliyet 886,20 TL (B partisi, 3.165 TL/m³).
- Fire, FIFO sırasıyla partiden düşer ve kârlılık raporunda ayrı kalem olarak görünür.
  > Doğrulama (Altın Senaryo 7): 140×200×5 × 2 adet → −0,28 m³, 848,40 TL (A partisi, 3.030).
- Açılış stoğu, `source_type = OPENING` olan bir parti ve `OPENING_IN` hareketi üretir.
  Açılış cari bakiyeleri vadeleriyle birlikte `customer_ledger`/`supplier_ledger`'a
  `doc_type = OPENING` ile yazılır ve tahsilat eşleştirmesinde hedef olabilir.

---

## 12. Yedekleme günlüğü

```mermaid
erDiagram
    backup_log {
        uuid id PK
        int occurred_at
        text kind "BACKUP | RESTORE"
        text trigger "MANUAL | AUTO_DAILY | AUTO_STARTUP | PRE_RISK | PRE_MIGRATION"
        text destination "LOCAL | DRIVE | SHARE"
        text file_name
        int size_bytes
        text sha256
        int schema_version
        text app_version
        text result "OK | FAIL"
        text error_message
        text device_id
    }
```

🔒 `backup_log` — "son cihaz dışı yedek" uyarısı `destination IN ('DRIVE','SHARE')` ve
`result = 'OK'` satırlarının en yenisinden hesaplanır.

---

## 13. Trigger listesi

| Tablo | no_update | no_delete |
|---|---|---|
| `stock_movements` | ✔ | ✔ |
| `customer_ledger` | ✔ | ✔ |
| `supplier_ledger` | ✔ | ✔ |
| `account_movements` | ✔ | ✔ |
| `instrument_events` | ✔ | ✔ |
| `cost_allocations` | ✔ | ✔ |
| `cost_adjustments` | ✔ | ✔ |
| `payment_allocations` | ✔ | ✔ |
| `supplier_payment_allocations` | ✔ | ✔ |
| `command_log` | ✔ | ✔ |
| `audit_logs` | ✔ | ✔ |
| `backup_log` | ✔ | ✔ |
| Belge başlıkları (`sales`, `purchases`, `collections`, `supplier_payments`, `sale_returns`, `purchase_returns`, `transfers`, `expenses`, `stock_adjustments`) | kısmi: yalnızca `status`, `cancelled_at`, `cancel_reason` değişebilir | ✔ |

Belge başlığı trigger'ı örneği:

```sql
CREATE TRIGGER trg_sales_status_only BEFORE UPDATE ON sales
WHEN OLD.doc_no      <> NEW.doc_no
  OR OLD.customer_id <> NEW.customer_id
  OR OLD.grand_total <> NEW.grand_total
  OR OLD.cost_total  <> NEW.cost_total
  OR OLD.doc_date    <> NEW.doc_date
BEGIN
  SELECT RAISE(ABORT, 'sales: yalnızca durum alanları güncellenebilir');
END;
```

---

## 14. Enum sözlüğü

Tüm enum'lar veritabanında `TEXT` olarak saklanır (okunabilirlik ve ileri uyumluluk için),
Dart tarafında `enum` ile temsil edilir ve `CHECK (col IN (...))` ile kısıtlanır.

| Enum | Değerler |
|---|---|
| `price_mode` | `EXCL`, `INCL` |
| `variant_kind` | `PLAKA`, `BLOK` |
| `location_code` | `ANA_DEPO`, `KESIMDE` |
| `supplier_type` | `FABRIKA`, `KESIMHANE`, `NAKLIYE`, `DIGER` |
| `costing_method` | `FIFO`, `WEIGHTED_AVERAGE` |
| `movement_type` | `PURCHASE_IN`, `SALE_OUT`, `SALE_RETURN_IN`, `PURCHASE_RETURN_OUT`, `COUNT_IN`, `COUNT_OUT`, `WASTE_OUT`, `TRANSFER_OUT`, `TRANSFER_IN`, `CUTTING_OUT`, `CUTTING_IN`, `OPENING_IN`, `REVERSAL` |
| `doc_status` | `ACTIVE`, `CANCELLED` |
| `quote_status` | `DRAFT`, `SENT`, `ACCEPTED`, `REJECTED`, `EXPIRED`, `CONVERTED` |
| `cutting_status` | `PREPARING`, `AT_CUTTER`, `PARTIAL`, `COMPLETED`, `CANCELLED` |
| `instrument_kind` | `CHECK`, `NOTE` |
| `instrument_direction` | `IN`, `OUT` |
| `instrument_status` (IN) | `PORTFOLIO`, `AT_BANK`, `COLLECTED`, `ENDORSED`, `BOUNCED`, `RETURNED` |
| `instrument_status` (OUT) | `ISSUED`, `PAID`, `TAKEN_BACK` |
| `payment_method` | `CASH`, `TRANSFER`, `CARD`, `CHECK`, `NOTE` |
| `cash_account_type` | `KASA`, `BANKA`, `POS` |
| `rounding_rule` | `NONE`, `NEAREST_1`, `NEAREST_5`, `NEAREST_10` |
| `allocation_key` | `VOLUME`, `AMOUNT` |
| `backup_kind` | `BACKUP`, `RESTORE` |
| `backup_trigger` | `MANUAL`, `AUTO_DAILY`, `AUTO_STARTUP`, `PRE_RISK`, `PRE_MIGRATION` |
| `backup_destination` | `LOCAL`, `DRIVE`, `SHARE` |

Türkçe karşılıklar yalnızca `ui` katmanında, tek bir çeviri haritasında tutulur.
