import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/core/rounding.dart';
import '../../domain/core/scales.dart';
import '../../domain/service/vat.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

/// Alış satırı girdisi.
final class PurchaseLineInput {
  final String variantId;
  final int pieces;
  final Volume volume;
  final UnitPrice unitPriceM3;
  final Rate vatRate;
  final Rate discountRate;

  const PurchaseLineInput({
    required this.variantId,
    required this.pieces,
    required this.volume,
    required this.unitPriceM3,
    required this.vatRate,
    this.discountRate = Rate.zero,
  });
}

/// Alış masrafı girdisi (nakliye, hamaliye, diğer) — KDV hariç.
final class PurchaseExpenseInput {
  final String kind;
  final Money amount;
  final String allocationKey;
  final String? supplierId;
  final Rate vatRate;

  const PurchaseExpenseInput({
    required this.kind,
    required this.amount,
    this.allocationKey = AllocationKey.volume,
    this.supplierId,
    this.vatRate = Rate.zero,
  });
}

final class PurchaseInput {
  final String supplierId;
  final DateTime docDate;
  final DateTime? dueDate;
  final PriceMode priceMode;
  final List<PurchaseLineInput> lines;
  final List<PurchaseExpenseInput> expenses;
  final String? invoiceNo;
  final String? waybillNo;
  final String? note;

  const PurchaseInput({
    required this.supplierId,
    required this.docDate,
    required this.priceMode,
    required this.lines,
    this.expenses = const [],
    this.dueDate,
    this.invoiceNo,
    this.waybillNo,
    this.note,
  });
}

/// Alış: belge + satırlar + partiler + masraf dağıtımı + stok hareketleri +
/// tedarikçi carisi + audit — hepsi **tek transaction** (BRIEF §3.9).
final class PurchaseRepository {
  final AppDatabase db;
  const PurchaseRepository(this.db);

  Future<String> create(PurchaseInput input, OperationContext ctx) =>
      db.runOperation(ctx, () => _create(input, ctx));

  Future<String> _create(PurchaseInput input, OperationContext ctx) async {
    final purchaseId = uuid.v7();
    final docNo = await db.nextDocumentNumber(
      DocPrefix.purchase,
      input.docDate.year,
    );
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);

    // 1) Satır hesapları — KDV moduna göre.
    final vatLines = <VatLine>[];
    for (final line in input.lines) {
      vatLines.add(
        VatCalculator.forMode(
          mode: input.priceMode,
          volume: line.volume,
          unitPrice: line.unitPriceM3,
          vatRate: line.vatRate,
          discountRate: line.discountRate,
        ),
      );
    }

    // 2) Masraf dağıtımı. Parti maliyeti her zaman KDV hariçtir (BRIEF §3.4).
    final expenseTotal = sumMoney(input.expenses.map((e) => e.amount));
    final perLineExpense = <Money>[];
    if (input.expenses.isEmpty) {
      perLineExpense.addAll(List.filled(input.lines.length, Money.zero));
    } else {
      final targets = [
        for (var i = 0; i < input.lines.length; i++)
          ExpenseTarget(
            volume: input.lines[i].volume,
            bareCost: vatLines[i].net,
          ),
      ];
      final byAmount =
          input.expenses.first.allocationKey == AllocationKey.amount;
      perLineExpense.addAll(
        CostingEngine.allocatePurchaseExpense(
          expense: expenseTotal,
          lines: targets,
          byAmount: byAmount,
        ),
      );
    }

