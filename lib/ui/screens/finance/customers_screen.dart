import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/stock_queries.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Cari listesi (SPEC §9).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cari')),
      body: m.Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Müşteri ara',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: customers.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(error: e),
              data: (rows) {
                final filtered = _query.isEmpty
                    ? rows
                    : rows
                          .where(
                            (r) => r.normalized.contains(_normalize(_query)),
                          )
                          .toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: _query.isEmpty ? 'Müşteri yok' : 'Sonuç yok',
                    description: _query.isEmpty
                        ? 'İlk müşterinizi ekleyerek başlayın.'
                        : '"$_query" için müşteri bulunamadı.',
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = filtered[i];
                    return ListTile(
                      title: Text(row.title),
                      subtitle: row.overdue.isPositive
                          ? Text(
                              'Vadesi geçen: ${TrFormat.moneyWithCurrency(row.overdue)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : null,
                      trailing: m.Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            TrFormat.moneyWithCurrency(row.balance),
                            style: context.numberStyle,
                          ),
                          Text(
                            row.balance.isPositive ? 'BORÇ' : 'ALACAK',
                            style: context.labelStyle,
                          ),
                        ],
                      ),
                      onTap: () => context.push('/customers/${row.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}

final class CustomerRow {
  final String id;
  final String title;
  final String normalized;
  final Money balance;
  final Money overdue;

  const CustomerRow({
    required this.id,
    required this.title,
    required this.normalized,
    required this.balance,
    required this.overdue,
  });
}

final customerBalancesProvider = FutureProvider.autoDispose<List<CustomerRow>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  final now = DateTime.now().millisecondsSinceEpoch;

  final rows = await db
      .customSelect(
        '''
    SELECT c.id, c.title, c.title_normalized,
      COALESCE((SELECT SUM(amount) FROM customer_ledger cl
                WHERE cl.customer_id = c.id), 0) AS balance,
      COALESCE((
        SELECT SUM(s.grand_total - COALESCE(paid.amount, 0))
        FROM sales s
        LEFT JOIN (SELECT target_id, SUM(amount) AS amount
                   FROM payment_allocations WHERE target_type = 'SALE'
                   GROUP BY target_id) paid ON paid.target_id = s.id
        WHERE s.customer_id = c.id AND s.status = 'ACTIVE'
          AND s.due_date IS NOT NULL AND s.due_date < ?
          AND s.grand_total > COALESCE(paid.amount, 0)
      ), 0) AS overdue
    FROM customers c
    WHERE c.is_active = 1
    ORDER BY balance DESC, c.title ASC
    ''',
        variables: [Variable.withInt(now)],
        readsFrom: {
          db.customers,
          db.customerLedger,
          db.sales,
          db.paymentAllocations,
        },
      )
      .get();

  return [
    for (final r in rows)
      CustomerRow(
        id: r.read<String>('id'),
        title: r.read<String>('title'),
        normalized: r.read<String>('title_normalized'),
        balance: Money.fromStored(r.read<int>('balance')),
        overdue: Money.fromStored(r.read<int>('overdue')),
      ),
  ];
});

/// Cari ekstre (SPEC §9): kronolojik hareketler.
class CustomerLedgerScreen extends ConsumerWidget {
  final String customerId;

  const CustomerLedgerScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(customerLedgerProvider(customerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Cari Ekstre')),
      body: data.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (value) {
          if (value.entries.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: value.customer.title,
              description: 'Henüz hareket yok.',
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: m.Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.customer.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (value.customer.contactPerson != null)
                          Text(
                            value.customer.contactPerson!,
                            style: context.labelStyle,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          '${TrFormat.moneyWithCurrency(value.balance)} '
                          '${value.balance.isPositive ? "BORÇ" : "ALACAK"}',
                          style: context.bigNumberStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final entry in value.entries)
                ListTile(
                  title: Text(
                    entry.description ?? _docTypeLabel(entry.docType),
                  ),
                  subtitle: Text(
                    '${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(entry.occurredAt))}'
                    '${entry.docNo != null ? " · ${entry.docNo}" : ""}',
                  ),
                  trailing: Text(
                    TrFormat.moneyWithCurrency(entry.amount),
                    style: context.numberStyle.copyWith(
                      color: entry.amount.isNegative
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _docTypeLabel(String docType) => switch (docType) {
    LedgerDocType.sale => 'Satış',
    LedgerDocType.saleReturn => 'Satış iadesi',
    LedgerDocType.collection => 'Tahsilat',
    LedgerDocType.instrumentIn => 'Çek/senet alındı',
    LedgerDocType.instrumentBounced => 'Karşılıksız evrak',
    LedgerDocType.opening => 'Açılış bakiyesi',
    LedgerDocType.reversal => 'İptal',
    _ => docType,
  };
}

final class CustomerLedgerView {
  final Customer customer;
  final List<CustomerLedgerEntry> entries;
  final Money balance;

  const CustomerLedgerView({
    required this.customer,
    required this.entries,
    required this.balance,
  });
}

final customerLedgerProvider = FutureProvider.autoDispose
    .family<CustomerLedgerView, String>((ref, customerId) async {
      final db = await ref.watch(databaseProvider.future);

      final customer = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();

      final entries =
          await (db.select(db.customerLedger)
                ..where((l) => l.customerId.equals(customerId))
                ..orderBy([(l) => OrderingTerm.desc(l.occurredAt)]))
              .get();

      return CustomerLedgerView(
        customer: customer,
        entries: entries,
        balance: await db.customerBalance(customerId),
      );
    });
