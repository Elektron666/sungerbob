import 'package:drift/drift.dart';

import '../converters.dart';
import '../enums.dart';
import 'master_tables.dart';
import 'stock_tables.dart';
import 'trade_tables.dart';

/// Sayım, fire, kesim ve açılış tabloları (ERD §10, §11).

/// Stok sayımı. DRAFT iken stok etkilenmez (SPEC §16).
class StockCounts extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get locationId => text().references(Locations, #id)();
  IntColumn get countDate => integer()();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
  IntColumn get appliedAt => integer().nullable()();
  IntColumn get costEffectTotal =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (status IN ('DRAFT','APPLIED','CANCELLED'))",
      ];
}

class StockCountItems extends Table {
  TextColumn get id => text()();
  TextColumn get stockCountId => text().references(StockCounts, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get systemPieces => integer()();
  IntColumn get countedPieces => integer()();

  /// İşaretli fark.
  IntColumn get diffPieces => integer()();
  IntColumn get diffVolume => integer().map(const VolumeConverter())();
  IntColumn get costEffect =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (system_pieces >= 0 AND counted_pieces >= 0)',
      ];
}

/// Fire / hasar / stok düzeltme (SPEC §17 + §26 `stock_adjustments`).
/// Neden ZORUNLU.
class StockAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  IntColumn get occurredAt => integer()();
  TextColumn get reasonCode => text()();
  IntColumn get costTotal =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (reason_code IN (${WasteReason.all.map((e) => "'$e'").join(',')}))",
      ];
}

class StockAdjustmentItems extends Table {
  TextColumn get id => text()();
  TextColumn get stockAdjustmentId => text().references(StockAdjustments, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}

/// Fason kesim emri (BRIEF §5).
@TableIndex(name: 'idx_co_status', columns: {#status})
class CuttingOrders extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();

  /// type = KESIMHANE olan tedarikçi.
  TextColumn get cutterSupplierId => text().references(Suppliers, #id)();
  TextColumn get salesQuoteId => text().nullable().references(SalesQuotes, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  IntColumn get sentDate => integer()();
  IntColumn get expectedReturnDate => integer().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant(CuttingStatus.preparing))();

  /// KDV hariç — maliyete böyle girer; cariye brüt yazılır.
  IntColumn get cuttingFeeNet =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get cuttingFeeVatRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  IntColumn get freightNet =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  IntColumn get sourceVolumeTotal =>
      integer().map(const VolumeConverter()).withDefault(const Constant(0))();
  IntColumn get resultVolumeTotal =>
      integer().map(const VolumeConverter()).withDefault(const Constant(0))();

  /// Kesim firesi = kaynak − hedef. Ayrı maliyet yazılmaz (BRIEF §5.3).
  IntColumn get wasteVolume =>
      integer().map(const VolumeConverter()).withDefault(const Constant(0))();

  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (status IN (${CuttingStatus.all.map((e) => "'$e'").join(',')}))",
        // Hedef toplam m³ kaynağı aşamaz (BRIEF §5.3).
        'CHECK (result_volume_total <= source_volume_total)',
      ];
}

class CuttingOrderSources extends Table {
  TextColumn get id => text()();
  TextColumn get cuttingOrderId => text().references(CuttingOrders, #id)();

  /// Ana depodaki kaynak parti.
  TextColumn get sourceBatchId => text().references(InventoryBatches, #id)();

  /// KESIMDE konumunda açılan çocuk parti (D-07).
  TextColumn get kesimdeBatchId =>
      text().nullable().references(InventoryBatches, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}

class CuttingOrderPlanItems extends Table {
  TextColumn get id => text()();
  TextColumn get cuttingOrderId => text().references(CuttingOrders, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get plannedPieces => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (planned_pieces > 0)'];
}

class CuttingOrderResults extends Table {
  TextColumn get id => text()();
  TextColumn get cuttingOrderId => text().references(CuttingOrders, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();

  /// Ana depoya giren yeni parti; kaynağın tarihini taşır (D-08).
  TextColumn get resultBatchId =>
      text().nullable().references(InventoryBatches, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get allocatedCost => integer().map(const MoneyConverter())();
  IntColumn get returnedAt => integer()();

  /// Artık parça (ör. 60×200).
  BoolColumn get isRemnant => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}

/// Açılış işlemleri (BRIEF §1.11, §5).
@TableIndex(name: 'idx_ob_kind', columns: {#kind})
class OpeningBalances extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();

  /// variant | customer | supplier | cash_account | instrument
  TextColumn get refId => text().nullable()();
  IntColumn get asOfDate => integer()();
  IntColumn get amount =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get pieces => integer().nullable()();
  IntColumn get unitCostM3 =>
      integer().map(const UnitPriceConverter()).nullable()();
  IntColumn get dueDate => integer().nullable()();

  /// Oluşturulan parti / ledger satırı.
  TextColumn get createdRecordId => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (kind IN ('STOCK','CUSTOMER','SUPPLIER','CASH','INSTRUMENT'))",
      ];
}
