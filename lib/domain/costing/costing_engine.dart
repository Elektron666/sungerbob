import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

import '../core/allocation.dart';
import '../core/money.dart';
import '../core/quantity.dart';
import '../core/rounding.dart';
import '../core/scales.dart';
import 'batch_view.dart';

export 'batch_view.dart' show BatchView, CostAllocation, CostingResult;

/// Negatif stok yasağı (BRIEF §3.8). Stokta olmayan malın FIFO maliyeti
/// bilinemez, dolayısıyla kârı da bilinemez.
final class InsufficientStockException implements Exception {
  final String variantId;
  final int requiredPieces;
  final int availablePieces;

  const InsufficientStockException({
    required this.variantId,
    required this.requiredPieces,
    required this.availablePieces,
  });

  @override
  String toString() => 'Yetersiz stok: $requiredPieces adet isteniyor, '
      '$availablePieces adet var (varyant $variantId).';
}

/// Kesimde hedef toplam m³ kaynağı aşamaz (BRIEF §5.3).
final class CuttingVolumeException implements Exception {
  final Volume sourceVolume;
  final Volume targetVolume;

  const CuttingVolumeException({
    required this.sourceVolume,
    required this.targetVolume,
  });

  @override
  String toString() => 'Kesim hedefi kaynağı aşıyor: hedef $targetVolume, '
      'kaynak $sourceVolume.';
}

/// İade satılan miktarı aşamaz (BRIEF §5).
final class ReturnExceedsSoldException implements Exception {
  final int soldPieces;
  final int returnPieces;

  const ReturnExceedsSoldException({
    required this.soldPieces,
    required this.returnPieces,
  });

  @override
  String toString() =>
      'İade satılanı aşıyor: $returnPieces adet iade, $soldPieces adet satılmış.';
}

/// Sonradan gelen masrafın stok / satılmış ayrımı (BRIEF §3.7).
@immutable
final class LateExpenseSplit {
  /// Partinin birim maliyetine eklenecek pay (stokta kalan kısım).
  final Money toStock;

  /// `cost_adjustments`'a maliyet farkı olarak yazılacak pay
  /// (satılmış veya firelenmiş kısım). Geçmiş satışlar değişmez.
  final Money toAdjustment;

  const LateExpenseSplit({required this.toStock, required this.toAdjustment});
}

/// Masraf dağıtımında bir hedef satır.
@immutable
final class ExpenseTarget {
  final Volume volume;
  final Money bareCost;

  const ExpenseTarget({required this.volume, required this.bareCost});
}

/// Fason kesim maliyet sonucu.
@immutable
final class CuttingCostResult {
  final Money totalCost;
  final UnitPrice unitCost;
  final List<Money> targetCosts;

  /// Kesim firesi. Ayrı maliyet yazılmaz; hedeflerin birim maliyetine yedirilir
  /// ve fire raporunda miktarıyla görünür (BRIEF §5.3).
  final Volume wasteVolume;

  const CuttingCostResult({
    required this.totalCost,
    required this.unitCost,
    required this.targetCosts,
    required this.wasteVolume,
  });
}

/// Maliyet motoru. Saf Dart — veritabanı, Flutter veya I/O bilmez.
abstract final class CostingEngine {
  /// Partileri FIFO sırasına dizer: `(received_at, sequence)` (BRIEF §3.6).
  static List<BatchView> _fifoOrder(List<BatchView> batches) {
    final sorted = batches.where((b) => !b.isEmpty).toList()
      ..sort((a, b) {
        final byDate = a.receivedAt.compareTo(b.receivedAt);
        return byDate != 0 ? byDate : a.sequence.compareTo(b.sequence);
      });
    return sorted;
  }

