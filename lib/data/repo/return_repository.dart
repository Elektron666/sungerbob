import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

final class SaleReturnLineInput {
  final String saleItemId;
  final int pieces;
  const SaleReturnLineInput({required this.saleItemId, required this.pieces});
}

final class SaleReturnInput {
  final String saleId;
  final DateTime docDate;
  final List<SaleReturnLineInput> lines;
  final String? reason;

  const SaleReturnInput({
    required this.saleId,
    required this.docDate,
    required this.lines,
    this.reason,
  });
}

/// Satış iadesi (BRIEF §5, D-12).
///
/// Mal, orijinal satışın tükettiği partilere **son tüketilenden başlayarak**
/// aynı maliyetle döner. Orijinal satış değişmez.
final class ReturnRepository {
  final AppDatabase db;
  const ReturnRepository(this.db);

  Future<String> createSaleReturn(
          SaleReturnInput input, OperationContext ctx) =>
      db.runOperation(ctx, () => _createSaleReturn(input, ctx));

  Future<String> _createSaleReturn(
      SaleReturnInput input, OperationContext ctx) async {
    final returnId = uuid.v7();
    final docNo =
        await db.nextDocumentNumber(DocPrefix.returnDoc, input.docDate.year);
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);

    final sale = await (db.select(db.sales)..where((s) => s.id.equals(input.saleId)))
        .getSingle();

    var netTotal = Money.zero;
    var vatTotal = Money.zero;
    var grossTotal = Money.zero;
    var costTotal = Money.zero;

    final pending = <_PendingReturnLine>[];

    for (final line in input.lines) {
      final item = await (db.select(db.saleItems)
            ..where((i) => i.id.equals(line.saleItemId)))
          .getSingle();

      // İade satılan miktarı aşamaz (BRIEF §5).
      final alreadyReturned = await _alreadyReturnedPieces(line.saleItemId);
      if (alreadyReturned + line.pieces > item.pieces) {
        throw ReturnExceedsSoldException(
          soldPieces: item.pieces - alreadyReturned,
          returnPieces: line.pieces,
        );
      }

      final unitVolume = Volume(item.volume.stored ~/ item.pieces);
      final volume = Volume(unitVolume.stored * line.pieces);

      // İade satırı, orijinal satış fiyatıyla değerlenir.
      final vat = VatCalculator.excluding(
        volume: volume,
        unitPrice: item.unitPriceM3,
        vatRate: item.vatRate,
      );

      // Maliyet: orijinal tüketimin TERSİNDEN.
      final original = await _originalAllocations(input.saleId, item.variantId);
      final reversal = CostingEngine.reverseForReturn(
        originalAllocations: original,
        returnPieces: line.pieces,
      );

      final lineCost = sumMoney(reversal.map((a) => a.cost));

      netTotal += vat.net;
      vatTotal += vat.vat;
      grossTotal += vat.gross;
      costTotal += lineCost;

      pending.add(_PendingReturnLine(
        saleItem: item,
        pieces: line.pieces,
        volume: volume,
        vat: vat,
        cost: lineCost,
        allocations: reversal,
      ));
    }

    await db.into(db.saleReturns).insert(SaleReturnsCompanion.insert(
          id: returnId,
          docNo: docNo,
          saleId: input.saleId,
          customerId: sale.customerId,
          docDate: input.docDate.millisecondsSinceEpoch,
          priceMode: sale.priceMode,
          subtotalNet: netTotal,
          vatTotal: vatTotal,
          grandTotal: grossTotal,
          costTotal: costTotal,
          commandId: Value(ctx.commandId),
          createdAt: ctx.nowMs,
          reason: Value(input.reason),
        ));

    for (final p in pending) {
      await db.into(db.saleReturnItems).insert(SaleReturnItemsCompanion.insert(
            id: uuid.v7(),
            saleReturnId: returnId,
            saleItemId: p.saleItem.id,
            pieces: p.pieces,
            volume: p.volume,
            unitPriceM3: p.saleItem.unitPriceM3,
            netTotal: p.vat.net,
            vatRate: p.saleItem.vatRate,
            vatTotal: p.vat.vat,
            grossTotal: p.vat.gross,
            costTotal: p.cost,
          ));

      final movementId = uuid.v7();
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: movementId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            type: MovementType.saleReturnIn,
            locationId: mainLocation,
            variantId: p.saleItem.variantId,
            pieces: p.pieces,
            volume: p.volume,
            unitCostM3: p.allocations.isEmpty
                ? UnitPrice.zero
                : p.allocations.first.unitCost,
            totalCost: p.cost,
            sourceType: 'RETURN',
            sourceId: Value(returnId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ));

