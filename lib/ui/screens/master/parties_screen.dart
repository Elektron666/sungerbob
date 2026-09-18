import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'party_form.dart';

/// Tedarikçiler listesi ve kart açma (SPEC §7).
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tedarikçiler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await openPartyForm(context, supplier: true);
          ref.invalidate(suppliersProvider);
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Yeni tedarikçi'),
      ),
      body: suppliers.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(suppliersProvider),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'Henüz tedarikçi yok',
                description:
                    'Stok girişi yapabilmek için en az bir tedarikçi kartı '
                    'gerekir. Sağ alttaki düğmeyle açabilirsiniz.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = list[i];
                  return ListTile(
                    title: Text(s.title),
                    subtitle: Text(
                      '${_typeLabel(s.type)} · ${s.code}'
                      '${s.phone == null ? '' : ' · ${s.phone}'}',
                      style: context.labelStyle,
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    SupplierType.factory => 'Fabrika',
    SupplierType.cutter => 'Kesimhane',
    SupplierType.carrier => 'Nakliye',
    _ => 'Diğer',
  };
}
