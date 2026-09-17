import 'package:meta/meta.dart';

import '../core/money.dart';
import '../core/quantity.dart';

/// Maliyet motorunun gördüğü parti. Veri katmanından bağımsız, salt okunur.
@immutable
final class BatchView {
  final String id;
  final String variantId;
  final String productId;

  /// FIFO sırasının birincil anahtarı (BRIEF §3.6).
  final DateTime receivedAt;

  /// `receivedAt` eşitliğinde kırıcı. Veri katmanında parti id'si (UUID v7)
  /// sıralanabilir olduğu için onun sırasını taşır.
  final int sequence;

  final int remainingPieces;
  final Volume remainingVolume;

  /// Masraflar dağıtıldıktan sonraki **gerçek** birim maliyet.
  final UnitPrice realUnitCost;

  const BatchView({
    required this.id,
    required this.variantId,
    required this.productId,
    required this.receivedAt,
    required this.sequence,
    required this.remainingPieces,
    required this.remainingVolume,
    required this.realUnitCost,
  });

  bool get isEmpty => remainingPieces <= 0 || remainingVolume.stored <= 0;

  /// Bir parçanın hacmi. Kısmi tüketimde kullanılır.
  Volume get unitVolume => remainingPieces <= 0
      ? Volume.zero
      : Volume(remainingVolume.stored ~/ remainingPieces);
}

/// Bir çıkışın tek bir partiye düşen payı. `cost_allocations` satırına karşılık gelir.
@immutable
final class CostAllocation {
  final String batchId;
  final int pieces;
  final Volume volume;
  final UnitPrice unitCost;
  final Money cost;

  /// Tüketim sırası. İade bu sıranın **tersinden** okunur (BRIEF §5).
  final int sequenceNo;

  const CostAllocation({
    required this.batchId,
    required this.pieces,
    required this.volume,
    required this.unitCost,
    required this.cost,
    required this.sequenceNo,
  });

  @override
  String toString() =>
      'CostAllocation($batchId, $pieces adet, $volume, $cost, #$sequenceNo)';
}

/// Bir çıkışın tüm maliyet dağılımı.
@immutable
final class CostingResult {
  final List<CostAllocation> allocations;
  final Money totalCost;

  const CostingResult({required this.allocations, required this.totalCost});
}
