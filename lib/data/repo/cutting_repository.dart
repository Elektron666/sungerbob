import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

final class CuttingSourceInput {
  final String batchId;
  final int pieces;
  const CuttingSourceInput({required this.batchId, required this.pieces});
}

final class CuttingResultInput {
  final String variantId;
  final int pieces;
  final bool isRemnant;
  const CuttingResultInput({
    required this.variantId,
    required this.pieces,
    this.isRemnant = false,
  });
}

/// Fason kesim emri (BRIEF §5).
///
/// Mal ana depodan sanal "Kesimde" konumuna transfer edilir; satılamaz,
/// stok değerinde ayrıca görünür, maliyetini aynen taşır (D-07).
final class CuttingRepository {
  final AppDatabase db;
  const CuttingRepository(this.db);

  /// 1. Kesime gönder.
  Future<String> sendToCutting({
    required String cutterSupplierId,
    required DateTime sentDate,
    required List<CuttingSourceInput> sources,
    required OperationContext ctx,
    List<({String variantId, int pieces})> plannedTargets = const [],
    String? customerId,
    String? salesQuoteId,
    String? note,
  }) => db.runOperation(ctx, () async {
    final orderId = uuid.v7();
    final docNo = await db.nextDocumentNumber(DocPrefix.cutting, sentDate.year);
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);
    final cuttingLocation = await db.locationId(LocationCode.cutting);

    var totalVolume = Volume.zero;
    final prepared =
        <
          ({
            InventoryBatch source,
            String childId,
            int pieces,
            Volume volume,
            Money cost,
          })
        >[];

    for (final input in sources) {
      final batch = await (db.select(
        db.inventoryBatches,
      )..where((b) => b.id.equals(input.batchId))).getSingle();

      if (batch.remainingPieces < input.pieces) {
        throw InsufficientStockException(
          variantId: batch.variantId,
          requiredPieces: input.pieces,
          availablePieces: batch.remainingPieces,
        );
      }

      final unitVolume = Volume(
        batch.remainingVolume.stored ~/ batch.remainingPieces,
      );
      final volume = Volume(unitVolume.stored * input.pieces);
      final cost = batch.realUnitCostM3.times(volume);
      totalVolume += volume;

      prepared.add((
        source: batch,
        childId: uuid.v7(),
        pieces: input.pieces,
        volume: volume,
        cost: cost,
      ));
    }

    await db
        .into(db.cuttingOrders)
        .insert(
          CuttingOrdersCompanion.insert(
            id: orderId,
            docNo: docNo,
            cutterSupplierId: cutterSupplierId,
            salesQuoteId: Value(salesQuoteId),
            customerId: Value(customerId),
            sentDate: sentDate.millisecondsSinceEpoch,
            status: const Value(CuttingStatus.atCutter),
            sourceVolumeTotal: Value(totalVolume),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            note: Value(note),
          ),
        );

    for (final p in prepared) {
      // Ana depodan çıkış.
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid.v7(),
              occurredAt: sentDate.millisecondsSinceEpoch,
              type: MovementType.transferOut,
              locationId: mainLocation,
              variantId: p.source.variantId,
              batchId: Value(p.source.id),
              pieces: -p.pieces,
              volume: -p.volume,
              unitCostM3: p.source.realUnitCostM3,
              totalCost: p.cost,
              sourceType: 'CUTTING_ORDER',
              sourceId: Value(orderId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );

      await (db.update(
        db.inventoryBatches,
      )..where((b) => b.id.equals(p.source.id))).write(
        InventoryBatchesCompanion(
          remainingPieces: Value(p.source.remainingPieces - p.pieces),
          remainingVolume: Value(p.source.remainingVolume - p.volume),
        ),
      );

      // "Kesimde" konumunda çocuk parti — aynı birim maliyeti taşır.
      await db
          .into(db.inventoryBatches)
          .insert(
            InventoryBatchesCompanion.insert(
              id: p.childId,
              variantId: p.source.variantId,
              locationId: cuttingLocation,
              supplierId: Value(p.source.supplierId),
              sourceType: BatchSourceType.transfer,
              sourceId: Value(orderId),
              parentBatchId: Value(p.source.id),
              // Kaynağın tarihini taşır: kesim malın yaşını değiştirmez (D-08).
              receivedAt: p.source.receivedAt,
              bareUnitCostM3: p.source.bareUnitCostM3,
              realUnitCostM3: p.source.realUnitCostM3,
              inPieces: p.pieces,
              inVolume: p.volume,
              remainingPieces: p.pieces,
              remainingVolume: p.volume,
              createdAt: ctx.nowMs,
            ),
          );

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid.v7(),
              occurredAt: sentDate.millisecondsSinceEpoch,
              type: MovementType.transferIn,
              locationId: cuttingLocation,
              variantId: p.source.variantId,
              batchId: Value(p.childId),
              pieces: p.pieces,
              volume: p.volume,
              unitCostM3: p.source.realUnitCostM3,
              totalCost: p.cost,
              sourceType: 'CUTTING_ORDER',
              sourceId: Value(orderId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );

      await db
          .into(db.cuttingOrderSources)
          .insert(
            CuttingOrderSourcesCompanion.insert(
              id: uuid.v7(),
              cuttingOrderId: orderId,
              sourceBatchId: p.source.id,
              kesimdeBatchId: Value(p.childId),
              variantId: p.source.variantId,
              pieces: p.pieces,
              volume: p.volume,
              costTotal: p.cost,
            ),
          );
    }

    for (final t in plannedTargets) {
      await db
          .into(db.cuttingOrderPlanItems)
          .insert(
            CuttingOrderPlanItemsCompanion.insert(
              id: uuid.v7(),
              cuttingOrderId: orderId,
              variantId: t.variantId,
              plannedPieces: t.pieces,
            ),
          );
    }

    await db.writeAudit(
      ctx,
      entityType: 'cutting_order',
      entityId: orderId,
      action: 'CREATE',
      summary: 'Kesim emri $docNo, $totalVolume kesime gönderildi',
    );
    return orderId;
  });

  /// 2. Kesimden dönüş. Kısmi dönüş desteklenir.
  ///
  /// Maliyet: kaynak + kesim ücreti + nakliye, hedeflere **m³ oranında**
  /// dağıtılır. Hedef toplam m³ kaynağı aşamaz. Fark **kesim firesidir**;
  /// ayrı maliyet yazılmaz, hedeflerin birim maliyetine yedirilir.
  Future<void> receiveFromCutting({
    required String orderId,
    required DateTime returnedAt,
    required List<CuttingResultInput> results,
    required OperationContext ctx,
    Money cuttingFeeNet = Money.zero,
    Money freightNet = Money.zero,
    Rate cuttingFeeVatRate = const Rate(2000),
  }) => db.runOperation(ctx, () async {
    final order = await (db.select(
      db.cuttingOrders,
    )..where((o) => o.id.equals(orderId))).getSingle();
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);
    final cuttingLocation = await db.locationId(LocationCode.cutting);

    final sources = await (db.select(
      db.cuttingOrderSources,
    )..where((s) => s.cuttingOrderId.equals(orderId))).get();

    // Kesimdeki partilerin kalan maliyeti.
    var sourceCost = Money.zero;
    var sourceVolume = Volume.zero;
    for (final s in sources) {
      final child = await (db.select(
        db.inventoryBatches,
      )..where((b) => b.id.equals(s.kesimdeBatchId!))).getSingle();
      sourceCost += child.realUnitCostM3.times(child.remainingVolume);
      sourceVolume += child.remainingVolume;
    }

    // Hedef hacimleri.
    final targetVolumes = <Volume>[];
    for (final r in results) {
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(r.variantId))).getSingle();
      targetVolumes.add(Volume(variant.unitVolume.stored * r.pieces));
    }

    final costing = CostingEngine.allocateCutting(
      sourceCost: sourceCost,
      cuttingFee: cuttingFeeNet,
      freight: freightNet,
      sourceVolume: sourceVolume,
      targets: targetVolumes,
    );

    // Kesimdeki partiler tüketilir.
    for (final s in sources) {
      final child = await (db.select(
        db.inventoryBatches,
      )..where((b) => b.id.equals(s.kesimdeBatchId!))).getSingle();
      if (child.remainingPieces == 0) continue;

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid.v7(),
              occurredAt: returnedAt.millisecondsSinceEpoch,
              type: MovementType.cuttingOut,
              locationId: cuttingLocation,
              variantId: child.variantId,
              batchId: Value(child.id),
              pieces: -child.remainingPieces,
              volume: -child.remainingVolume,
              unitCostM3: child.realUnitCostM3,
              totalCost: child.realUnitCostM3.times(child.remainingVolume),
              sourceType: 'CUTTING_ORDER',
              sourceId: Value(orderId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );

      await (db.update(
        db.inventoryBatches,
      )..where((b) => b.id.equals(child.id))).write(
        InventoryBatchesCompanion(
          remainingPieces: const Value(0),
          remainingVolume: Value(Volume.zero),
        ),
      );
    }

    // Hedef partiler ana depoya girer — kaynağın tarihini taşır (D-08).
    final sourceReceivedAt = sources.isEmpty
        ? returnedAt.millisecondsSinceEpoch
        : (await (db.select(db.inventoryBatches)
                    ..where((b) => b.id.equals(sources.first.sourceBatchId)))
                  .getSingle())
              .receivedAt;

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final volume = targetVolumes[i];
      final cost = costing.targetCosts[i];
      final unitCost = volume.isZero ? UnitPrice.zero : costing.unitCost;
      final batchId = uuid.v7();

      await db
          .into(db.inventoryBatches)
          .insert(
            InventoryBatchesCompanion.insert(
              id: batchId,
              variantId: r.variantId,
              locationId: mainLocation,
              supplierId: Value(order.cutterSupplierId),
              sourceType: BatchSourceType.cutting,
              sourceId: Value(orderId),
              receivedAt: sourceReceivedAt,
              bareUnitCostM3: unitCost,
              realUnitCostM3: unitCost,
              inPieces: r.pieces,
              inVolume: volume,
              remainingPieces: r.pieces,
              remainingVolume: volume,
              createdAt: ctx.nowMs,
            ),
          );

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid.v7(),
              occurredAt: returnedAt.millisecondsSinceEpoch,
              type: MovementType.cuttingIn,
              locationId: mainLocation,
              variantId: r.variantId,
              batchId: Value(batchId),
              pieces: r.pieces,
              volume: volume,
              unitCostM3: unitCost,
              totalCost: cost,
              sourceType: 'CUTTING_ORDER',
              sourceId: Value(orderId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );

      await db
          .into(db.cuttingOrderResults)
          .insert(
            CuttingOrderResultsCompanion.insert(
              id: uuid.v7(),
              cuttingOrderId: orderId,
              variantId: r.variantId,
              resultBatchId: Value(batchId),
              pieces: r.pieces,
              volume: volume,
              allocatedCost: cost,
              returnedAt: returnedAt.millisecondsSinceEpoch,
              isRemnant: Value(r.isRemnant),
            ),
          );
    }

    // Kesim ücreti kesimhane carisine BRÜT yazılır (BRIEF §5).
    if (cuttingFeeNet.isPositive || freightNet.isPositive) {
      final fee = VatCalculator.excludingFromNet(
        net: cuttingFeeNet + freightNet,
        vatRate: cuttingFeeVatRate,
      );
      await db
          .into(db.supplierLedger)
          .insert(
            SupplierLedgerCompanion.insert(
              id: uuid.v7(),
              supplierId: order.cutterSupplierId,
              occurredAt: returnedAt.millisecondsSinceEpoch,
              docType: LedgerDocType.cuttingFee,
              docId: Value(orderId),
              docNo: Value(order.docNo),
              amount: fee.gross,
              description: Value('Kesim ücreti ${order.docNo}'),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );
    }

    final remainingInCutting = await _remainingInCutting(orderId);

    await (db.update(
      db.cuttingOrders,
    )..where((o) => o.id.equals(orderId))).write(
      CuttingOrdersCompanion(
        status: Value(
          remainingInCutting.isZero
              ? CuttingStatus.completed
              : CuttingStatus.partial,
        ),
        resultVolumeTotal: Value(
          order.resultVolumeTotal + sumVolume(targetVolumes),
        ),
        wasteVolume: Value(order.wasteVolume + costing.wasteVolume),
        cuttingFeeNet: Value(order.cuttingFeeNet + cuttingFeeNet),
        freightNet: Value(order.freightNet + freightNet),
      ),
    );

    await db.writeAudit(
      ctx,
      entityType: 'cutting_order',
      entityId: orderId,
      action: 'STATUS_CHANGE',
      summary:
          'Kesim emri ${order.docNo} dönüşü: '
          '${costing.unitCost} birim maliyet, '
          'fire ${costing.wasteVolume}',
    );
  });

  Future<Volume> _remainingInCutting(String orderId) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(b.remaining_volume), 0) AS v '
          'FROM inventory_batches b '
          'JOIN cutting_order_sources s ON s.kesimde_batch_id = b.id '
          'WHERE s.cutting_order_id = ?',
          variables: [Variable.withString(orderId)],
          readsFrom: {db.inventoryBatches, db.cuttingOrderSources},
        )
        .getSingle();
    return Volume.fromStored(row.read<int>('v'));
  }
}
