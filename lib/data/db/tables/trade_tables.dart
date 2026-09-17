import 'package:drift/drift.dart';

import '../converters.dart';
import '../enums.dart';
import 'master_tables.dart';
import 'stock_tables.dart';

/// Alış ve satış tarafı tabloları (ERD §5 ve §6).

@TableIndex(name: 'idx_purchases_supplier', columns: {#supplierId})
@TableIndex(name: 'idx_purchases_date', columns: {#docDate})
class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  IntColumn get docDate => integer()();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get priceMode => text().map(const PriceModeConverter())();
  TextColumn get invoiceNo => text().nullable()();
  TextColumn get waybillNo => text().nullable()();
  IntColumn get subtotalNet => integer().map(const MoneyConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grandTotal => integer().map(const MoneyConverter())();
  IntColumn get expenseTotal =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN (${DocStatus.all.map((e) => "'$e'").join(',')}))",
  ];
}

@TableIndex(name: 'idx_pitems_purchase', columns: {#purchaseId})
class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  IntColumn get lineNo => integer()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get unitPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get discountRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  IntColumn get netTotal => integer().map(const MoneyConverter())();
  IntColumn get vatRate => integer().map(const RateConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();

  /// Bu satırın ürettiği parti.
  TextColumn get batchId =>
      text().nullable().references(InventoryBatches, #id)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (pieces > 0 AND volume > 0)',
    'CHECK (vat_rate >= 0 AND vat_rate <= 10000)',
    'CHECK (discount_rate >= 0 AND discount_rate <= 10000)',
  ];
}

/// Nakliye, hamaliye ve diğer masraflar (BRIEF §3.7).
@TableIndex(name: 'idx_pexp_purchase', columns: {#purchaseId})
class PurchaseExpenses extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();

  /// Nakliyeci farklıysa; null ise alışın tedarikçisi.
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get kind => text()();

  /// KDV hariç — parti maliyeti her zaman KDV hariçtir (BRIEF §3.4).
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get vatRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  TextColumn get allocationKey =>
      text().withDefault(const Constant(AllocationKey.volume))();
  IntColumn get occurredAt => integer()();

  /// Fatura maldan sonra geldiyse true → stok/satılmış ayrımı yapılır.
  BoolColumn get addedLater => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('NAKLIYE','HAMALIYE','DIGER'))",
    "CHECK (allocation_key IN (${AllocationKey.all.map((e) => "'$e'").join(',')}))",
    'CHECK (amount >= 0)',
  ];
}

/// Masrafın partilere nasıl bölündüğünün denetim izi.
@TableIndex(name: 'idx_pea_expense', columns: {#purchaseExpenseId})
class PurchaseExpenseAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseExpenseId =>
      text().references(PurchaseExpenses, #id)();
  TextColumn get batchId => text().references(InventoryBatches, #id)();
  IntColumn get volumeShare => integer().map(const VolumeConverter())();

  /// Partinin birim maliyetine eklenen pay (stokta kalan kısım).
  IntColumn get amountToStock => integer().map(const MoneyConverter())();

  /// cost_adjustments'a giden pay (satılmış/firelenmiş kısım).
  IntColumn get amountToAdjustment => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_preturns_purchase', columns: {#purchaseId})
class PurchaseReturns extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  IntColumn get docDate => integer()();
  TextColumn get priceMode => text().map(const PriceModeConverter())();
  IntColumn get subtotalNet => integer().map(const MoneyConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grandTotal => integer().map(const MoneyConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseReturnId => text().references(PurchaseReturns, #id)();
  TextColumn get purchaseItemId => text().references(PurchaseItems, #id)();
  TextColumn get batchId => text().references(InventoryBatches, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get unitPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get netTotal => integer().map(const MoneyConverter())();
  IntColumn get vatRate => integer().map(const RateConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}

// ---------------------------------------------------------------- satış

/// Teklif. SPEC §26 adlandırması. Stok DÜŞMEZ (SPEC §15).
@TableIndex(name: 'idx_quotes_customer', columns: {#customerId})
class SalesQuotes extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get docDate => integer()();
  IntColumn get validUntil => integer().nullable()();
  TextColumn get priceMode => text().map(const PriceModeConverter())();
  IntColumn get subtotalNet => integer().map(const MoneyConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grandTotal => integer().map(const MoneyConverter())();
  TextColumn get status =>
      text().withDefault(const Constant(QuoteStatus.draft))();
  TextColumn get convertedSaleId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN (${QuoteStatus.all.map((e) => "'$e'").join(',')}))",
  ];
}

class SalesQuoteItems extends Table {
  TextColumn get id => text()();
  TextColumn get salesQuoteId => text().references(SalesQuotes, #id)();
  IntColumn get lineNo => integer()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get listPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get discountRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  IntColumn get unitPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get netTotal => integer().map(const MoneyConverter())();
  IntColumn get vatRate => integer().map(const RateConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}

@TableIndex(name: 'idx_sales_customer', columns: {#customerId})
@TableIndex(name: 'idx_sales_date', columns: {#docDate})
@TableIndex(name: 'idx_sales_due', columns: {#dueDate})
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get salesQuoteId =>
      text().nullable().references(SalesQuotes, #id)();
  IntColumn get docDate => integer()();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get priceMode => text().map(const PriceModeConverter())();
  TextColumn get invoiceNo => text().nullable()();
  TextColumn get waybillNo => text().nullable()();
  IntColumn get subtotalNet => integer().map(const MoneyConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grandTotal => integer().map(const MoneyConverter())();

  /// Satış anında SABİTLENİR, bir daha değişmez (BRIEF §3.6, SPEC §30.3).
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN (${DocStatus.all.map((e) => "'$e'").join(',')}))",
  ];
}

@TableIndex(name: 'idx_sitems_sale', columns: {#saleId})
@TableIndex(name: 'idx_sitems_variant', columns: {#variantId})
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  IntColumn get lineNo => integer()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  TextColumn get priceListId => text().nullable().references(PriceLists, #id)();
  IntColumn get listPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get discountRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  IntColumn get unitPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get netTotal => integer().map(const MoneyConverter())();
  IntColumn get vatRate => integer().map(const RateConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();

  /// SABİT maliyet.
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (pieces > 0 AND volume > 0)',
    'CHECK (vat_rate >= 0 AND vat_rate <= 10000)',
    'CHECK (discount_rate >= 0 AND discount_rate <= 10000)',
  ];
}

@TableIndex(name: 'idx_sreturns_sale', columns: {#saleId})
class SaleReturns extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get docDate => integer()();
  TextColumn get priceMode => text().map(const PriceModeConverter())();
  IntColumn get subtotalNet => integer().map(const MoneyConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grandTotal => integer().map(const MoneyConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleReturnId => text().references(SaleReturns, #id)();
  TextColumn get saleItemId => text().references(SaleItems, #id)();
  IntColumn get pieces => integer()();
  IntColumn get volume => integer().map(const VolumeConverter())();
  IntColumn get unitPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get netTotal => integer().map(const MoneyConverter())();
  IntColumn get vatRate => integer().map(const RateConverter())();
  IntColumn get vatTotal => integer().map(const MoneyConverter())();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();
  IntColumn get costTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (pieces > 0)'];
}
