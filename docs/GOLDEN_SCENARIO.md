# Altın Senaryo — doğrulanmış rakamlar

`docs/BRIEF.md` §8'deki senaryonun her adımı elle yeniden hesaplandı ve **tamamı tutuyor**.
Bu doküman Faz 1 ve Faz 3 testlerinin birebir kaynağıdır.

> **Kural:** Rakamlardan biri testte tutmazsa **test değiştirilmez**. Önce hesap kontrol
> edilir; test gerçekten hatalıysa gerekçesi `docs/DECISIONS.md`'ye yazılır ve müşteriye sorulur.

Ayarlar: **FIFO**, KDV **%20**, fiyat modu **KDV Hariç**.

---

## Adım 1 — Alış A (01.09.2026), Beyaz Sünger, 2.930 TL/m³

| Varyant | Adet | m³/adet | m³ |
|---|---|---|---|
| 140×200×10 | 50 | 0,28 | **14,000000** |
| 140×200×5 | 40 | 0,14 | **5,600000** |
| | | **Toplam** | **19,600000** |

- Çıplak: 19,6 × 2.930 = **57.428,00 TL**
- Nakliye 1.960,00 TL, m³ bazlı → 1.960 / 19,6 = **100,00 TL/m³**
- **Gerçek maliyet: 3.030,0000 TL/m³ · toplam 59.388,00 TL** ✔

Oluşan partiler:

| Parti | Varyant | Adet | m³ | Gerçek TL/m³ | Maliyet |
|---|---|---|---|---|---|
| **A1** | 140×200×10 | 50 | 14,0 | 3.030,0000 | 42.420,00 |
| **A2** | 140×200×5 | 40 | 5,6 | 3.030,0000 | 16.968,00 |

## Adım 2 — Alış B (15.09.2026)

140×200×10 × 30 = **8,400000 m³** @ 3.165 TL/m³ → **26.586,00 TL** (masraf yok) ✔

## Adım 3 — Satış (17.09.2026), ABC Mobilya, vade 30 gün

140×200×10 × 60 adet = **16,800000 m³** @ 3.500 TL/m³

**FIFO tüketimi:**

| Sıra | Parti | Adet | m³ | TL/m³ | Maliyet |
|---|---|---|---|---|---|
| 1 | A1 | 50 | 14,0 | 3.030 | 42.420,00 |
| 2 | B | 10 | 2,8 | 3.165 | 8.862,00 |
| | | | | **Toplam** | **51.282,00** ✔ |

- Net satış (KDV hariç): **58.800,00** ✔
- Brüt kâr: 58.800 − 51.282 = **7.518,00** ✔
- Kâr marjı: 7.518 / 58.800 = **%12,79** ✔ *(12,7857… → 2 hane)*
- Maliyet üzerine kâr: 7.518 / 51.282 = **%14,66** ✔ *(14,6602…)*
- KDV: **11.760,00** → müşteri carisi **+70.560,00** ✔

**Satış sonrası stok:**

| Varyant | Adet | m³ | Parti | Maliyet |
|---|---|---|---|---|
| 140×200×10 | 20 | 5,6 | B | 17.724,00 |
| 140×200×5 | 40 | 5,6 | A2 | 16.968,00 |
| **Toplam** | | **11,2** | | **34.692,00** ✔ |

## Adım 4 — Tahsilat

30.000,00 TL havale → bakiye **40.560,00**, satışın açık tutarı **40.560,00** ✔

## Adım 5 — Yeni fiyat

- Alış C (18.09.2026): 140×200×8 × 10 = 0,224 × 10 = **1,120000 m³** @ 3.300 → **3.696,00 TL** ✔
- Ardından yeni fiyat listesi versiyonu (baz 3.700 TL/m³).
- **Doğrulanacak:** 3. adımdaki satışın maliyeti, fiyatı ve kârı **değişmemeli**; eski
  fiyat listesi versiyonu erişilebilir kalmalı.

## Adım 6 — Sayım

140×200×10: sistem 20, fiziksel 19 → **−1 adet, −0,28 m³**
Maliyet: 0,28 × 3.165 (B) = **886,20 TL** ✔

## Adım 7 — Fire

140×200×5 × 2 adet, "Hasarlı" → **−0,28 m³**
Maliyet: 0,28 × 3.030 (A2) = **848,40 TL** ✔

**Son stok:**

| Varyant | Adet | m³ | Parti | TL/m³ | Maliyet |
|---|---|---|---|---|---|
| 140×200×10 | 19 | 5,32 | B | 3.165 | 16.837,80 |
| 140×200×5 | 38 | 5,32 | A2 | 3.030 | 16.119,60 |
| 140×200×8 | 10 | 1,12 | C | 3.300 | 3.696,00 |
| **Toplam** | | **11,76** | | | **36.653,40** ✔ |

