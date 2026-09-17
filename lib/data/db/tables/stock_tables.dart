import 'package:drift/drift.dart';

import '../converters.dart';
import '../enums.dart';
import 'master_tables.dart';

/// Stok ve maliyet tabloları (ERD §4).

/// Parti. Her alış satırı, açılış stoğu ve kesim dönüşü bir parti üretir.
@DataClassName('InventoryBatch')
@TableIndex(
  name: 'idx_batch_fifo',
  columns: {#variantId, #locationId, #receivedAt, #id},
)
@TableIndex(name: 'idx_batch_source', columns: {#sourceType, #sourceId})
class InventoryBatches extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get locationId => text().references(Locations, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text().nullable()();

  /// Kesim/transfer zinciri (D-07).
  TextColumn get parentBatchId => text().nullable()();

  /// FIFO sırası. Kesim hedefi kaynağın tarihini taşır (D-08).
  IntColumn get receivedAt => integer()();

  /// Çıplak fabrika fiyatı ve gerçek (masraflı) maliyet AYRI saklanır (SPEC §4).
  IntColumn get bareUnitCostM3 => integer().map(const UnitPriceConverter())();
  IntColumn get realUnitCostM3 => integer().map(const UnitPriceConverter())();

  IntColumn get inPieces => integer()();
  IntColumn get inVolume => integer().map(const VolumeConverter())();

  /// ÖNBELLEK — doğrusu hareketlerden türetilir (D-10). checkIntegrity doğrular.
  IntColumn get remainingPieces => integer()();
  IntColumn get remainingVolume => integer().map(const VolumeConverter())();

  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (source_type IN (${BatchSourceType.all.map((e) => "'$e'").join(',')}))",
        'CHECK (in_pieces > 0 AND in_volume > 0)',
        // Negatif stok yasağının veritabanı tarafındaki güvencesi (BRIEF §3.8).
        'CHECK (remaining_pieces >= 0 AND remaining_volume >= 0)',
        'CHECK (remaining_pieces <= in_pieces AND remaining_volume <= in_volume)',
        'CHECK (bare_unit_cost_m3 >= 0 AND real_unit_cost_m3 >= 0)',
      ];
}

/// 🔒 append-only. Tüm stok hareketleri (BRIEF §6).
@TableIndex(name: 'idx_sm_variant_loc', columns: {#variantId, #locationId})
@TableIndex(name: 'idx_sm_batch', columns: {#batchId})
@TableIndex(name: 'idx_sm_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_sm_source', columns: {#sourceType, #sourceId})
@TableIndex(name: 'idx_sm_reversal', columns: {#reversalOfId}, unique: true)
class StockMovements extends Table {
  TextColumn get id => text()();
  IntColumn get occurredAt => integer()();
  TextColumn get type => text()();
  TextColumn get locationId => text().references(Locations, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get batchId => text().nullable().references(InventoryBatches, #id)();

  /// İşaretli: girişte pozitif, çıkışta negatif.
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();

  IntColumn get unitCostM3 => integer().map(const UnitPriceConverter())();
  IntColumn get totalCost => integer().map(const MoneyConverter())();

  TextColumn get sourceType => text()();
  TextColumn get sourceId => text().nullable()();

  /// Düzeltme yalnızca ters hareketle (BRIEF §3.5).
  TextColumn get reversalOfId => text().nullable()();

  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (type IN (${MovementType.all.map((e) => "'$e'").join(',')}))",
        'CHECK (pieces <> 0)',
        // Yön ile tip tutarlılığı.
        "CHECK ((type IN (${MovementType.inbound.map((e) => "'$e'").join(',')}) AND pieces > 0)"
            " OR (type IN (${MovementType.outbound.map((e) => "'$e'").join(',')}) AND pieces < 0)"
            " OR type = '${MovementType.reversal}')",
      ];
}

/// 🔒 append-only. Her çıkışın parti bazlı maliyeti (BRIEF §3.6).
@DataClassName('CostAllocationRow')
@TableIndex(name: 'idx_ca_movement', columns: {#movementId})
@TableIndex(name: 'idx_ca_batch', columns: {#batchId})
class CostAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get movementId => text().references(StockMovements, #id)();
  TextColumn get batchId => text().references(InventoryBatches, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get unitCostM3 => integer().map(const UnitPriceConverter())();
  IntColumn get totalCost => integer().map(const MoneyConverter())();

  /// Tüketim sırası. İade bunun TERSİNDEN okunur (D-12).
  IntColumn get sequenceNo => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (pieces > 0)',
        'CHECK (sequence_no >= 0)',
      ];
}

/// 🔒 append-only. Sonradan gelen masrafın satılmış/firelenmiş kısma düşen payı
/// (BRIEF §3.7). Geçmiş satış satırları değişmez.
@TableIndex(name: 'idx_cadj_batch', columns: {#batchId})
class CostAdjustments extends Table {
  TextColumn get id => text()();
  IntColumn get occurredAt => integer()();
  TextColumn get batchId => text().references(InventoryBatches, #id)();
  TextColumn get purchaseExpenseId => text().nullable()();
  TextColumn get reason => text()();
  IntColumn get volumeAffected => integer().map(const VolumeConverter())();
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get periodDate => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (reason IN ('LATE_EXPENSE','CUTTING_FEE_LATE','OTHER'))",
      ];
}
