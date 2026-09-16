import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/domain/core/quantity.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = newTestDatabase();
    // onCreate'i tetikle
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  group('Seed (BRIEF §1.6, SPEC §1 + §13)', () {
    test('12 ürün seed edilir', () async {
      final products = await db.select(db.products).get();
      expect(products.length, 12);
    });

    test('fiyat katsayıları SPEC §13 ile birebir', () async {
      final rows = await db.select(db.products).get();
      final byName = {for (final p in rows) p.name: p.priceCoefficient.stored};

      expect(byName['Beyaz Sünger'], 10000); // 1,00 — baz ürün
      expect(byName['D22 Gri'], 14000); // 1,40
      expect(byName['D28 Gri'], 17100); // 1,71
      expect(byName['D32 Gri'], 19100); // 1,91
      expect(byName['D35 Sert'], 22400); // 2,24
      expect(byName['D35 Yumuşak'], 22400); // 2,24
      expect(byName['D35 140×240'], 22400); // 2,24
      expect(byName['Kuş Tüyü'], 15600); // 1,56
      expect(byName['30 Dream Soft'], 18300); // 1,83
      expect(byName['HR35'], 25600); // 2,56
      expect(byName['HR35 140×240'], 25600); // 2,56
      expect(byName['Eko Gri D18'], 12300); // 1,23
    });

    test('D35 140×240 ve HR35 140×240 ayrı ürün, standart ölçüleri gelir', () async {
      final rows = await db.select(db.products).get();
      final d35 = rows.firstWhere((p) => p.name == 'D35 140×240');
      final hr35 = rows.firstWhere((p) => p.name == 'HR35 140×240');

      expect(d35.defaultWidth, Dimension.cm('140'));
      expect(d35.defaultHeight, Dimension.cm('240'));
      expect(hr35.defaultWidth, Dimension.cm('140'));
      expect(hr35.defaultHeight, Dimension.cm('240'));

      // Ayrı ürün: D35 Sert'ten farklı id ve kod.
      final d35Sert = rows.firstWhere((p) => p.name == 'D35 Sert');
      expect(d35.id, isNot(d35Sert.id));
    });

    test('Türkçe arama normalizasyonu yazılmış', () async {
      final rows = await db.select(db.products).get();
      final beyaz = rows.firstWhere((p) => p.code == 'BEYAZ');
      expect(beyaz.nameNormalized, 'beyaz sunger');

      final kus = rows.firstWhere((p) => p.code == 'KUSTUYU');
      expect(kus.nameNormalized, 'kus tuyu');
    });

    test('iki konum: ANA_DEPO satılabilir, KESIMDE satılamaz', () async {
      final locs = await db.select(db.locations).get();
      expect(locs.length, 2);

      final main = locs.firstWhere((l) => l.code == LocationCode.mainWarehouse);
      final cutting = locs.firstWhere((l) => l.code == LocationCode.cutting);

      expect(main.isSellable, isTrue);
      expect(cutting.isSellable, isFalse);
      expect(cutting.isVirtual, isTrue);
    });

    test('varsayılan ayarlar: FIFO, %20 KDV, EXCL', () async {
      final rows = await db.select(db.settings).get();
      final map = {for (final s in rows) s.key: s.value};
      expect(map['costing_method'], CostingMethod.fifo);
      expect(map['default_vat_rate'], '2000');
      expect(map['default_price_mode'], 'EXCL');
    });

    test('11 belge sayacı sıfırdan başlar', () async {
      final seqs = await db.select(db.documentSequences).get();
      expect(seqs.length, DocPrefix.all.length);
      expect(seqs.every((s) => s.lastNumber == 0), isTrue);
    });

    test('SPEC §23 yetki kodları hazır, ADMIN hepsine sahip', () async {
      final perms = await db.select(db.permissions).get();
      expect(perms.length, 9);
      expect(perms.map((p) => p.code), contains('COST_VIEW'));

      final admin = await (db.select(db.roles)..where((r) => r.code.equals('ADMIN'))).getSingle();
      final links = await (db.select(db.rolePermissions)
            ..where((rp) => rp.roleId.equals(admin.id)))
          .get();
      expect(links.length, 9);
    });
  });

  group('Append-only trigger\'ları (BRIEF §3.5)', () {
    Future<void> insertMovement(String id) async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      final product = await db.select(db.products).get().then((r) => r.first);

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: 'var-1',
            productId: product.id,
            width: Dimension.cm('140'),
            height: Dimension.cm('200'),
            thickness: Dimension.cm('10'),
            kind: VariantKind.plate,
            unitVolume: Volume.parse('0.28'),
          ));

      await db.customStatement(
        "INSERT INTO stock_movements (id, occurred_at, type, location_id, variant_id, "
        "pieces, volume, unit_cost_m3, total_cost, source_type, created_at) "
        "VALUES ('$id', 1, 'PURCHASE_IN', '${loc.id}', 'var-1', 10, 2800000, 30300000, 8484000, 'PURCHASE', 1)",
      );
    }

    test('stock_movements UPDATE reddedilir', () async {
      await insertMovement('m1');
      expect(
        () => db.customStatement("UPDATE stock_movements SET pieces = 5 WHERE id = 'm1'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('stock_movements DELETE reddedilir', () async {
      await insertMovement('m2');
      expect(
        () => db.customStatement("DELETE FROM stock_movements WHERE id = 'm2'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('kayıt UPDATE denemesinden sonra bozulmamış olarak durur', () async {
      await insertMovement('m3');
      try {
        await db.customStatement("UPDATE stock_movements SET pieces = 999 WHERE id = 'm3'");
      } catch (_) {/* beklenen */}

      final row = await db
          .customSelect("SELECT pieces FROM stock_movements WHERE id = 'm3'")
          .getSingle();
      expect(row.read<int>('pieces'), 10);
    });

    test('tüm append-only tablolar korunuyor', () async {
      const tables = [
        'customer_ledger', 'supplier_ledger', 'account_movements',
        'instrument_events', 'cost_allocations', 'cost_adjustments',
        'payment_allocations', 'supplier_payment_allocations',
        'command_log', 'audit_logs', 'backup_log',
      ];
      for (final t in tables) {
        final triggers = await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='$t'")
            .get();
        final names = triggers.map((r) => r.read<String>('name')).toList();
        expect(names, contains('trg_${t}_no_update'), reason: '$t UPDATE koruması');
        expect(names, contains('trg_${t}_no_delete'), reason: '$t DELETE koruması');
      }
    });
  });

  group('Belge başlığı: yalnızca durum güncellenebilir', () {
    Future<String> insertSale() async {
      final customer = await db.into(db.customers).insertReturning(
          CustomersCompanion.insert(
              id: 'c1', code: 'C1', title: 'ABC Mobilya', titleNormalized: 'abc mobilya'));
      await db.customStatement(
        "INSERT INTO sales (id, doc_no, customer_id, doc_date, price_mode, subtotal_net, "
        "vat_total, grand_total, cost_total, status, created_at) "
        "VALUES ('s1','STS-2026-000001','${customer.id}',1,'EXCL',5880000,1176000,7056000,5128200,'ACTIVE',1)",
      );
      return 's1';
    }

    test('status ve cancel alanları güncellenebilir', () async {
      await insertSale();
      await db.customStatement(
          "UPDATE sales SET status='CANCELLED', cancelled_at=2, cancel_reason='hatalı' WHERE id='s1'");
      final row = await db.customSelect("SELECT status FROM sales WHERE id='s1'").getSingle();
      expect(row.read<String>('status'), 'CANCELLED');
    });

    test('tutar güncellenemez', () async {
      await insertSale();
      expect(
        () => db.customStatement("UPDATE sales SET grand_total = 1 WHERE id='s1'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('sabitlenmiş maliyet güncellenemez (BRIEF §3.6)', () async {
      await insertSale();
      expect(
        () => db.customStatement("UPDATE sales SET cost_total = 1 WHERE id='s1'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('belge silinemez', () async {
      await insertSale();
      expect(
        () => db.customStatement("DELETE FROM sales WHERE id='s1'"),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('CHECK kısıtları (BRIEF §6)', () {
    test('negatif parti kalanı reddedilir — negatif stok yasağı', () async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      final product = await db.select(db.products).get().then((r) => r.first);
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: 'v1', productId: product.id,
            width: Dimension.cm('140'), height: Dimension.cm('200'),
            thickness: Dimension.cm('10'), kind: VariantKind.plate,
            unitVolume: Volume.parse('0.28'),
          ));

      expect(
        () => db.customStatement(
          "INSERT INTO inventory_batches (id, variant_id, location_id, source_type, "
          "received_at, bare_unit_cost_m3, real_unit_cost_m3, in_pieces, in_volume, "
          "remaining_pieces, remaining_volume, created_at) "
          "VALUES ('b1','v1','${loc.id}','PURCHASE',1,29300000,30300000,50,14000000,-1,0,1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('kalan girenden fazla olamaz', () async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      final product = await db.select(db.products).get().then((r) => r.first);
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: 'v2', productId: product.id,
            width: Dimension.cm('140'), height: Dimension.cm('200'),
            thickness: Dimension.cm('10'), kind: VariantKind.plate,
            unitVolume: Volume.parse('0.28'),
          ));

      expect(
        () => db.customStatement(
          "INSERT INTO inventory_batches (id, variant_id, location_id, source_type, "
          "received_at, bare_unit_cost_m3, real_unit_cost_m3, in_pieces, in_volume, "
          "remaining_pieces, remaining_volume, created_at) "
          "VALUES ('b2','v2','${loc.id}','PURCHASE',1,29300000,30300000,50,14000000,51,14000000,1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('giriş hareketinde negatif adet reddedilir', () async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      final product = await db.select(db.products).get().then((r) => r.first);
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: 'v3', productId: product.id,
            width: Dimension.cm('140'), height: Dimension.cm('200'),
            thickness: Dimension.cm('10'), kind: VariantKind.plate,
            unitVolume: Volume.parse('0.28'),
          ));

      expect(
        () => db.customStatement(
          "INSERT INTO stock_movements (id, occurred_at, type, location_id, variant_id, "
          "pieces, volume, unit_cost_m3, total_cost, source_type, created_at) "
          "VALUES ('bad','1','PURCHASE_IN','${loc.id}','v3',-10,-2800000,0,0,'PURCHASE',1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('geçersiz hareket tipi reddedilir', () async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      expect(
        () => db.customStatement(
          "INSERT INTO stock_movements (id, occurred_at, type, location_id, variant_id, "
          "pieces, volume, unit_cost_m3, total_cost, source_type, created_at) "
          "VALUES ('bad2',1,'UYDURMA','${loc.id}','v1',10,1,0,0,'PURCHASE',1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('bir hareket iki kez ters çevrilemez', () async {
      final loc = await (db.select(db.locations)
            ..where((l) => l.code.equals(LocationCode.mainWarehouse)))
          .getSingle();
      final product = await db.select(db.products).get().then((r) => r.first);
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: 'v4', productId: product.id,
            width: Dimension.cm('140'), height: Dimension.cm('200'),
            thickness: Dimension.cm('10'), kind: VariantKind.plate,
            unitVolume: Volume.parse('0.28'),
          ));

      Future<void> ins(String id, String? reversalOf) => db.customStatement(
            "INSERT INTO stock_movements (id, occurred_at, type, location_id, variant_id, "
            "pieces, volume, unit_cost_m3, total_cost, source_type, reversal_of_id, created_at) "
            "VALUES ('$id',1,'PURCHASE_IN','${loc.id}','v4',10,2800000,0,0,'PURCHASE',"
            "${reversalOf == null ? 'NULL' : "'$reversalOf'"},1)",
          );

      await ins('orig', null);
      await ins('rev1', 'orig');
      expect(() => ins('rev2', 'orig'), throwsA(isA<SqliteException>()));
    });

    test('command_log aynı UUID ikinci kez yazılamaz (idempotency)', () async {
      Future<void> ins() => db.customStatement(
            "INSERT INTO command_log (id, command_type, payload_hash, created_at) "
            "VALUES ('cmd-1','SALE_CREATE','abc',1)",
          );
      await ins();
      expect(ins, throwsA(isA<SqliteException>()));
    });
  });

  group('Yabancı anahtarlar', () {
    test('PRAGMA foreign_keys açık', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('olmayan ürüne varyant eklenemez', () async {
      expect(
        () => db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
              id: 'vx', productId: 'yok-boyle-urun',
              width: Dimension.cm('140'), height: Dimension.cm('200'),
              thickness: Dimension.cm('10'), kind: VariantKind.plate,
              unitVolume: Volume.parse('0.28'),
            )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('foreign_key_check temiz', () async {
      final issues = await db.foreignKeyCheck();
      expect(issues, isEmpty);
    });
  });
}
