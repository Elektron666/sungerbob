import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/stock_queries.dart';
import '../../../domain/core/money.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Stok ekranı (BRIEF §7).
///
/// Çeşit seçilince **ölçü satır, kalınlık sütun** olacak şekilde matris;
/// hücrede adet ve m³. Kritik stok vurgulu. "Kesimde" ayrı sekmede.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String? _selectedProductId;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Ana Depo'),
            Tab(text: 'Kesimde'),
          ],
        ),
      ),
      body: products.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'Ürün yok',
              description: 'Ayarlar → Ürünler bölümünden ürün ekleyin.',
            );
          }
          final selected = _selectedProductId ?? list.first.id;
          return TabBarView(
            controller: _tabs,
            children: [
              _StockTab(
                products: list,
                selectedProductId: selected,
                locationCode: LocationCode.mainWarehouse,
                onSelect: (id) => setState(() => _selectedProductId = id),
              ),
              _StockTab(
                products: list,
                selectedProductId: selected,
                locationCode: LocationCode.cutting,
                onSelect: (id) => setState(() => _selectedProductId = id),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StockTab extends ConsumerWidget {
  final List<Product> products;
  final String selectedProductId;
  final String locationCode;
  final ValueChanged<String> onSelect;

  const _StockTab({
    required this.products,
    required this.selectedProductId,
    required this.locationCode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrix = ref.watch(
      stockMatrixProvider((
        productId: selectedProductId,
        location: locationCode,
      )),
    );

    return Column(
      children: [
        // Sünger çeşidi çipleri
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final product = products[i];
              return ChoiceChip(
                label: Text(product.name),
                selected: product.id == selectedProductId,
                onSelected: (_) => onSelect(product.id),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: matrix.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(error: e),
            data: (cells) => cells.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: locationCode == LocationCode.cutting
                        ? 'Kesimde mal yok'
                        : 'Bu çeşitten stok yok',
                    description: locationCode == LocationCode.cutting
                        ? 'Kesime gönderilen mal burada görünür.'
                        : 'Stok girişi yaparak ekleyebilirsiniz.',
                  )
                : _Matrix(cells: cells),
          ),
        ),
      ],
    );
  }
}

class _Matrix extends StatelessWidget {
  final List<StockCell> cells;

  const _Matrix({required this.cells});

  @override
  Widget build(BuildContext context) {
    // Ölçü (en×boy) satır, kalınlık sütun.
    final sizes = <String>{};
    final thicknesses = <int>{};
    for (final c in cells) {
      sizes.add(c.sizeLabel);
      thicknesses.add(c.thickness.stored);
    }
    final sortedSizes = sizes.toList()..sort();
    final sortedThickness = thicknesses.toList()..sort();

    final byKey = {
      for (final c in cells) '${c.sizeLabel}|${c.thickness.stored}': c,
    };
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 20,
          columns: [
            const DataColumn(label: Text('Ölçü')),
            for (final t in sortedThickness)
              DataColumn(
                label: Text('${TrFormat.volumeBare(Volume(t * 10000))} cm'),
              ),
          ],
          rows: [
            for (final size in sortedSizes)
              DataRow(
                cells: [
                  DataCell(Text(size, style: context.numberStyle)),
                  for (final t in sortedThickness)
                    DataCell(_cell(context, byKey['$size|$t'], scheme)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, StockCell? cell, ColorScheme scheme) {
    if (cell == null || cell.pieces == 0) {
      return Text('—', style: context.labelStyle);
    }
    final critical = cell.isCritical;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${cell.pieces} adet',
          style: context.numberStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: critical ? scheme.error : null,
          ),
        ),
        Text(TrFormat.volume(cell.volume), style: context.labelStyle),
      ],
    );
  }
}

/// Matris hücresi.
final class StockCell {
  final String variantId;
  final String sizeLabel;
  final Dimension thickness;
  final int pieces;
  final Volume volume;
  final Money cost;
  final bool isCritical;

  const StockCell({
    required this.variantId,
    required this.sizeLabel,
    required this.thickness,
    required this.pieces,
    required this.volume,
    required this.cost,
    required this.isCritical,
  });
}

final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.products)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .get();
});

typedef StockMatrixArgs = ({String productId, String location});

final stockMatrixProvider = FutureProvider.autoDispose
    .family<List<StockCell>, StockMatrixArgs>((ref, args) async {
      final db = await ref.watch(databaseProvider.future);
      final locationId = await db.locationId(args.location);

      final variants = await (db.select(
        db.productVariants,
      )..where((v) => v.productId.equals(args.productId))).get();

      final cells = <StockCell>[];
      for (final variant in variants) {
        final stock = await db.variantStock(
          variant.id,
          locationCode: args.location,
        );
        if (stock.pieces == 0) continue;

        final batches =
            await (db.select(db.inventoryBatches)..where(
                  (b) =>
                      b.variantId.equals(variant.id) &
                      b.locationId.equals(locationId) &
                      b.remainingPieces.isBiggerThanValue(0),
                ))
                .get();

        cells.add(
          StockCell(
            variantId: variant.id,
            sizeLabel:
                '${TrFormat.volumeBare(Volume(variant.width.stored * 10000))}×'
                '${TrFormat.volumeBare(Volume(variant.height.stored * 10000))}',
            thickness: variant.thickness,
            pieces: stock.pieces,
            volume: stock.volume,
            cost: sumMoney(
              batches.map((b) => b.realUnitCostM3.times(b.remainingVolume)),
            ),
            isCritical:
                variant.criticalStockPieces > 0 &&
                stock.pieces <= variant.criticalStockPieces,
          ),
        );
      }
      return cells;
    });
