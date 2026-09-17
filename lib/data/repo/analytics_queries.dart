import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/core/rounding.dart';
import '../../domain/core/scales.dart';
import '../db/app_database.dart';
import '../db/enums.dart';

/// Müşteri analizi (SPEC §19).
final class CustomerAnalysis {
  final String customerId;
  final String title;
  final Money totalSales;
  final Volume totalVolume;
  final Money totalCollected;
  final Money currentDebt;
  final Money grossProfit;
  final DateTime? lastSaleAt;
  final String? topProductName;

  /// Ortalama ödeme süresi (gün). Hiç kapanmış belge yoksa null.
  final int? averagePaymentDays;

  const CustomerAnalysis({
    required this.customerId,
    required this.title,
    required this.totalSales,
    required this.totalVolume,
    required this.totalCollected,
    required this.currentDebt,
    required this.grossProfit,
    this.lastSaleAt,
    this.topProductName,
    this.averagePaymentDays,
  });
}

/// Ürün analizi (SPEC §20).
final class ProductAnalysis {
  final String productId;
  final String name;
  final Volume purchasedVolume;
  final Volume soldVolume;
  final Volume currentVolume;
  final int currentPieces;
  final UnitPrice averageCost;
  final UnitPrice averageSalePrice;
  final Money revenue;
  final Money grossProfit;
  final UnitPrice? lastPurchasePrice;
  final UnitPrice? lastSalePrice;

  const ProductAnalysis({
    required this.productId,
    required this.name,
    required this.purchasedVolume,
    required this.soldVolume,
    required this.currentVolume,
    required this.currentPieces,
    required this.averageCost,
    required this.averageSalePrice,
    required this.revenue,
    required this.grossProfit,
    this.lastPurchasePrice,
    this.lastSalePrice,
  });
}

/// Kârlılık raporu (BRIEF §5: brüt kâr, fire, maliyet farkları, giderler, net kâr).
final class ProfitabilityReport {
  final Money revenue;
  final Money costOfGoods;
  final Money grossProfit;
  final Money returns;
  final Money waste;
  final Money costAdjustments;
  final Money expenses;

  const ProfitabilityReport({
    required this.revenue,
    required this.costOfGoods,
    required this.grossProfit,
    required this.returns,
    required this.waste,
    required this.costAdjustments,
    required this.expenses,
  });

  /// Net kâr = brüt kâr − fire − maliyet farkları − giderler.
  Money get netProfit => grossProfit - waste - costAdjustments - expenses;

  Decimal? get grossMarginPercent => revenue.isZero
      ? null
      : (grossProfit.tl / revenue.tl).toDecimal(scaleOnInfinitePrecision: 6) *
            Decimal.fromInt(100);
}

/// Analiz ve rapor sorguları (SPEC §19, §20, §25).
///
/// Tüm kâr ve ciro rakamları **KDV hariçtir** (BRIEF §3.4).
extension AnalyticsQueries on AppDatabase {
  Future<CustomerAnalysis> customerAnalysis(String customerId) async {
    final customer = await (select(
      customers,
    )..where((c) => c.id.equals(customerId))).getSingle();

    final totals = await customSelect(
      '''
      SELECT
        COALESCE(SUM(s.subtotal_net), 0) AS net,
        COALESCE(SUM(s.cost_total), 0) AS cost,
        MAX(s.doc_date) AS last_sale
      FROM sales s
      WHERE s.customer_id = ? AND s.status = 'ACTIVE'
      ''',
      variables: [Variable.withString(customerId)],
      readsFrom: {sales},
    ).getSingle();

    final volumeRow = await customSelect(
      '''
      SELECT COALESCE(SUM(si.volume), 0) AS vol
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.customer_id = ? AND s.status = 'ACTIVE'
      ''',
      variables: [Variable.withString(customerId)],
      readsFrom: {saleItems, sales},
    ).getSingle();

    final collectedRow = await customSelect(
      "SELECT COALESCE(SUM(amount), 0) AS t FROM collections "
      "WHERE customer_id = ? AND status = 'ACTIVE'",
      variables: [Variable.withString(customerId)],
      readsFrom: {collections},
    ).getSingle();

    final balanceRow = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM customer_ledger '
      'WHERE customer_id = ?',
      variables: [Variable.withString(customerId)],
      readsFrom: {customerLedger},
    ).getSingle();

