import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/enums.dart';
import '../../data/repo/stock_queries.dart';
import '../../domain/core/quantity.dart';
import '../../domain/core/text_normalize.dart';
import '../format/tr_format.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Stokta bulunan bir varyantı seçtirir.
///
/// Fire, sayım ve kesim ekranlarının üçü de "hangi ölçüden, kaç adet"
/// sorusuyla başlar. **Yalnızca stokta olan** varyantlar listelenir —
/// negatif stok yasak olduğu için olmayan maldan fire veya kesim çıkamaz.
class InStockVariant {
  final String variantId;
  final String productName;

  /// Sünger için "200×100×5", ince malzeme için boş — ölçüsü yoktur (D-22).
  final String label;
  final int pieces;
  final Volume volume;

  /// Ürünün birimi (`ProductUnit`). Miktar hep aynı kolonda durduğu için
  /// ekranda doğru birimi yazmak buna bağlı.
  final String unit;

  const InStockVariant({
    required this.variantId,
    required this.productName,
    required this.label,
    required this.pieces,
    required this.volume,
    this.unit = ProductUnit.m3,
  });

  bool get isFoam => ProductUnit.hasDimensions(unit);

  /// Listede görünen tam ad: "Beyaz Sünger · 200×100×5" veya "Tutkal".
  String get title => label.isEmpty ? productName : '$productName · $label';

  /// "12 adet · 2,8 m³" / ince malzemede yalnızca "50 kg".
  String get quantityText => isFoam
      ? '${TrFormat.pieces(pieces)} · ${TrFormat.volume(volume)}'
      : TrFormat.quantity(volume, unit);

  /// Bu üründen [count] kadarını ürünün kendi birimiyle yazar:
  /// süngerde "5 adet", tutkalda "5 kg".
  String amount(int count) =>
      isFoam ? TrFormat.pieces(count) : '$count ${ProductUnit.label(unit)}';

  /// Miktar alanlarının etiketi: "Adet" / "Miktar (kg)".
  String get amountLabel =>
      isFoam ? 'Adet' : 'Miktar (${ProductUnit.label(unit)})';
}

final inStockVariantsProvider = FutureProvider.autoDispose
    .family<List<InStockVariant>, String>((ref, locationCode) async {
      final db = await ref.watch(databaseProvider.future);

      final products =
          await (db.select(db.products)
                ..where((p) => p.isActive.equals(true))
                ..orderBy([(p) => OrderingTerm.asc(p.name)]))
              .get();
      final names = {for (final p in products) p.id: p.name};
      final units = {for (final p in products) p.id: p.unit};

      final variants = await db.select(db.productVariants).get();
      final result = <InStockVariant>[];

      for (final variant in variants) {
        final stock = await db.variantStock(
          variant.id,
          locationCode: locationCode,
        );
        if (stock.pieces == 0) continue;

        final unit = units[variant.productId] ?? ProductUnit.m3;
        result.add(
          InStockVariant(
            variantId: variant.id,
            productName: names[variant.productId] ?? '—',
            label: ProductUnit.hasDimensions(unit)
                ? TrFormat.dimensions(
                    variant.width,
                    variant.height,
                    variant.thickness,
                  )
                : '',
            pieces: stock.pieces,
            volume: stock.volume,
            unit: unit,
          ),
        );
      }

      result.sort((a, b) {
        final byProduct = a.productName.compareTo(b.productName);
        return byProduct != 0 ? byProduct : a.label.compareTo(b.label);
      });
      return result;
    });

/// Stoktaki varyantları listeleyen seçim sayfası.
///
/// Seçilen varyantı döndürür; iptalde `null`.
Future<InStockVariant?> pickInStockVariant(
  BuildContext context, {
  String locationCode = LocationCode.mainWarehouse,
}) => showModalBottomSheet<InStockVariant>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _VariantSheet(locationCode: locationCode),
);

class _VariantSheet extends ConsumerStatefulWidget {
  final String locationCode;
  const _VariantSheet({required this.locationCode});

  @override
  ConsumerState<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends ConsumerState<_VariantSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final variants = ref.watch(inStockVariantsProvider(widget.locationCode));

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ölçü veya çeşit ara',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: variants.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(error: e),
              data: (list) {
                final filtered = _filter(list, _query);
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: list.isEmpty
                        ? 'Stokta ürün yok'
                        : 'Aramaya uyan ölçü yok',
                    description: list.isEmpty
                        ? 'Önce stok girişi veya açılış stoğu girin.'
                        : null,
                  );
                }
                return ListView.separated(
                  controller: controller,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final v = filtered[i];
                    return ListTile(
                      title: Text(v.title),
                      subtitle: Text(v.quantityText, style: context.labelStyle),
                      onTap: () => Navigator.of(context).pop(v),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Türkçe karakter duyarsız arama (İ/ı sorunu için normalize edilmiş).
  static List<InStockVariant> _filter(List<InStockVariant> list, String query) {
    final needle = normalizeTurkish(query);
    if (needle.isEmpty) return list;
    return list
        .where((v) => normalizeTurkish(v.title).contains(needle))
        .toList();
  }
}
