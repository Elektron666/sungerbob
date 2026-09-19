import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/finance/customers_screen.dart';

import '../data/test_db.dart';

/// **Yanlış girilen tahsilat düzeltilebiliyor mu?**
///
/// `cancelCollection` Faz 1'den beri yazılıydı ama hiçbir ekrandan
/// çağrılmıyordu (SK-22): kullanıcı yanlış tahsilatı gördüğü hâlde
/// düzeltemiyordu.
///
/// Tahsilatın kendisi başka testlerde ekranlardan geçiyor; burada sınanan
/// **iptal akışı**, o yüzden ön koşul repository'den hazırlanıyor.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  /// Müşteri + 1.000 TL nakit tahsilat.
  Future<String> seed() async {
    final customerId = uuid.v7();
    await db.customStatement(
      'INSERT INTO customers (id, code, title, title_normalized, '
      'default_discount_rate, risk_limit, payment_term_days, is_active) '
      "VALUES ('$customerId', 'M1', 'Mobilyacı Ahmet', 'mobilyaci ahmet', "
      '0, 0, 0, 1)',
    );

    final account = await db.select(db.cashAccounts).get();
    await CollectionRepository(db).create(
      CollectionInput(
        customerId: customerId,
        docDate: DateTime.now(),
        amount: Money.parse('1000'),
        method: PaymentMethod.cash,
        cashAccountId: account.first.id,
      ),
      OperationContext(commandType: 'COLLECTION_CREATE'),
    );
    return customerId;
  }

  testWidgets('ekstreden iptal: ters kayıt oluşur, bakiye geri gelir', (
    tester,
  ) async {
    final customerId = await seed();

    // Tahsilat cariyi 1.000 TL alacaklı yaptı.
    expect(await db.customerBalance(customerId), Money.parse('-1000'));

    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerLedgerScreen(customerId: customerId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tahsilatı iptal et'));
    await tester.pumpAndSettle();

    // Sebep zorunlu: boşken düğme iş görmemeli.
    await tester.tap(find.widgetWithText(FilledButton, 'İptal et'));
    await tester.pumpAndSettle();
    expect(
      find.text('İptal sebebi'),
      findsOneWidget,
      reason: 'sebepsiz iptal edilebilmiş',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'İptal sebebi'),
      'yanlış müşteriye girildi',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'İptal et'));
    await tester.pumpAndSettle();

    // Bakiye geri geldi.
    expect(await db.customerBalance(customerId), Money.zero);

    // Tahsilat SİLİNMEDİ, iptal işaretlendi; ters kayıt eklendi.
    final collection = await db.select(db.collections).getSingle();
    expect(collection.status, DocStatus.cancelled);
    expect(collection.cancelReason, 'yanlış müşteriye girildi');

    final ledger = await db.select(db.customerLedger).get();
    expect(ledger, hasLength(2), reason: 'ters kayıt yazılmadı');
    expect(ledger.any((l) => l.docType == LedgerDocType.reversal), isTrue);

    // Kasa hareketi de tersine döndü.
    final movements = await db.select(db.accountMovements).get();
    expect(movements, hasLength(2));
    expect(movements.map((m) => m.direction).toSet(), {
      'IN',
      'OUT',
    }, reason: 'kasadan çıkış yazılmamış');
  });

  testWidgets('iptal edilmiş tahsilat ikinci kez iptal ettirilmez', (
    tester,
  ) async {
    final customerId = await seed();
    final collection = await db.select(db.collections).getSingle();
    final repo = await ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    ).read(reversalRepositoryProvider.future);
    await repo.cancelCollection(
      collectionId: collection.id,
      reason: 'ilk iptal',
      ctx: OperationContext(commandType: 'COLLECTION_CANCEL'),
    );

    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(home: CustomerLedgerScreen(customerId: customerId)),
      ),
    );
    await tester.pumpAndSettle();

    // Seçenek hiç sunulmamalı — hatayı yaptırıp sonra söylemek yerine.
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
