import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/stock_ops_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/variant_picker.dart';
import '../home/home_screen.dart' show dashboardProvider;

/// Fire kaydı (SPEC §12 · FLOWS §8).
///
/// Fire, stoktan **maliyetiyle birlikte** düşer ve kârlılık raporunda ayrı
/// satır olarak görünür. Geri alınması ancak ters hareketle olur.
class WasteScreen extends ConsumerStatefulWidget {
  const WasteScreen({super.key});

  @override
  ConsumerState<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends ConsumerState<WasteScreen> {
  final _lines = <({InStockVariant variant, int pieces})>[];
  String _reason = WasteReason.damaged;
  String? _error;
  bool _saving = false;

  /// Form açılışında üretilir; aynı fire iki kez kaydedilmez (BRIEF §3.12).
  String _commandId = const Uuid().v7();

  static const _reasonLabels = {
    WasteReason.damaged: 'Hasarlı',
    WasteReason.cuttingWaste: 'Kesim firesi',
    WasteReason.humidity: 'Nem',
    WasteReason.other: 'Diğer',
  };

  Future<void> _addLine() async {
    final variant = await pickInStockVariant(context);
    if (variant == null || !mounted) return;

    final pieces = await _askPieces(variant);
    if (pieces == null || !mounted) return;

    setState(() {
      _lines.add((variant: variant, pieces: pieces));
      _error = null;
    });
  }

  Future<int?> _askPieces(InStockVariant variant) {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(variant.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stokta ${variant.amount(variant.pieces)}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Fire miktarı (${variant.amountLabel})',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final value = TrFormat.parsePieces(controller.text);
              // Stoktan fazla fire yazılamaz; negatif stok yasak.
              if (value == null || value <= 0 || value > variant.pieces) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'En az bir satır ekleyin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(stockOpsRepositoryProvider.future);
      await repo.recordWaste(
        occurredAt: DateTime.now(),
        reasonCode: _reason,
        lines: [
          for (final line in _lines)
            WasteLineInput(
              variantId: line.variant.variantId,
              pieces: line.pieces,
            ),
        ],
        ctx: OperationContext(
          commandType: 'WASTE_RECORD',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(inStockVariantsProvider);
      setState(() {
        _lines.clear();
        _commandId = const Uuid().v7();
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fire kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fire Kaydı')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Fire nedeni'),
              items: [
                for (final entry in _reasonLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _reason = v!),
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Fire verilen ölçüleri ekleyin.\n'
                        'Yalnızca stokta olanlar listelenir.',
                        textAlign: TextAlign.center,
                        style: context.labelStyle,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      return ListTile(
                        title: Text(line.variant.title),
                        subtitle: Text(line.variant.amount(line.pieces)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _lines.removeAt(i)),
                        ),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              // İki düğme dar telefonda yan yana sığmıyordu. Artık kalan
              // alanı paylaşıyorlar; metin sığmazsa kırpılır, düğme
              // ekrandan taşmaz.
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addLine,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Satır ekle',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_saving || _lines.isEmpty) ? null : _save,
                      child: const Text(
                        'Fireyi kaydet',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
