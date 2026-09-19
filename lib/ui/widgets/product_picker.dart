import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/enums.dart';
import '../screens/stock/stock_screen.dart' show productsProvider;

/// Ürün (sünger çeşidi veya ince malzeme) seçtirir.
///
/// Alış ve teklif ekranlarının ikisi de aynı soruyla başlıyor. Ayrı ayrı
/// yazılsalardı birinde birim farkındalığı olur, ötekinde unutulurdu.
class ProductPicker extends ConsumerWidget {
  final String? selectedId;

  /// Ürünle birlikte **birimi** de bildirir: ekran ölçü soracak mı,
  /// miktarı hangi birimde isteyecek, buna göre karar verir.
  final void Function(String id, String unit) onSelected;

  final String label;

  const ProductPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.label = 'Sünger çeşidi',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    return products.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (list) => DropdownButtonFormField<String>(
        initialValue: selectedId,
        // Uzun ürün adları dar telefonda satırı taşırıyordu.
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        hint: const Text('Çeşit seçin'),
        items: [
          for (final p in list)
            DropdownMenuItem(
              value: p.id,
              child: Text(
                p.unit == ProductUnit.m3
                    ? p.name
                    : '${p.name} · ${ProductUnit.label(p.unit)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          onSelected(id, list.firstWhere((p) => p.id == id).unit);
        },
      ),
    );
  }
}
