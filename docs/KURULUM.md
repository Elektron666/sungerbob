# Kurulum Kılavuzu

Bu doküman **teknik kurulum** içindir: APK'nın telefona yüklenmesi, imzalama
anahtarının oluşturulması ve Google Drive bağlantısı. Günlük kullanım için
`docs/KULLANIM.md`.

---

## 1. Uygulamayı telefona kurma

### 1.1 Test sürümü (debug APK)

Her kod değişikliğinde otomatik üretilir.

1. GitHub'da depoya gidin → **Actions** sekmesi.
2. En üstteki yeşil ✓ işaretli koşuyu açın.
3. Sayfanın altındaki **Artifacts** bölümünden `sungerbob-debug-apk` dosyasını indirin.
4. Zip'i açın, içindeki `app-debug.apk` dosyasını telefona aktarın.
5. Telefonda dosyaya dokunun. Android "bilinmeyen kaynak" uyarısı verirse
   **Ayarlar → Uygulamalar → Özel erişim → Bilinmeyen uygulamaları yükle**
   bölümünden dosya yöneticisine izin verin.

> Debug APK yavaş çalışır ve boyutu büyüktür. Günlük kullanım için release
> APK'yı kullanın.

### 1.2 Yayın sürümü (release APK)

Önce **Bölüm 2**'deki imzalama anahtarı kurulumunu bir kez yapın. Sonra:

- **Etiketle:** `git tag v1.0.0 && git push origin v1.0.0`, veya
- **Elle:** Actions → **Release APK** → *Run workflow*

Üretilen `sungerbob-release-apk` artifact'ini indirip kurun.

---

## 2. İmzalama anahtarı (bir kez)

> ⚠️ **Anahtar kaybolursa uygulama BİR DAHA güncellenemez.** Güncelleme için
> Android, yeni APK'nın eskisiyle **aynı anahtarla** imzalanmış olmasını şart
> koşar. Anahtarı kaybederseniz tek çare uygulamayı silip yeniden kurmaktır —
> **bu da telefondaki tüm veriyi siler.**
>
> **Anahtarı en az iki güvenli yere yedekleyin.** Şifresini de yedek şifrenizle
> aynı kâğıda yazın.

### 2.1 Anahtarı oluşturma

Bilgisayarınızda (Java kurulu olmalı):

```bash
keytool -genkey -v \
  -keystore sungerbob-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias sungerbob
```

Sorulara işletme bilgilerinizi girin. **Store şifresi** ve **key şifresi**
isteyecek — ikisini de not alın.

### 2.2 GitHub Secrets'a ekleme

