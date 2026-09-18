import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../../domain/core/money.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../sale/sale_return_screen.dart';

/// Satışlar ve Alışlar (BRIEF §7 menüsü).
///
/// En büyük eksik buydu: kullanıcı kaydettiği belgeyi bir daha göremiyordu.
/// "Dün kime ne sattım?" sorusunun cevabı olmayan bir defter, defter değildir.
class DocumentsScreen extends StatelessWidget {
  /// true: satışlar, false: alışlar.
  final bool sales;

  /// Açılışta detayı gösterilecek belge. Vade bildirimine dokunan kullanıcı
  /// listede belgeyi aramak zorunda kalmasın diye var.
  final String? openDocId;

  const DocumentsScreen({super.key, required this.sales, this.openDocId});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(sales ? 'Satışlar' : 'Alışlar')),
    body: _DocumentList(sales: sales, openDocId: openDocId),
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

  /// Bu satışa kesilmiş iade tutarı. Satış olduğu gibi durur ama listede
  /// "bunun bir kısmı geri geldi" bilgisi görünmezse defter yanıltır.
  final Money returned;

  const DocumentRow({
    required this.id,
    required this.docNo,
    required this.partyTitle,
    required this.date,
    required this.dueDate,
    required this.grandTotal,
    required this.status,
    this.returned = Money.zero,
  });

  bool get isCancelled => status != 'ACTIVE';

  bool get hasReturn => returned.stored > 0;
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
               d.status, p.title AS party,
               ${sales ? '''COALESCE((
                 SELECT SUM(r.grand_total) FROM sale_returns r
                 WHERE r.sale_id = d.id AND r.status = 'ACTIVE'
               ), 0)''' : '0'} AS returned
        FROM $table d
        JOIN $partyTable p ON p.id = d.$partyKey
        ORDER BY d.doc_date DESC, d.created_at DESC
        LIMIT 200
        ''',
            readsFrom: {
              if (sales) db.sales else db.purchases,
              if (sales) db.customers else db.suppliers,
              if (sales) db.saleReturns,
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
            returned: Money.fromStored(r.read<int>('returned')),
            status: r.read<String>('status'),
          ),
      ];
    });

class _DocumentList extends ConsumerStatefulWidget {
  final bool sales;
  final String? openDocId;
  const _DocumentList({required this.sales, this.openDocId});

  @override
  ConsumerState<_DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends ConsumerState<_DocumentList> {
  /// Bildirimden gelen belge yalnızca bir kez açılır; kullanıcı kapattıktan
  /// sonra liste her yeniden çizildiğinde tekrar açılmamalı.
  bool _opened = false;

  bool get sales => widget.sales;

  void _openRequested(List<DocumentRow> list) {
    final id = widget.openDocId;
    if (_opened || id == null) return;
    final doc = list.where((d) => d.id == id).firstOrNull;
    if (doc == null) return;

    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DocumentDetailSheet(sales: sales, doc: doc),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider(sales));
    final scheme = Theme.of(context).colorScheme;

    return docs.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(documentsProvider(sales)),
      ),
      data: (list) {
        _openRequested(list);
        return list.isEmpty
            ? EmptyState(
                icon: sales
                    ? Icons.receipt_long
                    : Icons.local_shipping_outlined,
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
                        '${doc.isCancelled ? ' · İPTAL' : ''}'
                        '${doc.hasReturn ? ' · ${TrFormat.moneyWithCurrency(doc.returned)} iade' : ''}',
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
              );
      },
    );
  }
}

/// Belge satırının adı: "Beyaz Sünger · 140×200×10" ya da ölçüsüz
/// malzemede yalnızca "Sünger Yapıştırıcı" (D-22).
String describeLine({
  required String product,
  required String unit,
  required int width,
  required int height,
  required int thickness,
}) {
  if (!ProductUnit.hasDimensions(unit)) return product;
  return '$product · '
      '${TrFormat.dimensions(Dimension.fromStored(width), Dimension.fromStored(height), Dimension.fromStored(thickness))}';
}

/// Belge satırı — kalem bilgileri.
final class DocumentLine {
  final String description;
  final int pieces;
  final Volume volume;
  final UnitPrice unitPrice;
  final Money net;
  final Money gross;

  /// Ürünün birimi; ince malzemede ölçü ve m³ yazılmaz (D-22).
  final String unit;

  const DocumentLine({
    required this.description,
    required this.pieces,
    required this.volume,
    required this.unitPrice,
    required this.net,
    required this.gross,
    this.unit = ProductUnit.m3,
  });

  /// "12 adet · 2,8 m³ · 2.500,00 TL/m³" veya "50 kg · 120,00 TL/kg".
  String get quantityText => ProductUnit.hasDimensions(unit)
      ? '${TrFormat.pieces(pieces)} · ${TrFormat.volume(volume)} · '
            '${TrFormat.unitPrice(unitPrice)}'
      : '${TrFormat.quantity(volume, unit)} · '
            '${TrFormat.unitPriceFor(unitPrice, unit)}';
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
               i.gross_total, pr.name AS product, pr.unit AS unit,
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
            description: describeLine(
              product: r.read<String>('product'),
              unit: r.read<String>('unit'),
              width: r.read<int>('width'),
              height: r.read<int>('height'),
              thickness: r.read<int>('thickness'),
            ),
            pieces: r.read<int>('pieces'),
            volume: Volume.fromStored(r.read<int>('volume')),
            unitPrice: UnitPrice.fromStored(r.read<int>('unit_price_m3')),
            net: Money.fromStored(r.read<int>('net_total')),
            gross: Money.fromStored(r.read<int>('gross_total')),
            unit: r.read<String>('unit'),
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
            '${doc.isCancelled ? ' · İPTAL EDİLDİ' : ''}'
            '${doc.hasReturn ? ' · ${TrFormat.moneyWithCurrency(doc.returned)} iade edildi' : ''}',
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
                                line.quantityText,
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
                // Müşteri malı geri getirdiğinde girilecek yer burası.
                // Satış **iptal edilmez**: iade ayrı bir belgedir, orijinal
                // satış olduğu gibi durur (D-12).
                if (sales && !doc.isCancelled) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => _openReturn(context, ref),
                    icon: const Icon(Icons.assignment_return),
                    label: const Text('İade al'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReturn(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => SaleReturnScreen(
          saleId: doc.id,
          saleTitle: '${doc.partyTitle} · ${doc.docNo}',
        ),
      ),
    );
    if (saved != true) return;

    ref.invalidate(documentsProvider(sales));
    ref.invalidate(documentLinesProvider((sales: sales, id: doc.id)));
    // İade kaydedildi; detay sayfası eski tutarları göstermesin.
    navigator.pop();
  }
}
