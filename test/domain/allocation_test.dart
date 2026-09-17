import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/core/allocation.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';

void main() {
  group('allocateByVolume — kuruş farkı son satıra (BRIEF §3.3)', () {
    test('Altın Senaryo 1: nakliye 1.960,00 TL, 14 + 5,6 m³', () {
      final r = allocateByVolume(
        total: Money.parse('1960'),
        weights: [Volume.parse('14'), Volume.parse('5.6')],
      );
      expect(r, [Money.parse('1400'), Money.parse('560')]);
      expect(sumMoney(r), Money.parse('1960'));
    });

    test('kesim: 12.600,00 TL, 2,52 + 1,08 m³', () {
      final r = allocateByVolume(
        total: Money.parse('12600'),
        weights: [Volume.parse('2.52'), Volume.parse('1.08')],
      );
      expect(r, [Money.parse('8820'), Money.parse('3780')]);
    });

    test('bölünemeyen tutar: 1,00 TL üçe bölünür, fark son satırda', () {
      final r = allocateByVolume(
        total: Money.parse('1.00'),
        weights: [Volume.parse('1'), Volume.parse('1'), Volume.parse('1')],
      );
      expect(r, [
        Money.parse('0.33'),
        Money.parse('0.33'),
        Money.parse('0.34'),
      ]);
      expect(sumMoney(r), Money.parse('1.00'));
    });

    test('değişmez: dağıtım toplamı her zaman orijinale eşit', () {
      final cases = <(String, List<String>)>[
        ('1000.01', ['3', '7']),
        ('0.03', ['1', '1', '1']),
        ('7777.77', ['1.111111', '2.222222', '3.333333']),
        ('0.01', ['5', '5']),
        ('123456.78', ['0.000001', '99.999999']),
      ];
      for (final (total, ws) in cases) {
        final r = allocateByVolume(
          total: Money.parse(total),
          weights: ws.map(Volume.parse).toList(),
        );
        expect(
          sumMoney(r),
          Money.parse(total),
          reason: 'toplam $total korunmalı',
        );
      }
    });

    test('negatif tutar da doğru dağıtılır', () {
      final r = allocateByVolume(
        total: Money.parse('-1.00'),
        weights: [Volume.parse('1'), Volume.parse('1'), Volume.parse('1')],
      );
      expect(sumMoney(r), Money.parse('-1.00'));
    });

    test('sıfır ağırlık toplamı → hepsi sıfır, fark son satıra', () {
      final r = allocateByVolume(
        total: Money.parse('10'),
        weights: [Volume.zero, Volume.zero],
      );
      expect(sumMoney(r), Money.parse('10'));
    });
  });

  group('allocateByAmount — tutar anahtarı', () {
    test('tutara göre dağıtır ve toplamı korur', () {
      final r = allocateByAmount(
        total: Money.parse('100'),
        weights: [Money.parse('30'), Money.parse('70')],
      );
      expect(r, [Money.parse('30'), Money.parse('70')]);
      expect(sumMoney(r), Money.parse('100'));
    });

    test('küsuratlı dağıtımda toplam korunur', () {
      final r = allocateByAmount(
        total: Money.parse('10'),
        weights: [Money.parse('1'), Money.parse('1'), Money.parse('1')],
      );
      expect(sumMoney(r), Money.parse('10'));
    });
  });
}
