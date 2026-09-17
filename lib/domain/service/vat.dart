import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

import '../core/money.dart';
import '../core/quantity.dart';
import '../core/rounding.dart';
import '../core/scales.dart';

/// Belgede fiyat giriş modu (BRIEF §3.4).
enum PriceMode {
  /// Girilen fiyat KDV hariçtir.
  excl,

  /// Girilen tutar KDV dahildir ve **aynen korunur**.
  incl;

  String get code => this == PriceMode.excl ? 'EXCL' : 'INCL';

  static PriceMode fromCode(String code) =>
      code == 'INCL' ? PriceMode.incl : PriceMode.excl;
}

/// Bir satırın net / KDV / brüt üçlüsü. Üçü de ayrı saklanır (BRIEF §3.4).
@immutable
final class VatLine {
  final Money net;
  final Money vat;
  final Money gross;

  const VatLine({required this.net, required this.vat, required this.gross});

  @override
  bool operator ==(Object other) =>
      other is VatLine &&
      other.net == net &&
      other.vat == vat &&
      other.gross == gross;

  @override
  int get hashCode => Object.hash(net, vat, gross);

  @override
  String toString() => 'net: $net · KDV: $vat · brüt: $gross';
}

abstract final class VatCalculator {
  /// KDV hariç mod: miktar × birim fiyat × (1 − iskonto) → net, sonra KDV eklenir.
  ///
  /// Ara değerler yuvarlanmaz; net **tek seferde** kuruşa yuvarlanır (BRIEF §3.3).
  static VatLine excluding({
    required Volume volume,
    required UnitPrice unitPrice,
    required Rate vatRate,
    Rate discountRate = Rate.zero,
  }) {
    final raw = volume.m3 * unitPrice.perM3;
    final discounted = raw * (Decimal.one - discountRate.fraction);
    return excludingFromNet(
      net: Money.fromDecimal(discounted),
      vatRate: vatRate,
    );
  }

  /// Net tutar zaten belliyken KDV ve brütü türetir.
  static VatLine excludingFromNet({required Money net, required Rate vatRate}) {
    final vat = Money.fromDecimal(net.tl * vatRate.fraction);
    return VatLine(net: net, vat: vat, gross: net + vat);
  }

  /// KDV dahil mod: girilen brüt **aynen korunur** (BRIEF §3.4).
  ///
  /// `KDV = yuvarla(brüt − brüt / (1 + oran))`, `net = brüt − KDV`.
  /// Net'i ayrıca yuvarlamak yerine brütten çıkarmak, `net + KDV = brüt`
  /// değişmezini her tutarda garanti eder.
  static VatLine includingFromGross({
    required Money gross,
    required Rate vatRate,
  }) {
    if (vatRate.isZero) {
      return VatLine(net: gross, vat: Money.zero, gross: gross);
    }
    final divisor = Decimal.one + vatRate.fraction;
    final netRaw = (gross.tl / divisor).toDecimal(scaleOnInfinitePrecision: 12);
    final vat = Money.fromDecimal(roundHalfUp(gross.tl - netRaw, Scales.money));
    return VatLine(net: gross - vat, vat: vat, gross: gross);
  }

  /// Mod'a göre satır hesabı.
  static VatLine forMode({
    required PriceMode mode,
    required Volume volume,
    required UnitPrice unitPrice,
    required Rate vatRate,
    Rate discountRate = Rate.zero,
  }) {
    switch (mode) {
      case PriceMode.excl:
        return excluding(
          volume: volume,
          unitPrice: unitPrice,
          vatRate: vatRate,
          discountRate: discountRate,
        );
      case PriceMode.incl:
        final raw = volume.m3 * unitPrice.perM3;
        final discounted = raw * (Decimal.one - discountRate.fraction);
        return includingFromGross(
          gross: Money.fromDecimal(discounted),
          vatRate: vatRate,
        );
    }
  }
}

/// Kâr hesapları. **Her zaman KDV hariç** tutarlar üzerinden (BRIEF §3.4).
@immutable
final class ProfitCalculator {
  final Money netRevenue;
  final Money cost;

  const ProfitCalculator._({required this.netRevenue, required this.cost});

  factory ProfitCalculator.of({
    required Money netRevenue,
    required Money cost,
  }) => ProfitCalculator._(netRevenue: netRevenue, cost: cost);

  Money get grossProfit => netRevenue - cost;

  /// Kâr marjı = kâr / net satış. Ciro sıfırsa tanımsız.
  Decimal? get marginPercent {
    if (netRevenue.isZero) return null;
    return ((grossProfit.tl / netRevenue.tl).toDecimal(
          scaleOnInfinitePrecision: 12,
        ) *
        Decimal.fromInt(100));
  }

  /// Maliyet üzerine kâr = kâr / maliyet. Maliyet sıfırsa tanımsız
  /// (SPEC §8: iki yüzde birbirine karıştırılmamalı).
  Decimal? get markupPercent {
    if (cost.isZero) return null;
    return ((grossProfit.tl / cost.tl).toDecimal(scaleOnInfinitePrecision: 12) *
        Decimal.fromInt(100));
  }
}