      // Mal çıktığı partilere geri döner.
      for (final alloc in p.allocations) {
        await db.into(db.costAllocations).insert(CostAllocationsCompanion.insert(
              id: uuid.v7(),
              movementId: movementId,
              batchId: alloc.batchId,
              pieces: alloc.pieces,
              volume: alloc.volume,
              unitCostM3: alloc.unitCost,
              totalCost: alloc.cost,
              sequenceNo: alloc.sequenceNo,
              createdAt: ctx.nowMs,
            ));

        final batch = await (db.select(db.inventoryBatches)
              ..where((b) => b.id.equals(alloc.batchId)))
            .getSingle();
        await (db.update(db.inventoryBatches)
              ..where((b) => b.id.equals(alloc.batchId)))
            .write(InventoryBatchesCompanion(
          remainingPieces: Value(batch.remainingPieces + alloc.pieces),
          remainingVolume: Value(batch.remainingVolume + alloc.volume),
        ));
      }
    }

    // Cariye alacak.
    await db.into(db.customerLedger).insert(CustomerLedgerCompanion.insert(
          id: uuid.v7(),
          customerId: sale.customerId,
          occurredAt: input.docDate.millisecondsSinceEpoch,
          docType: LedgerDocType.saleReturn,
          docId: Value(returnId),
          docNo: Value(docNo),
          amount: -grossTotal,
          description: Value('Satış iadesi $docNo'),
          commandId: Value(ctx.commandId),
          createdAt: ctx.nowMs,
        ));

    await db.writeAudit(ctx,
        entityType: 'sale_return',
        entityId: returnId,
        action: 'CREATE',
        summary: 'Satış iadesi $docNo, tutar $grossTotal');

    return returnId;
  }

  Future<int> _alreadyReturnedPieces(String saleItemId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(pieces), 0) AS total FROM sale_return_items '
      'WHERE sale_item_id = ?',
      variables: [Variable.withString(saleItemId)],
      readsFrom: {db.saleReturnItems},
    ).getSingle();
    return row.read<int>('total');
  }

  /// Orijinal satışın bu varyant için tükettiği partiler, tüketim sırasında.
  Future<List<CostAllocation>> _originalAllocations(
      String saleId, String variantId) async {
    final rows = await db.customSelect(
      '''
      SELECT ca.batch_id, ca.pieces, ca.volume, ca.unit_cost_m3, ca.total_cost,
             ca.sequence_no
      FROM cost_allocations ca
      JOIN stock_movements sm ON sm.id = ca.movement_id
      WHERE sm.source_type = 'SALE' AND sm.source_id = ?
        AND sm.variant_id = ? AND sm.type = 'SALE_OUT'
      ORDER BY ca.sequence_no ASC
      ''',
      variables: [Variable.withString(saleId), Variable.withString(variantId)],
      readsFrom: {db.costAllocations, db.stockMovements},
    ).get();

    return [
      for (final r in rows)
        CostAllocation(
          batchId: r.read<String>('batch_id'),
          pieces: r.read<int>('pieces'),
          volume: Volume.fromStored(r.read<int>('volume')),
          unitCost: UnitPrice.fromStored(r.read<int>('unit_cost_m3')),
          cost: Money.fromStored(r.read<int>('total_cost')),
          sequenceNo: r.read<int>('sequence_no'),
        )
    ];
  }
}

final class _PendingReturnLine {
  final SaleItem saleItem;
  final int pieces;
  final Volume volume;
  final VatLine vat;
  final Money cost;
  final List<CostAllocation> allocations;

  const _PendingReturnLine({
    required this.saleItem,
    required this.pieces,
    required this.volume,
    required this.vat,
    required this.cost,
    required this.allocations,
  });
}
