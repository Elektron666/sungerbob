import 'package:drift/drift.dart';

import '../../domain/costing/costing_engine.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../db/app_database.dart';
import '../db/enums.dart';

/// Stok ve bakiye sorguları.
///
/// Bakiyeler **hareketlerden türetilir** (D-10); önbellek kolonu yoktur.
/// SQL'de yalnızca toplama/çıkarma yapılır (ARCHITECTURE §3).
extension StockQueries on AppDatabase {
  Future<String> locationId(String code) async {
    final row = await (select(locations)..where((l) => l.code.equals(code)))
        .getSingle();
    return row.id;
  }

  /// Bir varyantın ana depodaki partileri, FIFO sırasında.
  Future<List<BatchView>> batchesForVariant(String variantId,
      {String locationCode = LocationCode.mainWarehouse}) async {
    final locId = await locationId(locationCode);
    final query = select(inventoryBatches).join([
      innerJoin(productVariants,
          productVariants.id.equalsExp(inventoryBatches.variantId)),
    ])
      ..where(inventoryBatches.variantId.equals(variantId) &
          inventoryBatches.locationId.equals(locId) &
          inventoryBatches.remainingPieces.isBiggerThanValue(0))
      ..orderBy([
        OrderingTerm.asc(inventoryBatches.receivedAt),
        OrderingTerm.asc(inventoryBatches.id),
      ]);

    final rows = await query.get();
    return [
      for (var i = 0; i < rows.length; i++)
        _toBatchView(rows[i].readTable(inventoryBatches),
            rows[i].readTable(productVariants), i)
    ];
  }

  /// Bir **ürünün** ana depodaki tüm partileri — ağırlıklı ortalama için (D-11).
  Future<List<BatchView>> batchesForProduct(String productId,
      {String locationCode = LocationCode.mainWarehouse}) async {
    final locId = await locationId(locationCode);
    final query = select(inventoryBatches).join([
      innerJoin(productVariants,
          productVariants.id.equalsExp(inventoryBatches.variantId)),
    ])
      ..where(productVariants.productId.equals(productId) &
          inventoryBatches.locationId.equals(locId) &
          inventoryBatches.remainingPieces.isBiggerThanValue(0))
      ..orderBy([
        OrderingTerm.asc(inventoryBatches.receivedAt),
        OrderingTerm.asc(inventoryBatches.id),
      ]);

    final rows = await query.get();
    return [
      for (var i = 0; i < rows.length; i++)
        _toBatchView(rows[i].readTable(inventoryBatches),
            rows[i].readTable(productVariants), i)
    ];
  }

  BatchView _toBatchView(
          InventoryBatch b, ProductVariant v, int seq) =>
      BatchView(
        id: b.id,
        variantId: b.variantId,
        productId: v.productId,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(b.receivedAt),
        sequence: seq,
        remainingPieces: b.remainingPieces,
        remainingVolume: b.remainingVolume,
        realUnitCost: b.realUnitCostM3,
      );

  /// Müşteri bakiyesi = SUM(customer_ledger.amount). Tamsayı toplaması, kesin.
  Future<Money> customerBalance(String customerId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM customer_ledger WHERE customer_id = ?',
      variables: [Variable.withString(customerId)],
      readsFrom: {customerLedger},
    ).getSingle();
    return Money.fromStored(row.read<int>('total'));
  }

  Future<Money> supplierBalance(String supplierId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM supplier_ledger WHERE supplier_id = ?',
      variables: [Variable.withString(supplierId)],
      readsFrom: {supplierLedger},
    ).getSingle();
    return Money.fromStored(row.read<int>('total'));
  }

  /// Kasa/banka bakiyesi = SUM(IN) − SUM(OUT).
  Future<Money> accountBalance(String accountId) async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(CASE WHEN direction = 'IN' THEN amount ELSE -amount END), 0) "
      'AS total FROM account_movements WHERE cash_account_id = ?',
      variables: [Variable.withString(accountId)],
      readsFrom: {accountMovements},
    ).getSingle();
    return Money.fromStored(row.read<int>('total'));
  }

  /// Portföydeki evrak toplamı (alınan, henüz tahsil/ciro edilmemiş).
  Future<Money> instrumentPortfolioTotal() async {
    final statuses =
        InstrumentStatus.inPortfolio.map((s) => "'$s'").join(',');
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM instruments '
      "WHERE direction = 'IN' AND current_status IN ($statuses)",
      readsFrom: {instruments},
    ).getSingle();
    return Money.fromStored(row.read<int>('total'));
  }

  /// Varyantın bir konumdaki stoğu (adet ve m³), partilerden.
  Future<({int pieces, Volume volume})> variantStock(String variantId,
      {String locationCode = LocationCode.mainWarehouse}) async {
    final locId = await locationId(locationCode);
    final row = await customSelect(
      'SELECT COALESCE(SUM(remaining_pieces), 0) AS pcs, '
      'COALESCE(SUM(remaining_volume), 0) AS vol '
      'FROM inventory_batches WHERE variant_id = ? AND location_id = ?',
      variables: [Variable.withString(variantId), Variable.withString(locId)],
      readsFrom: {inventoryBatches},
    ).getSingle();
    return (
      pieces: row.read<int>('pcs'),
      volume: Volume.fromStored(row.read<int>('vol')),
    );
  }

  /// Stok maliyeti (bir konumdaki tüm partiler).
  Future<Money> stockCostTotal(
      {String locationCode = LocationCode.mainWarehouse}) async {
    final locId = await locationId(locationCode);
    final rows = await (select(inventoryBatches)
          ..where((b) =>
              b.locationId.equals(locId) & b.remainingPieces.isBiggerThanValue(0)))
        .get();
    return sumMoney(
        rows.map((b) => b.realUnitCostM3.times(b.remainingVolume)));
  }
}
