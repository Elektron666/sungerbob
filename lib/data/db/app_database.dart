import 'package:drift/drift.dart';

// Üretilen `part` dosyası bu tipleri kullanır (TypeConverter'ların hedefi).
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import 'converters.dart';
import 'enums.dart';

import 'seed.dart';
import 'tables/finance_tables.dart';
import 'tables/master_tables.dart';
import 'tables/ops_tables.dart';
import 'tables/stock_tables.dart';
import 'tables/system_tables.dart';
import 'tables/trade_tables.dart';
import 'triggers.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    // sistem
    Roles, Permissions, RolePermissions, Users, Devices, Settings,
    DocumentSequences, CommandLog, AuditLogs, BackupLog,
    // ana veri
    Locations, Products, ProductVariants, Customers, Suppliers,
    PriceLists, PriceListItems, CustomerProductDiscounts,
    CashAccounts, ExpenseCategories,
    // stok ve maliyet
    InventoryBatches, StockMovements, CostAllocations, CostAdjustments,
    // alış
    Purchases, PurchaseItems, PurchaseExpenses, PurchaseExpenseAllocations,
    PurchaseReturns, PurchaseReturnItems,
    // satış
    SalesQuotes, SalesQuoteItems, Sales, SaleItems, SaleReturns, SaleReturnItems,
    // finans
    CustomerLedger, SupplierLedger, Collections, SupplierPayments,
    PaymentAllocations, SupplierPaymentAllocations, AccountMovements,
    Transfers, Expenses, Instruments, InstrumentEvents,
    // operasyon
    StockCounts, StockCountItems, StockAdjustments, StockAdjustmentItems,
    CuttingOrders, CuttingOrderSources, CuttingOrderPlanItems,
    CuttingOrderResults, OpeningBalances,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Şema sürümü. Her değişiklikte artırılır ve migration testi yazılır
  /// (ARCHITECTURE §11).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _installTriggers();
          await seedInitialData(this);
        },
        onUpgrade: (m, from, to) async {
          // Sürüm 1 ilk sürüm; buraya sonraki adımlar eklenecek.
          // Her migration öncesi otomatik yedek alınır (BRIEF §4.3).
          await _reinstallTriggers();
        },
        beforeOpen: (details) async {
          // Yabancı anahtarlar her bağlantıda açık olmalı (BRIEF §6).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _installTriggers() async {
    for (final sql in allTriggerSql()) {
      await customStatement(sql);
    }
  }

  /// Migration sonrası trigger'ları yeniden kurar — tablo yeniden
  /// oluşturulduysa trigger'ları düşmüş olabilir.
  Future<void> _reinstallTriggers() async {
    for (final table in [...appendOnlyTables, ...statusOnlyTables.keys]) {
      await customStatement('DROP TRIGGER IF EXISTS trg_${table}_no_update');
      await customStatement('DROP TRIGGER IF EXISTS trg_${table}_no_delete');
      await customStatement('DROP TRIGGER IF EXISTS trg_${table}_status_only');
    }
    await _installTriggers();
  }

  /// Yabancı anahtar bütünlüğünü doğrular (migration sonrası).
  Future<List<QueryRow>> foreignKeyCheck() =>
      customSelect('PRAGMA foreign_key_check').get();
}
