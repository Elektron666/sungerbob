import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/core/money.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Satışlar ve Alışlar (BRIEF §7 menüsü).
///
/// En büyük eksik buydu: kullanıcı kaydettiği belgeyi bir daha göremiyordu.
/// "Dün kime ne sattım?" sorusunun cevabı olmayan bir defter, defter değildir.
class DocumentsScreen extends StatelessWidget {
  /// true: satışlar, false: alışlar.
  final bool sales;

  const DocumentsScreen({super.key, required this.sales});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(sales ? 'Satışlar' : 'Alışlar')),
    body: _DocumentList(sales: sales),
  );
}

/// Liste satırı — başlık bilgileri.
final class DocumentRow {
  final String id;
  final String docNo;
  final String partyTitle;
  final DateTime date;
  final DateTime? dueDate;
  final Money grandTotal;
  final String status;

  const DocumentRow({
    required this.id,
    required this.docNo,
    required this.partyTitle,
    required this.date,
    required this.dueDate,
    required this.grandTotal,
    required this.status,
  });

  bool get isCancelled => status != 'ACTIVE';
}

final documentsProvider = FutureProvider.autoDispose
    .family<List<DocumentRow>, bool>((ref, sales) async {
      final db = await ref.watch(databaseProvider.future);
      final table = sales ? 'sales' : 'purchases';
      final partyTable = sales ? 'customers' : 'suppliers';
      final partyKey = sales ? 'customer_id' : 'supplier_id';

      final rows = await db
          .customSelect(
            '''
        SELECT d.id, d.doc_no, d.doc_date, d.due_date, d.grand_total,
               d.status, p.title AS party
        FROM $table d
        JOIN $partyTable p ON p.id = d.$partyKey
        ORDER BY d.doc_date DESC, d.created_at DESC
        LIMIT 200
        ''',
            readsFrom: {
              if (sales) db.sales else db.purchases,
              if (sales) db.customers else db.suppliers,
            },
          )
          .get();

      return [
        for (final r in rows)
          DocumentRow(
            id: r.read<String>('id'),
            docNo: r.read<String>('doc_no'),
            partyTitle: r.read<String>('party'),
            date: DateTime.fromMillisecondsSinceEpoch(r.read<int>('doc_date')),
            dueDate: r.read<int?>('due_date') == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(r.read<int>('due_date')),
            grandTotal: Money.fromStored(r.read<int>('grand_total')),
            status: r.read<String>('status'),
          ),
      ];
    });

class _DocumentList extends ConsumerWidget {
  final bool sales;
  const _DocumentList({required this.sales});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider(sales));
    final scheme = Theme.of(context).colorScheme;

    return docs.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(documentsProvider(sales)),
      ),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: sales ? Icons.receipt_long : Icons.local_shipping_outlined,
              title: sales ? 'Henüz satış yok' : 'Henüz alış yok',
              description: sales
                  ? 'İlk satışını girdiğinde burada listelenir.'
                  : 'Stok girişi yaptığında burada listelenir.',
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(documentsProvider(sales)),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final doc = list[i];
                  return ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.partyTitle,
                            overflow: TextOverflow.ellipsis,
                            style: doc.isCancelled
                                ? TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: scheme.onSurfaceVariant,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          TrFormat.moneyWithCurrency(doc.grandTotal),
                          style: context.numberStyle,
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${doc.docNo} · ${TrFormat.date(doc.date)}'
                      '${doc.dueDate == null ? '' : ' · vade ${TrFormat.date(doc.dueDate)}'}'
                      '${doc.isCancelled ? ' · İPTAL' : ''}',
                      style: context.labelStyle,
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          DocumentDetailSheet(sales: sales, doc: doc),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Belge satırı — kalem bilgileri.
final class DocumentLine {
  final String description;
  final int pieces;
  final Volume volume;
  final UnitPrice unitPrice;
  final Money net;
  final Money gross;

  const DocumentLine({
    required this.description,
    required this.pieces,
    required this.volume,
    required this.unitPrice,
    required this.net,
    required this.gross,
  });
}

final documentLinesProvider = FutureProvider.autoDispose
    .family<List<DocumentLine>, ({bool sales, String id})>((ref, args) async {
      final db = await ref.watch(databaseProvider.future);
      final table = args.sales ? 'sale_items' : 'purchase_items';
      final parentKey = args.sales ? 'sale_id' : 'purchase_id';

      final rows = await db
          .customSelect(
            '''
        SELECT i.pieces, i.volume, i.unit_price_m3, i.net_total,
               i.gross_total, pr.name AS product,
               v.width, v.height, v.thickness
        FROM $table i
        JOIN product_variants v ON v.id = i.variant_id
        JOIN products pr ON pr.id = v.product_id
        WHERE i.$parentKey = ?
        ORDER BY i.line_no
        ''',
            variables: [Variable.withString(args.id)],
            readsFrom: {
              if (args.sales) db.saleItems else db.purchaseItems,
              db.productVariants,
              db.products,
            },
          )
          .get();

      return [
        for (final r in rows)
          DocumentLine(
            description:
                '${r.read<String>('product')} · '
                '${TrFormat.dimensions(Dimension.fromStored(r.read<int>('width')), Dimension.fromStored(r.read<int>('height')), Dimension.fromStored(r.read<int>('thickness')))}',
            pieces: r.read<int>('pieces'),
            volume: Volume.fromStored(r.read<int>('volume')),
            unitPrice: UnitPrice.fromStored(r.read<int>('unit_price_m3')),
            net: Money.fromStored(r.read<int>('net_total')),
            gross: Money.fromStored(r.read<int>('gross_total')),
          ),
      ];
    });

/// Belge detayı: kalemler ve toplamlar.
class DocumentDetailSheet extends ConsumerWidget {
  final bool sales;
  final DocumentRow doc;

  const DocumentDetailSheet({
    super.key,
    required this.sales,
    required this.doc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(documentLinesProvider((sales: sales, id: doc.id)));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Text(doc.partyTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${doc.docNo} · ${TrFormat.date(doc.date)}'
            '${doc.isCancelled ? ' · İPTAL EDİLDİ' : ''}',
            style: context.labelStyle,
          ),
          const SizedBox(height: 20),
          lines.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: LoadingState(),
            ),
            error: (e, _) => ErrorState(error: e),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in list) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.description),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${TrFormat.pieces(line.pieces)} · '
                                '${TrFormat.volume(line.volume)} · '
                                '${TrFormat.unitPrice(line.unitPrice)}',
                                style: context.labelStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              TrFormat.moneyWithCurrency(line.gross),
                              style: context.numberStyle,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Genel toplam',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      TrFormat.moneyWithCurrency(doc.grandTotal),
                      style: context.bigNumberStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
