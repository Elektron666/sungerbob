import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../db/app_database.dart';
import '../db/enums.dart';

/// Bir bildirim isteği. Platform katmanı bunu
/// `flutter_local_notifications`'a verir.
final class PendingNotification {
  final String id;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final String route;

  const PendingNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.route,
  });
}

/// Vade bildirimleri (BRIEF §5).
///
/// "Vade gününden **bir gün önce** yerel bildirim."
///
/// Karar mantığı saf tutuluyor: hangi bildirimlerin gerektiğini hesaplar,
/// göndermez. Böylece cihaz olmadan test edilebilir.
final class DueDateNotifier {
  final AppDatabase db;
  const DueDateNotifier(this.db);

  Future<List<PendingNotification>> pendingNotifications({
    DateTime? now,
    int horizonDays = 30,
  }) async {
    final reference = now ?? DateTime.now();
    final horizon = reference.add(Duration(days: horizonDays));
    final result = <PendingNotification>[];

    // --- Çek/senet vadeleri ---
    final instrumentRows =
        await (db.select(db.instruments)
              ..where(
                (i) =>
                    i.dueDate.isBetweenValues(
                      reference.millisecondsSinceEpoch,
                      horizon.millisecondsSinceEpoch,
                    ) &
                    i.currentStatus.isIn([
                      InstrumentStatus.portfolio,
                      InstrumentStatus.atBank,
                      InstrumentStatus.issued,
                    ]),
              )
              ..orderBy([(i) => OrderingTerm.asc(i.dueDate)]))
            .get();

    for (final inst in instrumentRows) {
      final due = DateTime.fromMillisecondsSinceEpoch(inst.dueDate);
      final notifyAt = _dayBefore(due);
      if (notifyAt.isBefore(reference)) continue;

      final incoming = inst.direction == InstrumentDirection.incoming;
      result.add(
        PendingNotification(
          id: 'instrument-${inst.id}',
          title: incoming
              ? 'Yarın tahsil edilecek evrak'
              : 'Yarın ödenecek evrak',
          body:
              '${_kindLabel(inst.kind)} ${inst.serialNo ?? ''} · '
              '${_money(inst.amount)} TL',
          scheduledAt: notifyAt,
          route: '/instruments/${inst.id}',
        ),
      );
    }

    // --- Satış vadeleri ---
    final saleRows = await db
        .customSelect(
          '''
      SELECT s.id, s.doc_no, s.due_date, c.title,
             s.grand_total - COALESCE(paid.amount, 0) AS remaining
      FROM sales s
      JOIN customers c ON c.id = s.customer_id
      LEFT JOIN (SELECT target_id, SUM(amount) AS amount
                 FROM payment_allocations WHERE target_type = 'SALE'
                 GROUP BY target_id) paid ON paid.target_id = s.id
      WHERE s.status = 'ACTIVE' AND s.due_date BETWEEN ? AND ?
        AND s.grand_total > COALESCE(paid.amount, 0)
      ORDER BY s.due_date
      ''',
          variables: [
            Variable.withInt(reference.millisecondsSinceEpoch),
            Variable.withInt(horizon.millisecondsSinceEpoch),
          ],
          readsFrom: {db.sales, db.customers, db.paymentAllocations},
        )
        .get();

    for (final row in saleRows) {
      final due = DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('due_date'),
      );
      final notifyAt = _dayBefore(due);
      if (notifyAt.isBefore(reference)) continue;

      result.add(
        PendingNotification(
          id: 'sale-${row.read<String>('id')}',
          title: 'Yarın vadesi dolan alacak',
          body:
              '${row.read<String>('title')} · '
              '${_money(Money.fromStored(row.read<int>('remaining')))} TL',
          scheduledAt: notifyAt,
          route: '/sales/${row.read<String>('id')}',
        ),
      );
    }

    result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return result;
  }

  /// Vade gününden bir gün önce, sabah 09:00.
  static DateTime _dayBefore(DateTime due) =>
      DateTime(due.year, due.month, due.day - 1, 9);

  static String _kindLabel(String kind) =>
      kind == InstrumentKind.check ? 'Çek' : 'Senet';

  static String _money(Money value) =>
      value.tl.toStringAsFixed(2); // ignore: allowed-double
}