Anahtar dosyası **asla depoya girmez** (`.gitignore`'da `*.jks` var). GitHub'a
şifreli secret olarak eklenir:

```bash
base64 -w 0 sungerbob-upload.jks > keystore.b64
```

Depoda **Settings → Secrets and variables → Actions → New repository secret**:

| Secret adı | Değer |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `keystore.b64` dosyasının içeriği |
| `ANDROID_KEYSTORE_PASSWORD` | store şifresi |
| `ANDROID_KEY_ALIAS` | `sungerbob` |
| `ANDROID_KEY_PASSWORD` | key şifresi |

Derleme sırasında anahtar geçici olarak üretilir ve adım sonunda **her koşulda
silinir** (`.github/workflows/release.yml`).

### 2.3 Yerel derleme (isteğe bağlı)

Kendi bilgisayarınızda release APK derlemek isterseniz `android/key.properties`
oluşturun:

```properties
storePassword=<store şifresi>
keyPassword=<key şifresi>
keyAlias=sungerbob
storeFile=upload-keystore.jks
```

`.jks` dosyasını `android/app/` altına koyun. Bu iki dosya da `.gitignore`'da.

---

## 3. Güncelleme

APK elden dağıtılır (Play Store yok).

- **Veri korunur:** paket adı (`com.sungerbob.sungerbob`) ve imza aynı kaldığı
  sürece yeni APK eskisinin üzerine kurulur ve **veritabanı yerinde kalır**.
- **Migration öncesi otomatik yedek alınır.** Şema değişmişse uygulama açılışta
  veritabanını günceller; başarısız olursa o yedekten dönülür.
- Ayarlar → Uygulama bölümünde sürüm bilgisi görünür.

> Paket adını veya imzalama anahtarını **değiştirmeyin**. İkisinden biri
> değişirse Android bunu farklı bir uygulama sayar; eski veriye erişilemez.

---

## 4. Google Drive yedeklemesi (isteğe bağlı)

Drive bağlantısı olmadan da yedek alabilirsiniz — "Paylaş / Kaydet" ile
WhatsApp veya e-postaya gönderirsiniz. Drive'ı bağlamak otomatik yedeklemeyi
kolaylaştırır.

### 4.1 Google Cloud projesi

1. https://console.cloud.google.com → yeni proje oluşturun.
2. **APIs & Services → Library** → *Google Drive API* → **Enable**.
3. **APIs & Services → OAuth consent screen**:
   - User type: **External**
   - Uygulama adı, destek e-postası ve geliştirici e-postası girin
   - **Scopes** → `../auth/drive.file` ekleyin (yalnızca uygulamanın kendi
     oluşturduğu dosyalara erişim; Drive'ınızın geri kalanına dokunmaz)
   - **Test users** bölümüne kendi Google hesabınızı ekleyin
4. **Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Android**
   - Package name: `com.sungerbob.sungerbob`
   - SHA-1 parmak izi: aşağıdaki komutla alın

### 4.2 SHA-1 parmak izi

**Release anahtarı için:**

```bash
keytool -list -v -keystore sungerbob-upload.jks -alias sungerbob
```

Çıktıdaki `SHA1:` satırını kopyalayın.

**Debug APK ile test edecekseniz** debug anahtarının parmak izi de gerekir:

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```

İki parmak izini de OAuth client'a ekleyin (ayrı ayrı client oluşturabilirsiniz).

### 4.3 Uygulamada bağlama

Uygulama → **Ayarlar → Yedek ve Drive → Google hesabını bağla**. Bir kez
yapılır. Yedekler Drive'ınızda görünür bir **"Sünger Yedekleri"** klasörüne
yüklenir; son 30 yedek tutulur.

---

## 5. Kurulum sonrası ilk adımlar

1. **Yedek şifresi belirleyin** (en az 8 karakter). Bu şifre unutulursa
   yedekleriniz açılamaz. **Bir kâğıda yazıp güvenli yerde saklayın.**
2. **PIN belirleyin**, isterseniz parmak izini açın.
3. **Firma bilgilerini** ve logoyu girin (PDF belgelerde kullanılır).
4. **Maliyet yöntemini seçin** (FIFO önerilir). ⚠️ İlk stok hareketinden sonra
   **kilitlenir**.
5. **Açılış işlemlerini** girin: depodaki mal (maliyetiyle), müşteri ve
   tedarikçi borçları, kasa/banka bakiyesi, portföydeki çek/senet.
6. **İlk yedeğinizi alın** ve telefon dışına çıkarın.

---

## 6. Sorun giderme

| Belirti | Çözüm |
|---|---|
| APK kurulmuyor, "uygulama yüklenmedi" | Eski sürüm farklı anahtarla imzalanmış olabilir. Eski sürümü kaldırmadan önce **mutlaka yedek alın**. |
| "Bilinmeyen kaynak" uyarısı | Ayarlar → Uygulamalar → Özel erişim → Bilinmeyen uygulamaları yükle |
| Drive'a yüklenmiyor | Ayarlar → Yedek ve Drive → hesabı yeniden bağlayın. İnternet yoksa yedek yerelde kalır, "Paylaş" ile dışarı alın. |
| Yedek açılmıyor, "şifre yanlış" | Yedek şifresi, PIN'den farklıdır. Kurulumda belirlediğiniz ve kâğıda yazdığınız şifredir. |
| Uygulama açılışta donuyor | Migration sürüyor olabilir. Bekleyin; başarısız olursa otomatik yedekten döner. |
