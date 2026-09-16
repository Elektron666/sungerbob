import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/core/rounding.dart';

void main() {
  group('roundHalfUp — tek yuvarlama kaynağı', () {
    test('yarım yukarı yuvarlar (pozitif)', () {
      expect(roundHalfUp(Decimal.parse('2.5'), 0), Decimal.parse('3'));
      expect(roundHalfUp(Decimal.parse('1.5'), 0), Decimal.parse('2'));
      expect(roundHalfUp(Decimal.parse('0.5'), 0), Decimal.parse('1'));
      expect(roundHalfUp(Decimal.parse('2.4999'), 0), Decimal.parse('2'));
    });

    test('bankacı yuvarlaması DEĞİL', () {
      // ROUND_HALF_EVEN olsaydı 2.5 -> 2 ve 0.5 -> 0 olurdu.
      expect(roundHalfUp(Decimal.parse('2.5'), 0), isNot(Decimal.parse('2')));
      expect(roundHalfUp(Decimal.parse('0.5'), 0), isNot(Decimal.zero));
    });

    test('yarım yukarı yuvarlar (negatif): -2.5 -> -2', () {
      // HALF_UP burada "yukarı" yönü sıfırdan uzağa değil, sayı ekseninde yukarıdır.
      expect(roundHalfUp(Decimal.parse('-2.5'), 0), Decimal.parse('-2'));
      expect(roundHalfUp(Decimal.parse('-2.6'), 0), Decimal.parse('-3'));
    });

    test('ondalık basamakla yuvarlar', () {
      expect(roundHalfUp(Decimal.parse('166.665'), 2), Decimal.parse('166.67'));
      expect(roundHalfUp(Decimal.parse('833.3333'), 2), Decimal.parse('833.33'));
      expect(roundHalfUp(Decimal.parse('3030.00005'), 4), Decimal.parse('3030.0001'));
    });

    test('zaten yuvarlaksa değiştirmez', () {
      expect(roundHalfUp(Decimal.parse('42420.00'), 2), Decimal.parse('42420'));
    });
  });
}
