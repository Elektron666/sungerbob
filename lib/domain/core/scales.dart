/// Sabit ölçek katsayıları (BRIEF §3.2 · ARCHITECTURE §3).
///
/// SQLite'ta kesin ondalık tip yoktur; bu yüzden **hiçbir** sayısal değer
/// ondalık olarak saklanmaz. Her değer, aşağıdaki ölçekle çarpılmış bir
/// `INTEGER` olarak durur ve Dart'ta `Decimal`'e çevrilir.
///
/// Ölçek katsayısı başka hiçbir yerde yazılmaz — tek kaynak burasıdır.
abstract final class Scales {
  /// Para: kuruş. 59.388,00 TL → 5938800
  static const int money = 2;

  /// Birim fiyat (TL/m³, TL/plaka). 3.030,0000 → 30300000
  static const int unitPrice = 4;

  /// Hacim (m³). 14,000000 → 14000000
  static const int volume = 6;

  /// Ölçü (cm; kalınlık 2,5 olabilir). 140 cm → 14000
  static const int dimension = 2;

  /// Oran (%). %20 → 2000
  static const int rate = 2;
}
