import 'package:drift/drift.dart';

import '../converters.dart';
import '../enums.dart';
import 'master_tables.dart';

/// Cari, tahsilat, kasa ve evrak tabloları (ERD §7, §8, §9).

/// 🔒 append-only. Bakiye = SUM(amount) — ayrı bakiye kolonu YOK (D-10).
/// İşaretli: **+ borç** (müşteri bize borçlu), **− alacak**.
/// Cariye **brüt** (KDV dahil) tutar yazılır (BRIEF §3.4).
@TableIndex(name: 'idx_cl_customer', columns: {#customerId})
@TableIndex(name: 'idx_cl_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_cl_doc', columns: {#docType, #docId})
@TableIndex(name: 'idx_cl_reversal', columns: {#reversalOfId}, unique: true)
class CustomerLedger extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get occurredAt => integer()();
  TextColumn get docType => text()();
  TextColumn get docId => text().nullable()();
  TextColumn get docNo => text().nullable()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get reversalOfId => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (doc_type IN (${LedgerDocType.customerAll.map((e) => "'$e'").join(',')}))",
      ];
}

/// 🔒 append-only. **+ bizim borcumuz**, − azalış.
@TableIndex(name: 'idx_sl_supplier', columns: {#supplierId})
@TableIndex(name: 'idx_sl_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_sl_reversal', columns: {#reversalOfId}, unique: true)
class SupplierLedger extends Table {
  TextColumn get id => text()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  IntColumn get occurredAt => integer()();
  TextColumn get docType => text()();
  TextColumn get docId => text().nullable()();
  TextColumn get docNo => text().nullable()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get reversalOfId => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (doc_type IN (${LedgerDocType.supplierAll.map((e) => "'$e'").join(',')}))",
      ];
}

@TableIndex(name: 'idx_collections_customer', columns: {#customerId})
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get docDate => integer()();
  TextColumn get method => text()();
  TextColumn get cashAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get instrumentId => text().nullable()();
  IntColumn get amount => integer().map(const MoneyConverter())();
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
        "CHECK (method IN (${PaymentMethod.all.map((e) => "'$e'").join(',')}))",
        "CHECK (status IN (${DocStatus.all.map((e) => "'$e'").join(',')}))",
        'CHECK (amount > 0)',
      ];
}

@TableIndex(name: 'idx_spayments_supplier', columns: {#supplierId})
class SupplierPayments extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  IntColumn get docDate => integer()();
  TextColumn get method => text()();
  TextColumn get cashAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get instrumentId => text().nullable()();
  IntColumn get amount => integer().map(const MoneyConverter())();
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
        "CHECK (method IN (${PaymentMethod.all.map((e) => "'$e'").join(',')}))",
        'CHECK (amount > 0)',
      ];
}

/// 🔒 append-only. Tahsilatın hangi belgeyi kapattığı (BRIEF §3.10).
@TableIndex(name: 'idx_pa_collection', columns: {#collectionId})
@TableIndex(name: 'idx_pa_target', columns: {#targetType, #targetId})
class PaymentAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get collectionId => text().references(Collections, #id)();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (target_type IN ('SALE','OPENING','SALE_RETURN'))",
        'CHECK (amount > 0)',
      ];
}

/// 🔒 append-only.
@TableIndex(name: 'idx_spa_payment', columns: {#supplierPaymentId})
class SupplierPaymentAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get supplierPaymentId => text().references(SupplierPayments, #id)();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (target_type IN ('PURCHASE','OPENING','CUTTING_ORDER'))",
        'CHECK (amount > 0)',
      ];
}

/// 🔒 append-only. Bakiye = SUM(IN) − SUM(OUT).
@TableIndex(name: 'idx_am_account', columns: {#cashAccountId})
@TableIndex(name: 'idx_am_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_am_reversal', columns: {#reversalOfId}, unique: true)
class AccountMovements extends Table {
  TextColumn get id => text()();
  TextColumn get cashAccountId => text().references(CashAccounts, #id)();
  IntColumn get occurredAt => integer()();
  TextColumn get direction => text()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get type => text()();
  TextColumn get sourceType => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get counterAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get reversalOfId => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get commandId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (direction IN ('IN','OUT'))",
        "CHECK (type IN (${AccountMovementType.all.map((e) => "'$e'").join(',')}))",
        'CHECK (amount > 0)',
      ];
}

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get fromAccountId => text().references(CashAccounts, #id)();
  TextColumn get toAccountId => text().references(CashAccounts, #id)();
  IntColumn get amount => integer().map(const MoneyConverter())();
  IntColumn get docDate => integer()();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (from_account_id <> to_account_id)',
        'CHECK (amount > 0)',
      ];
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get docNo => text().unique()();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  IntColumn get docDate => integer()();
  IntColumn get amountNet => integer().map(const MoneyConverter())();
  IntColumn get vatRate =>
      integer().map(const RateConverter()).withDefault(const Constant(0))();
  IntColumn get vatTotal =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get grossTotal => integer().map(const MoneyConverter())();
  TextColumn get cashAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get status =>
      text().withDefault(const Constant(DocStatus.active))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Çek ve senet tek modelde (BRIEF §5).
@TableIndex(name: 'idx_inst_customer', columns: {#customerId})
@TableIndex(name: 'idx_inst_due', columns: {#dueDate})
@TableIndex(name: 'idx_inst_status', columns: {#currentStatus})
class Instruments extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get direction => text()();
  TextColumn get serialNo => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get branch => text().nullable()();

  /// Keşideci veya borçlu.
  TextColumn get drawerName => text().nullable()();
  IntColumn get dueDate => integer()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get endorsedToSupplierId =>
      text().nullable().references(Suppliers, #id)();

  /// ÖNBELLEK — doğrusu instrument_events zincirinin sonucudur.
  TextColumn get currentStatus => text()();

  TextColumn get sourceType => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (kind IN (${InstrumentKind.all.map((e) => "'$e'").join(',')}))",
        "CHECK (direction IN (${InstrumentDirection.all.map((e) => "'$e'").join(',')}))",
        "CHECK (current_status IN (${InstrumentStatus.all.map((e) => "'$e'").join(',')}))",
        'CHECK (amount > 0)',
      ];
}

/// 🔒 append-only. Durum geçmişi.
@TableIndex(name: 'idx_ie_instrument', columns: {#instrumentId})
@TableIndex(name: 'idx_ie_reversal', columns: {#reversalOfId}, unique: true)
class InstrumentEvents extends Table {
  TextColumn get id => text()();
  TextColumn get instrumentId => text().references(Instruments, #id)();
  IntColumn get occurredAt => integer()();
  TextColumn get fromStatus => text().nullable()();
  TextColumn get toStatus => text()();
  TextColumn get cashAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get counterpartyId => text().nullable()();
  IntColumn get amount => integer().map(const MoneyConverter())();
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
        "CHECK (to_status IN (${InstrumentStatus.all.map((e) => "'$e'").join(',')}))",
      ];
}
