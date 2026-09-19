import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/db/triggers.dart';
import 'package:drift/drift.dart' show Variable;

import 'package:drift_dev/api/migrations_native.dart';

import 'generated_migrations/schema.dart';

/// Migration ve sıfırdan kurulum testleri (ARCHITECTURE §11).
///
/// Sıfırdan kurulumun yanı sıra **v1 → v2 yükseltmesi** de sınanır:
/// telefonundaki veriyle uygulamayı güncelleyen kullanıcı, verisini
/// kaybetmemelidir.
void main() {
  group('Sıfırdan kurulum', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA foreign_keys = ON');
          },
        ),
      );
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async => db.close());

    test('şema sürümü 2', () {
      expect(db.schemaVersion, 2);
    });

    test('bütün tablolar oluşturuldu', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();

      // SPEC §26'nın minimum listesi
      for (final t in [
        'users',
        'roles',
        'permissions',
        'products',
        'product_variants',
        'price_lists',
        'price_list_items',
        'suppliers',
        'customers',
        'purchases',
        'purchase_items',
        'inventory_batches',
        'sales_quotes',
        'sales',
        'sale_items',
        'stock_movements',
        'stock_adjustments',
        'customer_ledger',
        'supplier_ledger',
        'collections',
        'supplier_payments',
        'expenses',
        'audit_logs',
      ]) {
        expect(names, contains(t), reason: 'SPEC §26 tablosu eksik: $t');
      }

      // BRIEF §6'nın ek tabloları
      for (final t in [
        'locations',
        'settings',
        'document_sequences',
        'command_log',
        'cash_accounts',
        'account_movements',
        'cost_allocations',
        'payment_allocations',
        'supplier_payment_allocations',
        'sale_returns',
        'sale_return_items',
        'purchase_returns',
        'purchase_return_items',
        'purchase_expenses',
        'cost_adjustments',
        'stock_counts',
        'stock_count_items',
        'cutting_orders',
        'cutting_order_sources',
        'cutting_order_results',
        'instruments',
        'instrument_events',
        'expense_categories',
        'opening_balances',
        'backup_log',
      ]) {
        expect(names, contains(t), reason: 'BRIEF §6 tablosu eksik: $t');
      }
    });

    test('bütün trigger\'lar kuruldu', () async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='trigger'")
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();

      for (final t in appendOnlyTables) {
        expect(names, contains('trg_${t}_no_update'));
        expect(names, contains('trg_${t}_no_delete'));
      }
      for (final t in statusOnlyTables.keys) {
        expect(names, contains('trg_${t}_status_only'));
        expect(names, contains('trg_${t}_no_delete'));
      }
    });

    test('yabancı anahtar bütünlüğü temiz', () async {
      expect(await db.foreignKeyCheck(), isEmpty);
    });

    test('integrity_check temiz', () async {
      final row = await db.customSelect('PRAGMA integrity_check').getSingle();
      expect(row.data.values.first, 'ok');
    });

    test('seed iki kez çalıştırılmaz (benzersiz kısıtlar)', () async {
      final products = await db.select(db.products).get();
      expect(products.length, 12, reason: 'seed tam olarak bir kez çalışmalı');

      final codes = products.map((p) => p.code).toSet();
      expect(codes.length, 12, reason: 'ürün kodları benzersiz');
    });
  });

  group('Şema anlık görüntüsü', () {
    test('mevcut schemaVersion için anlık görüntü dosyası var', () {
      // Sürüm 2'ye geçildiğinde bu dosyalar yükseltme testlerinin temeli olur:
      //   dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/
      //   dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
      final db = AppDatabase(NativeDatabase.memory());
      final version = db.schemaVersion;
      db.close();

      final file = File('drift_schemas/drift_schema_v$version.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'schemaVersion $version icin anlik goruntu alinmamis. '
            'Sema degistiyse `drift_dev schema dump` calistirin.',
      );

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['_meta']?['version'], isNotNull);
    });
  });

  group('v1 → v2 yükseltmesi (ürün birimi)', () {
    late SchemaVerifier verifier;

    setUpAll(() {
      verifier = SchemaVerifier(GeneratedHelper());
    });

    test('şema v1\'den v2\'ye sorunsuz yükselir', () async {
      final connection = await verifier.startAt(1);
      final db = AppDatabase(connection);
      await verifier.migrateAndValidate(db, 2);
      await db.close();
    });

    test('yükseltmede mevcut ürünler kaybolmaz ve birimi M3 olur', () async {
      // v1 şemasıyla bir ürün yaz — o sürümde `unit` sütunu yok.
      final upgraded = AppDatabase(await verifier.startAt(1));
      await upgraded.customStatement(
        "INSERT INTO products (id, code, name, name_normalized, "
        'price_coefficient, critical_stock_pieces, is_active) '
        "VALUES ('p1', 'TEST', 'Test Sünger', 'test sunger', 10000, 0, 1)",
      );

      // Açılış migration'ı tetikler.
      await upgraded.customSelect('SELECT 1').get();
      final rows = await upgraded
          .customSelect(
            'SELECT id, unit FROM products WHERE id = ?',
            variables: [Variable.withString('p1')],
          )
          .get();

      expect(rows, hasLength(1), reason: 'yükseltmede ürün kayboldu');
      expect(
        rows.single.read<String>('unit'),
        ProductUnit.m3,
        reason: 'eski ürünler sünger; birimi m³ olmalı',
      );
      await upgraded.close();
    });

    test('yükseltilen tablolar taze kurulumla birebir aynı', () async {
      // Asıl güvence: telefonunda v1 taşıyan kullanıcı ile bugün uygulamayı
      // ilk kez kuran kullanıcı **aynı** veritabanına sahip olmalı.
      final upgraded = AppDatabase(await verifier.startAt(1));
      await upgraded.customSelect('SELECT 1').get();
      final fresh = AppDatabase(NativeDatabase.memory());
      await fresh.customSelect('SELECT 1').get();

      Future<String> tableSql(AppDatabase d, String name) async {
        final row = await d
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [Variable.withString(name)],
            )
            .getSingle();
        return row.read<String>('sql');
      }

      for (final table in ['products', 'product_variants']) {
        expect(
          await tableSql(upgraded, table),
          await tableSql(fresh, table),
          reason: '$table yükseltmede taze kurulumdan farklı oluştu',
        );
      }

      await upgraded.close();
      await fresh.close();
    });

    test('yükseltilen veritabanı ölçüsüz varyantı kabul eder', () async {
      // İnce malzemenin ölçüsü yoktur; v1'in ölçü kısıtı bunu engelliyordu.
      final upgraded = AppDatabase(await verifier.startAt(1));
      await upgraded.customStatement(
        "INSERT INTO products (id, code, name, name_normalized, "
        'price_coefficient, critical_stock_pieces, is_active, unit) '
        "VALUES ('p2', 'TUTKAL', 'Tutkal', 'tutkal', 10000, 0, 1, 'KG')",
      );
      await upgraded.customStatement(
        'INSERT INTO product_variants (id, product_id, width, height, '
        'thickness, kind, unit_volume, critical_stock_pieces, is_active) '
        "VALUES ('v2', 'p2', 0, 0, 0, 'PLAKA', 1000000, 0, 1)",
      );
      final rows = await upgraded
          .customSelect("SELECT id FROM product_variants WHERE id = 'v2'")
          .get();
      expect(rows, hasLength(1));
      await upgraded.close();
    });

    test('yükseltilen veritabanı geçersiz birimi reddeder', () async {
      // `ADD COLUMN` tablo kısıtı ekleyemediği için tablo yeniden kuruluyor;
      // bu test o kararın gerçekten işe yaradığını doğrular.
      final upgraded = AppDatabase(await verifier.startAt(1));
      await expectLater(
        upgraded.customStatement(
          "INSERT INTO products (id, code, name, name_normalized, "
          'price_coefficient, critical_stock_pieces, is_active, unit) '
          "VALUES ('p3', 'X', 'X', 'x', 10000, 0, 1, 'SAKA_BIRIM')",
        ),
        throwsA(isA<Exception>()),
      );
      await upgraded.close();
    });
  });
}
