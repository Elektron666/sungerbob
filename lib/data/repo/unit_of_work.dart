import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

const uuid = Uuid();

/// Aynı komut ikinci kez geldi — işlem tekrarlanmadı (BRIEF §3.9, D-09).
final class DuplicateCommandException implements Exception {
  final String commandId;
  const DuplicateCommandException(this.commandId);

  @override
  String toString() =>
      'Bu işlem zaten kaydedilmiş (komut $commandId). Tekrarlanmadı.';
}

/// Bir iş işleminin bağlamı: kim, hangi cihaz, hangi komut.
final class OperationContext {
  /// Form açıldığında üretilen UUID v7. Aynı UUID ikinci kez gelirse işlem
  /// tekrarlanmaz.
  final String commandId;
  final String commandType;
  final String? userId;
  final String? deviceId;
  final DateTime now;

  OperationContext({
    required this.commandType,
    String? commandId,
    this.userId,
    this.deviceId,
    DateTime? now,
  }) : commandId = commandId ?? uuid.v7(),
       now = now ?? DateTime.now();

  int get nowMs => now.millisecondsSinceEpoch;
}

/// Her iş işlemi tek bir Drift transaction'ıdır (BRIEF §3.9).
///
/// `command_log` kaydı **aynı transaction içinde** yazılır:
/// - işlem başarılıysa komut loglanmış olur,
/// - başarısızsa log da geri alınır ve UUID yeniden denenebilir,
/// - aynı UUID ikinci kez gelirse birincil anahtar çakışır → çift kayıt olmaz.
extension UnitOfWork on AppDatabase {
  Future<T> runOperation<T>(
    OperationContext ctx,
    Future<T> Function() body, {
    String payloadHash = '',
  }) async {
    return transaction(() async {
      try {
        await into(commandLog).insert(
          CommandLogCompanion.insert(
            id: ctx.commandId,
            commandType: ctx.commandType,
            payloadHash: payloadHash,
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
            deviceId: Value(ctx.deviceId),
          ),
        );
      } on SqliteException catch (e) {
        if (e.message.contains('UNIQUE') || e.message.contains('PRIMARY KEY')) {
          throw DuplicateCommandException(ctx.commandId);
        }
        rethrow;
      }
      return body();
    });
  }

  /// Belge numarası atar: `STS-2026-000123`. Aynı transaction içinde
  /// artırıldığı için işlem geri alınırsa numara da geri alınır → boşluk
  /// oluşmaz (BRIEF §3.11, D-15).
  Future<String> nextDocumentNumber(String prefix, int year) async {
    final existing =
        await (select(documentSequences)
              ..where((s) => s.docType.equals(prefix) & s.year.equals(year)))
            .getSingleOrNull();

    if (existing == null) {
      await into(documentSequences).insert(
        DocumentSequencesCompanion.insert(
          id: uuid.v7(),
          docType: prefix,
          year: year,
          lastNumber: const Value(1),
        ),
      );
      return '$prefix-$year-${'1'.padLeft(6, '0')}';
    }

    final next = existing.lastNumber + 1;
    await (update(documentSequences)..where((s) => s.id.equals(existing.id)))
        .write(DocumentSequencesCompanion(lastNumber: Value(next)));
    return '$prefix-$year-${next.toString().padLeft(6, '0')}';
  }

  /// Denetim kaydı (SPEC §24).
  Future<void> writeAudit(
    OperationContext ctx, {
    required String entityType,
    required String entityId,
    required String action,
    required String summary,
    String? beforeJson,
    String? afterJson,
  }) => into(auditLogs).insert(
    AuditLogsCompanion.insert(
      id: uuid.v7(),
      occurredAt: ctx.nowMs,
      actorUserId: Value(ctx.userId),
      deviceId: Value(ctx.deviceId),
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      beforeJson: Value(beforeJson),
      afterJson: Value(afterJson),
      commandId: Value(ctx.commandId),
    ),
  );
}
