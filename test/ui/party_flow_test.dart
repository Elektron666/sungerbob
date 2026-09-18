import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/party_repository.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/master/parties_screen.dart';
import 'package:sungerbob/ui/screens/purchase/purchase_screen.dart';

import '../data/test_db.dart';

/// Cari kartı olmadan uygulama hiçbir iş yapamıyordu: alış tedarikçi,
/// satış müşteri ister ve ikisini de açacak ekran yoktu. Bu testler
/// **boştan başlayıp iş yapabilmeyi** doğruluyor.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: MaterialApp(home: child),
  );

  group('Kod üretimi', () {
    test('unvandan okunabilir kod türetir', () {
      expect(PartyRepository.codeFromTitle('Öz Sünger A.Ş.'), 'OZSUNGERAS');
      expect(PartyRepository.codeFromTitle('Çınar Ticaret'), 'CINARTICAR');
    });

    test('harfsiz unvanda bile kod üretir', () {
      expect(PartyRepository.codeFromTitle('...'), 'CARI');
    });

    test('aynı unvandan ikinci kart çakışmaz', () async {
      final repo = PartyRepository(db);
      final a = await repo.createCustomer(
        title: 'Aynı Firma',
        ctx: OperationContext(commandType: 'T1'),
      );
      final b = await repo.createCustomer(
        title: 'Aynı Firma',
        ctx: OperationContext(commandType: 'T2'),
      );
      final rows = await db.select(db.customers).get();
      expect(rows.length, 2);
      expect(rows.map((c) => c.code).toSet().length, 2, reason: 'kod çakıştı');
      expect(a, isNot(b));
    });

    test('Türkçe arama için normalize kopya yazılır', () async {
      await PartyRepository(db).createSupplier(
        title: 'Şişli Sünger',
        type: SupplierType.factory,
        ctx: OperationContext(commandType: 'T'),
      );
      final row = await db.select(db.suppliers).getSingle();
      expect(row.titleNormalized, contains('sisli'));
    });
  });

  group('Tedarikçi ekranı', () {
    testWidgets('boşken yönlendirir, kart açılınca listeler', (tester) async {
      await tester.pumpWidget(wrap(const SuppliersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Henüz tedarikçi yok'), findsOneWidget);

      await tester.tap(find.text('Yeni tedarikçi'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Öz Sünger');
      await tester.pump();
      await tester.tap(find.text('Tedarikçi kartını aç'));
      await tester.pumpAndSettle();

      expect(find.text('Öz Sünger'), findsOneWidget);
      expect(find.text('Henüz tedarikçi yok'), findsNothing);
    });

    testWidgets('unvan boşken kaydetmez', (tester) async {
      await tester.pumpWidget(wrap(const SuppliersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni tedarikçi'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tedarikçi kartını aç'));
      await tester.pumpAndSettle();

      expect(find.text('Unvan girin'), findsOneWidget);
      expect(await db.select(db.suppliers).get(), isEmpty);
    });
  });

  group('Stok girişi', () {
    testWidgets('tedarikçi yokken açılır listeden kart açılabilir', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const PurchaseScreen()));
      await tester.pumpAndSettle();

      // Eski sürümde burada "Önce bir tedarikçi ekleyin" yazan ölü bir kart
      // vardı; kullanıcı stok girişi yapamıyordu.
      expect(find.text('Yeni tedarikçi ekle'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Yeni tedarikçi ekle'), findsOneWidget);

      await tester.tap(find.text('Yeni tedarikçi ekle').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Fabrika A');
      await tester.pump();
      await tester.tap(find.text('Tedarikçi kartını aç'));
      await tester.pumpAndSettle();

      // Kart açıldı ve seçili geldi.
      expect(await db.select(db.suppliers).get(), hasLength(1));
      expect(find.text('Fabrika A'), findsWidgets);
    });
  });
}
