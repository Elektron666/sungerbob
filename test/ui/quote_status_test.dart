import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/quote_repository.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';
import 'package:sungerbob/ui/format/tr_format.dart';
import 'package:sungerbob/ui/providers/app_providers.dart';
import 'package:sungerbob/ui/screens/ops/quotes_screen.dart';

import '../data/test_db.dart';

/// **Teklif durumu işaretlenebiliyor mu?**
///
/// `setStatus` Faz 3'ten beri yazılıydı ama hiçbir ekrandan çağrılmıyordu:
/// liste sonsuza kadar "Taslak" görünüyordu (SK-22). Geçiş kuralı hem
/// ekranda hem repository'de duruyor — ekranın izin verilmeyeni
/// göstermemesi, iş kuralının kendisi değildir.
void main() {
  setUpAll(() async => TrFormat.ensureInitialized());

  late AppDatabase db;
  setUp(() => db = newTestDatabase());
  tearDown(() async => db.close());

  /// Ekranlara dokunmadan bir teklif yazar (durum akışını sınıyoruz).
  Future<String> seedQuote() async {
    final customerId = uuid.v7();
    await db.customStatement(
      "INSERT INTO customers (id, code, title, title_normalized, "
      'default_discount_rate, risk_limit, payment_term_days, is_active) '
      "VALUES ('$customerId', 'M1', 'Mobilyacı Ahmet', 'mobilyaci ahmet', "
      '0, 0, 0, 1)',
    );

    final product = await db.select(db.products).get();
    final variantId = uuid.v7();
    await db.customStatement(
      'INSERT INTO product_variants (id, product_id, width, height, '
      'thickness, kind, unit_volume, critical_stock_pieces, is_active) '
      "VALUES ('$variantId', '${product.first.id}', 14000, 20000, 1000, "
      "'PLAKA', 280000, 0, 1)",
    );

    return QuoteRepository(db).create(
      QuoteInput(
        customerId: customerId,
        docDate: DateTime.now(),
        priceMode: PriceMode.excl,
        lines: [
          QuoteLineInput(
            variantId: variantId,
            pieces: 1,
            volume: Volume.parse('0.28'),
            unitPriceM3: UnitPrice.parse('3500'),
            vatRate: Rate.percent('20'),
          ),
        ],
      ),
      OperationContext(commandType: 'QUOTE_CREATE'),
    );
  }

  group('Durum geçiş kuralı', () {
    test('taslak → gönderildi → kabul edildi', () async {
      final id = await seedQuote();
      final repo = QuoteRepository(db);

      await repo.setStatus(
        quoteId: id,
        status: QuoteStatus.sent,
        ctx: OperationContext(commandType: 'QUOTE_STATUS'),
      );
      await repo.setStatus(
        quoteId: id,
        status: QuoteStatus.accepted,
        ctx: OperationContext(commandType: 'QUOTE_STATUS'),
      );

      final quote = await db.select(db.salesQuotes).getSingle();
      expect(quote.status, QuoteStatus.accepted);
    });

    test('taslaktan doğrudan kabule atlanamaz', () async {
      final id = await seedQuote();
      await expectLater(
        QuoteRepository(db).setStatus(
          quoteId: id,
          status: QuoteStatus.accepted,
          ctx: OperationContext(commandType: 'QUOTE_STATUS'),
        ),
        throwsA(isA<InvalidQuoteTransitionException>()),
      );
      final quote = await db.select(db.salesQuotes).getSingle();
      expect(quote.status, QuoteStatus.draft);
    });

    test('satışa çevirme elle işaretlenemez', () async {
      // CONVERTED stok ve cari hareketi üretir; durum atlanarak elde
      // edilemez.
      final id = await seedQuote();
      await expectLater(
        QuoteRepository(db).setStatus(
          quoteId: id,
          status: QuoteStatus.converted,
          ctx: OperationContext(commandType: 'QUOTE_STATUS'),
        ),
        throwsA(isA<InvalidQuoteTransitionException>()),
      );
    });
  });

  testWidgets('ekran yalnızca izin verilen geçişi gösterir', (tester) async {
    await seedQuote();

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
        MaterialPageRoute<void>(builder: (_) => const QuotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Taslak'), findsNothing, reason: 'durum satırda yazılı');
    expect(find.textContaining('Taslak'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Taslakta yalnızca "Gönderildi" olmalı; kabul/ret henüz sunulmamalı.
    expect(find.text('Gönderildi'), findsOneWidget);
    expect(find.text('Kabul edildi'), findsNothing);
    expect(find.text('Reddedildi'), findsNothing);

    await tester.tap(find.text('Gönderildi'));
    await tester.pumpAndSettle();

    final quote = await db.select(db.salesQuotes).getSingle();
    expect(quote.status, QuoteStatus.sent);

    // Artık kabul ve ret sunulmalı.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Kabul edildi'), findsOneWidget);
    expect(find.text('Reddedildi'), findsOneWidget);
  });
}
