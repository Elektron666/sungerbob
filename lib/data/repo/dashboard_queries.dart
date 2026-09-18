import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'stock_queries.dart';

/// Ana sayfa kartları (SPEC §18 + BRIEF §7).
final class DashboardSnapshot {
  final Volume totalStockVolume;
  final Money stockCost;
  final Money stockSaleValue;
  final Money monthSales;
  final Money monthGrossProfit;
  final Money receivables;
  final Money supplierDebt;
  final Money overdue;

  // BRIEF §7'nin eklediği kartlar
  final Money cashAndBank;
  final Money instrumentPortfolio;
  final Money issuedInstruments;
  final Money cuttingStockValue;

  const DashboardSnapshot({
    required this.totalStockVolume,
    required this.stockCost,
    required this.stockSaleValue,
    required this.monthSales,
    required this.monthGrossProfit,
    required this.receivables,
    required this.supplierDebt,
    required this.overdue,
    required this.cashAndBank,
    required this.instrumentPortfolio,
    required this.issuedInstruments,
    required this.cuttingStockValue,
  });

  /// Sermaye Dağılımı (BRIEF §7):
  /// Stok + Kesimde + Alacak + Portföy + Kasa/Banka − Tedarikçi Borcu − Verilen Evrak
  Money get capital =>
      stockCost +
      cuttingStockValue +
      receivables +
      instrumentPortfolio +
      cashAndBank -
      supplierDebt -
      issuedInstruments;
}

