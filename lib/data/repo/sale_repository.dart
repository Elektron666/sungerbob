import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';
import 'unit_of_work.dart';

/// Müşteri risk limiti aşıldı (BRIEF §5). Uyarı gösterilir; kullanıcı
/// [SaleInput.riskLimitApproved] ile onaylarsa satış devam eder.
final class RiskLimitExceededException implements Exception {
  final Money balance;
  final Money pendingInstruments;
  final Money newTotal;
  final Money limit;

  const RiskLimitExceededException({
    required this.balance,
    required this.pendingInstruments,
    required this.newTotal,
    required this.limit,
  });

  @override
  String toString() =>
      'Risk limiti aşılıyor: mevcut bakiye $balance + '
      'portföydeki evrak $pendingInstruments + bu satış $newTotal, limit $limit.';
}

final class SaleLineInput {
  final String variantId;
  final int pieces;
  final Volume volume;
  final UnitPrice listPriceM3;
  final UnitPrice unitPriceM3;
  final Rate vatRate;
  final Rate discountRate;
  final String? priceListId;

  const SaleLineInput({
    required this.variantId,
    required this.pieces,
    required this.volume,
    required this.unitPriceM3,
    required this.vatRate,
    UnitPrice? listPriceM3,
    this.discountRate = Rate.zero,
    this.priceListId,
  }) : listPriceM3 = listPriceM3 ?? unitPriceM3;
}

final class SaleInput {
  final String customerId;
  final DateTime docDate;
  final DateTime? dueDate;
  final PriceMode priceMode;
  final List<SaleLineInput> lines;
  final String? invoiceNo;
  final String? waybillNo;
  final String? salesQuoteId;
  final String? note;

  /// Risk limiti uyarısı kullanıcı tarafından onaylandıysa true (BRIEF §5).
  final bool riskLimitApproved;

  const SaleInput({
    required this.customerId,
    required this.docDate,
    required this.priceMode,
    required this.lines,
    this.dueDate,
    this.invoiceNo,
    this.waybillNo,
    this.salesQuoteId,
    this.note,
    this.riskLimitApproved = false,
  });
}

/// Satış: belge + satırlar + stok hareketleri + maliyet dağıtımı + parti
/// kalanları + müşteri carisi + audit — **tek transaction** (BRIEF §3.9).
final class SaleRepository {
  final AppDatabase db;
  const SaleRepository(this.db);

  Future<String> create(SaleInput input, OperationContext ctx) =>
      db.runOperation(ctx, () => _create(input, ctx));

