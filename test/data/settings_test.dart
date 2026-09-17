import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/settings_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

OperationContext ctxFor(String t) => OperationContext(commandType: t);

void main() {
  late ScenarioFixture f;
  late SettingsRepository settings;

  setUp(() async {
    f = await ScenarioFixture.create();
    settings = SettingsRepository(f.db);
  });
  tearDown(() async => f.close());

  group('PIN', () {
    test('düz metin saklanmıyor, doğrulama çalışıyor', () async {
      expect(await settings.hasPin(), isFalse);

      await settings.setPin('1234');
      expect(await settings.hasPin(), isTrue);
      expect(await settings.verifyPin('1234'), isTrue);
      expect(await settings.verifyPin('4321'), isFalse);

      // Ayarlar tablosunda düz PIN yok.
      final rows = await f.db.select(f.db.settings).get();
      final values = rows.map((r) => r.value).join('|');
      expect(
        values.contains('1234'),
        isFalse,
        reason: 'PIN düz metin saklanmamalı',
      );
    });

    test('aynı PIN farklı tuzla farklı hash üretir', () async {
      await settings.setPin('1234');
      final rows1 = await f.db.select(f.db.settings).get();
      final hash1 = rows1.firstWhere((r) => r.key == 'pin_hash').value;

      await settings.setPin('1234');
      final rows2 = await f.db.select(f.db.settings).get();
      final hash2 = rows2.firstWhere((r) => r.key == 'pin_hash').value;

      expect(hash1, isNot(hash2), reason: 'her PIN yeni tuz almalı');
      expect(await settings.verifyPin('1234'), isTrue);
    });
  });

  group('Maliyet yöntemi kilidi (BRIEF §3.6)', () {
    test('stok hareketi yokken kilitli değil', () async {
      expect(await settings.isCostingMethodLocked(), isFalse);
      expect(await settings.costingMethod(), CostingMethod.fifo);
    });

    test('ilk stok hareketinden sonra KİLİTLENİR', () async {
      await PurchaseRepository(f.db).create(
        PurchaseInput(
          supplierId: f.supplierId,
          docDate: DateTime.utc(2026, 9, 1),
          priceMode: PriceMode.excl,
          lines: [
            PurchaseLineInput(
              variantId: f.v10,
              pieces: 10,
              volume: f.volumeOf('140', '200', '10', 10),
              unitPriceM3: UnitPrice.parse('3000'),
              vatRate: Rate.percent('20'),
            ),
          ],
        ),
        ctxFor('PURCHASE_CREATE'),
      );

      expect(await settings.isCostingMethodLocked(), isTrue);
    });

    test('kilitliyken değişiklik audit kaydı bırakır', () async {
      await PurchaseRepository(f.db).create(
        PurchaseInput(
          supplierId: f.supplierId,
          docDate: DateTime.utc(2026, 9, 1),
          priceMode: PriceMode.excl,
          lines: [
            PurchaseLineInput(
              variantId: f.v10,
              pieces: 10,
              volume: f.volumeOf('140', '200', '10', 10),
              unitPriceM3: UnitPrice.parse('3000'),
              vatRate: Rate.percent('20'),
            ),
          ],
        ),
        ctxFor('PURCHASE_CREATE'),
      );

      await settings.setCostingMethod(
        CostingMethod.weightedAverage,
        ctxFor('SETTING_CHANGE'),
      );

      expect(await settings.costingMethod(), CostingMethod.weightedAverage);

      final audits = await f.db.select(f.db.auditLogs).get();
      final entry = audits.firstWhere((a) => a.entityId == 'costing_method');
      expect(entry.action, 'SETTING_CHANGE');
      expect(entry.summary, contains('kilitliyken'));
      expect(entry.beforeJson, contains('FIFO'));
      expect(entry.afterJson, contains('WEIGHTED_AVERAGE'));
    });
  });

  group('Kurulum durumu', () {
    test('başta tamamlanmamış, işaretlenince tamamlanmış', () async {
      expect(await settings.isSetupCompleted(), isFalse);
      await settings.markSetupCompleted();
      expect(await settings.isSetupCompleted(), isTrue);
    });
  });

  group('İş ayarları', () {
    test('varsayılanlar seed ile geliyor', () async {
      expect(await settings.defaultPriceMode(), 'EXCL');
      expect(await settings.defaultVatRate(), Rate.percent('20'));
      expect(await settings.allowedVatRates().then((l) => l.length), 4);
      expect(await settings.backupTime(), '20:00');
      expect(await settings.offsiteWarnDays(), 3);
      expect(await settings.backupWifiOnly(), isTrue);
    });

    test('firma bilgileri kaydediliyor', () async {
      await settings.saveCompany(
        const CompanySettings(
          name: 'Sünger Toptan Ltd. Şti.',
          address: 'İstanbul',
          taxOffice: 'Kadıköy',
          taxNumber: '1234567890',
        ),
      );

      final company = await settings.company();
      expect(company.name, 'Sünger Toptan Ltd. Şti.');
      expect(company.taxOffice, 'Kadıköy');
    });

    test('otomatik yedek tarihi saklanıyor', () async {
      expect(await settings.lastAutoBackupDate(), isNull);
      final now = DateTime.utc(2026, 9, 17, 20);
      await settings.setLastAutoBackupDate(now);
      expect(await settings.lastAutoBackupDate(), now);
    });
  });
}
