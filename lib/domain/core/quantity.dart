import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

import 'money.dart';
import 'rounding.dart';
import 'scales.dart';

/// Ölçü (cm). İçeride cm ×100 tutar — 2,5 cm kalınlık temsil edilebilir.
@immutable
final class Dimension {
  final int stored;
  const Dimension(this.stored);

  factory Dimension.fromStored(int stored) => Dimension(stored);
  factory Dimension.cm(String cm) =>
      Dimension((Decimal.parse(cm) * Decimal.fromInt(100)).toBigInt().toInt());

  Decimal get cm => (Decimal.fromInt(stored) / Decimal.fromInt(100)).toDecimal(
    scaleOnInfinitePrecision: Scales.dimension,
  );

  @override
  bool operator ==(Object other) =>
      other is Dimension && other.stored == stored;
  @override
  int get hashCode => stored.hashCode;
  @override
  String toString() => cm.toString();
}

/// Hacim (m³). İçeride m³ ×1.000.000 tutar.
@immutable
final class Volume implements Comparable<Volume> {
  final int stored;
  const Volume(this.stored);

  static const Volume zero = Volume(0);

  factory Volume.fromStored(int stored) => Volume(stored);
  factory Volume.fromDecimal(Decimal m3) =>
      Volume((roundHalfUp(m3, Scales.volume) * _factor).toBigInt().toInt());
  factory Volume.parse(String m3) => Volume.fromDecimal(Decimal.parse(m3));

  /// m³ = (en/100) × (boy/100) × (kalınlık/100) × adet   (BRIEF §3.3)
  ///
  /// Ölçüler cm×100 tamsayı olduğu için hesap tamsayı çarpımıyla yapılır:
  /// (w · h · t · adet) / 10⁶ → m³ ×10⁶. Bölme tam çıkmazsa ROUND_HALF_UP.
  factory Volume.fromDimensions({
    required Dimension width,
    required Dimension height,
    required Dimension thickness,
    required int pieces,
  }) {
    final product = Decimal.fromBigInt(
      BigInt.from(width.stored) *
          BigInt.from(height.stored) *
          BigInt.from(thickness.stored) *
          BigInt.from(pieces),
    );
    final scaled = (product / Decimal.fromInt(1000000)).toDecimal(
      scaleOnInfinitePrecision: 0,
    );
    return Volume(roundHalfUp(scaled, 0).toBigInt().toInt());
  }

  static final Decimal _factor = Decimal.fromInt(1000000);

  Decimal get m3 => (Decimal.fromInt(stored) / _factor).toDecimal(
    scaleOnInfinitePrecision: Scales.volume,
  );

  bool get isZero => stored == 0;
  bool get isNegative => stored < 0;
  bool get isPositive => stored > 0;

  Volume operator +(Volume other) => Volume(stored + other.stored);
  Volume operator -(Volume other) => Volume(stored - other.stored);
  Volume operator -() => Volume(-stored);
  Volume get abs => Volume(stored.abs());

  @override
  int compareTo(Volume other) => stored.compareTo(other.stored);
  bool operator <(Volume other) => stored < other.stored;
  bool operator <=(Volume other) => stored <= other.stored;
  bool operator >(Volume other) => stored > other.stored;
  bool operator >=(Volume other) => stored >= other.stored;

  @override
  bool operator ==(Object other) => other is Volume && other.stored == stored;
  @override
  int get hashCode => stored.hashCode;
  @override
  String toString() => '${m3.toStringAsFixed(Scales.volume)} m³'; // ignore: allowed-double — yalnızca hata ayıklama gösterimi
}

Volume sumVolume(Iterable<Volume> items) =>
    items.fold(Volume.zero, (a, b) => a + b);

/// Birim fiyat (TL/m³ veya TL/plaka). İçeride ×10.000 tutar.
@immutable
final class UnitPrice implements Comparable<UnitPrice> {
  final int stored;
  const UnitPrice(this.stored);

  static const UnitPrice zero = UnitPrice(0);

  factory UnitPrice.fromStored(int stored) => UnitPrice(stored);
  factory UnitPrice.fromDecimal(Decimal perM3) => UnitPrice(
    (roundHalfUp(perM3, Scales.unitPrice) * _factor).toBigInt().toInt(),
  );
  factory UnitPrice.parse(String perM3) =>
      UnitPrice.fromDecimal(Decimal.parse(perM3));

  static final Decimal _factor = Decimal.fromInt(10000);

  Decimal get perM3 => (Decimal.fromInt(stored) / _factor).toDecimal(
    scaleOnInfinitePrecision: Scales.unitPrice,
  );

  bool get isZero => stored == 0;

  /// Tutar = hacim × birim fiyat. Tek seferde kuruşa yuvarlanır.
  Money times(Volume volume) => Money.fromDecimal(volume.m3 * perM3);

  UnitPrice operator +(UnitPrice other) => UnitPrice(stored + other.stored);
  UnitPrice operator -(UnitPrice other) => UnitPrice(stored - other.stored);

  @override
  int compareTo(UnitPrice other) => stored.compareTo(other.stored);

  @override
  bool operator ==(Object other) =>
      other is UnitPrice && other.stored == stored;
  @override
  int get hashCode => stored.hashCode;
  @override
  String toString() => '${perM3.toStringAsFixed(Scales.unitPrice)} TL/m³'; // ignore: allowed-double — yalnızca hata ayıklama gösterimi
}

/// Oran (%). İçeride ×100 tutar. %20 → 2000.
@immutable
final class Rate {
  final int stored;
  const Rate(this.stored);

  static const Rate zero = Rate(0);

  factory Rate.fromStored(int stored) => Rate(stored);
  factory Rate.percent(String percent) =>
      Rate((Decimal.parse(percent) * Decimal.fromInt(100)).toBigInt().toInt());

  /// %20 → 0,20
  Decimal get fraction => (Decimal.fromInt(stored) / Decimal.fromInt(10000))
      .toDecimal(scaleOnInfinitePrecision: 6);

  /// %20 → 20
  Decimal get percent => (Decimal.fromInt(stored) / Decimal.fromInt(100))
      .toDecimal(scaleOnInfinitePrecision: Scales.rate);

  bool get isZero => stored == 0;

  @override
  bool operator ==(Object other) => other is Rate && other.stored == stored;
  @override
  int get hashCode => stored.hashCode;
  @override
  String toString() => '%${percent.toString()}';
}
