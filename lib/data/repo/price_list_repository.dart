import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/core/quantity.dart';
import '../../domain/core/rounding.dart';
import '../../domain/core/scales.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Yeni fiyat listesi versiyonu önizlemesi: eski ↔ yeni karşılaştırma.
final class PricePreviewRow {
  final String productId;
  final String productName;
  final UnitPrice? oldPrice;
  final UnitPrice newPrice;

  const PricePreviewRow({
    required this.productId,
    required this.productName,
    required this.newPrice,
    this.oldPrice,
  });

  Decimal? get changePercent {
    if (oldPrice == null || oldPrice!.isZero) return null;
    return ((newPrice.perM3 - oldPrice!.perM3) / oldPrice!.perM3).toDecimal(
          scaleOnInfinitePrecision: 6,
        ) *
        Decimal.fromInt(100);
  }
}

/// Fiyat listesi (SPEC §13, §30.11).
///
/// Fiyat = baz TL/m³ × ürün katsayısı, ardından yuvarlama kuralı.
/// **Eski versiyonlar silinmez**, `ARCHIVED` olur; geçmiş satışlar kendi
/// versiyonuna referans verdiği için geçmiş kâr etkilenmez.
final class PriceListRepository {
  final AppDatabase db;
  const PriceListRepository(this.db);

  /// Onaydan önce gösterilecek karşılaştırma (BRIEF §5).
  Future<List<PricePreviewRow>> preview({
    required UnitPrice basePrice,
    String roundingRule = RoundingRule.none,
    Map<String, UnitPrice> manualPrices = const {},
  }) async {
    final products = await (db.select(
      db.products,
    )..where((p) => p.isActive.equals(true))).get();

    final active = await _activeList();
    final currentItems = active == null
        ? <String, UnitPrice>{}
        : {
            for (final i in await (db.select(
              db.priceListItems,
            )..where((i) => i.priceListId.equals(active.id))).get())
              i.productId: i.effectivePriceM3,
          };

    return [
      for (final p in products)
        PricePreviewRow(
          productId: p.id,
          productName: p.name,
          oldPrice: currentItems[p.id],
          newPrice:
              manualPrices[p.id] ??
              _applyRounding(
                _computed(basePrice, p.priceCoefficient),
                roundingRule,
              ),
        ),
    ];
  }

  /// Yeni versiyon oluşturur; önceki versiyon arşivlenir.
  Future<String> createVersion({
    required UnitPrice basePrice,
    required String name,
    required DateTime validFrom,
    required OperationContext ctx,
    String roundingRule = RoundingRule.none,
    Map<String, UnitPrice> manualPrices = const {},
  }) => db.runOperation(ctx, () async {
    final previous = await _activeList();
    final versionNo = (previous?.versionNo ?? 0) + 1;
    final listId = uuid.v7();

    await db
        .into(db.priceLists)
        .insert(
          PriceListsCompanion.insert(
            id: listId,
            versionNo: versionNo,
            name: name,
            basePriceM3: basePrice,
            roundingRule: Value(roundingRule),
            validFrom: validFrom.millisecondsSinceEpoch,
            status: 'ACTIVE',
            createdAt: ctx.nowMs,
            createdBy: Value(ctx.userId),
          ),
        );

    final products = await (db.select(
      db.products,
    )..where((p) => p.isActive.equals(true))).get();

    for (final p in products) {
      final computed = _applyRounding(
        _computed(basePrice, p.priceCoefficient),
        roundingRule,
      );
      final manual = manualPrices[p.id];

      await db
          .into(db.priceListItems)
          .insert(
            PriceListItemsCompanion.insert(
              id: uuid.v7(),
              priceListId: listId,
              productId: p.id,
              // Katsayı versiyona KOPYALANIR: ürün katsayısı sonradan
              // değişse bile geçmiş versiyon aynı kalır.
              coefficient: p.priceCoefficient,
              computedPriceM3: computed,
              manualPriceM3: Value(manual),
              effectivePriceM3: manual ?? computed,
            ),
          );
    }

    // Önceki versiyon arşivlenir — SİLİNMEZ (SPEC §30.11).
    if (previous != null) {
      await (db.update(db.priceLists)..where((l) => l.id.equals(previous.id)))
          .write(const PriceListsCompanion(status: Value('ARCHIVED')));
    }

    await db.writeAudit(
      ctx,
      entityType: 'price_list',
      entityId: listId,
      action: 'CREATE',
      summary: 'Fiyat listesi v$versionNo, baz $basePrice',
    );

    return listId;
  });

  Future<PriceList?> _activeList() =>
      (db.select(db.priceLists)
            ..where((l) => l.status.equals('ACTIVE'))
            ..orderBy([(l) => OrderingTerm.desc(l.versionNo)])
            ..limit(1))
          .getSingleOrNull();

  /// Ürün m³ fiyatı = baz × katsayı (SPEC §13).
  ///
  /// Katsayı ×10.000 saklanır (1,00 → 10000) ve `Rate.fraction` tam olarak bu
  /// çarpanı verir: 10000 → 1,0 · 14000 → 1,4 · 19100 → 1,91.
  static UnitPrice _computed(UnitPrice base, Rate coefficient) =>
      UnitPrice.fromDecimal(
        roundHalfUp(base.perM3 * coefficient.fraction, Scales.unitPrice),
      );

  /// Yuvarlama kuralı: yok / en yakın 1, 5, 10 TL (BRIEF §5).
  static UnitPrice _applyRounding(UnitPrice price, String rule) {
    final step = switch (rule) {
      RoundingRule.nearest1 => 1,
      RoundingRule.nearest5 => 5,
      RoundingRule.nearest10 => 10,
      _ => 0,
    };
    if (step == 0) return price;

    final divided = (price.perM3 / Decimal.fromInt(step)).toDecimal(
      scaleOnInfinitePrecision: 12,
    );
    return UnitPrice.fromDecimal(
      roundHalfUp(divided, 0) * Decimal.fromInt(step),
    );
  }

  /// SPEC §14: plaka fiyatı = en(m) × boy(m) × kalınlık(m) × m³ fiyatı.
  static UnitPrice platePrice({
    required UnitPrice pricePerM3,
    required Volume unitVolume,
  }) => UnitPrice.fromDecimal(
    roundHalfUp(pricePerM3.perM3 * unitVolume.m3, Scales.unitPrice),
  );
}
