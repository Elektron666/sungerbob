import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

final class StockCountLineInput {
  final String variantId;
  final int countedPieces;
  const StockCountLineInput({
    required this.variantId,
    required this.countedPieces,
  });
}

final class WasteLineInput {
  final String variantId;
  final int pieces;
  const WasteLineInput({required this.variantId, required this.pieces});
}

/// Stok sayımı ve fire (SPEC §16, §17 · BRIEF §9 Faz 3).
final class StockOpsRepository {
  final AppDatabase db;
  const StockOpsRepository(this.db);

  /// Sayım taslağı oluşturur — **stok etkilenmez** (SPEC §16).
  Future<String> createDraftCount({
    required DateTime countDate,
    required List<StockCountLineInput> lines,
    required OperationContext ctx,
    String? note,
  }) => db.runOperation(ctx, () async {
    final countId = uuid.v7();
    final docNo = await db.nextDocumentNumber(
      DocPrefix.stockCount,
      countDate.year,
    );
    final locationId = await db.locationId(LocationCode.mainWarehouse);

    await db
        .into(db.stockCounts)
        .insert(
          StockCountsCompanion.insert(
            id: countId,
            docNo: docNo,
            locationId: locationId,
            countDate: countDate.millisecondsSinceEpoch,
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            note: Value(note),
          ),
        );

    for (final line in lines) {
      final stock = await db.variantStock(line.variantId);
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(line.variantId))).getSingle();

      final diffPieces = line.countedPieces - stock.pieces;
      await db
          .into(db.stockCountItems)
          .insert(
            StockCountItemsCompanion.insert(
              id: uuid.v7(),
              stockCountId: countId,
              variantId: line.variantId,
              systemPieces: stock.pieces,
              countedPieces: line.countedPieces,
              diffPieces: diffPieces,
              diffVolume: Volume(variant.unitVolume.stored * diffPieces),
            ),
          );
    }