  Future<String> _create(SaleInput input, OperationContext ctx) async {
    final saleId = uuid.v7();
    final docNo = await db.nextDocumentNumber(
      DocPrefix.sale,
      input.docDate.year,
    );
    final mainLocation = await db.locationId(LocationCode.mainWarehouse);
    final method = await _costingMethod();

    // 1) Satır hesapları.
    final vatLines = [
      for (final line in input.lines)
        VatCalculator.forMode(
          mode: input.priceMode,
          volume: line.volume,
          unitPrice: line.unitPriceM3,
          vatRate: line.vatRate,
          discountRate: line.discountRate,
        ),
    ];
    final grandTotal = sumMoney(vatLines.map((v) => v.gross));

    // 2) Risk limiti kontrolü (BRIEF §5).
    await _checkRiskLimit(input, grandTotal);

    // 3) Maliyet: FIFO veya ağırlıklı ortalama.
    final lineCosts = <CostingResult>[];
    for (final line in input.lines) {
      final batches = await db.batchesForVariant(line.variantId);

      if (method == CostingMethod.weightedAverage) {
        final variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(line.variantId))).getSingle();
        final productBatches = await db.batchesForProduct(variant.productId);
        lineCosts.add(
          CostingEngine.weightedAverage(
            batches: batches,
            productBatches: productBatches,
            requiredPieces: line.pieces,
            requiredVolume: line.volume,
          ),
        );
      } else {
        lineCosts.add(
          CostingEngine.fifo(
            batches: batches,
            requiredPieces: line.pieces,
            requiredVolume: line.volume,
          ),
        );
      }
    }

    // 4) Belge başlığı. cost_total SABİTLENİR (BRIEF §3.6).
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: saleId,
            docNo: docNo,
            customerId: input.customerId,
            salesQuoteId: Value(input.salesQuoteId),
            docDate: input.docDate.millisecondsSinceEpoch,
            dueDate: Value(input.dueDate?.millisecondsSinceEpoch),
            priceMode: input.priceMode,
            invoiceNo: Value(input.invoiceNo),
            waybillNo: Value(input.waybillNo),
            subtotalNet: sumMoney(vatLines.map((v) => v.net)),
            vatTotal: sumMoney(vatLines.map((v) => v.vat)),
            grandTotal: grandTotal,
            costTotal: sumMoney(lineCosts.map((c) => c.totalCost)),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
            note: Value(input.note),
          ),
        );

    // 5) Satırlar, stok hareketleri, maliyet dağıtımı, parti kalanları.
    for (var i = 0; i < input.lines.length; i++) {
      final line = input.lines[i];
      final vat = vatLines[i];
      final costing = lineCosts[i];

      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: uuid.v7(),
              saleId: saleId,
              lineNo: i + 1,
              variantId: line.variantId,
              pieces: line.pieces,
              volume: line.volume,
              priceListId: Value(line.priceListId),
              listPriceM3: line.listPriceM3,
              discountRate: Value(line.discountRate),
              unitPriceM3: line.unitPriceM3,
              netTotal: vat.net,
              vatRate: line.vatRate,
              vatTotal: vat.vat,
              grossTotal: vat.gross,
              costTotal: costing.totalCost,
            ),
          );

      final movementId = uuid.v7();
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: movementId,
              occurredAt: input.docDate.millisecondsSinceEpoch,
              type: MovementType.saleOut,
              locationId: mainLocation,
              variantId: line.variantId,
              pieces: -line.pieces,
              volume: -line.volume,
              unitCostM3: costing.allocations.isEmpty
                  ? UnitPrice.zero
                  : costing.allocations.first.unitCost,
              totalCost: costing.totalCost,
              sourceType: 'SALE',
              sourceId: Value(saleId),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
              createdBy: Value(ctx.userId),
              deviceId: Value(ctx.deviceId),
            ),
          );

      await _applyAllocations(movementId, costing.allocations, ctx);
    }

    // 6) Müşteri carisine BRÜT (BRIEF §3.4).
    await db
        .into(db.customerLedger)
        .insert(
          CustomerLedgerCompanion.insert(
            id: uuid.v7(),
            customerId: input.customerId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            docType: LedgerDocType.sale,
            docId: Value(saleId),
            docNo: Value(docNo),
            amount: grandTotal,
            dueDate: Value(input.dueDate?.millisecondsSinceEpoch),
            description: Value('Satış $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'sale',
      entityId: saleId,
      action: 'CREATE',
      summary: 'Satış $docNo kaydedildi, tutar $grandTotal',
    );

    return saleId;
  }

  /// Maliyet dağıtımını yazar ve parti kalanlarını düşer.
  Future<void> _applyAllocations(
    String movementId,
    List<CostAllocation> allocations,
    OperationContext ctx,
  ) async {
    for (final alloc in allocations) {
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

      // remaining_* bir ÖNBELLEKTİR (D-10); CHECK kısıtı negatife düşmeyi
      // veritabanı seviyesinde de engeller.
      await (db.update(
        db.inventoryBatches,
      )..where((b) => b.id.equals(alloc.batchId))).write(
        InventoryBatchesCompanion(
          remainingPieces: Value(batch.remainingPieces - alloc.pieces),
          remainingVolume: Value(batch.remainingVolume - alloc.volume),
        ),
      );
    }
  }

  Future<void> _checkRiskLimit(SaleInput input, Money newTotal) async {
    if (input.riskLimitApproved) return;

    final customer = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(input.customerId))).getSingle();
    if (customer.riskLimit.isZero) return; // 0 = limitsiz

    final balance = await db.customerBalance(input.customerId);
    final statuses = InstrumentStatus.inPortfolio.map((s) => "'$s'").join(',');
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM instruments '
          "WHERE direction = 'IN' AND customer_id = ? AND current_status IN ($statuses)",
          variables: [Variable.withString(input.customerId)],
          readsFrom: {db.instruments},
        )
        .getSingle();
    final pending = Money.fromStored(row.read<int>('total'));

    if (balance + pending + newTotal > customer.riskLimit) {
      throw RiskLimitExceededException(
        balance: balance,
        pendingInstruments: pending,
        newTotal: newTotal,
        limit: customer.riskLimit,
      );
    }
  }

  Future<String> _costingMethod() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('costing_method'))).getSingleOrNull();
    return row?.value ?? CostingMethod.fifo;
  }
}
