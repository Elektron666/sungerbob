import 'package:drift/drift.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/quantity.dart';

import '../data/test_db.dart';

/// Altın Senaryo için ortak kurulum (docs/GOLDEN_SCENARIO.md).
class ScenarioFixture {
  final AppDatabase db;
  late final String beyazProductId;
  late final String customerId;
  late final String supplierId;
  late final String bankAccountId;

  /// 140×200×10 — senaryonun ana varyantı
  late final String v10;

  /// 140×200×5
  late final String v5;

  /// 140×200×8
  late final String v8;

  ScenarioFixture(this.db);

  static Future<ScenarioFixture> create({String? costingMethod}) async {
    final f = ScenarioFixture(newTestDatabase());
    await f._setUp(costingMethod);
    return f;
  }

  Future<void> _setUp(String? costingMethod) async {
    await db.customSelect('SELECT 1').get(); // onCreate + seed

    if (costingMethod != null) {
      await (db.update(
        db.settings,
      )..where((s) => s.key.equals('costing_method'))).write(
        SettingsCompanion(value: Value(costingMethod), updatedAt: Value(0)),
      );
    }

    final beyaz = await (db.select(
      db.products,
    )..where((p) => p.code.equals('BEYAZ'))).getSingle();
    beyazProductId = beyaz.id;

    v10 = await _variant('140', '200', '10');
    v5 = await _variant('140', '200', '5');
    v8 = await _variant('140', '200', '8');

    customerId = uuid.v7();
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: customerId,
            code: 'ABC',
            title: 'ABC Mobilya',
            titleNormalized: 'abc mobilya',
            paymentTermDays: const Value(30),
          ),
        );

    supplierId = uuid.v7();
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: supplierId,
            code: 'FAB1',
            title: 'Sünger Fabrikası',
            titleNormalized: 'sunger fabrikasi',
            type: SupplierType.factory,
          ),
        );

    final bank = await (db.select(
      db.cashAccounts,
    )..where((a) => a.code.equals('KASA'))).getSingle();
    bankAccountId = bank.id;
  }

  Future<String> _variant(String w, String h, String t) async {
    final id = uuid.v7();
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: id,
            productId: beyazProductId,
            width: Dimension.cm(w),
            height: Dimension.cm(h),
            thickness: Dimension.cm(t),
            kind: VariantKind.plate,
            unitVolume: Volume.fromDimensions(
              width: Dimension.cm(w),
              height: Dimension.cm(h),
              thickness: Dimension.cm(t),
              pieces: 1,
            ),
          ),
        );
    return id;
  }

  Volume volumeOf(String w, String h, String t, int pieces) =>
      Volume.fromDimensions(
        width: Dimension.cm(w),
        height: Dimension.cm(h),
        thickness: Dimension.cm(t),
        pieces: pieces,
      );

  Future<void> close() => db.close();
}
