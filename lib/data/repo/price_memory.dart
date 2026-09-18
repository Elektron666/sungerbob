import 'package:drift/drift.dart';

import '../../domain/core/quantity.dart';
import '../db/app_database.dart';

/// "Bu müşteriye en son kaça satmıştım?"
///
/// Toptan süngercide fiyat müşteriye göre değişir ve pazarlık telefonda,
/// ayaküstü yapılır. Son fiyatı hatırlamak için eski fişe bakmak zaman
/// kaybıdır; ekran bunu kendisi söylemeli.
///
/// Yalnızca **ipucudur**: fiyatı doldurmaz, kullanıcı yerine karar vermez.
/// Otomatik doldurmak, zam yapılması gereken yerde eski fiyatı sessizce
/// tekrarlama riski taşır.
final class PriceMemory {
  final AppDatabase db;
  const PriceMemory(this.db);

  /// Müşteriye o üründen yapılan son satışın birim fiyatı ve tarihi.
  Future<PriceHint?> lastSalePrice({
    required String customerId,
    required String productId,
  }) => _last(
    sql: '''
      SELECT i.unit_price_m3 AS price, s.doc_date AS date
      FROM sale_items i
      JOIN sales s ON s.id = i.sale_id
      JOIN product_variants v ON v.id = i.variant_id
      WHERE s.customer_id = ? AND v.product_id = ? AND s.status = 'ACTIVE'
      ORDER BY s.doc_date DESC, s.created_at DESC
      LIMIT 1
      ''',
    args: [customerId, productId],
    reads: {db.saleItems, db.sales, db.productVariants},
  );

  /// Tedarikçiden o üründen yapılan son alışın birim fiyatı ve tarihi.
  Future<PriceHint?> lastPurchasePrice({
    required String supplierId,
    required String productId,
  }) => _last(
    sql: '''
      SELECT i.unit_price_m3 AS price, p.doc_date AS date
      FROM purchase_items i
      JOIN purchases p ON p.id = i.purchase_id
      JOIN product_variants v ON v.id = i.variant_id
      WHERE p.supplier_id = ? AND v.product_id = ? AND p.status = 'ACTIVE'
      ORDER BY p.doc_date DESC, p.created_at DESC
      LIMIT 1
      ''',
    args: [supplierId, productId],
    reads: {db.purchaseItems, db.purchases, db.productVariants},
  );

  Future<PriceHint?> _last({
    required String sql,
    required List<String> args,
    required Set<ResultSetImplementation<dynamic, dynamic>> reads,
  }) async {
    final row = await db
        .customSelect(
          sql,
          variables: [for (final a in args) Variable.withString(a)],
          readsFrom: reads,
        )
        .getSingleOrNull();
    if (row == null) return null;

    return PriceHint(
      unitPrice: UnitPrice.fromStored(row.read<int>('price')),
      date: DateTime.fromMillisecondsSinceEpoch(row.read<int>('date')),
    );
  }
}

final class PriceHint {
  final UnitPrice unitPrice;
  final DateTime date;

  const PriceHint({required this.unitPrice, required this.date});
}
