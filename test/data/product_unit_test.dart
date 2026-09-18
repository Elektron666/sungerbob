import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/db/enums.dart';
import 'package:sungerbob/data/repo/dashboard_queries.dart';
import 'package:sungerbob/data/repo/product_repository.dart';
import 'package:sungerbob/data/repo/purchase_repository.dart';
import 'package:sungerbob/data/repo/stock_queries.dart';
import 'package:sungerbob/data/repo/unit_of_work.dart';
import 'package:sungerbob/domain/core/quantity.dart';
import 'package:sungerbob/domain/service/vat.dart';

import '../golden_scenario/scenario_fixture.dart';

/// İnce malzeme (çivi, yapıştırıcı, zikzak yay) — D-22.
///
/// Sünger m³ ile döner, ince malzeme kendi birimiyle. İkisi aynı maliyet
/// motorunu kullanır ama **m³ toplamlarına yalnızca sünger girer**:
/// 50 kg tutkalı 11 m³ süngere eklemek toplamı anlamsız kılar.
void main() {
  final vat = Rate.percent('20');
  OperationContext ctx(String t) => OperationContext(commandType: t);

  late ScenarioFixture f;
  setUp(() async => f = await ScenarioFixture.create());
  tearDown(() async => f.close());

  group('Birim tanımı', () {
    test('ölçü yalnızca m³ üründe sorulur', () {
      expect(ProductUnit.hasDimensions(ProductUnit.m3), isTrue);
      for (final u in [
        ProductUnit.piece,
        ProductUnit.kilogram,
        ProductUnit.box,
        ProductUnit.litre,
        ProductUnit.metre,
      ]) {
        expect(ProductUnit.hasDimensions(u), isFalse, reason: u);
      }
    });

    test('etiketler Türkçe ve kısa', () {
      expect(ProductUnit.label(ProductUnit.m3), 'm³');
      expect(ProductUnit.label(ProductUnit.kilogram), 'kg');
      expect(ProductUnit.priceLabel(ProductUnit.piece), 'TL/adet');
      expect(ProductUnit.priceLabel(ProductUnit.m3), 'TL/m³');
    });
  });

  group('Ürün kartı', () {
    test('seed ürünlerin tamamı m³', () async {
      final products = await f.db.select(f.db.products).get();
      expect(products, isNotEmpty);
      expect(products.every((p) => p.unit == ProductUnit.m3), isTrue);
    });

    test('ince malzeme açılır ve tek varyantı hazır gelir', () async {
      final repo = ProductRepository(f.db);
      final id = await repo.create(
        name: 'Sünger Yapıştırıcı',
        unit: ProductUnit.kilogram,
        ctx: ctx('PRODUCT_CREATE'),
      );

      final product = await (f.db.select(
        f.db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(product.unit, ProductUnit.kilogram);

      // Ölçüsü olmadığı için varyant kart açılışında oluşur.
      final variant = await repo.singleVariantOf(id);
      expect(variant.width.stored, 0);
      expect(variant.unitVolume, Volume.parse('1'));
    });

    test(
      'sünger üründe varyant önceden açılmaz (ölçüye göre oluşur)',
      () async {
        final id = await ProductRepository(f.db).create(
          name: 'Gri Sünger',
          unit: ProductUnit.m3,
          ctx: ctx('PRODUCT_CREATE'),
        );
        final variants = await (f.db.select(
          f.db.productVariants,
        )..where((v) => v.productId.equals(id))).get();
        expect(variants, isEmpty);
      },
    );

    test('aynı addan ikinci ürün kod çakıştırmaz', () async {
      final repo = ProductRepository(f.db);
      await repo.create(name: 'Çivi', unit: ProductUnit.piece, ctx: ctx('P1'));
      await repo.create(name: 'Çivi', unit: ProductUnit.piece, ctx: ctx('P2'));
      final codes = (await f.db.select(f.db.products).get())
          .map((p) => p.code)
          .toList();
      expect(codes.toSet().length, codes.length, reason: 'kod çakıştı');
    });
  });

  group('İnce malzeme stoğu', () {
    /// Tutkal alışı: 50 kg, 120 TL/kg.
    Future<String> buyGlue() async {
      final repo = ProductRepository(f.db);
      final productId = await repo.create(
        name: 'Sünger Yapıştırıcı',
        unit: ProductUnit.kilogram,
        ctx: ctx('PRODUCT_CREATE'),
      );
      final variant = await repo.singleVariantOf(productId);

      await PurchaseRepository(f.db).create(
        PurchaseInput(
          supplierId: f.supplierId,
          docDate: DateTime.utc(2026, 9, 1),
          priceMode: PriceMode.excl,
          lines: [
            PurchaseLineInput(
              variantId: variant.id,
              pieces: 50,
              // Miktar kendi biriminde: 50 kg.
              volume: Volume.parse('50'),
              unitPriceM3: UnitPrice.parse('120'),
              vatRate: vat,
            ),
          ],
        ),
        ctx('PURCHASE_CREATE'),
      );
      return variant.id;
    }

    test('maliyet motoru birim bazlı üründe de çalışır', () async {
      final variantId = await buyGlue();
      final stock = await f.db.variantStock(variantId);

      expect(stock.pieces, 50);
      expect(stock.volume, Volume.parse('50'));

      // 50 kg × 120 TL/kg = 6.000 TL
      final batch = await (f.db.select(
        f.db.inventoryBatches,
      )..where((b) => b.variantId.equals(variantId))).getSingle();
      expect(
        batch.realUnitCostM3.times(batch.remainingVolume).tl.toString(),
        '6000',
      );
    });

    test('TUTKAL m³ TOPLAMINA KARIŞMAZ', () async {
      // Önce sünger al.
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
              unitPriceM3: UnitPrice.parse('2500'),
              vatRate: vat,
            ),
          ],
        ),
        ctx('PURCHASE_CREATE'),
      );

      final foamOnly = (await f.db.dashboardSnapshot()).totalStockVolume;

      // Sonra 50 kg tutkal al.
      await buyGlue();
      final afterGlue = (await f.db.dashboardSnapshot()).totalStockVolume;

      expect(
        afterGlue,
        foamOnly,
        reason: '50 kg tutkal m³ toplamına eklenmiş — toplam anlamsızlaşır',
      );
      // 140×200×10 cm × 10 adet = 2,8 m³
      expect(foamOnly, Volume.parse('2.8'));
    });
  });
}
