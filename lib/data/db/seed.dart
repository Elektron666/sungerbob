import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/core/quantity.dart';
import '../../domain/core/text_normalize.dart';
import 'app_database.dart';
import 'enums.dart';

/// Kurulumda yazılan zorunlu veriler. **Demo/örnek veri değildir** —
/// mock veriyle doldurulmuş ekran yoktur (BRIEF §0).

const _uuid = Uuid();

/// SPEC §1 ürünleri ve SPEC §13 fiyat katsayıları.
///
/// Katsayı ×10.000 saklanır: 1,00 → 10000. Baz ürün Beyaz Sünger = 1,00.
/// "D35 140×240" ve "HR35 140×240" katsayıları D35/HR35 ile aynıdır ama
/// müşteri kararıyla **ayrı ürünlerdir** (BRIEF §1.6, DECISIONS V-01).
const seedProducts = <({
  String code,
  String name,
  int coefficient,
  int? defaultWidth,
  int? defaultHeight,
})>[
  (code: 'BEYAZ', name: 'Beyaz Sünger', coefficient: 10000, defaultWidth: null, defaultHeight: null),
  (code: 'D22GRI', name: 'D22 Gri', coefficient: 14000, defaultWidth: null, defaultHeight: null),
  (code: 'D28GRI', name: 'D28 Gri', coefficient: 17100, defaultWidth: null, defaultHeight: null),
  (code: 'D32GRI', name: 'D32 Gri', coefficient: 19100, defaultWidth: null, defaultHeight: null),
  (code: 'D35SERT', name: 'D35 Sert', coefficient: 22400, defaultWidth: null, defaultHeight: null),
  (code: 'D35YUM', name: 'D35 Yumuşak', coefficient: 22400, defaultWidth: null, defaultHeight: null),
  (code: 'D35-140240', name: 'D35 140×240', coefficient: 22400, defaultWidth: 14000, defaultHeight: 24000),
  (code: 'KUSTUYU', name: 'Kuş Tüyü', coefficient: 15600, defaultWidth: null, defaultHeight: null),
  (code: 'DREAMSOFT30', name: '30 Dream Soft', coefficient: 18300, defaultWidth: null, defaultHeight: null),
  (code: 'HR35', name: 'HR35', coefficient: 25600, defaultWidth: null, defaultHeight: null),
  (code: 'HR35-140240', name: 'HR35 140×240', coefficient: 25600, defaultWidth: 14000, defaultHeight: 24000),
  (code: 'EKOGRID18', name: 'Eko Gri D18', coefficient: 12300, defaultWidth: null, defaultHeight: null),
];

/// SPEC §23'teki yetki alanları. v1'de arayüz gizli ama kodlar hazır (D-03).
const seedPermissions = <({String code, String description})>[
  (code: 'PURCHASE_PRICE_VIEW', description: 'Alış fiyatını görebilir'),
  (code: 'COST_VIEW', description: 'Maliyeti görebilir'),
  (code: 'PROFIT_VIEW', description: 'Kârı görebilir'),
  (code: 'SALE_PRICE_EDIT', description: 'Satış fiyatını değiştirebilir'),
  (code: 'STOCK_IN', description: 'Stok girişi yapabilir'),
  (code: 'SALE_CREATE', description: 'Satış yapabilir'),
  (code: 'COLLECTION_CREATE', description: 'Tahsilat girebilir'),
  (code: 'LEDGER_VIEW', description: 'Cari bakiyeyi görebilir'),
  (code: 'DOC_CANCEL', description: 'İşlem iptal edebilir'),
];

Future<void> seedInitialData(AppDatabase db) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  // --- roller ve yetkiler -------------------------------------------------
  final adminRoleId = _uuid.v7();
  await db.into(db.roles).insert(RolesCompanion.insert(
      id: adminRoleId, code: 'ADMIN', name: 'Patron'));
  await db.into(db.roles).insert(RolesCompanion.insert(
      id: _uuid.v7(), code: 'ACCOUNTANT', name: 'Muhasebeci'));

  for (final p in seedPermissions) {
    final permId = _uuid.v7();
    await db.into(db.permissions).insert(PermissionsCompanion.insert(
        id: permId, code: p.code, description: p.description));
    // v1'de tek ADMIN kullanıcı her yetkiye sahiptir.
    await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: adminRoleId, permissionId: permId));
  }

  // --- konumlar -----------------------------------------------------------
  await db.into(db.locations).insert(LocationsCompanion.insert(
        id: _uuid.v7(),
        code: LocationCode.mainWarehouse,
        name: 'Ana Depo',
      ));
  await db.into(db.locations).insert(LocationsCompanion.insert(
        id: _uuid.v7(),
        code: LocationCode.cutting,
        name: 'Kesimde',
        isVirtual: const Value(true),
        // Kesimdeki mal satılamaz (D-07).
        isSellable: const Value(false),
      ));

  // --- 12 ürün ------------------------------------------------------------
  for (final p in seedProducts) {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: _uuid.v7(),
          code: p.code,
          name: p.name,
          nameNormalized: normalizeTurkish(p.name),
          priceCoefficient: Rate.fromStored(p.coefficient),
          defaultWidth: Value(
              p.defaultWidth == null ? null : Dimension.fromStored(p.defaultWidth!)),
          defaultHeight: Value(
              p.defaultHeight == null ? null : Dimension.fromStored(p.defaultHeight!)),
        ));
  }

  // --- belge sayaçları ----------------------------------------------------
  final year = DateTime.now().year;
  for (final prefix in DocPrefix.all) {
    await db.into(db.documentSequences).insert(DocumentSequencesCompanion.insert(
        id: _uuid.v7(), docType: prefix, year: year));
  }

  // --- varsayılan ayarlar -------------------------------------------------
  const defaults = <String, String>{
    'costing_method': CostingMethod.fifo,
    'default_price_mode': 'EXCL',
    'default_vat_rate': '2000',
    'allowed_vat_rates': '[0,100,1000,2000]',
    'backup_auto_time': '20:00',
    'backup_offsite_warn_days': '3',
    'backup_wifi_only': 'true',
    'hide_cost_mode': 'false',
  };
  for (final e in defaults.entries) {
    await db.into(db.settings).insert(SettingsCompanion.insert(
        key: e.key, value: e.value, updatedAt: now));
  }

  // --- varsayılan kasa ----------------------------------------------------
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
        id: _uuid.v7(),
        code: 'KASA',
        name: 'Nakit Kasa',
        type: CashAccountType.cash,
      ));

  // --- gider kategorileri -------------------------------------------------
  for (final name in ['Kira', 'Maaş', 'Yakıt', 'Elektrik', 'Diğer']) {
    await db.into(db.expenseCategories).insert(ExpenseCategoriesCompanion.insert(
        id: _uuid.v7(), name: name));
  }
}
