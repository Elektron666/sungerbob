import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/quote_repository.dart';
import 'package:sungerbob/data/repo/search_queries.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

Future<void> seedStock(ScenarioFixture f) => PurchaseRepository(f.db).create(
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

QuoteInput quoteOf(ScenarioFixture f, int pieces) => QuoteInput(
  customerId: f.customerId,
  docDate: DateTime.utc(2026, 9, 10),
  validUntil: DateTime.utc(2026, 9, 30),
  priceMode: PriceMode.excl,
  lines: [
    QuoteLineInput(
      variantId: f.v10,
      pieces: pieces,
      volume: f.volumeOf('140', '200', '10', pieces),
      unitPriceM3: UnitPrice.parse('3500'),
      vatRate: vat20,
    ),
  ],
);

void main() {
  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  group('Teklif (SPEC §15)', () {
    test('teklif oluşturmak stoktan ürün DÜŞMEZ', () async {
      await seedStock(f);
      final before = await f.db.variantStock(f.v10);

      await QuoteRepository(f.db)
          .create(quoteOf(f, 10), ctxFor('QUOTE_CREATE'));

      final after = await f.db.variantStock(f.v10);
      expect(
        after.pieces,
        before.pieces,
        reason: 'teklif stok düşürmemeli (SPEC §15)',
      );
      expect(
        await f.db.customerBalance(f.customerId),
        Money.zero,
        reason: 'teklif cariye yazılmamalı',
      );
    });

    test('teklif tutarları KDV ile doğru hesaplanıyor', () async {
      await seedStock(f);
      final quoteId = await QuoteRepository(f.db)
          .create(quoteOf(f, 10), ctxFor('QUOTE_CREATE'));

      final quote = await (f.db.select(
        f.db.salesQuotes,
      )..where((q) => q.id.equals(quoteId))).getSingle();

      // 10 adet × 0,28 m³ = 2,8 m³ × 3.500 = 9.800 net + 1.960 KDV
      expect(quote.subtotalNet, Money.parse('9800'));
      expect(quote.vatTotal, Money.parse('1960'));
      expect(quote.grandTotal, Money.parse('11760'));
      expect(quote.docNo, startsWith('TKL-'));
    });

    test('satışa dönüştürünce stok düşer ve cari yazılır', () async {
      await seedStock(f);
      final quoteId = await QuoteRepository(f.db)
          .create(quoteOf(f, 10), ctxFor('QUOTE_CREATE'));

      final saleId = await QuoteRepository(f.db).convertToSale(
        quoteId: quoteId,
        docDate: DateTime.utc(2026, 9, 12),
        ctx: ctxFor('QUOTE_CONVERT'),
      );

      expect((await f.db.variantStock(f.v10)).pieces, 40);
      expect(await f.db.customerBalance(f.customerId), Money.parse('11760'));

      final sale = await (f.db.select(
        f.db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      expect(sale.salesQuoteId, quoteId);
      expect(sale.subtotalNet, Money.parse('9800'));
      // 2,8 m³ × 3.000 TL/m³
      expect(sale.costTotal, Money.parse('8400'));

      // Teklif SİLİNMEZ, CONVERTED olur ve satışa referans verir.
      final quote = await (f.db.select(
        f.db.salesQuotes,
      )..where((q) => q.id.equals(quoteId))).getSingle();
      expect(quote.status, QuoteStatus.converted);
      expect(quote.convertedSaleId, saleId);
    });

    test('aynı teklif iki kez satışa dönüştürülemez', () async {
      await seedStock(f);
      final quoteId = await QuoteRepository(f.db)
          .create(quoteOf(f, 10), ctxFor('QUOTE_CREATE'));

      await QuoteRepository(f.db)
          .convertToSale(quoteId: quoteId, ctx: ctxFor('CONVERT_1'));

      await expectLater(
        QuoteRepository(f.db)
            .convertToSale(quoteId: quoteId, ctx: ctxFor('CONVERT_2')),
        throwsA(isA<QuoteAlreadyConvertedException>()),
      );
      expect(
        (await f.db.variantStock(f.v10)).pieces,
        40,
        reason: 'stok yalnızca bir kez düşmeli',
      );
    });

    test('geçerlilik tarihi geçen teklifler EXPIRED olur', () async {
      await seedStock(f);
      final quoteId = await QuoteRepository(f.db)
          .create(quoteOf(f, 10), ctxFor('QUOTE_CREATE'));
      await QuoteRepository(f.db).setStatus(
        quoteId: quoteId,
        status: QuoteStatus.sent,
        ctx: ctxFor('SEND'),
      );

      final count = await QuoteRepository(f.db)
          .expireOverdue(now: DateTime.utc(2026, 10, 1));
      expect(count, 1);

      final quote = await (f.db.select(
        f.db.salesQuotes,
      )..where((q) => q.id.equals(quoteId))).getSingle();
      expect(quote.status, QuoteStatus.expired);
    });
  });

  group('Global arama (SPEC §21)', () {
    test('müşteri adıyla bulunur — Türkçe karakter duyarsız', () async {
      await f.db
          .into(f.db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'c-ozis',
              code: 'OZIS',
              title: 'Öziş Mobilya',
              titleNormalized: 'ozis mobilya',
            ),
          );

      // "ozis" yazınca "Öziş" bulunmalı.
      final hits = await f.db.globalSearch('ozis');
      expect(hits.any((h) => h.title == 'Öziş Mobilya'), isTrue);

      // "ÖZİŞ" de bulmalı.
      final hits2 = await f.db.globalSearch('ÖZİŞ');
      expect(hits2.any((h) => h.title == 'Öziş Mobilya'), isTrue);
    });

    test('ürün adıyla bulunur ve stok gösterir', () async {
      await seedStock(f);
      final hits = await f.db.globalSearch('beyaz');
      final product = hits.firstWhere((h) => h.kind == 'Ürün');
      expect(product.title, 'Beyaz Sünger');
      expect(product.subtitle, contains('50'));
    });

    test('SPEC örneği: "D32" ürünü bulur', () async {
      final hits = await f.db.globalSearch('D32');
      expect(hits.any((h) => h.title == 'D32 Gri'), isTrue);
    });

    test('belge numarasıyla satış bulunur', () async {
      await seedStock(f);
      final quoteId = await QuoteRepository(f.db)
          .create(quoteOf(f, 5), ctxFor('QUOTE_CREATE'));
      await QuoteRepository(f.db)
          .convertToSale(quoteId: quoteId, ctx: ctxFor('CONVERT'));

      final hits = await f.db.globalSearch('STS-2026');
      expect(hits.any((h) => h.kind == 'Satış'), isTrue);
    });

    test('boş sorgu boş sonuç döner', () async {
      expect(await f.db.globalSearch(''), isEmpty);
      expect(await f.db.globalSearch('   '), isEmpty);
    });
  });
}
