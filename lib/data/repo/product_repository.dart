import 'package:drift/drift.dart';

import '../../domain/core/quantity.dart';
import '../../domain/core/text_normalize.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'party_repository.dart';
import 'unit_of_work.dart';

/// Ürün kartı açma (SPEC §1, §13).
///
/// İki tür ürün vardır ve ikisi de aynı makineyi kullanır:
///
/// - **Sünger** (`M3`) — ölçüye göre varyantlanır, m³ ile fiyatlanır.
/// - **İnce malzeme** (`ADET`, `KG`, `KUTU`, `LITRE`, `METRE`) — çivi,
///   yapıştırıcı, zikzak yay, tela. Ölçüsü yoktur; tek varyantı olur ve
///   birim başına fiyatlanır.
///
/// Maliyet motoru değişmez: birim bazlı üründe `volume` kolonu **ürünün
/// kendi birimindeki miktarı**, `unitCostM3` ise **birim maliyetini**
/// taşır. Çarpım aynı kaldığı için FIFO ve ağırlıklı ortalama olduğu gibi
/// çalışır (D-22).
final class ProductRepository {
  final AppDatabase db;
  const ProductRepository(this.db);

  Future<String> create({
    required String name,
    required String unit,
    required OperationContext ctx,
    Rate? priceCoefficient,
    UnitPrice? defaultSalePrice,
    int criticalStockPieces = 0,
    String? note,
  }) => db.runOperation(ctx, () async {
    final id = uuid.v7();
    final clean = name.trim();

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: id,
            code: await _uniqueCode(clean),
            name: clean,
            nameNormalized: normalizeTurkish(clean),
            // Katsayı yalnızca süngerde anlamlı (SPEC §13); ince malzemede
            // 1,00 kalır.
            priceCoefficient: priceCoefficient ?? Rate.fromStored(10000),
            unit: Value(unit),
            defaultSalePriceM3: Value(defaultSalePrice),
            criticalStockPieces: Value(criticalStockPieces),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
          ),
        );

    // İnce malzemenin ölçüsü yoktur: varyantı burada, bir kez açılır.
    // Böylece alış/satış ekranı kullanıcıdan en/boy/kalınlık istemez.
    if (!ProductUnit.hasDimensions(unit)) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: uuid.v7(),
              productId: id,
              width: Dimension.fromStored(0),
              height: Dimension.fromStored(0),
              thickness: Dimension.fromStored(0),
              kind: VariantKind.plate,
              // Bir birim = 1. Miktar `volume` kolonunda bu ölçekle durur.
              unitVolume: Volume.parse('1'),
            ),
          );
    }

    await db.writeAudit(
      ctx,
      entityType: 'product',
      entityId: id,
      action: 'CREATE',
      summary: 'Ürün açıldı: $clean (${ProductUnit.label(unit)})',
    );
    return id;
  });

  /// İnce malzemenin tek varyantı.
  Future<ProductVariant> singleVariantOf(String productId) async =>
      (db.select(db.productVariants)
            ..where((v) => v.productId.equals(productId))
            ..limit(1))
          .getSingle();

  Future<String> _uniqueCode(String name) async {
    final base = PartyRepository.codeFromTitle(name);
    for (var i = 1; i < 1000; i++) {
      final candidate = i == 1 ? base : '$base$i';
      final clash = await (db.select(
        db.products,
      )..where((p) => p.code.equals(candidate))).getSingleOrNull();
      if (clash == null) return candidate;
    }
    return '$base-${uuid.v7().substring(0, 8)}';
  }
}
