import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

final class SupplierPaymentInput {
  final String supplierId;
  final DateTime docDate;
  final Money amount;
  final String method;
  final String? cashAccountId;
  final Map<String, Money>? manualAllocations;
  final String? note;

  const SupplierPaymentInput({
    required this.supplierId,
    required this.docDate,
    required this.amount,
    required this.method,
    this.cashAccountId,
    this.manualAllocations,
    this.note,
  });
}

/// Tedarikçi ödemesi ve virman. Tahsilatla aynı mantık (BRIEF §3.10).
final class PaymentRepository {
  final AppDatabase db;
  const PaymentRepository(this.db);

  Future<String> paySupplier(
    SupplierPaymentInput input,
    OperationContext ctx,
  ) => db.runOperation(ctx, () async {
    final paymentId = uuid.v7();
    final docNo = await db.nextDocumentNumber(
      DocPrefix.payment,
      input.docDate.year,
    );

    await db
        .into(db.supplierPayments)
        .insert(
          SupplierPaymentsCompanion.insert(
            id: paymentId,
            docNo: docNo,
            supplierId: input.supplierId,
            docDate: input.docDate.millisecondsSinceEpoch,
            method: input.method,
            cashAccountId: Value(input.cashAccountId),
            amount: input.amount,
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            note: Value(input.note),
          ),
        );

    // Tedarikçi borcu azalır.
    await db
        .into(db.supplierLedger)
        .insert(
          SupplierLedgerCompanion.insert(
            id: uuid.v7(),
            supplierId: input.supplierId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            docType: LedgerDocType.payment,
            docId: Value(paymentId),
            docNo: Value(docNo),
            amount: -input.amount,
            description: Value('Ödeme $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    if (input.cashAccountId != null &&
        PaymentMethod.needsAccount.contains(input.method)) {
      await db
          .into(db.accountMovements)
          .insert(
            AccountMovementsCompanion.insert(
              id: uuid.v7(),
              cashAccountId: input.cashAccountId!,
              occurredAt: input.docDate.millisecondsSinceEpoch,
              direction: 'OUT',
              amount: input.amount,
              type: AccountMovementType.payment,
              sourceType: const Value('SUPPLIER_PAYMENT'),
              sourceId: Value(paymentId),
              description: Value('Ödeme $docNo'),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );
    }

    await _allocate(paymentId, input, ctx);

    await db.writeAudit(
      ctx,
      entityType: 'supplier_payment',
      entityId: paymentId,
      action: 'CREATE',
      summary: 'Tedarikçi ödemesi $docNo, tutar ${input.amount}',
    );

    return paymentId;
  });

  Future<void> _allocate(
    String paymentId,
    SupplierPaymentInput input,
    OperationContext ctx,
  ) async {
    if (input.manualAllocations != null) {
      for (final e in input.manualAllocations!.entries) {
        await db
            .into(db.supplierPaymentAllocations)
            .insert(
              SupplierPaymentAllocationsCompanion.insert(
                id: uuid.v7(),
                supplierPaymentId: paymentId,
                targetType: 'PURCHASE',
                targetId: e.key,
                amount: e.value,
                isManual: const Value(true),
                createdAt: ctx.nowMs,
              ),
            );
      }
      return;
    }

    var remaining = input.amount;
    for (final open in await openPurchases(input.supplierId)) {
      if (!remaining.isPositive) break;
      final take = open.remaining < remaining ? open.remaining : remaining;
      await db
          .into(db.supplierPaymentAllocations)
          .insert(
            SupplierPaymentAllocationsCompanion.insert(
              id: uuid.v7(),
              supplierPaymentId: paymentId,
              targetType: 'PURCHASE',
              targetId: open.id,
              amount: take,
              createdAt: ctx.nowMs,
            ),
          );
      remaining -= take;
    }
  }

  /// Tedarikçinin açık alışları, vadesi en erken önce.
  Future<List<({String id, Money remaining, int? dueDate})>> openPurchases(
    String supplierId,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT p.id AS id, p.due_date AS due_date, p.grand_total AS total,
             COALESCE((SELECT SUM(spa.amount) FROM supplier_payment_allocations spa
                       WHERE spa.target_type = 'PURCHASE' AND spa.target_id = p.id), 0) AS paid
      FROM purchases p
      WHERE p.supplier_id = ? AND p.status = 'ACTIVE'
      ORDER BY COALESCE(p.due_date, p.doc_date) ASC, p.doc_date ASC
      ''',
          variables: [Variable.withString(supplierId)],
          readsFrom: {db.purchases, db.supplierPaymentAllocations},
        )
        .get();

    final result = <({String id, Money remaining, int? dueDate})>[];
    for (final r in rows) {
      final remaining = Money.fromStored(
        r.read<int>('total') - r.read<int>('paid'),
      );
      if (remaining.isPositive) {
        result.add((
          id: r.read<String>('id'),
          remaining: remaining,
          dueDate: r.read<int?>('due_date'),
        ));
      }
    }
    return result;
  }

  /// Virman: tek transaction'da iki hesap hareketi (ERD §8).
  Future<String> transfer({
    required String fromAccountId,
    required String toAccountId,
    required Money amount,
    required DateTime docDate,
    required OperationContext ctx,
    String? note,
  }) => db.runOperation(ctx, () async {
    final transferId = uuid.v7();
    final docNo = await db.nextDocumentNumber(DocPrefix.transfer, docDate.year);

    await db
        .into(db.transfers)
        .insert(
          TransfersCompanion.insert(
            id: transferId,
            docNo: docNo,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            amount: amount,
            docDate: docDate.millisecondsSinceEpoch,
            createdAt: ctx.nowMs,
            note: Value(note),
          ),
        );

    await db
        .into(db.accountMovements)
        .insert(
          AccountMovementsCompanion.insert(
            id: uuid.v7(),
            cashAccountId: fromAccountId,
            occurredAt: docDate.millisecondsSinceEpoch,
            direction: 'OUT',
            amount: amount,
            type: AccountMovementType.transferOut,
            sourceType: const Value('TRANSFER'),
            sourceId: Value(transferId),
            counterAccountId: Value(toAccountId),
            description: Value('Virman $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.accountMovements)
        .insert(
          AccountMovementsCompanion.insert(
            id: uuid.v7(),
            cashAccountId: toAccountId,
            occurredAt: docDate.millisecondsSinceEpoch,
            direction: 'IN',
            amount: amount,
            type: AccountMovementType.transferIn,
            sourceType: const Value('TRANSFER'),
            sourceId: Value(transferId),
            counterAccountId: Value(fromAccountId),
            description: Value('Virman $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'transfer',
      entityId: transferId,
      action: 'CREATE',
      summary: 'Virman $docNo, tutar $amount',
    );

    return transferId;
  });
}
