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
  final String label;
  final int pieces;
  final Volume volume;

  const InStockVariant({
    required this.variantId,
    required this.productName,
    required this.label,
    required this.pieces,
    required this.volume,
  });
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

      final variants = await db.select(db.productVariants).get();
      final result = <InStockVariant>[];

      for (final variant in variants) {
        final stock = await db.variantStock(
          variant.id,
          locationCode: locationCode,
        );
        if (stock.pieces == 0) continue;

        result.add(
          InStockVariant(
            variantId: variant.id,
            productName: names[variant.productId] ?? '—',
            label: TrFormat.dimensions(
              variant.width,
              variant.height,
              variant.thickness,
            ),
            pieces: stock.pieces,
            volume: stock.volume,
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
                      title: Text('${v.productName} · ${v.label}'),
                      subtitle: Text(
                        '${TrFormat.pieces(v.pieces)} · '
                        '${TrFormat.volume(v.volume)}',
                        style: context.labelStyle,
                      ),
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
        .where(
          (v) =>
              normalizeTurkish('${v.productName} ${v.label}').contains(needle),
        )
        .toList();
  }
}
