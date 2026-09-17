/// Append-only trigger'ları (BRIEF §3.5, ERD §13).
///
/// Bu tablolara yalnızca INSERT yapılabilir; UPDATE ve DELETE veritabanı
/// seviyesinde reddedilir. Düzeltme yalnızca `reversal_of_id` ile ters
/// hareketle yapılır. Kural uygulama katmanında değil burada durur; böylece
/// bir programlama hatası bile finansal geçmişi bozamaz.
library;

/// Hiçbir koşulda güncellenemeyen/silinemeyen tablolar.
const appendOnlyTables = <String>[
  'stock_movements',
  'customer_ledger',
  'supplier_ledger',
  'account_movements',
  'instrument_events',
  'cost_allocations',
  'cost_adjustments',
  'payment_allocations',
  'supplier_payment_allocations',
  'command_log',
  'audit_logs',
  'backup_log',
];

/// Belge başlıkları: yalnızca durum alanları güncellenebilir (BRIEF §3.5).
/// Değer: değişmesi yasak olan kolonlar.
const statusOnlyTables = <String, List<String>>{
  'sales': [
    'doc_no',
    'customer_id',
    'doc_date',
    'subtotal_net',
    'vat_total',
    'grand_total',
    'cost_total',
  ],
  'purchases': [
    'doc_no',
    'supplier_id',
    'doc_date',
    'subtotal_net',
    'vat_total',
    'grand_total',
  ],
  'sale_returns': [
    'doc_no',
    'sale_id',
    'customer_id',
    'doc_date',
    'grand_total',
    'cost_total',
  ],
  'purchase_returns': [
    'doc_no',
    'purchase_id',
    'supplier_id',
    'doc_date',
    'grand_total',
  ],
  'collections': ['doc_no', 'customer_id', 'doc_date', 'amount', 'method'],
  'supplier_payments': [
    'doc_no',
    'supplier_id',
    'doc_date',
    'amount',
    'method',
  ],
  'transfers': [
    'doc_no',
    'from_account_id',
    'to_account_id',
    'amount',
    'doc_date',
  ],
  'expenses': [
    'doc_no',
    'category_id',
    'doc_date',
    'amount_net',
    'gross_total',
  ],
  'stock_adjustments': ['doc_no', 'occurred_at', 'reason_code', 'cost_total'],
};

/// Bir tablo için append-only trigger SQL'leri.
List<String> appendOnlyTriggerSql(String table) => [
  '''
CREATE TRIGGER IF NOT EXISTS trg_${table}_no_update
BEFORE UPDATE ON $table
BEGIN
  SELECT RAISE(ABORT, 'append-only: $table güncellenemez, ters hareket kullanın');
END;''',
  '''
CREATE TRIGGER IF NOT EXISTS trg_${table}_no_delete
BEFORE DELETE ON $table
BEGIN
  SELECT RAISE(ABORT, 'append-only: $table silinemez, ters hareket kullanın');
END;''',
];

/// Belge başlığı için "yalnızca durum güncellenebilir" trigger SQL'leri.
List<String> statusOnlyTriggerSql(String table, List<String> frozenColumns) {
  final condition = frozenColumns
      .map((c) => 'OLD.$c IS NOT NEW.$c')
      .join('\n   OR ');
  return [
    '''
CREATE TRIGGER IF NOT EXISTS trg_${table}_status_only
BEFORE UPDATE ON $table
WHEN $condition
BEGIN
  SELECT RAISE(ABORT, '$table: yalnızca durum alanları güncellenebilir');
END;''',
    '''
CREATE TRIGGER IF NOT EXISTS trg_${table}_no_delete
BEFORE DELETE ON $table
BEGIN
  SELECT RAISE(ABORT, '$table: belge silinemez, iptal edin');
END;''',
  ];
}

/// Tüm trigger SQL'leri.
List<String> allTriggerSql() => [
  for (final t in appendOnlyTables) ...appendOnlyTriggerSql(t),
  for (final e in statusOnlyTables.entries)
    ...statusOnlyTriggerSql(e.key, e.value),
];