  /// Partileri fiziksel olarak FIFO ile tüketir.
  ///
  /// [unitCostOverride] verilirse (ağırlıklı ortalama modu) maliyet o birim
  /// fiyattan yazılır; verilmezse her partinin kendi gerçek maliyetinden.
  static CostingResult _consume({
    required List<BatchView> batches,
    required int requiredPieces,
    required Volume requiredVolume,
    UnitPrice? unitCostOverride,
  }) {
    final ordered = _fifoOrder(batches);
    final available = ordered.fold(0, (s, b) => s + b.remainingPieces);

    if (available < requiredPieces) {
      throw InsufficientStockException(
        variantId: batches.isEmpty ? '?' : batches.first.variantId,
        requiredPieces: requiredPieces,
        availablePieces: available,
      );
    }

    final allocations = <CostAllocation>[];
    var remainingPieces = requiredPieces;
    var remainingVolume = requiredVolume;
    var seq = 0;

    for (final batch in ordered) {
      if (remainingPieces <= 0) break;

      final takePieces = remainingPieces < batch.remainingPieces
          ? remainingPieces
          : batch.remainingPieces;

      // Partinin tamamı alınıyorsa kalan hacmin tamamı gider; kısmi alımda
      // parça başına hacim kullanılır. Son partide kalan hacim birebir verilir
      // ki Σ hacim = istenen hacim değişmezi korunsun.
      final Volume takeVolume;
      if (takePieces == remainingPieces) {
        takeVolume = remainingVolume;
      } else if (takePieces == batch.remainingPieces) {
        takeVolume = batch.remainingVolume;
      } else {
        takeVolume = Volume(batch.unitVolume.stored * takePieces);
      }

      final unitCost = unitCostOverride ?? batch.realUnitCost;

      allocations.add(CostAllocation(
        batchId: batch.id,
        pieces: takePieces,
        volume: takeVolume,
        unitCost: unitCost,
        cost: unitCost.times(takeVolume),
        sequenceNo: seq++,
      ));

      remainingPieces -= takePieces;
      remainingVolume -= takeVolume;
    }

    return CostingResult(
      allocations: allocations,
      totalCost: sumMoney(allocations.map((a) => a.cost)),
    );
  }

  /// **FIFO (varsayılan).** Aynı varyantın ana depodaki partileri
  /// `(received_at, id)` sırasıyla tüketilir.
  static CostingResult fifo({
    required List<BatchView> batches,
    required int requiredPieces,
    required Volume requiredVolume,
  }) =>
      _consume(
        batches: batches,
        requiredPieces: requiredPieces,
        requiredVolume: requiredVolume,
      );

  /// **Ağırlıklı ortalama birim maliyet.** Ürün (çeşit) bazında, ana depodaki
  /// tüm kalan partilerin m³ ağırlıklı ortalaması (BRIEF §3.6, DECISIONS D-11).
  static UnitPrice weightedAverageUnitCost(List<BatchView> productBatches) {
    final live = productBatches.where((b) => !b.isEmpty).toList();
    if (live.isEmpty) return UnitPrice.zero;

    final totalVolume = sumVolume(live.map((b) => b.remainingVolume));
    if (totalVolume.isZero) return UnitPrice.zero;

    final totalCost = sumMoney(
        live.map((b) => b.realUnitCost.times(b.remainingVolume)));

    return UnitPrice.fromDecimal(roundHalfUp(
      (totalCost.tl / totalVolume.m3)
          .toDecimal(scaleOnInfinitePrecision: 12),
      Scales.unitPrice,
    ));
  }

  /// **Ağırlıklı ortalama modu.** Fiziksel tüketim yine FIFO'dur; yalnızca
  /// yazılan birim maliyet ürün bazlı ortalamadır.
  static CostingResult weightedAverage({
    required List<BatchView> batches,
    required List<BatchView> productBatches,
    required int requiredPieces,
    required Volume requiredVolume,
  }) {
    final avg = weightedAverageUnitCost(productBatches);
    final result = _consume(
      batches: batches,
      requiredPieces: requiredPieces,
      requiredVolume: requiredVolume,
      unitCostOverride: avg,
    );

    // Toplam maliyet, ortalama × toplam hacim olmalı. Satır bazındaki
    // yuvarlamalardan doğabilecek kuruş farkı son satıra yedirilir.
    final expected = avg.times(requiredVolume);
    final diff = expected - result.totalCost;
    if (diff.isZero || result.allocations.isEmpty) {
      return CostingResult(
          allocations: result.allocations, totalCost: expected);
    }

    final fixed = [...result.allocations];
    final last = fixed.removeLast();
    fixed.add(CostAllocation(
      batchId: last.batchId,
      pieces: last.pieces,
      volume: last.volume,
      unitCost: last.unitCost,
      cost: last.cost + diff,
      sequenceNo: last.sequenceNo,
    ));
    return CostingResult(allocations: fixed, totalCost: expected);
  }

