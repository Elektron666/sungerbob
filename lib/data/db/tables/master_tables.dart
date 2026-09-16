import 'package:drift/drift.dart';

import '../converters.dart';
import '../enums.dart';

/// Ana veri tabloları (ERD §3).

class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  BoolColumn get isVirtual => boolean().withDefault(const Constant(false))();

  /// `KESIMDE` için false — kesimdeki mal satılamaz (D-07).
  BoolColumn get isSellable => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (code IN (${LocationCode.all.map((e) => "'$e'").join(',')}))",
      ];
}

/// Sünger çeşidi. Fiyat katsayısı burada (SPEC §1 + §13, BRIEF §3.1).
@TableIndex(name: 'idx_products_norm', columns: {#nameNormalized})
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get nameNormalized => text()();

  /// SPEC §13 katsayısı, ×10.000 (1,00 → 10000).
  IntColumn get priceCoefficient => integer().map(const RateConverter())();

  TextColumn get dns => text().nullable()();
  TextColumn get foamType => text().nullable()();
  IntColumn get defaultWidth =>
      integer().map(const DimensionConverter()).nullable()();
  IntColumn get defaultHeight =>
      integer().map(const DimensionConverter()).nullable()();

  /// JSON dizi, ör. `[5,8,10]` (SPEC §1 "standart kalınlıklar").
  TextColumn get standardThicknesses => text().nullable()();

  IntColumn get defaultSalePriceM3 =>
      integer().map(const UnitPriceConverter()).nullable()();
  IntColumn get criticalStockPieces =>
      integer().withDefault(const Constant(0))();
  IntColumn get minStockVolume =>
      integer().map(const VolumeConverter()).nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (price_coefficient > 0)',
        'CHECK (critical_stock_pieces >= 0)',
      ];
}

/// en × boy × kalınlık × tip (BRIEF §3.1).
@TableIndex(
  name: 'idx_variant_unique',
  columns: {#productId, #width, #height, #thickness, #kind},
  unique: true,
)
class ProductVariants extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get width => integer().map(const DimensionConverter())();
  IntColumn get height => integer().map(const DimensionConverter())();
  IntColumn get thickness => integer().map(const DimensionConverter())();
  TextColumn get kind => text()();

  /// Tek parçanın m³'ü. Dart'ta hesaplanıp yazılır; SQL'de çarpma yapılmaz
  /// (ARCHITECTURE §3), böylece stok toplamları saf SUM() ile alınır.
  IntColumn get unitVolume => integer().map(const VolumeConverter())();

  TextColumn get sku => text().nullable()();
  IntColumn get criticalStockPieces =>
      integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (kind IN (${VariantKind.all.map((e) => "'$e'").join(',')}))",
        'CHECK (width > 0 AND height > 0 AND thickness > 0)',
        'CHECK (unit_volume > 0)',
      ];
}

@TableIndex(name: 'idx_customers_norm', columns: {#titleNormalized})
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get title => text()();
  TextColumn get titleNormalized => text()();

  /// SPEC §9 "Yetkili".
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get taxOffice => text().nullable()();
  TextColumn get taxNumber => text().nullable()();

  /// null ise Ayarlar'daki varsayılan kullanılır (BRIEF §3.4).
  TextColumn get defaultPriceMode => text().nullable()();
  IntColumn get defaultDiscountRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();

  /// 0 = limitsiz (BRIEF §5).
  IntColumn get riskLimit =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get paymentTermDays => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (default_price_mode IS NULL OR default_price_mode IN ('EXCL','INCL'))",
        'CHECK (default_discount_rate >= 0 AND default_discount_rate <= 10000)',
        'CHECK (risk_limit >= 0)',
        'CHECK (payment_term_days >= 0)',
      ];
}

@TableIndex(name: 'idx_suppliers_norm', columns: {#titleNormalized})
class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get title => text()();
  TextColumn get titleNormalized => text()();
  TextColumn get type => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get taxOffice => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  IntColumn get paymentTermDays => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (type IN (${SupplierType.all.map((e) => "'$e'").join(',')}))",
      ];
}

/// Fiyat listesi versiyonu. Eski versiyonlar SİLİNMEZ (SPEC §30.11).
class PriceLists extends Table {
  TextColumn get id => text()();
  IntColumn get versionNo => integer().unique()();
  TextColumn get name => text()();

  /// Beyaz Sünger baz fiyatı, KDV hariç (SPEC §13).
  IntColumn get basePriceM3 => integer().map(const UnitPriceConverter())();
  TextColumn get roundingRule =>
      text().withDefault(const Constant(RoundingRule.none))();
  IntColumn get validFrom => integer()();
  TextColumn get status => text()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (rounding_rule IN (${RoundingRule.all.map((e) => "'$e'").join(',')}))",
        "CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED'))",
        'CHECK (base_price_m3 > 0)',
        'CHECK (version_no > 0)',
      ];
}

@TableIndex(
    name: 'idx_pli_list_product',
    columns: {#priceListId, #productId},
    unique: true)
class PriceListItems extends Table {
  TextColumn get id => text()();
  TextColumn get priceListId => text().references(PriceLists, #id)();
  TextColumn get productId => text().references(Products, #id)();

  /// Versiyona kopyalanır — sonradan ürün katsayısı değişse bile geçmiş
  /// versiyon aynı kalır.
  IntColumn get coefficient => integer().map(const RateConverter())();
  IntColumn get computedPriceM3 => integer().map(const UnitPriceConverter())();
  IntColumn get manualPriceM3 =>
      integer().map(const UnitPriceConverter()).nullable()();
  IntColumn get effectivePriceM3 => integer().map(const UnitPriceConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (effective_price_m3 >= 0)'];
}

@TableIndex(
    name: 'idx_cpd_unique', columns: {#customerId, #productId}, unique: true)
class CustomerProductDiscounts extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get discountRate => integer().map(const RateConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (discount_rate >= 0 AND discount_rate <= 10000)',
      ];
}

class CashAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get bankName => text().nullable()();
  TextColumn get iban => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (type IN (${CashAccountType.all.map((e) => "'$e'").join(',')}))",
      ];
}

class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
