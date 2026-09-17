import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/triggers.dart';

/// Migration ve sıfırdan kurulum testleri (ARCHITECTURE §11).
///
/// Sürüm 1 ilk sürüm olduğu için henüz yükseltme adımı yok; bu testler
/// şemanın sıfırdan tutarlı kurulduğunu ve trigger'ların yerinde olduğunu
/// doğrular. Sürüm 2 geldiğinde `drift_schemas/` anlık görüntüleriyle
/// üretilen yükseltme testleri buraya eklenir.
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

    test('şema sürümü 1', () {
      expect(db.schemaVersion, 1);
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
}
