/// Günün Sözü (imza öğesi).
///
/// Uygulama her açıldığında değil, **her gün** değişir: aynı gün içinde
/// ekranı kaç kez açarsanız açın söz aynı kalır. Sabah gördüğü sözü akşam
/// bulamayan kullanıcı için rastgelelik hoş değil, dağınıktır.
///
/// Seçim tarihten türetilir; kayıt tutulmaz, rastgele sayı üretilmez —
/// böylece saf, yan etkisiz ve test edilebilir.
///
/// **Kaynak seçimi:** listenin tamamı **Türk atasözü ve deyimleridir.**
/// Kişiye atfedilen sözler bilerek kullanılmadı: internette dolaşan
/// alıntıların büyük bölümü yanlış kişiye mal edilmiş oluyor ve uygulamanın
/// her gün bir kişiye yanlış söz yakıştırması kabul edilebilir değil.
/// Atasözünün kaynağı ortak kültürdür, yanlış atıf riski yoktur.
final class DailyQuote {
  final String text;
  final String source;

  const DailyQuote(this.text, this.source);

  /// Verilen günün sözü. Aynı gün → aynı söz.
  static DailyQuote of(DateTime day) => all[_indexFor(day)];

  /// Gün numarası listenin boyuna göre döner. Yerel gün kullanılır; saat,
  /// dakika ve saat dilimi elenir ki gün ortasında söz değişmesin.
  static int _indexFor(DateTime day) {
    final dayNumber =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    return dayNumber.remainder(all.length).abs();
  }

  /// Konular bilinçli seçildi: emek, sabır, ölçü, dürüst ticaret, itibar,
  /// hazırlık, tutumluluk. Hepsi tezgâh başındaki bir işletmeciye hitap eder.
  static const all = <DailyQuote>[
    DailyQuote('Damlaya damlaya göl olur.', 'Türk atasözü'),
    DailyQuote('İşleyen demir ışıldar.', 'Türk atasözü'),
    DailyQuote('Ağaç yaşken eğilir.', 'Türk atasözü'),
    DailyQuote('Sabreden derviş muradına ermiş.', 'Türk atasözü'),
    DailyQuote('Ayağını yorganına göre uzat.', 'Türk atasözü'),
    DailyQuote('Bugünün işini yarına bırakma.', 'Türk atasözü'),
    DailyQuote('Akıllı düşman, akılsız dosttan hayırlıdır.', 'Türk atasözü'),
    DailyQuote('Veresiye şarap içen, iki kere sarhoş olur.', 'Türk atasözü'),
    DailyQuote('Hesabını bilmeyen kasap, elinde kalır masat.', 'Türk atasözü'),
    DailyQuote('Ticaretin temeli dürüstlüktür.', 'Türk atasözü'),
    DailyQuote('Zararın neresinden dönülse kârdır.', 'Türk atasözü'),
    DailyQuote('Ucuz alan pahalı alır.', 'Türk atasözü'),
    DailyQuote('Emek olmadan yemek olmaz.', 'Türk atasözü'),
    DailyQuote('Erken kalkan yol alır.', 'Türk atasözü'),
    DailyQuote('Az veren candan, çok veren maldan.', 'Türk atasözü'),
    DailyQuote('Bir elin nesi var, iki elin sesi var.', 'Türk atasözü'),
    DailyQuote('Keskin sirke küpüne zarar.', 'Türk atasözü'),
    DailyQuote('Aç ayı oynamaz.', 'Türk atasözü'),
    DailyQuote('Sona kalan dona kalır.', 'Türk atasözü'),
    DailyQuote('Bin ölç bir biç.', 'Türk atasözü'),
    DailyQuote('İşini kış tut da yaz çıkarsa bahtına.', 'Türk atasözü'),
    DailyQuote('Ummadığın taş baş yarar.', 'Türk atasözü'),
    DailyQuote('Para parayı çeker.', 'Türk atasözü'),
    DailyQuote(
      'Çok söyleme arsız edersin, aç koyma hırsız edersin.',
      'Türk atasözü',
    ),
    DailyQuote('Görünen köy kılavuz istemez.', 'Türk atasözü'),
    DailyQuote('Denize düşen yılana sarılır.', 'Türk atasözü'),
    DailyQuote('İki kere ölçüp bir kere kesen pişman olmaz.', 'Türk atasözü'),
    DailyQuote('Malın iyisi, alıcısını bulur.', 'Türk atasözü'),
    DailyQuote('Borç yiğidin kamçısıdır.', 'Türk atasözü'),
    DailyQuote('Kimse kimsenin ekmeğine mani olmaz.', 'Türk atasözü'),
    DailyQuote('Rızkını taştan çıkaran, aç kalmaz.', 'Türk atasözü'),
    DailyQuote('Doğru söyleyeni dokuz köyden kovarlar.', 'Türk atasözü'),
    DailyQuote('Adamın iyisi, işinden belli olur.', 'Türk atasözü'),
    DailyQuote('Yavaş giden yol alır.', 'Türk atasözü'),
    DailyQuote('Taşıma su ile değirmen dönmez.', 'Türk atasözü'),
    DailyQuote('Bir yiğit, kendi elinin emeğiyle bey olur.', 'Türk atasözü'),
    DailyQuote('Beş parmağın beşi bir değil.', 'Türk atasözü'),
    DailyQuote('Yerin kulağı vardır.', 'Türk atasözü'),
    DailyQuote('Söz gümüşse sükût altındır.', 'Türk atasözü'),
    DailyQuote('Her işin başı sağlık.', 'Türk atasözü'),
    DailyQuote('Sakla samanı, gelir zamanı.', 'Türk atasözü'),
    DailyQuote('Gün doğmadan neler doğar.', 'Türk atasözü'),
  ];
}

/// Günün saatine göre selamlama. Ana sayfanın ilk satırı.
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 6) return 'İyi geceler';
  if (hour < 12) return 'Günaydın';
  if (hour < 18) return 'İyi günler';
  return 'İyi akşamlar';
}
