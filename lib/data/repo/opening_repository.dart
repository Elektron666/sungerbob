import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

/// Açılış işlemleri (BRIEF §1.11, §5).
///
/// İşletme sıfırdan başlamıyor: depoda mal, müşterilerde borç, kasada para ve
/// portföyde evrak var. Bunlar girilemezse sistem ilk günden yanlış rakam
/// gösterir (ANALİZ §2.6).
final class OpeningRepository {
  final AppDatabase db;
  const OpeningRepository(this.db);

  /// Açılış stoğu: maliyetli açılış partisi + OPENING_IN hareketi.
  Future<String> openingStock({
    required String variantId,
    required int pieces,
    required Volume volume,
    required UnitPrice unitCost,
    required DateTime asOfDate,
    required OperationContext ctx,
    String? supplierId,
  }) => db.runOperation(ctx, () async {
    final batchId = uuid.v7();
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);

    await db
        .into(db.inventoryBatches)
        .insert(
          InventoryBatchesCompanion.insert(
            id: batchId,
            variantId: variantId,
            locationId: mainLocation,
            // Açılışta tedarikçi bilinmeyebilir (DECISIONS V-03).
            supplierId: Value(supplierId),
            sourceType: BatchSourceType.opening,
            receivedAt: asOfDate.millisecondsSinceEpoch,
            bareUnitCostM3: unitCost,
            realUnitCostM3: unitCost,
            inPieces: pieces,
            inVolume: volume,
            remainingPieces: pieces,
            remainingVolume: volume,
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    await db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: uuid.v7(),
            occurredAt: asOfDate.millisecondsSinceEpoch,
            type: MovementType.openingIn,
            locationId: mainLocation,
            variantId: variantId,
            batchId: Value(batchId),
            pieces: pieces,
            volume: volume,
            unitCostM3: unitCost,
            totalCost: unitCost.times(volume),
            sourceType: 'OPENING',
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.openingBalances)
        .insert(
          OpeningBalancesCompanion.insert(
            id: uuid.v7(),
            kind: 'STOCK',
            refId: Value(variantId),
            asOfDate: asOfDate.millisecondsSinceEpoch,
            amount: Value(unitCost.times(volume)),
            pieces: Value(pieces),
            unitCostM3: Value(unitCost),
            createdRecordId: Value(batchId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'opening_balance',
      entityId: batchId,
      action: 'CREATE',
      summary: 'Açılış stoğu: $pieces adet, $volume',
    );

    return batchId;
  });

  /// Açılış cari bakiyesi (vadeli). Tahsilat eşleştirmesinde hedef olabilir.
  Future<String> openingCustomerBalance({
    required String customerId,
    required Money amount,
    required DateTime asOfDate,
    required OperationContext ctx,
    DateTime? dueDate,
  }) => db.runOperation(ctx, () async {
    final ledgerId = uuid.v7();
    await db
        .into(db.customerLedger)
        .insert(
          CustomerLedgerCompanion.insert(
            id: ledgerId,
            customerId: customerId,
            occurredAt: asOfDate.millisecondsSinceEpoch,
            docType: LedgerDocType.opening,
            amount: amount,
            dueDate: Value(dueDate?.millisecondsSinceEpoch),
            description: const Value('Açılış bakiyesi'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.openingBalances)
        .insert(
          OpeningBalancesCompanion.insert(
            id: uuid.v7(),
            kind: 'CUSTOMER',
            refId: Value(customerId),
            asOfDate: asOfDate.millisecondsSinceEpoch,
            amount: Value(amount),
            dueDate: Value(dueDate?.millisecondsSinceEpoch),
            createdRecordId: Value(ledgerId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );
    return ledgerId;
  });

  /// Açılış kasa/banka bakiyesi.
  Future<String> openingCashBalance({
    required String cashAccountId,
    required Money amount,
    required DateTime asOfDate,
    required OperationContext ctx,
  }) => db.runOperation(ctx, () async {
    final movementId = uuid.v7();
    await db
        .into(db.accountMovements)
        .insert(
          AccountMovementsCompanion.insert(
            id: movementId,
            cashAccountId: cashAccountId,
            occurredAt: asOfDate.millisecondsSinceEpoch,
            direction: 'IN',
            amount: amount,
            type: AccountMovementType.opening,
            sourceType: const Value('OPENING'),
            description: const Value('Açılış bakiyesi'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.openingBalances)
        .insert(
          OpeningBalancesCompanion.insert(
            id: uuid.v7(),
            kind: 'CASH',
            refId: Value(cashAccountId),
            asOfDate: asOfDate.millisecondsSinceEpoch,
            amount: Value(amount),
            createdRecordId: Value(movementId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );
    return movementId;
  });
}