    // En çok aldığı sünger
    final topRow = await customSelect(
      '''
      SELECT p.name AS name, SUM(si.volume) AS vol
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN product_variants v ON v.id = si.variant_id
      JOIN products p ON p.id = v.product_id
      WHERE s.customer_id = ? AND s.status = 'ACTIVE'
      GROUP BY p.id, p.name
      ORDER BY vol DESC
      LIMIT 1
      ''',
      variables: [Variable.withString(customerId)],
      readsFrom: {saleItems, sales, productVariants, products},
    ).getSingleOrNull();

    final lastSale = totals.read<int?>('last_sale');
    final net = Money.fromStored(totals.read<int>('net'));
    final cost = Money.fromStored(totals.read<int>('cost'));

    return CustomerAnalysis(
      customerId: customerId,
      title: customer.title,
      totalSales: net,
      totalVolume: Volume.fromStored(volumeRow.read<int>('vol')),
      totalCollected: Money.fromStored(collectedRow.read<int>('t')),
      currentDebt: Money.fromStored(balanceRow.read<int>('t')),
      grossProfit: net - cost,
      lastSaleAt: lastSale == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSale),
      topProductName: topRow?.read<String?>('name'),
      averagePaymentDays: await _averagePaymentDays(customerId),
    );
  }

  /// Ortalama ödeme süresi: kapanmış satışların vade ile tahsilat arasındaki
  /// gün farkının ortalaması (SPEC §19).
  Future<int?> _averagePaymentDays(String customerId) async {
    final rows = await customSelect(
      '''
      SELECT s.doc_date AS sale_date, c.doc_date AS pay_date, pa.amount AS amount
      FROM payment_allocations pa
      JOIN collections c ON c.id = pa.collection_id
      JOIN sales s ON s.id = pa.target_id
      WHERE pa.target_type = 'SALE' AND s.customer_id = ?
        AND c.status = 'ACTIVE' AND s.status = 'ACTIVE'
      ''',
      variables: [Variable.withString(customerId)],
      readsFrom: {paymentAllocations, collections, sales},
    ).get();

    if (rows.isEmpty) return null;

    // Tutarla ağırlıklandırılmış ortalama.
    var weightedDays = BigInt.zero;
    var totalAmount = BigInt.zero;
    for (final r in rows) {
      final days = Duration(
        milliseconds: r.read<int>('pay_date') - r.read<int>('sale_date'),
      ).inDays;
      final amount = BigInt.from(r.read<int>('amount'));
      weightedDays += BigInt.from(days) * amount;
      totalAmount += amount;
    }
    if (totalAmount == BigInt.zero) return null;
    return (weightedDays ~/ totalAmount).toInt();
  }

  Future<List<ProductAnalysis>> productAnalysis() async {
    final rows = await customSelect(
      '''
      SELECT p.id AS product_id, p.name AS name,
        COALESCE((SELECT SUM(pi.volume) FROM purchase_items pi
                  JOIN product_variants v2 ON v2.id = pi.variant_id
                  JOIN purchases pu ON pu.id = pi.purchase_id
                  WHERE v2.product_id = p.id AND pu.status = 'ACTIVE'), 0) AS purchased,
        COALESCE((SELECT SUM(si.volume) FROM sale_items si
                  JOIN product_variants v3 ON v3.id = si.variant_id
                  JOIN sales s ON s.id = si.sale_id
                  WHERE v3.product_id = p.id AND s.status = 'ACTIVE'), 0) AS sold,
        COALESCE((SELECT SUM(si.net_total) FROM sale_items si
                  JOIN product_variants v4 ON v4.id = si.variant_id
                  JOIN sales s ON s.id = si.sale_id
                  WHERE v4.product_id = p.id AND s.status = 'ACTIVE'), 0) AS revenue,
        COALESCE((SELECT SUM(si.cost_total) FROM sale_items si
                  JOIN product_variants v5 ON v5.id = si.variant_id
                  JOIN sales s ON s.id = si.sale_id
                  WHERE v5.product_id = p.id AND s.status = 'ACTIVE'), 0) AS cost,
        COALESCE((SELECT SUM(b.remaining_volume) FROM inventory_batches b
                  JOIN product_variants v6 ON v6.id = b.variant_id
                  WHERE v6.product_id = p.id), 0) AS current_vol,
        COALESCE((SELECT SUM(b.remaining_pieces) FROM inventory_batches b
                  JOIN product_variants v7 ON v7.id = b.variant_id
                  WHERE v7.product_id = p.id), 0) AS current_pcs
      FROM products p
      WHERE p.is_active = 1
      ORDER BY p.name
      ''',
      readsFrom: {
        products,
        purchaseItems,
        purchases,
        saleItems,
        sales,
        productVariants,
        inventoryBatches,
      },
    ).get();

    final result = <ProductAnalysis>[];
    for (final r in rows) {
      final sold = Volume.fromStored(r.read<int>('sold'));
      final revenue = Money.fromStored(r.read<int>('revenue'));
      final cost = Money.fromStored(r.read<int>('cost'));

      result.add(
        ProductAnalysis(
          productId: r.read<String>('product_id'),
          name: r.read<String>('name'),
          purchasedVolume: Volume.fromStored(r.read<int>('purchased')),
          soldVolume: sold,
          currentVolume: Volume.fromStored(r.read<int>('current_vol')),
          currentPieces: r.read<int>('current_pcs'),
          averageCost: _perM3(cost, sold),
          averageSalePrice: _perM3(revenue, sold),
          revenue: revenue,
          grossProfit: revenue - cost,
          lastPurchasePrice: await _lastPrice(
            r.read<String>('product_id'),
            purchase: true,
          ),
          lastSalePrice: await _lastPrice(
            r.read<String>('product_id'),
            purchase: false,
          ),
        ),
      );
    }
    return result;
  }

  Future<UnitPrice?> _lastPrice(
    String productId, {
    required bool purchase,
  }) async {
    final table = purchase ? 'purchase_items' : 'sale_items';
    final parent = purchase ? 'purchases' : 'sales';
    final fk = purchase ? 'purchase_id' : 'sale_id';

    final row = await customSelect(
      '''
      SELECT i.unit_price_m3 AS price
      FROM $table i
      JOIN product_variants v ON v.id = i.variant_id
      JOIN $parent d ON d.id = i.$fk
      WHERE v.product_id = ? AND d.status = 'ACTIVE'
      ORDER BY d.doc_date DESC, i.id DESC
      LIMIT 1
      ''',
      variables: [Variable.withString(productId)],
    ).getSingleOrNull();

    return row == null ? null : UnitPrice.fromStored(row.read<int>('price'));
  }

  /// Kârlılık raporu — dönem bazlı.
  Future<ProfitabilityReport> profitability({
    required DateTime from,
    required DateTime to,
  }) async {
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

    Future<Money> scalar(String sql, Set<ResultSetImplementation> reads) async {
      final row = await customSelect(
        sql,
        variables: [Variable.withInt(f), Variable.withInt(t)],
        readsFrom: reads,
      ).getSingle();
      return Money.fromStored(row.read<int>('t'));
    }

    final revenue = await scalar(
      "SELECT COALESCE(SUM(subtotal_net), 0) AS t FROM sales "
      "WHERE status = 'ACTIVE' AND doc_date BETWEEN ? AND ?",
      {sales},
    );
    final cost = await scalar(
      "SELECT COALESCE(SUM(cost_total), 0) AS t FROM sales "
      "WHERE status = 'ACTIVE' AND doc_date BETWEEN ? AND ?",
      {sales},
    );
    final returns = await scalar(
      "SELECT COALESCE(SUM(subtotal_net), 0) AS t FROM sale_returns "
      "WHERE status = 'ACTIVE' AND doc_date BETWEEN ? AND ?",
      {saleReturns},
    );
    final waste = await scalar(
      "SELECT COALESCE(SUM(cost_total), 0) AS t FROM stock_adjustments "
      "WHERE status = 'ACTIVE' AND occurred_at BETWEEN ? AND ?",
      {stockAdjustments},
    );
    final adjustments = await scalar(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM cost_adjustments '
      'WHERE occurred_at BETWEEN ? AND ?',
      {costAdjustments},
    );
    final expenses = await scalar(
      "SELECT COALESCE(SUM(amount_net), 0) AS t FROM expenses "
      "WHERE status = 'ACTIVE' AND doc_date BETWEEN ? AND ?",
      {this.expenses},
    );

    return ProfitabilityReport(
      revenue: revenue,
      costOfGoods: cost,
      grossProfit: revenue - cost,
      returns: returns,
      waste: waste,
      costAdjustments: adjustments,
      expenses: expenses,
    );
  }

  /// Dönem bazlı satış raporu (SPEC §25: günlük/haftalık/aylık/yıllık).
  Future<List<({DateTime period, Money net, Money profit, int count})>>
  salesByPeriod({
    required DateTime from,
    required DateTime to,
    String granularity = 'month',
  }) async {
    final format = switch (granularity) {
      'day' => '%Y-%m-%d',
      'week' => '%Y-W%W',
      'year' => '%Y',
      _ => '%Y-%m',
    };

    final rows = await customSelect(
      '''
      SELECT strftime('$format', doc_date / 1000, 'unixepoch') AS period,
             COALESCE(SUM(subtotal_net), 0) AS net,
             COALESCE(SUM(subtotal_net), 0) - COALESCE(SUM(cost_total), 0) AS profit,
             COUNT(*) AS cnt,
             MIN(doc_date) AS first_date
      FROM sales
      WHERE status = 'ACTIVE' AND doc_date BETWEEN ? AND ?
      GROUP BY period
      ORDER BY period
      ''',
      variables: [
        Variable.withInt(from.millisecondsSinceEpoch),
        Variable.withInt(to.millisecondsSinceEpoch),
      ],
      readsFrom: {sales},
    ).get();

    return [
      for (final r in rows)
        (
          period: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('first_date'),
          ),
          net: Money.fromStored(r.read<int>('net')),
          profit: Money.fromStored(r.read<int>('profit')),
          count: r.read<int>('cnt'),
        ),
    ];
  }

  /// Evrak vade raporu (BRIEF §5).
  Future<List<Instrument>> instrumentsDueReport({
    required DateTime from,
    required DateTime to,
  }) =>
      (select(instruments)
            ..where(
              (i) =>
                  i.dueDate.isBetweenValues(
                    from.millisecondsSinceEpoch,
                    to.millisecondsSinceEpoch,
                  ) &
                  i.currentStatus.isIn([
                    InstrumentStatus.portfolio,
                    InstrumentStatus.atBank,
                    InstrumentStatus.issued,
                  ]),
            )
            ..orderBy([(i) => OrderingTerm.asc(i.dueDate)]))
          .get();

  static UnitPrice _perM3(Money amount, Volume volume) {
    if (volume.isZero) return UnitPrice.zero;
    return UnitPrice.fromDecimal(
      roundHalfUp(
        (amount.tl / volume.m3).toDecimal(scaleOnInfinitePrecision: 12),
        Scales.unitPrice,
      ),
    );
  }
}