  /// Alış masrafını satırlara dağıtır. Varsayılan anahtar m³ (BRIEF §3.7).
  /// Kuruş farkı son satıra eklenir.
  static List<Money> allocatePurchaseExpense({
    required Money expense,
    required List<ExpenseTarget> lines,
    bool byAmount = false,
  }) =>
      byAmount
          ? allocateByAmount(
              total: expense, weights: lines.map((l) => l.bareCost).toList())
          : allocateByVolume(
              total: expense, weights: lines.map((l) => l.volume).toList());

  /// Sonradan gelen masrafın bir partiye düşen payını, **stokta kalan** ve
  /// **satılmış/firelenmiş** kısımlara böler (BRIEF §3.7).
  ///
  /// Stokta kalana düşen pay partinin birim maliyetine eklenir; diğeri
  /// `cost_adjustments`'a dönem maliyet farkı olarak yazılır. Geçmiş satış
  /// satırları değişmez.
  static LateExpenseSplit splitLateExpense({
    required Money expenseShare,
    required Volume totalInVolume,
    required Volume remainingVolume,
  }) {
    if (totalInVolume.isZero) {
      return LateExpenseSplit(toStock: Money.zero, toAdjustment: expenseShare);
    }
    final ratio = (remainingVolume.m3 / totalInVolume.m3)
        .toDecimal(scaleOnInfinitePrecision: 12);
    final toStock = Money.fromDecimal(expenseShare.tl * ratio);
    return LateExpenseSplit(
      toStock: toStock,
      toAdjustment: expenseShare - toStock,
    );
  }

  /// **Fason kesim maliyeti** (BRIEF §5.3).
  ///
  /// Kaynak maliyeti + kesim ücreti + nakliye, hedeflere m³ oranında dağıtılır.
  /// Hedef toplam m³ kaynağı aşamaz. Aradaki fark kesim firesidir ve ayrı
  /// maliyet olarak yazılmaz — hedeflerin birim maliyetine yedirilir.
  static CuttingCostResult allocateCutting({
    required Money sourceCost,
    required Money cuttingFee,
    required Money freight,
    required Volume sourceVolume,
    required List<Volume> targets,
  }) {
    final targetTotal = sumVolume(targets);
    if (targetTotal > sourceVolume) {
      throw CuttingVolumeException(
          sourceVolume: sourceVolume, targetVolume: targetTotal);
    }

    final totalCost = sourceCost + cuttingFee + freight;
    final unitCost = targetTotal.isZero
        ? UnitPrice.zero
        : UnitPrice.fromDecimal(roundHalfUp(
            (totalCost.tl / targetTotal.m3)
                .toDecimal(scaleOnInfinitePrecision: 12),
            Scales.unitPrice,
          ));

    return CuttingCostResult(
      totalCost: totalCost,
      unitCost: unitCost,
      targetCosts: allocateByVolume(total: totalCost, weights: targets),
      wasteVolume: sourceVolume - targetTotal,
    );
  }

  /// **İade.** Mal, orijinal satışın tükettiği partilere **son tüketilenden
  /// başlayarak** aynı maliyetle döner (BRIEF §5, DECISIONS D-12).
  static List<CostAllocation> reverseForReturn({
    required List<CostAllocation> originalAllocations,
    required int returnPieces,
  }) {
    final sold = originalAllocations.fold(0, (s, a) => s + a.pieces);
    if (returnPieces > sold) {
      throw ReturnExceedsSoldException(
          soldPieces: sold, returnPieces: returnPieces);
    }

    final reversed = [...originalAllocations]
      ..sort((a, b) => b.sequenceNo.compareTo(a.sequenceNo));

    final result = <CostAllocation>[];
    var left = returnPieces;
    var seq = 0;

    for (final alloc in reversed) {
      if (left <= 0) break;

      final take = left < alloc.pieces ? left : alloc.pieces;
      final unitVolume = Volume(alloc.volume.stored ~/ alloc.pieces);
      final volume = take == alloc.pieces
          ? alloc.volume
          : Volume(unitVolume.stored * take);

      result.add(CostAllocation(
        batchId: alloc.batchId,
        pieces: take,
        volume: volume,
        unitCost: alloc.unitCost,
        // İade, malın çıktığı maliyetle döner — yeniden hesaplanmaz.
        cost: take == alloc.pieces
            ? alloc.cost
            : alloc.unitCost.times(volume),
        sequenceNo: seq++,
      ));

      left -= take;
    }

    return result;
  }
}
