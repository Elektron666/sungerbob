import '../../domain/core/quantity.dart';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Ölçü bazlı varyant bulma/oluşturma.
///
/// Sünger çeşidi (ürün) sabittir; ölçüler ise iş aktıkça çeşitlenir. Aynı
/// ölçü ikinci kez girildiğinde yeni varyant açılmaz — aksi hâlde stok
/// matrisi aynı hücreyi iki kez gösterirdi.
extension VariantHelper on AppDatabase {
  Future<String> ensureVariant({
    required String productId,
    required Dimension width,
    required Dimension height,
    required Dimension thickness,
    String kind = VariantKind.plate,
  }) async {
    final existing =
        await (select(productVariants)..where(
              (v) =>
                  v.productId.equals(productId) &
                  v.width.equals(width.stored) &
                  v.height.equals(height.stored) &
                  v.thickness.equals(thickness.stored),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    final id = uuid.v7();
    await into(productVariants).insert(
      ProductVariantsCompanion.insert(
        id: id,
        productId: productId,
        width: width,
        height: height,
        thickness: thickness,
        kind: kind,
        unitVolume: Volume.fromDimensions(
          width: width,
          height: height,
          thickness: thickness,
          pieces: 1,
        ),
      ),
    );
    return id;
  }
}
