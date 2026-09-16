import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';

Volume volOf(String w, String h, String t, int pieces) => Volume.fromDimensions(
      width: Dimension.cm(w),
      height: Dimension.cm(h),
      thickness: Dimension.cm(t),
      pieces: pieces,
    );

void main() {
  group('m³ hesabı (BRIEF §3.3)', () {
    test('140×200×10 × 50 = 14,000000 m³ (Altın Senaryo 1)', () {
      expect(volOf('140', '200', '10', 50), Volume.parse('14'));
    });

    test('140×200×5 × 40 = 5,600000 m³', () {
      expect(volOf('140', '200', '5', 40), Volume.parse('5.6'));
    });

    test('140×200×10 × 30 = 8,400000 m³ (Alış B)', () {
      expect(volOf('140', '200', '10', 30), Volume.parse('8.4'));
    });

    test('140×200×8 × 5 = 1,120000 m³ (Alış C — bkz. DECISIONS SK-06)', () {
      // BRIEF §8 adım 5 "× 10 adet" diyor ama 10 adet 2,24 m³ eder.
      // 1,12 m³ üç türetilmiş toplamla doğrulanıyor; adet 5 olmalı.
      expect(volOf('140', '200', '8', 5), Volume.parse('1.12'));
    });

    test('SK-06 kanıtı: 140×200×8 × 10 adet 2,24 m³ eder, 1,12 değil', () {
      expect(volOf('140', '200', '8', 10), Volume.parse('2.24'));
      expect(volOf('140', '200', '8', 10), isNot(Volume.parse('1.12')));
    });

    test('140×200×10 × 60 = 16,800000 m³ (satış)', () {
      expect(volOf('140', '200', '10', 60), Volume.parse('16.8'));
    });

    test('SPEC §2 örneği: 140×200×10 × 10 = 2,80 m³', () {
      expect(volOf('140', '200', '10', 10), Volume.parse('2.8'));
    });

    test('blok 200×200×100 × 2 = 8 m³ (fason kesim)', () {
      expect(volOf('200', '200', '100', 2), Volume.parse('8'));
    });

    test('kesim hedefleri: 140×200×10 ×9 = 2,52 · 60×200×10 ×9 = 1,08', () {
      expect(volOf('140', '200', '10', 9), Volume.parse('2.52'));
      expect(volOf('60', '200', '10', 9), Volume.parse('1.08'));
    });

    test('kesirli kalınlık 2,5 cm çalışır', () {
      // 1,40 × 2,00 × 0,025 × 1 = 0,07 m³
      expect(volOf('140', '200', '2.5', 1), Volume.parse('0.07'));
    });

    test('hacim toplamı kesin', () {
      final total = sumVolume([volOf('140', '200', '10', 50), volOf('140', '200', '5', 40)]);
      expect(total, Volume.parse('19.6'));
    });
  });

  group('Money', () {
    test('kuruş olarak saklanır', () {
      expect(Money.parse('59388.00').stored, 5938800);
      expect(Money.parse('0.01').stored, 1);
    });

    test('toplama ve çıkarma kesin', () {
      expect(Money.parse('0.10') + Money.parse('0.20'), Money.parse('0.30'));
      expect(sumMoney([Money.parse('42420'), Money.parse('8862')]), Money.parse('51282'));
    });

    test('karşılaştırma', () {
      expect(Money.parse('100') > Money.parse('99.99'), isTrue);
      expect(Money.parse('-5').isNegative, isTrue);
    });
  });

  group('UnitPrice × Volume = Money', () {
    test('14 m³ × 3.030,0000 = 42.420,00 (Altın Senaryo parti A1)', () {
      expect(UnitPrice.parse('3030').times(Volume.parse('14')), Money.parse('42420'));
    });

    test('2,8 m³ × 3.165 = 8.862,00 (parti B)', () {
      expect(UnitPrice.parse('3165').times(Volume.parse('2.8')), Money.parse('8862'));
    });

    test('19,6 m³ × 2.930 = 57.428,00 (çıplak alış A)', () {
      expect(UnitPrice.parse('2930').times(Volume.parse('19.6')), Money.parse('57428'));
    });

    test('16,8 m³ × 3.500 = 58.800,00 (satış)', () {
      expect(UnitPrice.parse('3500').times(Volume.parse('16.8')), Money.parse('58800'));
    });

    test('1,12 m³ × 3.300 = 3.696,00 (alış C)', () {
      expect(UnitPrice.parse('3300').times(Volume.parse('1.12')), Money.parse('3696'));
    });

    test('ağırlıklı ortalama: 16,8 × 3.070,5000 = 51.584,40', () {
      expect(UnitPrice.parse('3070.5').times(Volume.parse('16.8')), Money.parse('51584.40'));
    });

    test('kesim: 2,52 × 3.500 = 8.820,00 · 1,08 × 3.500 = 3.780,00', () {
      expect(UnitPrice.parse('3500').times(Volume.parse('2.52')), Money.parse('8820'));
      expect(UnitPrice.parse('3500').times(Volume.parse('1.08')), Money.parse('3780'));
    });
  });

  group('Rate', () {
    test('%20 saklama ve dönüşüm', () {
      final r = Rate.percent('20');
      expect(r.stored, 2000);
      expect(r.fraction, Decimal.parse('0.2'));
      expect(r.percent, Decimal.parse('20'));
    });
  });
}
