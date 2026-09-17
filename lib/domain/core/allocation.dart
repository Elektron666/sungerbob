import 'package:decimal/decimal.dart';

import 'money.dart';
import 'quantity.dart';
import 'rounding.dart';
import 'scales.dart';

/// Bir tutarı ağırlıklara göre satırlara dağıtır (BRIEF §3.3).
///
/// Değişmez: **`Σ dağıtılan = total`**. Yuvarlama nedeniyle oluşan kuruş farkı
/// her zaman **son satıra** eklenir. Ağırlıkların toplamı sıfırsa tüm paylar
/// sıfır olur ve tutarın tamamı son satıra düşer.
List<Money> _allocate(Money total, List<Decimal> weights) {
  if (weights.isEmpty) return const [];
  if (weights.length == 1) return [total];

  final weightSum = weights.fold(Decimal.zero, (a, b) => a + b);
  final result = <Money>[];

  if (weightSum == Decimal.zero) {
    for (var i = 0; i < weights.length - 1; i++) {
      result.add(Money.zero);
    }
    result.add(total);
    return result;
  }

  // Son satır hariç hepsi orantıyla hesaplanır ve kuruşa yuvarlanır.
  for (var i = 0; i < weights.length - 1; i++) {
    final share = (total.tl * weights[i]) / weightSum;
    result.add(
      Money.fromDecimal(
        roundHalfUp(
          share.toDecimal(scaleOnInfinitePrecision: 12),
          Scales.money,
        ),
      ),
    );
  }

  // Son satır: kalanın tamamı. Toplamın korunmasını bu garanti eder.
  result.add(total - sumMoney(result));
  return result;
}

/// m³ anahtarıyla dağıtım (varsayılan — nakliye, hamaliye, kesim maliyeti).
List<Money> allocateByVolume({
  required Money total,
  required List<Volume> weights,
}) => _allocate(total, weights.map((v) => v.m3).toList());

/// Tutar anahtarıyla dağıtım (alternatif).
List<Money> allocateByAmount({
  required Money total,
  required List<Money> weights,
}) => _allocate(total, weights.map((m) => m.tl).toList());
