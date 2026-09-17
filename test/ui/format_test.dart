import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/ui/format/tr_format.dart';

void main() {
  group('Sayı gösterimi (BRIEF §2: 1.234,56)', () {
    test('para binlik ayracı nokta, ondalık virgül', () {
      expect(TrFormat.money(Money.parse('1234.56')), '1.234,56');
      expect(TrFormat.money(Money.parse('59388')), '59.388,00');
      expect(TrFormat.money(Money.parse('0')), '0,00');
      expect(TrFormat.money(Money.parse('-5880')), '-5.880,00');
    });

    test('para birimi ekli gösterim', () {
      expect(TrFormat.moneyWithCurrency(Money.parse('70560')), '70.560,00 TL');
    });

    test('m³ altı haneye kadar, gereksiz sıfırlar atılır', () {
      expect(TrFormat.volume(Volume.parse('14')), '14 m³');
      expect(TrFormat.volume(Volume.parse('0.28')), '0,28 m³');
      expect(TrFormat.volume(Volume.parse('11.76')), '11,76 m³');
      expect(TrFormat.volume(Volume.parse('5.32')), '5,32 m³');
    });

    test('birim fiyat dört haneye kadar', () {
      expect(TrFormat.unitPrice(UnitPrice.parse('3030')), '3.030,00 TL/m³');
      expect(TrFormat.unitPrice(UnitPrice.parse('3070.5')), '3.070,50 TL/m³');
    });

    test('oran', () {
      expect(TrFormat.rate(Rate.percent('20')), '%20');
      expect(TrFormat.rate(Rate.percent('12.79')), '%12,79');
    });

    test('yüzde (Decimal)', () {
      expect(TrFormat.percent(Decimal.parse('12.7857')), '%12,79');
      expect(TrFormat.percent(null), '—');
    });

    test('adet', () {
      expect(TrFormat.pieces(60), '60 adet');
      expect(TrFormat.pieces(1250), '1.250 adet');
    });
  });

  group('Tarih (dd.MM.yyyy)', () {
    test('tarih biçimi', () {
      expect(TrFormat.date(DateTime(2026, 9, 17)), '17.09.2026');
      expect(TrFormat.date(DateTime(2026, 1, 5)), '05.01.2026');
    });

    test('tarih ve saat', () {
      expect(
        TrFormat.dateTime(DateTime(2026, 9, 17, 14, 32)),
        '17.09.2026 14:32',
      );
    });

    test('null tarih', () {
      expect(TrFormat.date(null), '—');
    });
  });

  group('Sayı girişi — virgül VE nokta kabul edilir (BRIEF §2)', () {
    test('virgüllü giriş', () {
      expect(TrFormat.parseDecimal('3,5'), Decimal.parse('3.5'));
      expect(TrFormat.parseDecimal('1234,56'), Decimal.parse('1234.56'));
    });

    test('noktalı giriş', () {
      expect(TrFormat.parseDecimal('3.5'), Decimal.parse('3.5'));
    });

    test('binlik ayracı temizlenir', () {
      expect(TrFormat.parseDecimal('1.234,56'), Decimal.parse('1234.56'));
      expect(TrFormat.parseDecimal('59.388,00'), Decimal.parse('59388'));
    });

    test('boşluk ve TL eki temizlenir', () {
      expect(TrFormat.parseDecimal(' 1.234,56 TL '), Decimal.parse('1234.56'));
    });

    test('geçersiz giriş null döner', () {
      expect(TrFormat.parseDecimal('abc'), isNull);
      expect(TrFormat.parseDecimal(''), isNull);
      expect(TrFormat.parseDecimal('1,2,3'), isNull);
    });

    test('para girişi', () {
      expect(TrFormat.parseMoney('3.500,00'), Money.parse('3500'));
      expect(TrFormat.parseMoney('3500'), Money.parse('3500'));
      expect(TrFormat.parseMoney('abc'), isNull);
    });

    test('ölçü girişi: 2,5 cm kalınlık', () {
      expect(TrFormat.parseDimension('2,5'), Dimension.cm('2.5'));
      expect(TrFormat.parseDimension('140'), Dimension.cm('140'));
    });

    test('negatif giriş', () {
      expect(TrFormat.parseDecimal('-5,5'), Decimal.parse('-5.5'));
    });
  });

  group('Gidiş-dönüş', () {
    test('biçimlendir → ayrıştır aynı değeri verir', () {
      for (final value in ['0.01', '1234.56', '59388', '1000000.99']) {
        final money = Money.parse(value);
        expect(
          TrFormat.parseMoney(TrFormat.money(money)),
          money,
          reason: '$value gidiş-dönüşte korunmalı',
        );
      }
    });
  });
}
