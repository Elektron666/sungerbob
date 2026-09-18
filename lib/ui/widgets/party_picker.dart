import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/enums.dart';
import '../providers/app_providers.dart';
import '../screens/master/party_form.dart';
import 'common.dart';

/// Müşteri veya tedarikçi seçtirir — **ve kart yoksa açtırır.**
///
/// Uygulamanın en can alıcı kusuru buydu: liste boş olduğunda açılır menü
/// hiçbir şey yapmıyor, kullanıcı alış veya satış giremiyordu. Artık boşken
/// de "Yeni ... ekle" görünür; kullanıcı hiçbir noktada çıkmaza düşmez.
class PartyPicker extends ConsumerWidget {
  /// true: tedarikçi, false: müşteri.
  final bool supplier;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  /// Yalnızca bu tipteki tedarikçiler listelensin (ör. kesimhane).
  final String? supplierType;

  const PartyPicker({
    super.key,
    required this.supplier,
    required this.value,
    required this.onChanged,
    required this.label,
    this.supplierType,
  });

  static const _newValue = '__yeni__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = supplier
        ? ref
              .watch(suppliersProvider)
              .whenData(
                (list) => [
                  for (final s in list)
                    if (supplierType == null || s.type == supplierType)
                      (id: s.id, title: s.title),
                ],
              )
        : ref
              .watch(customersProvider)
              .whenData(
                (list) => [for (final c in list) (id: c.id, title: c.title)],
              );

    return entries.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorState(error: e),
      data: (list) {
        // Silinmiş/filtrelenmiş bir kart seçili kalmasın.
        final selected = list.any((e) => e.id == value) ? value : null;

        return DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            helperText: list.isEmpty
                ? 'Henüz kart yok — listeden ekleyin'
                : null,
          ),
          hint: Text(supplier ? 'Tedarikçi seçin' : 'Müşteri seçin'),
          items: [
            for (final entry in list)
              DropdownMenuItem(
                value: entry.id,
                child: Text(entry.title, overflow: TextOverflow.ellipsis),
              ),
            DropdownMenuItem(
              value: _newValue,
              child: Row(
                children: [
                  const Icon(Icons.add, size: 18),
                  const SizedBox(width: 8),
                  Text(supplier ? 'Yeni tedarikçi ekle' : 'Yeni müşteri ekle'),
                ],
              ),
            ),
          ],
          onChanged: (picked) async {
            if (picked != _newValue) {
              onChanged(picked);
              return;
            }
            final created = await openPartyForm(
              context,
              supplier: supplier,
              supplierType: supplierType,
            );
            if (created != null) onChanged(created);
          },
        );
      },
    );
  }
}

/// Kesimhane seçtiren kısayol.
class CutterPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const CutterPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => PartyPicker(
    supplier: true,
    supplierType: SupplierType.cutter,
    value: value,
    onChanged: onChanged,
    label: 'Kesimhane',
  );
}
