import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/ui/content/daily_quote.dart';

/// Günün Sözü (imza öğesi).
void main() {
  group('Günün Sözü', () {
    test('aynı gün içinde söz değişmez', () {
      final sabah = DateTime(2026, 3, 14, 7, 30);
      final aksam = DateTime(2026, 3, 14, 22, 59, 59);
      expect(DailyQuote.of(aksam).text, DailyQuote.of(sabah).text);
    });

    test('ertesi gün başka söz gelir', () {
      final bugun = DailyQuote.of(DateTime(2026, 3, 14));
      final yarin = DailyQuote.of(DateTime(2026, 3, 15));
      expect(yarin.text, isNot(bugun.text));
    });

    test('bir yıl boyunca her gün söz üretilir, listenin dışına taşmaz', () {
      var day = DateTime(2026);
      for (var i = 0; i < 366; i++) {
        final quote = DailyQuote.of(day);
        expect(DailyQuote.all, contains(quote));
        day = day.add(const Duration(days: 1));
      }
    });

    test('geçmiş tarihlerde de çalışır (negatif gün numarası)', () {
      expect(DailyQuote.of(DateTime(1969, 7, 20)).text, isNotEmpty);
    });

    test('liste tekrar içermiyor ve her sözün kaynağı var', () {
      final texts = DailyQuote.all.map((q) => q.text).toSet();
      expect(texts.length, DailyQuote.all.length, reason: 'tekrar eden söz');
      for (final quote in DailyQuote.all) {
        expect(quote.source, isNotEmpty);
        expect(quote.text.trim(), quote.text);
      }
    });

    test('bir aydan uzun süre tekrar etmez', () {
      final seen = <String>{};
      var day = DateTime(2026, 5);
      for (var i = 0; i < 31; i++) {
        seen.add(DailyQuote.of(day).text);
        day = day.add(const Duration(days: 1));
      }
      expect(seen.length, 31);
    });
  });

  group('Selamlama', () {
    test('saate göre değişir', () {
      expect(greetingFor(DateTime(2026, 1, 1, 3)), 'İyi geceler');
      expect(greetingFor(DateTime(2026, 1, 1, 9)), 'Günaydın');
      expect(greetingFor(DateTime(2026, 1, 1, 14)), 'İyi günler');
      expect(greetingFor(DateTime(2026, 1, 1, 21)), 'İyi akşamlar');
    });

    test('sınırlarda doğru', () {
      expect(greetingFor(DateTime(2026, 1, 1, 6)), 'Günaydın');
      expect(greetingFor(DateTime(2026, 1, 1, 12)), 'İyi günler');
      expect(greetingFor(DateTime(2026, 1, 1, 18)), 'İyi akşamlar');
    });
  });
}
