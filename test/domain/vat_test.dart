import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

final vat20 = Rate.percent('20');

void main() {
  group('KDV Hariç (EXCL)', () {
    test(
      '16,8 m³ × 3.500 → net 58.800, KDV 11.760, brüt 70.560 (Altın Senaryo 3)',
      () {
        final line = VatCalculator.excluding(
          volume: Volume.parse('16.8'),
          unitPrice: UnitPrice.parse('3500'),
          vatRate: vat20,
        );
        expect(line.net, Money.parse('58800'));
        expect(line.vat, Money.parse('11760'));
        expect(line.gross, Money.parse('70560'));
      },
    );

    test('iskonto net tutara uygulanır', () {
      final line = VatCalculator.excluding(
        volume: Volume.parse('10'),
        unitPrice: UnitPrice.parse('1000'),
        vatRate: vat20,
        discountRate: Rate.percent('10'),
      );
      expect(line.net, Money.parse('9000'));
      expect(line.vat, Money.parse('1800'));
      expect(line.gross, Money.parse('10800'));
    });

    test(
      'iade satırı: 1,4 m³ × 3.500 → net 4.900, KDV 980, brüt 5.880 (adım 8)',
      () {
        final line = VatCalculator.excluding(
          volume: Volume.parse('1.4'),
          unitPrice: UnitPrice.parse('3500'),
          vatRate: vat20,
        );
        expect(line.net, Money.parse('4900'));
        expect(line.gross, Money.parse('5880'));
      },
    );

    test('kesim ücreti 1.000 + %20 → kesimhane carisi 1.200 (Ek C)', () {
      final line = VatCalculator.excludingFromNet(
        net: Money.parse('1000'),
        vatRate: vat20,
      );
      expect(line.vat, Money.parse('200'));
      expect(line.gross, Money.parse('1200'));
    });
  });

  group('KDV Dahil (INCL) — girilen tutar AYNEN korunur (Ek B)', () {
    test('4.200,00 dahil %20 → net 3.500,00 · KDV 700,00', () {
      final line = VatCalculator.includingFromGross(
        gross: Money.parse('4200'),
        vatRate: vat20,
      );
      expect(line.net, Money.parse('3500'));
      expect(line.vat, Money.parse('700'));
      expect(line.gross, Money.parse('4200'));
    });

    test(
      '1.000,00 dahil %20 → KDV 166,67 · net 833,33 · toplam TAM 1.000,00',
      () {
        final line = VatCalculator.includingFromGross(
          gross: Money.parse('1000'),
          vatRate: vat20,
        );
        expect(line.vat, Money.parse('166.67'));
        expect(line.net, Money.parse('833.33'));
        expect(line.gross, Money.parse('1000'));
        // Değişmez: net + KDV her zaman girilen brüte eşit.
        expect(line.net + line.vat, Money.parse('1000'));
      },
    );

    test('değişmez: her tutarda net + KDV = girilen brüt', () {
      for (final g in ['0.01', '0.99', '1', '33.33', '999.99', '123456.78']) {
        final line = VatCalculator.includingFromGross(
          gross: Money.parse(g),
          vatRate: vat20,
        );
        expect(
          line.net + line.vat,
          Money.parse(g),
          reason: 'brüt $g korunmalı',
        );
      }
    });

    test('%0 KDV: net = brüt', () {
      final line = VatCalculator.includingFromGross(
        gross: Money.parse('500'),
        vatRate: Rate.zero,
      );
      expect(line.net, Money.parse('500'));
      expect(line.vat, Money.zero);
    });
  });

  group('Kâr (her zaman KDV hariç)', () {
    test(
      'Altın Senaryo 3: kâr 7.518,00 · marj %12,79 · maliyet üstü %14,66',
      () {
        final p = ProfitCalculator.of(
          netRevenue: Money.parse('58800'),
          cost: Money.parse('51282'),
        );
        expect(p.grossProfit, Money.parse('7518'));
        expect(p.marginPercent!.toStringAsFixed(2), '12.79');
        expect(p.markupPercent!.toStringAsFixed(2), '14.66');
      },
    );

    test('SPEC §8 örneği: maliyet 2.930, satış 3.200', () {
      final p = ProfitCalculator.of(
        netRevenue: Money.parse('3200'),
        cost: Money.parse('2930'),
      );
      expect(p.grossProfit, Money.parse('270'));
      expect(p.marginPercent!.toStringAsFixed(2), '8.44');
      expect(p.markupPercent!.toStringAsFixed(2), '9.22');
    });

    test('maliyet sıfırsa maliyet üstü kâr tanımsız (null)', () {
      final p = ProfitCalculator.of(
        netRevenue: Money.parse('100'),
        cost: Money.zero,
      );
      expect(p.markupPercent, isNull);
    });
  });
}
