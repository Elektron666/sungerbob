import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

final class CollectionInput {
  final String customerId;
  final DateTime docDate;
  final Money amount;
  final String method;
  final String? cashAccountId;

  /// Elle eşleştirme: belge id → tutar. Boşsa vadesi en erken açık belgeler
  /// otomatik kapatılır (BRIEF §3.10).
  final Map<String, Money>? manualAllocations;
  final String? note;

  /// Çek/senet ise evrak bilgileri.
  final InstrumentInput? instrument;

  const CollectionInput({
    required this.customerId,
    required this.docDate,
    required this.amount,
    required this.method,
    this.cashAccountId,
    this.manualAllocations,
    this.instrument,
    this.note,
  });
}

final class InstrumentInput {
  final String kind;
  final String? serialNo;
  final String? bankName;
  final String? branch;
  final String? drawerName;
  final DateTime dueDate;

  const InstrumentInput({
    required this.kind,
    required this.dueDate,
    this.serialNo,
    this.bankName,
    this.branch,
    this.drawerName,
  });
}

/// Tahsilat: belge + eşleştirme + cari + kasa hareketi veya evrak — tek
/// transaction (BRIEF §3.9, §3.10).
final class CollectionRepository {
  final AppDatabase db;
  const CollectionRepository(this.db);

  Future<String> create(CollectionInput input, OperationContext ctx) =>
      db.runOperation(ctx, () => _create(input, ctx));

  Future<String> _create(CollectionInput input, OperationContext ctx) async {
    final collectionId = uuid.v7();
    final docNo = await db.nextDocumentNumber(
      DocPrefix.collection,
      input.docDate.year,
    );

    String? instrumentId;
    if (PaymentMethod.needsInstrument.contains(input.method)) {
      instrumentId = await _createInstrument(input, ctx);
    }

    await db
        .into(db.collections)
        .insert(
          CollectionsCompanion.insert(
            id: collectionId,
            docNo: docNo,
            customerId: input.customerId,
            docDate: input.docDate.millisecondsSinceEpoch,
            method: input.method,
            cashAccountId: Value(input.cashAccountId),
            instrumentId: Value(instrumentId),
            amount: input.amount,
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            note: Value(input.note),
          ),
        );

    // Cari: alacak (bakiye düşer).
    await db
        .into(db.customerLedger)
        .insert(
          CustomerLedgerCompanion.insert(
            id: uuid.v7(),
            customerId: input.customerId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            docType: instrumentId != null
                ? LedgerDocType.instrumentIn
                : LedgerDocType.collection,
            docId: Value(collectionId),
            docNo: Value(docNo),
            amount: -input.amount,
            description: Value('Tahsilat $docNo'),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    // Kasa/banka hareketi (nakit, havale, kart).
    if (input.cashAccountId != null &&
        PaymentMethod.needsAccount.contains(input.method)) {
      await db
          .into(db.accountMovements)
          .insert(
            AccountMovementsCompanion.insert(
              id: uuid.v7(),
              cashAccountId: input.cashAccountId!,
              occurredAt: input.docDate.millisecondsSinceEpoch,
              direction: 'IN',
              amount: input.amount,
              type: AccountMovementType.collection,
              sourceType: const Value('COLLECTION'),
              sourceId: Value(collectionId),
              description: Value('Tahsilat $docNo'),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );
    }

    await _allocate(collectionId, input, ctx);

    await db.writeAudit(
      ctx,
      entityType: 'collection',
      entityId: collectionId,
      action: 'CREATE',
      summary: 'Tahsilat $docNo, tutar ${input.amount}',
    );

    return collectionId;
  }

  /// Eşleştirme: elle verilmişse onu, yoksa **vadesi en erken açık belgeleri**
  /// kapatır (BRIEF §3.10).
  Future<void> _allocate(
    String collectionId,
    CollectionInput input,
    OperationContext ctx,
  ) async {
    if (input.manualAllocations != null) {
      for (final e in input.manualAllocations!.entries) {
        await db
            .into(db.paymentAllocations)
            .insert(
              PaymentAllocationsCompanion.insert(
                id: uuid.v7(),
                collectionId: collectionId,
                targetType: 'SALE',
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
    for (final open in await openDocuments(input.customerId)) {
      if (remaining.isZero || !remaining.isPositive) break;
      final take = open.remaining < remaining ? open.remaining : remaining;
      await db
          .into(db.paymentAllocations)
          .insert(
            PaymentAllocationsCompanion.insert(
              id: uuid.v7(),
              collectionId: collectionId,
              targetType: open.targetType,
              targetId: open.id,
              amount: take,
              createdAt: ctx.nowMs,
            ),
          );
      remaining -= take;
    }
  }

  /// Müşterinin açık belgeleri, vadesi en erken önce.
  Future<List<({String id, String targetType, Money remaining, int? dueDate})>>
  openDocuments(String customerId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT s.id AS id, s.due_date AS due_date, s.grand_total AS total,
             COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa
                       WHERE pa.target_type = 'SALE' AND pa.target_id = s.id), 0) AS paid
      FROM sales s
      WHERE s.customer_id = ? AND s.status = 'ACTIVE'
      ORDER BY COALESCE(s.due_date, s.doc_date) ASC, s.doc_date ASC
      ''',
          variables: [Variable.withString(customerId)],
          readsFrom: {db.sales, db.paymentAllocations},
        )
        .get();

    final result =
        <({String id, String targetType, Money remaining, int? dueDate})>[];
    for (final r in rows) {
      final remaining = Money.fromStored(
        r.read<int>('total') - r.read<int>('paid'),
      );
      if (remaining.isPositive) {
        result.add((
          id: r.read<String>('id'),
          targetType: 'SALE',
          remaining: remaining,
          dueDate: r.read<int?>('due_date'),
        ));
      }
    }
    return result;
  }

  Future<String> _createInstrument(
    CollectionInput input,
    OperationContext ctx,
  ) async {
    final inst = input.instrument!;
    final instrumentId = uuid.v7();

    await db
        .into(db.instruments)
        .insert(
          InstrumentsCompanion.insert(
            id: instrumentId,
            kind: inst.kind,
            direction: InstrumentDirection.incoming,
            serialNo: Value(inst.serialNo),
            bankName: Value(inst.bankName),
            branch: Value(inst.branch),
            drawerName: Value(inst.drawerName),
            dueDate: inst.dueDate.millisecondsSinceEpoch,
            amount: input.amount,
            customerId: Value(input.customerId),
            currentStatus: InstrumentStatus.portfolio,
            sourceType: const Value('COLLECTION'),
            createdAt: ctx.nowMs,
          ),
        );

    await db
        .into(db.instrumentEvents)
        .insert(
          InstrumentEventsCompanion.insert(
            id: uuid.v7(),
            instrumentId: instrumentId,
            occurredAt: input.docDate.millisecondsSinceEpoch,
            toStatus: InstrumentStatus.portfolio,
            amount: input.amount,
            counterpartyId: Value(input.customerId),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    return instrumentId;
  }
}