    // 3) Belge başlığı.
    await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: purchaseId,
            docNo: docNo,
            supplierId: input.supplierId,
            docDate: input.docDate.millisecondsSinceEpoch,
            dueDate: Value(input.dueDate?.millisecondsSinceEpoch),
            priceMode: input.priceMode,
            invoiceNo: Value(input.invoiceNo),
            waybillNo: Value(input.waybillNo),
            subtotalNet: sumMoney(vatLines.map((v) => v.net)),
            vatTotal: sumMoney(vatLines.map((v) => v.vat)),
            grandTotal: sumMoney(vatLines.map((v) => v.gross)),
            expenseTotal: Value(expenseTotal),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
            note: Value(input.note),
          ),
        );

    // 4) Satırlar + partiler + stok hareketleri.
    for (var i = 0; i < input.lines.length; i++) {
      final line = input.lines[i];
      final vat = vatLines[i];
      final batchId = uuid.v7();

      // Çıplak fabrika fiyatı ve gerçek maliyet AYRI saklanır (SPEC §4).
      final bareUnitCost = _unitCostOf(vat.net, line.volume);
      final realUnitCost = _unitCostOf(
        vat.net + perLineExpense[i],
        line.volume,
      );

      await db
          .into(db.inventoryBatches)
          .insert(
            InventoryBatchesCompanion.insert(
              id: batchId,
              variantId: line.variantId,
              locationId: mainLocation,
              supplierId: Value(input.supplierId),
              sourceType: BatchSourceType.purchase,
              sourceId: Value(purchaseId),
              receivedAt: input.docDate.millisecondsSinceEpoch,
              bareUnitCostM3: bareUnitCost,
              realUnitCostM3: realUnitCost,
              inPieces: line.pieces,
              inVolume: line.volume,
              remainingPieces: line.pieces,
              remainingVolume: line.volume,
              createdAt: ctx.nowMs,
              createdBy: Value(ctx.userId),
              deviceId: Value(ctx.deviceId),
            ),
          );

      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              id: uuid.v7(),
              purchaseId: purchaseId,
              lineNo: i + 1,
              variantId: line.variantId,
              pieces: line.pieces,
              volume: line.volume,
              unitPriceM3: line.unitPriceM3,
              discountRate: Value(line.discountRate),
              netTotal: vat.net,
              vatRate: line.vatRate,
              vatTotal: vat.vat,
              grossTotal: vat.gross,
              batchId: Value(batchId),
            ),
          );

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid.v7(),
              occurredAt: input.docDate.millisecondsSinceEpoch,
              type: MovementType.purchaseIn,
              locationId: mainLocation,
              variantId: line.variantId,
              batchId: Value(batchId),
              pieces: line.pieces,
              volume: line.volume,
              unitCostM3: realUnitCost,
              totalCost: realUnitCost.times(line.volume),
              sourceType: 'PURCHASE',
              sourceId: Value(purchaseId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
              createdBy: Value(ctx.userId),
              deviceId: Value(ctx.deviceId),
            ),
          );
    }

    // 5) Masraf kayıtları.
    for (final expense in input.expenses) {
      await db
          .into(db.purchaseExpenses)
          .insert(
            PurchaseExpensesCompanion.insert(
              id: uuid.v7(),
              purchaseId: purchaseId,
              supplierId: Value(expense.supplierId),
              kind: expense.kind,
              amount: expense.amount,
              vatRate: Value(expense.vatRate),
              allocationKey: Value(expense.allocationKey),
              occurredAt: input.docDate.millisecondsSinceEpoch,
            ),
          );
    }

    // 6) Tedarikçi carisine BRÜT (BRIEF §3.4).
    await db
        .into(db.supplierLedger)
        .insert(
          SupplierLedgerCompanion.insert(
            id: uuid.v7(),
            supplierId: input.supplierId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            docType: LedgerDocType.purchase,
            docId: Value(purchaseId),
            docNo: Value(docNo),
            amount: sumMoney(vatLines.map((v) => v.gross)),
            dueDate: Value(input.dueDate?.millisecondsSinceEpoch),
            description: Value('Alış $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'CREATE',
      summary: 'Alış $docNo kaydedildi',
    );

    return purchaseId;
  }

  /// Sonradan gelen masraf (BRIEF §3.7).
  ///
  /// Partinin toplam giriş m³'üne bölünür; stokta kalana düşen pay partinin
  /// birim maliyetine eklenir, satılmış/firelenmiş kısma düşen pay
  /// `cost_adjustments`'a yazılır. **Geçmiş satış satırları değişmez.**
  Future<void> addLateExpense({
    required String purchaseId,
    required PurchaseExpenseInput expense,
    required OperationContext ctx,
  }) => db.runOperation(ctx, () async {
    final expenseId = uuid.v7();
    await db
        .into(db.purchaseExpenses)
        .insert(
          PurchaseExpensesCompanion.insert(
            id: expenseId,
            purchaseId: purchaseId,
            supplierId: Value(expense.supplierId),
            kind: expense.kind,
            amount: expense.amount,
            vatRate: Value(expense.vatRate),
            allocationKey: Value(expense.allocationKey),
            occurredAt: ctx.nowMs,
            addedLater: const Value(true),
          ),
        );

    final batches = await (db.select(
      db.inventoryBatches,
    )..where((b) => b.sourceId.equals(purchaseId))).get();
    if (batches.isEmpty) return;

    final shares = CostingEngine.allocatePurchaseExpense(
      expense: expense.amount,
      lines: [
        for (final b in batches)
          ExpenseTarget(
            volume: b.inVolume,
            bareCost: b.bareUnitCostM3.times(b.inVolume),
          ),
      ],
      byAmount: expense.allocationKey == AllocationKey.amount,
    );

    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final split = CostingEngine.splitLateExpense(
        expenseShare: shares[i],
        totalInVolume: batch.inVolume,
        remainingVolume: batch.remainingVolume,
      );

      // Stokta kalana düşen pay → partinin birim maliyeti artar.
      if (!split.toStock.isZero && !batch.remainingVolume.isZero) {
        final currentCost = batch.realUnitCostM3.times(batch.remainingVolume);
        final newUnitCost = _unitCostOf(
          currentCost + split.toStock,
          batch.remainingVolume,
        );
        await (db.update(
          db.inventoryBatches,
        )..where((b) => b.id.equals(batch.id))).write(
          InventoryBatchesCompanion(realUnitCostM3: Value(newUnitCost)),
        );
      }

      // Satılmış/firelenmiş kısma düşen pay → dönem maliyet farkı.
      if (!split.toAdjustment.isZero) {
        await db
            .into(db.costAdjustments)
            .insert(
              CostAdjustmentsCompanion.insert(
                id: uuid.v7(),
                occurredAt: ctx.nowMs,
                batchId: batch.id,
                purchaseExpenseId: Value(expenseId),
                reason: 'LATE_EXPENSE',
                volumeAffected: batch.inVolume - batch.remainingVolume,
                amount: split.toAdjustment,
                periodDate: ctx.nowMs,
              ),
            );
      }

      await db
          .into(db.purchaseExpenseAllocations)
          .insert(
            PurchaseExpenseAllocationsCompanion.insert(
              id: uuid.v7(),
              purchaseExpenseId: expenseId,
              batchId: batch.id,
              volumeShare: batch.inVolume,
              amountToStock: split.toStock,
              amountToAdjustment: split.toAdjustment,
            ),
          );
    }

    await db.writeAudit(
      ctx,
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'LATE_EXPENSE',
      summary: 'Sonradan masraf eklendi: ${expense.kind} ${expense.amount}',
    );
  });

  static UnitPrice _unitCostOf(Money cost, Volume volume) {
    if (volume.isZero) return UnitPrice.zero;
    return UnitPrice.fromDecimal(
      roundHalfUp(
        (cost.tl / volume.m3).toDecimal(scaleOnInfinitePrecision: 12),
        Scales.unitPrice,
      ),
    );
  }
}