## Adım 8 — İade

3. adımdaki satıştan **5 adet** 140×200×10 iade.
Tüketim tersinden döner (son tüketilen **B**) → **B partisine 3.165 TL/m³ ile**:
1,4 m³ → **4.431,00 TL** ✔

Cari: 5 × 0,28 × 3.500 = 4.900,00 net + 980,00 KDV = **−5.880,00** → bakiye **34.680,00** ✔

## Adım 9 — İptal

4. adımdaki tahsilat iptal → **ters kayıt**, orijinal silinmez → bakiye **64.680,00** ✔

## Adım 10 — Çek

ABC'den 20.000,00 TL çek (vade 30.10.2026) → bakiye **44.680,00**, portföy **20.000,00**
Karşılıksız → bakiye **64.680,00**, portföy **0** ✔

## Adım 11 — Yedek *(Faz 2)*

Yedek al → veritabanını sil → yedeği yükle → 1–10. adımlardaki **tüm** bakiye, stok ve
maliyetler birebir aynı.

## Adım 12 — Doğrulama

Tüm işlemler hareket tablolarında ve `audit_logs`'ta görünür; `checkIntegrity()` fark bulmaz.

---

## Ek A — Ağırlıklı ortalama (ayrı veritabanı)

1–3. adımlar aynı. Satış anında **ürün bazında** ağırlıklı ortalama:

```
(59.388,00 + 26.586,00) / (19,6 + 8,4) m³ = 85.974,00 / 28 = 3.070,5000 TL/m³
16,8 m³ × 3.070,5000 = 51.584,40 TL ✔
```

> Paydanın **28** olması ortalamanın varyant değil **ürün (çeşit)** bazında alındığını
> kanıtlar (D-11). Varyant bazlı olsaydı payda 22,4 m³ olurdu.

## Ek B — KDV Dahil

| Girilen (dahil) | Oran | KDV | Net | Toplam kontrolü |
|---|---|---|---|---|
| 4.200,00 | %20 | **700,00** | **3.500,00** | 4.200,00 ✔ |
| 1.000,00 | %20 | **166,67** | **833,33** | **tam 1.000,00** ✔ |

İkinci satır kuralın neden `net = toplam − KDV` olduğunu gösterir:
1.000 / 1,2 = 833,3333… ayrı yuvarlansaydı 833,33 + 166,67 = 1.000,00 yine tutardı, ama
`KDV = yuvarla(1.000 − 833,3333…) = 166,67` ve `net = 1.000 − 166,67` zinciri toplamın
**her zaman** korunmasını garanti eder.

## Ek C — Fason kesim (ayrı veritabanı)

- **Alış:** Beyaz blok 200×200×100 × 2 = 4 m³/adet × 2 = **8 m³** @ 2.900 → **23.200,00 TL**
- **Kesime gönder:** 1 blok (**4 m³**, 11.600,00 TL)
  → ana depo: 1 blok / 4 m³ · "Kesimde": 1 blok / 4 m³
- **Dönüş:** 140×200×10 × 9 (**2,52 m³**) + 60×200×10 × 9 (**1,08 m³**) = **3,6 m³**
  Kesim ücreti **1.000,00 TL** (KDV hariç)

**Maliyet:**

```
11.600,00 (kaynak) + 1.000,00 (kesim ücreti) = 12.600,00
12.600,00 / 3,6 m³ = 3.500,0000 TL/m³ ✔
```

| Hedef parti | m³ | Maliyet |
|---|---|---|
| 140×200×10 | 2,52 | **8.820,00** ✔ |
| 60×200×10 | 1,08 | **3.780,00** ✔ |

- Kesim firesi: 4 − 3,6 = **0,4 m³** ✔
- Kesimhane carisi: 1.000 + %20 KDV = **+1.200,00** ✔
- "Kesimde" boş, emir **Tamamlandı** ✔

---

## Faz kapsamı

| Adım | Faz 1 | Faz 2 | Faz 3 |
|---|---|---|---|
| 1–5, 8–10, 12 | ✔ | | |
| Ek A (ağırlıklı ortalama) | ✔ | | |
| Ek B (KDV dahil) | ✔ | | |
| 11 (yedek) | | ✔ | |
| 6–7 (sayım, fire) | | | ✔ |
| Ek C (fason kesim) | | | ✔ |

> Not: 6. ve 7. adım Faz 3'te uygulanır ama **sonuçları** 8. adımın girdisi değildir —
> iade, 3. adımdaki satışa bağlıdır. Faz 1 testi 1–5 ve 8–10'u kesintisiz koşabilir.