    await db.writeAudit(
      ctx,
      entityType: 'stock_count',
      entityId: countId,
      action: 'CREATE',
      summary: 'Sayım $docNo taslak oluşturuldu',
    );
    return countId;
  });

  /// Sayımı onaylar — **riskli işlem**, çağıran taraf önce yedek almalıdır
  /// (BRIEF §4.3).
  Future<void> applyCount({
    required String countId,
    required OperationContext ctx,
  }) => db.runOperation(ctx, () async {
    final count = await (db.select(
      db.stockCounts,
    )..where((c) => c.id.equals(countId))).getSingle();
    if (count.status != 'DRAFT') {
      throw StateError('Bu sayım zaten uygulanmış.');
    }

    final items = await (db.select(
      db.stockCountItems,
    )..where((i) => i.stockCountId.equals(countId))).get();

    var costEffect = Money.zero;
    for (final item in items) {
      if (item.diffPieces == 0) continue;
      costEffect += item.diffPieces < 0
          ? -(await _consume(
              variantId: item.variantId,
              pieces: -item.diffPieces,
              volume: -item.diffVolume,
              type: MovementType.countOut,
              sourceType: 'STOCK_COUNT',
              sourceId: countId,
              occurredAt: count.countDate,
              ctx: ctx,
            ))
          : await _addBack(
              variantId: item.variantId,
              pieces: item.diffPieces,
              volume: item.diffVolume,
              sourceId: countId,
              occurredAt: count.countDate,
              ctx: ctx,
            );
    }

    await (db.update(db.stockCounts)..where((c) => c.id.equals(countId))).write(
      StockCountsCompanion(
        status: const Value('APPLIED'),
        appliedAt: Value(ctx.nowMs),
        costEffectTotal: Value(costEffect),
      ),
    );

    await db.writeAudit(
      ctx,
      entityType: 'stock_count',
      entityId: countId,
      action: 'STATUS_CHANGE',
      summary: 'Sayım ${count.docNo} uygulandı, maliyet etkisi $costEffect',
    );
  });

  /// Fire / hasar. Neden zorunludur (SPEC §17).
  Future<String> recordWaste({
    required DateTime occurredAt,
    required String reasonCode,
    required List<WasteLineInput> lines,
    required OperationContext ctx,
    String? note,
  }) => db.runOperation(ctx, () async {
    final wasteId = uuid.v7();
    final docNo = await db.nextDocumentNumber(DocPrefix.waste, occurredAt.year);

    // Stok çıkışları ÖNCE yapılır ve toplam maliyet hesaplanır; başlık
    // doğru toplamla TEK SEFERDE yazılır. stock_adjustments append-only
    // olduğu için sonradan UPDATE edilemez (BRIEF §3.5) — bu kural
    // bilerek zayıflatılmadı.
    final consumed =
        <({String variantId, int pieces, Volume volume, Money cost})>[];
    for (final line in lines) {
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(line.variantId))).getSingle();
      final volume = Volume(variant.unitVolume.stored * line.pieces);

      final cost = await _consume(
        variantId: line.variantId,
        pieces: line.pieces,
        volume: volume,
        type: MovementType.wasteOut,
        sourceType: 'WASTE',
        sourceId: wasteId,
        occurredAt: occurredAt.millisecondsSinceEpoch,
        ctx: ctx,
      );
      consumed.add((
        variantId: line.variantId,
        pieces: line.pieces,
        volume: volume,
        cost: cost,
      ));
    }

    final total = sumMoney(consumed.map((c) => c.cost));

    await db
        .into(db.stockAdjustments)
        .insert(
          StockAdjustmentsCompanion.insert(
            id: wasteId,
            docNo: docNo,
            occurredAt: occurredAt.millisecondsSinceEpoch,
            reasonCode: reasonCode,
            costTotal: Value(total),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            note: Value(note),
          ),
        );

    for (final c in consumed) {
      await db
          .into(db.stockAdjustmentItems)
          .insert(
            StockAdjustmentItemsCompanion.insert(
              id: uuid.v7(),
              stockAdjustmentId: wasteId,
              variantId: c.variantId,
              pieces: c.pieces,
              volume: c.volume,
              costTotal: c.cost,
            ),
          );
    }

    await db.writeAudit(
      ctx,
      entityType: 'stock_adjustment',
      entityId: wasteId,
      action: 'CREATE',
      summary: 'Fire $docNo ($reasonCode), maliyet $total',
    );
    return wasteId;
  });

  /// FIFO ile partilerden düşer ve maliyeti döndürür.
  Future<Money> _consume({
    required String variantId,
    required int pieces,
    required Volume volume,
    required String type,
    required String sourceType,
    required String sourceId,
    required int occurredAt,
    required OperationContext ctx,
  }) async {
    final batches = await db.batchesForVariant(variantId);
    final costing = CostingEngine.fifo(
      batches: batches,
      requiredPieces: pieces,
      requiredVolume: volume,
    );

    final locationId = await db.locationId(LocationCode.mainWarehouse);
    final movementId = uuid.v7();

    await db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: movementId,
            occurredAt: occurredAt,
            type: type,
            locationId: locationId,
            variantId: variantId,
            pieces: -pieces,
            volume: -volume,
            unitCostM3: costing.allocations.isEmpty
                ? UnitPrice.zero
                : costing.allocations.first.unitCost,
            totalCost: costing.totalCost,
            sourceType: sourceType,
            sourceId: Value(sourceId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    for (final alloc in costing.allocations) {
      await db
          .into(db.costAllocations)
          .insert(
            CostAllocationsCompanion.insert(
              id: uuid.v7(),
              movementId: movementId,
              batchId: alloc.batchId,
              pieces: alloc.pieces,
              volume: alloc.volume,
              unitCostM3: alloc.unitCost,
              totalCost: alloc.cost,
              sequenceNo: alloc.sequenceNo,
              createdAt: ctx.nowMs,
            ),
          );

      final batch = await (db.select(
        db.inventoryBatches,
      )..where((b) => b.id.equals(alloc.batchId))).getSingle();
      await (db.update(
        db.inventoryBatches,
      )..where((b) => b.id.equals(alloc.batchId))).write(
        InventoryBatchesCompanion(
          remainingPieces: Value(batch.remainingPieces - alloc.pieces),
          remainingVolume: Value(batch.remainingVolume - alloc.volume),
        ),
      );
    }
    return costing.totalCost;
  }

  /// Sayımda fazla çıkan mal: son partinin birim maliyetiyle geri girer.
  Future<Money> _addBack({
    required String variantId,
    required int pieces,
    required Volume volume,
    required String sourceId,
    required int occurredAt,
    required OperationContext ctx,
  }) async {
    final locationId = await db.locationId(LocationCode.mainWarehouse);
    final latest =
        await (db.select(db.inventoryBatches)
              ..where((b) => b.variantId.equals(variantId))
              ..orderBy([(b) => OrderingTerm.desc(b.receivedAt)])
              ..limit(1))
            .getSingleOrNull();

    final unitCost = latest?.realUnitCostM3 ?? UnitPrice.zero;
    final cost = unitCost.times(volume);
    final batchId = uuid.v7();

    await db
        .into(db.inventoryBatches)
        .insert(
          InventoryBatchesCompanion.insert(
            id: batchId,
            variantId: variantId,
            locationId: locationId,
            sourceType: BatchSourceType.opening,
            sourceId: Value(sourceId),
            receivedAt: occurredAt,
            bareUnitCostM3: unitCost,
            realUnitCostM3: unitCost,
            inPieces: pieces,
            inVolume: volume,
            remainingPieces: pieces,
            remainingVolume: volume,
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: uuid.v7(),
            occurredAt: occurredAt,
            type: MovementType.countIn,
            locationId: locationId,
            variantId: variantId,
            batchId: Value(batchId),
            pieces: pieces,
            volume: volume,
            unitCostM3: unitCost,
            totalCost: cost,
            sourceType: 'STOCK_COUNT',
            sourceId: Value(sourceId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    return cost;
  }
}
