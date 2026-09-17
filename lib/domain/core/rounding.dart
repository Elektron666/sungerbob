import 'package:decimal/decimal.dart';

/// Sistemdeki **tek** yuvarlama kaynağı (BRIEF §3.3).
///
/// Kural: ROUND_HALF_UP. Tam yarım değerler sayı ekseninde yukarı gider
/// (2,5 → 3 ve −2,5 → −2). Başka hiçbir yerde yuvarlama yapılmaz; ara
/// değerler yuvarlanmadan taşınır ve satır toplamı **tek seferde** yuvarlanır.
Decimal roundHalfUp(Decimal value, int decimals) {
  assert(decimals >= 0, 'ondalık basamak negatif olamaz');
  final factor = (Decimal.ten.pow(decimals)).toDecimal();
  final shifted = value * factor;
  final floor = shifted.floor();
  final fraction = shifted - floor;
  final rounded = fraction >= Decimal.parse('0.5')
      ? floor + Decimal.one
      : floor;
  return (rounded / factor).toDecimal(scaleOnInfinitePrecision: decimals);
}
