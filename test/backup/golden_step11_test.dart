import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/app_database.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/collection_repository.dart';
import 'package:sungerbob/data/repo/instrument_repository.dart';
import 'package:sungerbob/data/repo/integrity_service.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/return_repository.dart';
import 'package:sungerbob/data/repo/reversal_repository.dart';
import 'package:sungerbob/data/repo/sale_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import 'backup_fixture.dart';

final vat20 = Rate.percent('20');
OperationContext ctxFor(String t) => OperationContext(commandType: t);

Volume vol(String w, String h, String t, int pieces) => Volume.fromDimensions(
  width: Dimension.cm(w),
  height: Dimension.cm(h),
  thickness: Dimension.cm(t),
  pieces: pieces,
);

/// ALTIN SENARYO ADIM 11 (docs/GOLDEN_SCENARIO.md)
///
/// "Bu noktada yedek al → veritabanını sil → yedeği yükle → 1–10. adımlardaki
/// tüm bakiyeler, stoklar ve maliyetler birebir aynı."
void main() {
  test(
    'adım 11 — yedek/geri yükleme sonrası bakiye, stok ve maliyetler aynı',
    () async {
      final f = await BackupFixture.create();
      try {
        // --- Kurulum: senaryonun aktörleri ------------------------------
        final beyaz = await (f.db.select(
          f.db.products,
        )..where((p) => p.code.equals('BEYAZ'))).getSingle();

        Future<String> variant(String w, String h, String t) async {
          final id = uuid.v7();
          await f.db
              .into(f.db.productVariants)
              .insert(
                ProductVariantsCompanion.insert(
                  id: id,
                  productId: beyaz.id,
                  width: Dimension.cm(w),
                  height: Dimension.cm(h),
                  thickness: Dimension.cm(t),
                  kind: VariantKind.plate,
                  unitVolume: vol(w, h, t, 1),
                ),
              );
          return id;
        }

        final v10 = await variant('140', '200', '10');
        final v5 = await variant('140', '200', '5');
        final v8 = await variant('140', '200', '8');

        const customerId = 'abc-mobilya';
        await f.db
            .into(f.db.customers)
            .insert(
              CustomersCompanion.insert(
                id: customerId,
                code: 'ABC',
                title: 'ABC Mobilya',
                titleNormalized: 'abc mobilya',
              ),
            );

        const supplierId = 'fabrika';
        await f.db
            .into(f.db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: supplierId,
                code: 'FAB',
                title: 'Sünger Fabrikası',
                titleNormalized: 'sunger fabrikasi',
                type: SupplierType.factory,
              ),
            );

        final cash = await (f.db.select(
          f.db.cashAccounts,
        )..where((a) => a.code.equals('KASA'))).getSingle();

        final purchases = PurchaseRepository(f.db);
        final sales = SaleRepository(f.db);
        final collections = CollectionRepository(f.db);

        // --- Adım 1–2: alışlar ------------------------------------------
        await purchases.create(
          PurchaseInput(
            supplierId: supplierId,
            docDate: DateTime.utc(2026, 9, 1),
            priceMode: PriceMode.excl,
            lines: [
              PurchaseLineInput(
                variantId: v10,
                pieces: 50,
                volume: vol('140', '200', '10', 50),
                unitPriceM3: UnitPrice.parse('2930'),
                vatRate: vat20,
              ),
              PurchaseLineInput(
                variantId: v5,
                pieces: 40,
                volume: vol('140', '200', '5', 40),
                unitPriceM3: UnitPrice.parse('2930'),
                vatRate: vat20,
              ),
            ],
            expenses: const [
              PurchaseExpenseInput(kind: 'NAKLIYE', amount: Money(196000)),
            ],
          ),
          ctxFor('PURCHASE_CREATE'),
        );
        await purchases.create(
          PurchaseInput(
            supplierId: supplierId,
            docDate: DateTime.utc(2026, 9, 15),
            priceMode: PriceMode.excl,
            lines: [
              PurchaseLineInput(
                variantId: v10,
                pieces: 30,
                volume: vol('140', '200', '10', 30),
                unitPriceM3: UnitPrice.parse('3165'),
                vatRate: vat20,
              ),
            ],
          ),
          ctxFor('PURCHASE_CREATE'),
        );

        // --- Adım 3: satış ----------------------------------------------
        final saleId = await sales.create(
          SaleInput(
            customerId: customerId,
            docDate: DateTime.utc(2026, 9, 17),
            dueDate: DateTime.utc(2026, 10, 17),
            priceMode: PriceMode.excl,
            lines: [
              SaleLineInput(
                variantId: v10,
                pieces: 60,
                volume: vol('140', '200', '10', 60),
                unitPriceM3: UnitPrice.parse('3500'),
                vatRate: vat20,
              ),
            ],
          ),
          ctxFor('SALE_CREATE'),
        );

        // --- Adım 4: tahsilat -------------------------------------------
        final collectionId = await collections.create(
          CollectionInput(
            customerId: customerId,
            docDate: DateTime.utc(2026, 9, 20),
            amount: Money.parse('30000'),
            method: PaymentMethod.transfer,
            cashAccountId: cash.id,
          ),
          ctxFor('COLLECTION_CREATE'),
        );

        // --- Adım 5: yeni alış ------------------------------------------
        await purchases.create(
          PurchaseInput(
            supplierId: supplierId,
            docDate: DateTime.utc(2026, 9, 18),
            priceMode: PriceMode.excl,
            lines: [
              PurchaseLineInput(
                variantId: v8,
                pieces: 5,
                volume: vol('140', '200', '8', 5),
                unitPriceM3: UnitPrice.parse('3300'),
                vatRate: vat20,
              ),
            ],
          ),
          ctxFor('PURCHASE_CREATE'),
        );

        // --- Adım 8: iade -----------------------------------------------
        final saleItem = await (f.db.select(
          f.db.saleItems,
        )..where((i) => i.saleId.equals(saleId))).getSingle();
        await ReturnRepository(f.db).createSaleReturn(
          SaleReturnInput(
            saleId: saleId,
            docDate: DateTime.utc(2026, 9, 25),
            lines: [SaleReturnLineInput(saleItemId: saleItem.id, pieces: 5)],
          ),
          ctxFor('SALE_RETURN_CREATE'),
        );

        // --- Adım 9: tahsilat iptali ------------------------------------
        await ReversalRepository(f.db).cancelCollection(
          collectionId: collectionId,
          reason: 'Yanlış müşteri',
          ctx: ctxFor('COLLECTION_CANCEL'),
        );

        // --- Adım 10: çek ve karşılıksız --------------------------------
        final checkCollection = await collections.create(
          CollectionInput(
            customerId: customerId,
            docDate: DateTime.utc(2026, 9, 28),
            amount: Money.parse('20000'),
            method: PaymentMethod.check,
            instrument: InstrumentInput(
              kind: InstrumentKind.check,
              dueDate: DateTime.utc(2026, 10, 30),
              serialNo: '0012345',
            ),
          ),
          ctxFor('COLLECTION_CREATE'),
        );
        final instrumentId =
            (await (f.db.select(
                  f.db.collections,
                )..where((c) => c.id.equals(checkCollection))).getSingle())
                .instrumentId!;
        await InstrumentRepository(f.db).changeStatus(
          instrumentId: instrumentId,
          toStatus: InstrumentStatus.bounced,
          ctx: ctxFor('INSTRUMENT_STATUS'),
        );

        // --- Yedek öncesi durum -----------------------------------------
        final balanceBefore = await f.db.customerBalance(customerId);
        final supplierBefore = await f.db.supplierBalance(supplierId);
        final accountBefore = await f.db.accountBalance(cash.id);
        final portfolioBefore = await f.db.instrumentPortfolioTotal();
        final stockCostBefore = await f.db.stockCostTotal();
        final stock10Before = await f.db.variantStock(v10);
        final stock5Before = await f.db.variantStock(v5);
        final stock8Before = await f.db.variantStock(v8);
        final saleBefore = await (f.db.select(
          f.db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        final digestBefore = await f.contentDigest();

        // Senaryonun beklediği rakamlar yerinde mi?
        expect(balanceBefore, Money.parse('64680'));
        expect(portfolioBefore, Money.zero);

        // --- ADIM 11: yedek al → veritabanını sil → yükle ---------------
        final backup = await f.service.createBackup(
          password: 'kagida-yazdigim-sifre',
        );

        await f.closeDatabase();
        f.databaseFile.deleteSync();
        await f.reopen();
        expect(
          (await f.db.select(f.db.sales).get()),
          isEmpty,
          reason: 'veritabanı gerçekten silinmiş olmalı',
        );

        await f.service.restore(
          file: backup.file,
          password: 'kagida-yazdigim-sifre',
          closeDatabase: f.closeDatabase,
        );
        await f.reopen();

        // --- Birebir aynı mı? -------------------------------------------
        expect(await f.db.customerBalance(customerId), balanceBefore);
        expect(await f.db.supplierBalance(supplierId), supplierBefore);
        expect(await f.db.accountBalance(cash.id), accountBefore);
        expect(await f.db.instrumentPortfolioTotal(), portfolioBefore);
        expect(await f.db.stockCostTotal(), stockCostBefore);

        final stock10After = await f.db.variantStock(v10);
        expect(stock10After.pieces, stock10Before.pieces);
        expect(stock10After.volume, stock10Before.volume);
        expect((await f.db.variantStock(v5)).volume, stock5Before.volume);
        expect((await f.db.variantStock(v8)).volume, stock8Before.volume);

        final saleAfter = await (f.db.select(
          f.db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        expect(saleAfter.costTotal, saleBefore.costTotal);
        expect(saleAfter.grandTotal, saleBefore.grandTotal);
        expect(saleAfter.docNo, saleBefore.docNo);

        // Tüm tabloların içeriği birebir.
        final digestAfter = await f.contentDigest();
        for (final table in digestBefore.keys) {
          expect(
            digestAfter[table],
            digestBefore[table],
            reason: '$table tablosu birebir aynı olmalı',
          );
        }

        // Geri yükleme sonrası tutarlılık kontrolü otomatik çalışır ve
        // fark bulmamalı (BRIEF §3.5).
        final report = await IntegrityService(f.db).check();
        expect(report.isClean, isTrue, reason: report.findings.join('\n'));
      } finally {
        await f.dispose();
      }
    },
  );
}
