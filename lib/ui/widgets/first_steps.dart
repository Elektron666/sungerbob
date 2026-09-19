import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Defter boşken **ne yapılacağını** söyler.
///
/// İlk açılışta her ekran boş bir durum gösteriyordu ve kullanıcı nereden
/// başlayacağını bilmiyordu — "çok karmaşık ve düzensiz" hissinin kaynağı
/// buydu. Sıra, işin doğal akışı: önce malı aldığın yer, sonra mal, sonra
/// sattığın kişi, sonra satış.
///
/// Adımlar tamamlandıkça kart küçülür; hepsi bitince tamamen kaybolur.
/// Kalıcı bir "öğretici" değil, yalnızca başlangıç iskelesi.
class FirstStepsCard extends ConsumerWidget {
  const FirstStepsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(firstStepsProvider);

    return progress.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (state) {
        if (state.allDone) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        final steps = [
          (
            done: state.hasSupplier,
            title: 'Tedarikçi ekle',
            hint: 'Malı aldığın firma',
            route: '/suppliers',
          ),
          (
            done: state.hasStock,
            title: 'Stok gir',
            hint: 'Eldeki veya yeni alınan mal',
            route: '/purchase/new',
          ),
          (
            done: state.hasCustomer,
            title: 'Müşteri ekle',
            hint: 'Sattığın kişi veya firma',
            route: '/customers',
          ),
          (
            done: state.hasSale,
            title: 'İlk satışını gir',
            hint: 'Kâr ve cari buradan işler',
            route: '/sale/new',
          ),
        ];
        final doneCount = steps.where((s) => s.done).length;

        // Container yerine Material: ListTile dokunma efektini en yakın
        // Material'a çizer, renkli bir kutu onu gizler.
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius + 4),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      Container(width: 18, height: 1.5, color: scheme.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('İLK ADIMLAR', style: context.eyebrowStyle),
                      ),
                      Text(
                        '$doneCount/${steps.length}',
                        style: context.labelStyle,
                      ),
                    ],
                  ),
                ),
                for (final step in steps)
                  ListTile(
                    leading: Icon(
                      step.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: step.done ? scheme.secondary : scheme.outline,
                    ),
                    title: Text(
                      step.title,
                      style: step.done
                          ? TextStyle(
                              color: scheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: step.done ? null : Text(step.hint),
                    trailing: step.done
                        ? null
                        : const Icon(Icons.chevron_right, size: 18),
                    onTap: step.done ? null : () => context.push(step.route),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// İlk adımların durumu. Her biri tek bir "var mı?" sorgusu.
final class FirstStepsState {
  final bool hasSupplier;
  final bool hasStock;
  final bool hasCustomer;
  final bool hasSale;

  const FirstStepsState({
    required this.hasSupplier,
    required this.hasStock,
    required this.hasCustomer,
    required this.hasSale,
  });

  bool get allDone => hasSupplier && hasStock && hasCustomer && hasSale;
}

final firstStepsProvider = FutureProvider.autoDispose<FirstStepsState>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);

  Future<bool> any(String table) async {
    final row = await db
        .customSelect('SELECT EXISTS(SELECT 1 FROM $table) AS v')
        .getSingle();
    return row.read<int>('v') == 1;
  }

  return FirstStepsState(
    hasSupplier: await any('suppliers'),
    hasStock: await any('inventory_batches'),
    hasCustomer: await any('customers'),
    hasSale: await any('sales'),
  );
});
