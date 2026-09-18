import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';

/// Enum listeleri ile veritabanı CHECK kısıtlarının birbirinden kopmasını
/// engelleyen bekçi testi.
///
/// CHECK metinleri `drift_dev schema dump` **yalnızca literal metinleri**
/// anlık görüntüye yazdığı için elle yazılıdır (D-23). Elle yazılı olan her
/// şey Dart tarafındaki listeden sapabilir: bir enum'a yeni değer eklenip
/// SQL güncellenmezse uygulama çalışma anında `CHECK constraint failed`
/// verir — hem de tam kullanıcı kaydetmeye bastığı anda. Bu test o sapmayı
/// derleme değil ama test zamanında yakalar.
void main() {
  late AppDatabase db;
  late Map<String, String> schema;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rows = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master "
          "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    schema = {
      for (final r in rows) r.read<String>('name'): r.read<String>('sql'),
    };
  });

  tearDownAll(() async => db.close());

  /// `table.column` üzerindeki CHECK, tam olarak [values] listesini içermeli.
  void expectEnumCheck(String table, String column, List<String> values) {
    final sql = schema[table];
    expect(sql, isNotNull, reason: '$table tablosu yok');
    final expected =
        'CHECK ($column IN (${values.map((v) => "'$v'").join(',')}))';
    expect(
      sql,
      contains(expected),
      reason:
          '$table.$column kısıtı Dart listesiyle uyuşmuyor.\n'
          'Beklenen: $expected',
    );
  }

  test('ana veri kısıtları enum listeleriyle aynı', () {
    expectEnumCheck('locations', 'code', LocationCode.all);
    expectEnumCheck('products', 'unit', ProductUnit.all);
    expectEnumCheck('product_variants', 'kind', VariantKind.all);
    expectEnumCheck('suppliers', 'type', SupplierType.all);
    expectEnumCheck('price_lists', 'rounding_rule', RoundingRule.all);
    expectEnumCheck('cash_accounts', 'type', CashAccountType.all);
  });

  test('stok kısıtları enum listeleriyle aynı', () {
    expectEnumCheck('inventory_batches', 'source_type', BatchSourceType.all);
    expectEnumCheck('stock_movements', 'type', MovementType.all);
    expectEnumCheck('stock_adjustments', 'reason_code', WasteReason.all);
    expectEnumCheck('cutting_orders', 'status', CuttingStatus.all);
  });

  test('ticaret kısıtları enum listeleriyle aynı', () {
    expectEnumCheck('purchases', 'status', DocStatus.all);
    expectEnumCheck('sales', 'status', DocStatus.all);
    expectEnumCheck('sales_quotes', 'status', QuoteStatus.all);
    expectEnumCheck('purchase_expenses', 'allocation_key', AllocationKey.all);
  });

  test('finans kısıtları enum listeleriyle aynı', () {
    expectEnumCheck('customer_ledger', 'doc_type', LedgerDocType.customerAll);
    expectEnumCheck('supplier_ledger', 'doc_type', LedgerDocType.supplierAll);
    expectEnumCheck('collections', 'method', PaymentMethod.all);
    expectEnumCheck('collections', 'status', DocStatus.all);
    expectEnumCheck('supplier_payments', 'method', PaymentMethod.all);
    expectEnumCheck('account_movements', 'type', AccountMovementType.all);
    expectEnumCheck('instruments', 'kind', InstrumentKind.all);
    expectEnumCheck('instruments', 'direction', InstrumentDirection.all);
    expectEnumCheck('instruments', 'current_status', InstrumentStatus.all);
    expectEnumCheck('instrument_events', 'to_status', InstrumentStatus.all);
  });

  test('sistem kısıtları enum listeleriyle aynı', () {
    expectEnumCheck('document_sequences', 'doc_type', DocPrefix.all);
    expectEnumCheck('backup_log', 'kind', BackupKind.all);
    expectEnumCheck('backup_log', 'trigger', BackupTrigger.all);
    expectEnumCheck('backup_log', 'destination', BackupDestination.all);
  });

  test('stok hareketi yön kısıtı giriş/çıkış listeleriyle aynı', () {
    final sql = schema['stock_movements']!;
    String inList(List<String> v) => v.map((e) => "'$e'").join(',');
    expect(
      sql,
      contains(
        'CHECK ((type IN (${inList(MovementType.inbound)}) AND pieces > 0)'
        ' OR (type IN (${inList(MovementType.outbound)}) AND pieces < 0)'
        " OR type = '${MovementType.reversal}')",
      ),
      reason: 'giriş/çıkış listeleri ile SQL kısıtı ayrışmış',
    );
  });
}
