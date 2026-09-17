import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

import 'rounding.dart';
import 'scales.dart';

/// Para tutarı. İçeride **kuruş** (int) tutar — saklama biçimiyle birebir aynı.
///
/// Toplama ve çıkarma tamsayı üzerinde yapıldığı için kesindir. Çarpma ve
/// bölme `Decimal` üzerinden gider ve sonunda ROUND_HALF_UP ile kuruşa iner.
/// `double` hiçbir aşamada kullanılmaz (BRIEF §2).
@immutable
final class Money implements Comparable<Money> {
  /// Kuruş cinsinden tutar. Veritabanında saklanan değerin aynısı.
  final int minor;

  const Money(this.minor);

  static const Money zero = Money(0);

  /// Veritabanından okunan ölçekli tamsayıdan.
  factory Money.fromStored(int stored) => Money(stored);

  /// `Decimal` TL tutarından (ROUND_HALF_UP ile kuruşa iner).
  factory Money.fromDecimal(Decimal tl) =>
      Money((roundHalfUp(tl, Scales.money) * _factor).toBigInt().toInt());

  /// `'59388.00'` gibi bir metinden.
  factory Money.parse(String tl) => Money.fromDecimal(Decimal.parse(tl));

  static final Decimal _factor = Decimal.fromInt(100);

  /// Veritabanına yazılacak ölçekli tamsayı.
  int get stored => minor;

  /// TL cinsinden kesin değer.
  Decimal get tl => (Decimal.fromInt(minor) / _factor).toDecimal(
    scaleOnInfinitePrecision: Scales.money,
  );

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  Money operator +(Money other) => Money(minor + other.minor);
  Money operator -(Money other) => Money(minor - other.minor);
  Money operator -() => Money(-minor);

  /// Bir oranla çarpar (ör. KDV oranı, iskonto). Sonuç kuruşa yuvarlanır.
  Money multiplyBy(Decimal factor) => Money.fromDecimal(tl * factor);

  Money get abs => Money(minor.abs());

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  bool operator <(Money other) => minor < other.minor;
  bool operator <=(Money other) => minor <= other.minor;
  bool operator >(Money other) => minor > other.minor;
  bool operator >=(Money other) => minor >= other.minor;

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => '${tl.toStringAsFixed(Scales.money)} TL'; // ignore: allowed-double — yalnızca hata ayıklama gösterimi
}

/// Bir `Money` listesini toplar. Tamsayı toplaması olduğu için kesindir.
Money sumMoney(Iterable<Money> items) =>
    items.fold(Money.zero, (a, b) => a + b);
