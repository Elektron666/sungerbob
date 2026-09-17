import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Bir belge iki kez iptal edilemez.
final class AlreadyCancelledException implements Exception {
  final String docId;
  const AlreadyCancelledException(this.docId);
  @override
  String toString() => 'Bu belge zaten iptal edilmiş ($docId).';
}

/// İptal = **ters hareket** (SPEC §24, §30.10 · BRIEF §3.5).
///
/// Hiçbir kayıt silinmez. Orijinal satırlar yerinde kalır; etkileri
/// `reversal_of_id` ile birbirine bağlı ters kayıtlarla geri alınır.
final class ReversalRepository {
  final AppDatabase db;
  const ReversalRepository(this.db);

  /// Tahsilat iptali (Altın Senaryo 9).
  Future<void> cancelCollection({
    required String collectionId,
    required String reason,
    required OperationContext ctx,
  }) => db.runOperation(ctx, () async {
    final collection = await (db.select(
      db.collections,
    )..where((c) => c.id.equals(collectionId))).getSingle();

    if (collection.status == DocStatus.cancelled) {
      throw AlreadyCancelledException(collectionId);
    }

    // 1) Cari: orijinal satırın tersi.
    final original =
        await (db.select(db.customerLedger)..where(
              (l) =>
                  l.docId.equals(collectionId) &
                  l.docType.isIn([
                    LedgerDocType.collection,
                    LedgerDocType.instrumentIn,
                  ]),
            ))
            .getSingle();

    await db
        .into(db.customerLedger)
        .insert(
          CustomerLedgerCompanion.insert(
            id: uuid.v7(),
            customerId: collection.customerId,
            occurredAt: ctx.nowMs,
            docType: LedgerDocType.reversal,
            docId: Value(collectionId),
            docNo: Value(collection.docNo),
            amount: -original.amount,
            description: Value('İptal: ${collection.docNo} — $reason'),
            reversalOfId: Value(original.id),
            commandId: Value(ctx.commandId),
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );

    // 2) Kasa hareketi varsa tersi.
    final movements = await (db.select(
      db.accountMovements,
    )..where((m) => m.sourceId.equals(collectionId))).get();
    for (final m in movements) {
      await db
          .into(db.accountMovements)
          .insert(
            AccountMovementsCompanion.insert(
              id: uuid.v7(),
              cashAccountId: m.cashAccountId,
              occurredAt: ctx.nowMs,
              direction: m.direction == 'IN' ? 'OUT' : 'IN',
              amount: m.amount,
              type: AccountMovementType.reversal,
              sourceType: const Value('COLLECTION_CANCEL'),
              sourceId: Value(collectionId),
              reversalOfId: Value(m.id),
              description: Value('İptal: ${collection.docNo}'),
              commandId: Value(ctx.commandId),
              createdAt: ctx.nowMs,
            ),
          );
    }

    // 3) Belge başlığında YALNIZCA durum alanları güncellenir.
    await (db.update(
      db.collections,
    )..where((c) => c.id.equals(collectionId))).write(
      CollectionsCompanion(
        status: const Value(DocStatus.cancelled),
        cancelledAt: Value(ctx.nowMs),
        cancelReason: Value(reason),
      ),
    );

    await db.writeAudit(
      ctx,
      entityType: 'collection',
      entityId: collectionId,
      action: 'REVERSE',
      summary: 'Tahsilat ${collection.docNo} iptal edildi: $reason',
    );
  });
}