extension DashboardQueries on AppDatabase {
  Future<DashboardSnapshot> dashboardSnapshot({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final monthStart = DateTime(reference.year, reference.month);

    return DashboardSnapshot(
      totalStockVolume: await _totalStockVolume(LocationCode.mainWarehouse),
      stockCost: await stockCostTotal(),
      stockSaleValue: await _stockSaleValue(),
      monthSales: await _monthSales(monthStart),
      monthGrossProfit: await _monthGrossProfit(monthStart),
      receivables: await _receivables(),
      supplierDebt: await _supplierDebt(),
      overdue: await _overdue(reference),
      cashAndBank: await _cashAndBank(),
      instrumentPortfolio: await instrumentPortfolioTotal(),
      issuedInstruments: await _issuedInstruments(),
      cuttingStockValue: await stockCostTotal(
        locationCode: LocationCode.cutting,
      ),
    );
  }

  Future<Volume> _totalStockVolume(String locationCode) async {
    final locId = await locationId(locationCode);
    // **Yalnızca m³ ürünler.** İnce malzemenin miktarı da aynı kolonda
    // durur (kendi biriminde); 50 kg tutkalı 11 m³ süngere eklemek toplamı
    // anlamsız kılardı (D-22).
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(b.remaining_volume), 0) AS v
      FROM inventory_batches b
      JOIN product_variants v ON v.id = b.variant_id
      JOIN products p ON p.id = v.product_id
      WHERE b.location_id = ? AND p.unit = ?
      ''',
      variables: [
        Variable.withString(locId),
        Variable.withString(ProductUnit.m3),
      ],
      readsFrom: {inventoryBatches, productVariants, products},
    ).getSingle();
    return Volume.fromStored(row.read<int>('v'));
  }

  /// Güncel fiyat listesiyle stoğun satış değeri (SPEC §18).
  Future<Money> _stockSaleValue() async {
    final locId = await locationId(LocationCode.mainWarehouse);
    final rows = await customSelect(
      '''
      SELECT b.remaining_volume AS vol, pli.effective_price_m3 AS price
      FROM inventory_batches b
      JOIN product_variants v ON v.id = b.variant_id
      LEFT JOIN price_lists pl ON pl.status = 'ACTIVE'
      LEFT JOIN price_list_items pli
        ON pli.price_list_id = pl.id AND pli.product_id = v.product_id
      WHERE b.location_id = ? AND b.remaining_pieces > 0
      ''',
      variables: [Variable.withString(locId)],
      readsFrom: {
        inventoryBatches,
        productVariants,
        priceLists,
        priceListItems,
      },
    ).get();

    var total = Money.zero;
    for (final r in rows) {
      final price = r.read<int?>('price');
      if (price == null) continue;
      total += UnitPrice.fromStored(price)
          .times(Volume.fromStored(r.read<int>('vol')));
    }
    return total;
  }

  Future<Money> _monthSales(DateTime monthStart) async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(subtotal_net), 0) AS t FROM sales "
      "WHERE status = 'ACTIVE' AND doc_date >= ?",
      variables: [Variable.withInt(monthStart.millisecondsSinceEpoch)],
      readsFrom: {sales},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  /// Brüt kâr = KDV hariç satış − sabitlenmiş maliyet (BRIEF §3.4).
  Future<Money> _monthGrossProfit(DateTime monthStart) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(subtotal_net), 0) - COALESCE(SUM(cost_total), 0) AS t '
      "FROM sales WHERE status = 'ACTIVE' AND doc_date >= ?",
      variables: [Variable.withInt(monthStart.millisecondsSinceEpoch)],
      readsFrom: {sales},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  Future<Money> _receivables() async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM customer_ledger',
      readsFrom: {customerLedger},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  Future<Money> _supplierDebt() async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_ledger',
      readsFrom: {supplierLedger},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  /// Vadesi geçmiş açık satışlar (SPEC §11).
  Future<Money> _overdue(DateTime reference) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(s.grand_total - COALESCE(paid.amount, 0)), 0) AS t
      FROM sales s
      LEFT JOIN (
        SELECT target_id, SUM(amount) AS amount
        FROM payment_allocations WHERE target_type = 'SALE'
        GROUP BY target_id
      ) paid ON paid.target_id = s.id
      WHERE s.status = 'ACTIVE' AND s.due_date IS NOT NULL AND s.due_date < ?
        AND s.grand_total > COALESCE(paid.amount, 0)
      ''',
      variables: [Variable.withInt(reference.millisecondsSinceEpoch)],
      readsFrom: {sales, paymentAllocations},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  Future<Money> _cashAndBank() async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(CASE WHEN direction = 'IN' THEN amount ELSE -amount END), 0) "
      'AS t FROM account_movements',
      readsFrom: {accountMovements},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  Future<Money> _issuedInstruments() async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(amount), 0) AS t FROM instruments "
      "WHERE direction = 'OUT' AND current_status = '${InstrumentStatus.issued}'",
      readsFrom: {instruments},
    ).getSingle();
    return Money.fromStored(row.read<int>('t'));
  }

  /// Vadesi geçen alacaklar listesi (SPEC §11 kartı).
  Future<List<({String customerId, String title, Money amount, int daysLate})>>
  overdueCustomers({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final rows = await customSelect(
      '''
      SELECT c.id AS customer_id, c.title AS title,
             SUM(s.grand_total - COALESCE(paid.amount, 0)) AS amount,
             MIN(s.due_date) AS earliest_due
      FROM sales s
      JOIN customers c ON c.id = s.customer_id
      LEFT JOIN (
        SELECT target_id, SUM(amount) AS amount
        FROM payment_allocations WHERE target_type = 'SALE'
        GROUP BY target_id
      ) paid ON paid.target_id = s.id
      WHERE s.status = 'ACTIVE' AND s.due_date IS NOT NULL AND s.due_date < ?
        AND s.grand_total > COALESCE(paid.amount, 0)
      GROUP BY c.id, c.title
      ORDER BY amount DESC
      ''',
      variables: [Variable.withInt(reference.millisecondsSinceEpoch)],
      readsFrom: {sales, customers, paymentAllocations},
    ).get();

    return [
      for (final r in rows)
        (
          customerId: r.read<String>('customer_id'),
          title: r.read<String>('title'),
          amount: Money.fromStored(r.read<int>('amount')),
          daysLate: reference
              .difference(
                DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('earliest_due'),
                ),
              )
              .inDays,
        ),
    ];
  }

  /// Bu hafta vadesi gelen evrak (BRIEF §5).
  Future<List<Instrument>> instrumentsDueThisWeek({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final weekEnd = reference.add(const Duration(days: 7));
    return (select(instruments)
          ..where(
            (i) =>
                i.dueDate.isBetweenValues(
                  reference.millisecondsSinceEpoch,
                  weekEnd.millisecondsSinceEpoch,
                ) &
                i.currentStatus.isIn([
                  InstrumentStatus.portfolio,
                  InstrumentStatus.atBank,
                  InstrumentStatus.issued,
                ]),
          )
          ..orderBy([(i) => OrderingTerm.asc(i.dueDate)]))
        .get();
  }

  /// Kritik stok: kalan adet, varyant veya ürün eşiğinin altında (SPEC §18).
  Future<
    List<({String variantId, String productName, int pieces, int threshold})>
  >
  criticalStock() async {
    final locId = await locationId(LocationCode.mainWarehouse);
    final rows = await customSelect(
      '''
      SELECT v.id AS variant_id, p.name AS product_name,
             COALESCE(SUM(b.remaining_pieces), 0) AS pieces,
             MAX(COALESCE(NULLIF(v.critical_stock_pieces, 0), p.critical_stock_pieces)) AS threshold
      FROM product_variants v
      JOIN products p ON p.id = v.product_id
      LEFT JOIN inventory_batches b
        ON b.variant_id = v.id AND b.location_id = ?
      WHERE v.is_active = 1
      GROUP BY v.id, p.name
      HAVING threshold > 0 AND pieces <= threshold
      ORDER BY pieces ASC
      ''',
      variables: [Variable.withString(locId)],
      readsFrom: {productVariants, products, inventoryBatches},
    ).get();

    return [
      for (final r in rows)
        (
          variantId: r.read<String>('variant_id'),
          productName: r.read<String>('product_name'),
          pieces: r.read<int>('pieces'),
          threshold: r.read<int>('threshold'),
        ),
    ];
  }
}
