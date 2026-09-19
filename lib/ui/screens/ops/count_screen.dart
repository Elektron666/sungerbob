import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/stock_ops_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/variant_picker.dart';
import '../home/home_screen.dart' show dashboardProvider;

/// Stok sayımı (SPEC §11 · FLOWS §7).
///
/// İki adımlı: önce **taslak** sayılır, farklar görülür; onaylanınca stok
/// hareketleri yazılır. Onay **riskli işlemdir** — önce yedek alınır.
class CountScreen extends ConsumerWidget {
  const CountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(stockCountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sayım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const NewCountScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Yeni sayım'),
      ),
      body: counts.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(stockCountsProvider),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'Henüz sayım yapılmadı',
                description:
                    'Yeni sayım ile eldeki adetleri girin; farklar onaydan '
                    'sonra stoğa işlenir.',
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final count = list[i];
                  final draft = count.status == 'DRAFT';
                  return ListTile(
                    leading: Icon(
                      draft ? Icons.edit_note : Icons.check_circle_outline,
                      color: draft
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                    title: Text(count.docNo),
                    subtitle: Text(
                      '${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(count.countDate))}'
                      ' · ${draft ? "Taslak" : "Uygulandı"}',
                    ),
                    trailing: draft
                        ? TextButton(
                            onPressed: () => _apply(context, ref, count.id),
                            child: const Text('Onayla'),
                          )
                        : Text(
                            TrFormat.moneyWithCurrency(count.costEffectTotal),
                            style: context.numberStyle,
                          ),
                  );
                },
              ),
      ),
    );
  }

  /// Onay öncesi yedek alınır (BRIEF §4.3 — riskli işlem).
  Future<void> _apply(BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sayımı onayla'),
        content: const Text(
          'Farklar stoğa işlenecek ve geri alınamayacak. Onaydan önce '
          'otomatik yedek alınır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final password = await ref.read(backupPasswordStoreProvider).read();
      if (password != null) {
        final policy = await ref.read(autoBackupPolicyProvider.future);
        await policy.backupBeforeRiskyOperation(
          password: password,
          operation: 'stock_count',
        );
      }

      final repo = await ref.read(stockOpsRepositoryProvider.future);
      await repo.applyCount(
        countId: id,
        ctx: OperationContext(commandType: 'STOCK_COUNT_APPLY'),
      );

      ref.invalidate(stockCountsProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(inStockVariantsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Sayım uygulandı')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Uygulanamadı: $e')));
    }
  }
}

final stockCountsProvider = FutureProvider.autoDispose<List<StockCount>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.stockCounts)
        ..orderBy([(c) => OrderingTerm.desc(c.countDate)])
        ..limit(50))
      .get();
});

/// Yeni sayım taslağı.
class NewCountScreen extends ConsumerStatefulWidget {
  const NewCountScreen({super.key});

  @override
  ConsumerState<NewCountScreen> createState() => _NewCountScreenState();
}

class _NewCountScreenState extends ConsumerState<NewCountScreen> {
  /// variantId → sayılan adet
  final _counted = <String, int>{};
  String? _error;
  bool _saving = false;
  String _commandId = const Uuid().v7();

  Future<void> _save() async {
    if (_counted.isEmpty) {
      setState(() => _error = 'En az bir ölçü için sayım girin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(stockOpsRepositoryProvider.future);
      await repo.createDraftCount(
        countDate: DateTime.now(),
        lines: [
          for (final entry in _counted.entries)
            StockCountLineInput(
              variantId: entry.key,
              countedPieces: entry.value,
            ),
        ],
        ctx: OperationContext(
          commandType: 'STOCK_COUNT_DRAFT',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(stockCountsProvider);
      setState(() => _commandId = const Uuid().v7());
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sayım taslağı oluşturuldu')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = ref.watch(
      inStockVariantsProvider(LocationCode.mainWarehouse),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni sayım')),
      body: variants.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Stokta ürün yok',
                description: 'Sayılacak bir şey yok.',
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Eldeki adedi girin. Boş bırakılan ölçüler sayıma '
                      'girmez — sistemdeki adet korunur.',
                      style: context.labelStyle,
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _CountRow(variant: list[i], onChanged: _onChanged),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: const Text('Taslağı kaydet'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _onChanged(String variantId, int? value) {
    setState(() {
      if (value == null) {
        _counted.remove(variantId);
      } else {
        _counted[variantId] = value;
      }
      _error = null;
    });
  }
}

class _CountRow extends StatefulWidget {
  final InStockVariant variant;
  final void Function(String variantId, int? value) onChanged;

  const _CountRow({required this.variant, required this.onChanged});

  @override
  State<_CountRow> createState() => _CountRowState();
}

class _CountRowState extends State<_CountRow> {
  final _controller = TextEditingController();
  int? _value;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = _value == null ? null : _value! - widget.variant.pieces;

    return ListTile(
      title: Text(widget.variant.title),
      subtitle: Text(
        'Sistemde ${widget.variant.amount(widget.variant.pieces)}'
        '${diff == null || diff == 0 ? "" : " · fark ${diff > 0 ? "+" : ""}$diff"}',
        style: context.labelStyle,
      ),
      trailing: SizedBox(
        width: 88,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          decoration: const InputDecoration(hintText: 'adet'),
          onChanged: (text) {
            final parsed = text.trim().isEmpty
                ? null
                : TrFormat.parsePieces(text);
            setState(() => _value = parsed);
            widget.onChanged(widget.variant.variantId, parsed);
          },
        ),
      ),
    );
  }
}
