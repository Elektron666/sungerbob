import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/text_normalize.dart';
import '../db/app_database.dart';

/// Global arama sonucu.
final class SearchHit {
  final String kind;
  final String id;
  final String title;
  final String subtitle;
  final String route;

  /// Varsa gösterilecek tutar. **Biçimlendirme arayüzün işi** — veri
  /// katmanı para formatlamaz (yuvarlama tek yerde: rounding.dart).
  final Money? amount;

  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
    this.amount,
  });
}

/// Hızlı arama (SPEC §21).
///
/// "D32" yazıldığında D32 stokları, alışları ve satışları bulunur; müşteri
/// adı yazıldığında müşterinin carisi, satışları ve tahsilatları bulunur.
/// Arama Türkçe normalize edilmiş kolonlarda yapılır (D-18).
extension SearchQueries on AppDatabase {
  Future<List<SearchHit>> globalSearch(String query, {int limit = 20}) async {
    final normalized = normalizeTurkish(query.trim());
    if (normalized.isEmpty) return const [];
    final pattern = '%$normalized%';

    final hits = <SearchHit>[];

    // Müşteriler
    final customerRows = await customSelect(
      '''
      SELECT c.id, c.title,
        COALESCE((SELECT SUM(amount) FROM customer_ledger cl
                  WHERE cl.customer_id = c.id), 0) AS balance
      FROM customers c
      WHERE c.title_normalized LIKE ? AND c.is_active = 1
      LIMIT ?
      ''',
      variables: [Variable.withString(pattern), Variable.withInt(limit)],
      readsFrom: {customers, customerLedger},
    ).get();

    for (final r in customerRows) {
      final balance = Money.fromStored(r.read<int>('balance'));
      hits.add(
        SearchHit(
          kind: 'Müşteri',
          id: r.read<String>('id'),
          title: r.read<String>('title'),
          subtitle: balance.isPositive ? 'BORÇ' : 'ALACAK',
          amount: balance,
          route: '/customers/${r.read<String>('id')}',
        ),
      );
    }

    // Tedarikçiler
    final supplierRows = await customSelect(
      'SELECT id, title FROM suppliers '
      'WHERE title_normalized LIKE ? AND is_active = 1 LIMIT ?',
      variables: [Variable.withString(pattern), Variable.withInt(limit)],
      readsFrom: {suppliers},
    ).get();

    for (final r in supplierRows) {
      hits.add(
        SearchHit(
          kind: 'Tedarikçi',
          id: r.read<String>('id'),
          title: r.read<String>('title'),
          subtitle: 'Tedarikçi kartı',
          // Tedarikçi detay ekranı yok; listeye götürülür.
          route: '/suppliers',
        ),
      );
    }

    // Ürünler ve stok durumu
    final productRows = await customSelect(
      '''
      SELECT p.id, p.name,
        COALESCE((SELECT SUM(b.remaining_pieces)
                  FROM inventory_batches b
                  JOIN product_variants v ON v.id = b.variant_id
                  WHERE v.product_id = p.id), 0) AS pieces
      FROM products p
      WHERE p.name_normalized LIKE ? AND p.is_active = 1
      LIMIT ?
      ''',
      variables: [Variable.withString(pattern), Variable.withInt(limit)],
      readsFrom: {products, inventoryBatches, productVariants},
    ).get();

    for (final r in productRows) {
      hits.add(
        SearchHit(
          kind: 'Ürün',
          id: r.read<String>('id'),
          title: r.read<String>('name'),
          subtitle: 'Stok: ${r.read<int>('pieces')} adet',
          route: '/stock',
        ),
      );
    }

    // Belge numarası ile satış
    final saleRows = await customSelect(
      "SELECT s.id, s.doc_no, s.grand_total, c.title FROM sales s "
      'JOIN customers c ON c.id = s.customer_id '
      'WHERE LOWER(s.doc_no) LIKE ? LIMIT ?',
      variables: [
        Variable.withString('%${query.trim().toLowerCase()}%'),
        Variable.withInt(limit),
      ],
      readsFrom: {sales, customers},
    ).get();

    for (final r in saleRows) {
      hits.add(
        SearchHit(
          kind: 'Satış',
          id: r.read<String>('id'),
          title: r.read<String>('doc_no'),
          subtitle: r.read<String>('title'),
          // Satış detayı listeden açılır; ayrı rota yok.
          route: '/sales',
        ),
      );
    }

    return hits.take(limit).toList();
  }
}
