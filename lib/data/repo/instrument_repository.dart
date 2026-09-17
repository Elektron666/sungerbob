import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Çek/senet için geçersiz durum geçişi (ERD §9).
final class InvalidInstrumentTransitionException implements Exception {
  final String from;
  final String to;
  const InvalidInstrumentTransitionException(this.from, this.to);

  @override
  String toString() => 'Geçersiz evrak durum geçişi: $from → $to';
}

/// Çek ve senet durum yönetimi (BRIEF §5).
final class InstrumentRepository {
  final AppDatabase db;
  const InstrumentRepository(this.db);

  /// Durum değiştirir ve muhasebe etkisini yazar — tek transaction.
  Future<void> changeStatus({
    required String instrumentId,
    required String toStatus,
    required OperationContext ctx,
    String? cashAccountId,
    String? supplierId,
    String? note,
  }) => db.runOperation(ctx, () async {
    final inst = await (db.select(
      db.instruments,
    )..where((i) => i.id.equals(instrumentId))).getSingle();

    final allowed = inst.direction == InstrumentDirection.incoming
        ? InstrumentStatus.incomingTransitions[inst.currentStatus] ?? const []
        : InstrumentStatus.outgoingTransitions[inst.currentStatus] ?? const [];

    if (!allowed.contains(toStatus)) {
      throw InvalidInstrumentTransitionException(inst.currentStatus, toStatus);
    }

    await db
        .into(db.instrumentEvents)
        .insert(
          InstrumentEventsCompanion.insert(
            id: uuid.v7(),
            instrumentId: instrumentId,
            occurredAt: ctx.nowMs,
            fromStatus: Value(inst.currentStatus),
            toStatus: toStatus,
            cashAccountId: Value(cashAccountId),
            counterpartyId: Value(supplierId ?? inst.customerId),
            amount: inst.amount,
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
            note: Value(note),
          ),
        );

    await _applyEffect(inst, toStatus, cashAccountId, supplierId, ctx);

    await (db.update(
      db.instruments,
    )..where((i) => i.id.equals(instrumentId))).write(
      InstrumentsCompanion(
        currentStatus: Value(toStatus),
        endorsedToSupplierId: toStatus == InstrumentStatus.endorsed
            ? Value(supplierId)
            : const Value.absent(),
      ),
    );

    await db.writeAudit(
      ctx,
      entityType: 'instrument',
      entityId: instrumentId,
      action: 'STATUS_CHANGE',
      summary:
          'Evrak ${inst.serialNo ?? instrumentId}: ${inst.currentStatus} → $toStatus',
    );
  });

  Future<void> _applyEffect(
    Instrument inst,
    String toStatus,
    String? cashAccountId,
    String? supplierId,
    OperationContext ctx,
  ) async {
    switch (toStatus) {
      // Tahsil edildi → banka hesabına giriş.
      case InstrumentStatus.collected:
        if (cashAccountId != null) {
          await db
              .into(db.accountMovements)
              .insert(
                AccountMovementsCompanion.insert(
                  id: uuid.v7(),
                  cashAccountId: cashAccountId,
                  occurredAt: ctx.nowMs,
                  direction: 'IN',
                  amount: inst.amount,
                  type: AccountMovementType.instrumentCollected,
                  sourceType: const Value('INSTRUMENT'),
                  sourceId: Value(inst.id),
                  description: Value('Evrak tahsil: ${inst.serialNo ?? ''}'),
                  commandId: Value(ctx.commandId),
                  createdAt: ctx.nowMs,
                ),
              );
        }

      // Karşılıksız / protestolu → müşteri carisine TERS kayıt.
      case InstrumentStatus.bounced:
      case InstrumentStatus.returned:
        if (inst.customerId != null) {
          await db
              .into(db.customerLedger)
              .insert(
                CustomerLedgerCompanion.insert(
                  id: uuid.v7(),
                  customerId: inst.customerId!,
                  occurredAt: ctx.nowMs,
                  docType: LedgerDocType.instrumentBounced,
                  docId: Value(inst.id),
                  amount: inst.amount, // borç geri gelir
                  description: Value(
                    toStatus == InstrumentStatus.bounced
                        ? 'Karşılıksız çek/senet: ${inst.serialNo ?? ''}'
                        : 'İade edilen evrak: ${inst.serialNo ?? ''}',
                  ),
                  commandId: Value(ctx.commandId),
                  createdAt: ctx.nowMs,
                ),
              );
        }

      // Ciro → tedarikçi borcu azalır.
      case InstrumentStatus.endorsed:
        if (supplierId != null) {
          await db
              .into(db.supplierLedger)
              .insert(
                SupplierLedgerCompanion.insert(
                  id: uuid.v7(),
                  supplierId: supplierId,
                  occurredAt: ctx.nowMs,
                  docType: LedgerDocType.instrumentEndorsed,
                  docId: Value(inst.id),
                  amount: -inst.amount,
                  description: Value('Ciro: ${inst.serialNo ?? ''}'),
                  commandId: Value(ctx.commandId),
                  createdAt: ctx.nowMs,
                ),
              );
        }

      // Verilen evrak ödendi → bankadan çıkış.
      case InstrumentStatus.paid:
        if (cashAccountId != null) {
          await db
              .into(db.accountMovements)
              .insert(
                AccountMovementsCompanion.insert(
                  id: uuid.v7(),
                  cashAccountId: cashAccountId,
                  occurredAt: ctx.nowMs,
                  direction: 'OUT',
                  amount: inst.amount,
                  type: AccountMovementType.instrumentPaid,
                  sourceType: const Value('INSTRUMENT'),
                  sourceId: Value(inst.id),
                  description: Value(
                    'Verilen evrak ödendi: ${inst.serialNo ?? ''}',
                  ),
                  commandId: Value(ctx.commandId),
                  createdAt: ctx.nowMs,
                ),
              );
        }
    }
  }
}
