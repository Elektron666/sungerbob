import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/notifications/due_date_notifier.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

/// Vade bildirimleri (BRIEF §5): "Vade gününden bir gün önce yerel bildirim."
void main() {
  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  Future<void> seedStock() => PurchaseRepository(f.db).create(
    PurchaseInput(
      supplierId: f.supplierId,
      docDate: DateTime.utc(2026, 9, 1),
      priceMode: PriceMode.excl,
      lines: [
        PurchaseLineInput(
          variantId: f.v10,
          pieces: 50,
          volume: f.volumeOf('140', '200', '10', 50),
          unitPriceM3: UnitPrice.parse('3000'),
          vatRate: vat20,
        ),
      ],
    ),
    ctxFor('PURCHASE_CREATE'),
  );

  test('bildirim yokken boş liste', () async {
    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 9, 17));
    expect(list, isEmpty);
  });

  test('çek vadesinden BİR GÜN ÖNCE bildirim planlanıyor', () async {
    await CollectionRepository(f.db).create(
      CollectionInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 17),
        amount: Money.parse('20000'),
        method: PaymentMethod.check,
        instrument: InstrumentInput(
          kind: InstrumentKind.check,
          dueDate: DateTime(2026, 10, 30),
          serialNo: '0012345',
        ),
      ),
      ctxFor('COLLECTION_CREATE'),
    );

    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 10, 1), horizonDays: 60);

    expect(list.length, 1);
    final n = list.single;
    expect(n.title, 'Yarın tahsil edilecek evrak');
    expect(n.body, contains('Çek'));
    expect(n.body, contains('0012345'));
    // Vade 30.10 → bildirim 29.10 saat 09:00
    expect(n.scheduledAt, DateTime(2026, 10, 29, 9));
  });

  test('vadeli satış için bildirim planlanıyor', () async {
    await seedStock();
    await SaleRepository(f.db).create(
      SaleInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 17),
        dueDate: DateTime(2026, 10, 17),
        priceMode: PriceMode.excl,
        lines: [
          SaleLineInput(
            variantId: f.v10,
            pieces: 10,
            volume: f.volumeOf('140', '200', '10', 10),
            unitPriceM3: UnitPrice.parse('3500'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('SALE_CREATE'),
    );

    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 10, 1), horizonDays: 60);

    final sale = list.firstWhere((n) => n.id.startsWith('sale-'));
    expect(sale.title, 'Yarın vadesi dolan alacak');
    expect(sale.body, contains('ABC Mobilya'));
    expect(sale.scheduledAt, DateTime(2026, 10, 16, 9));
  });

  test('tahsil edilmiş satış için bildirim YOK', () async {
    await seedStock();
    await SaleRepository(f.db).create(
      SaleInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 17),
        dueDate: DateTime(2026, 10, 17),
        priceMode: PriceMode.excl,
        lines: [
          SaleLineInput(
            variantId: f.v10,
            pieces: 10,
            volume: f.volumeOf('140', '200', '10', 10),
            unitPriceM3: UnitPrice.parse('3500'),
            vatRate: vat20,
          ),
        ],
      ),
      ctxFor('SALE_CREATE'),
    );

    // Tamamını tahsil et: 10 × 0,28 × 3500 = 9.800 + KDV = 11.760
    await CollectionRepository(f.db).create(
      CollectionInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 20),
        amount: Money.parse('11760'),
        method: PaymentMethod.transfer,
        cashAccountId: f.bankAccountId,
      ),
      ctxFor('COLLECTION_CREATE'),
    );

    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 10, 1), horizonDays: 60);
    expect(
      list.where((n) => n.id.startsWith('sale-')),
      isEmpty,
      reason: 'kapanmış satış için bildirim olmamalı',
    );
  });

  test('geçmiş vade için bildirim planlanmıyor', () async {
    await CollectionRepository(f.db).create(
      CollectionInput(
        customerId: f.customerId,
        docDate: DateTime.utc(2026, 9, 1),
        amount: Money.parse('5000'),
        method: PaymentMethod.check,
        instrument: InstrumentInput(
          kind: InstrumentKind.check,
          dueDate: DateTime(2026, 9, 10),
        ),
      ),
      ctxFor('COLLECTION_CREATE'),
    );

    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 9, 20));
    expect(list, isEmpty, reason: 'vadesi geçmiş evrak için bildirim yok');
  });

  test('bildirimler tarihe göre sıralı', () async {
    for (final day in [30, 15, 22]) {
      await CollectionRepository(f.db).create(
        CollectionInput(
          customerId: f.customerId,
          docDate: DateTime.utc(2026, 9, 17),
          amount: Money.parse('1000'),
          method: PaymentMethod.check,
          instrument: InstrumentInput(
            kind: InstrumentKind.check,
            dueDate: DateTime(2026, 10, day),
            serialNo: '$day',
          ),
        ),
        ctxFor('COLLECTION_CREATE'),
      );
    }

    final list = await DueDateNotifier(f.db)
        .pendingNotifications(now: DateTime(2026, 10, 1), horizonDays: 60);
    expect(list.length, 3);
    for (var i = 1; i < list.length; i++) {
      expect(list[i].scheduledAt.isAfter(list[i - 1].scheduledAt), isTrue);
    }
  });
}
