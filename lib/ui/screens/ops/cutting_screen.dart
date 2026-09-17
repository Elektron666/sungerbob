import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/cutting_repository.dart';
import '../../../data/repo/stock_queries.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../data/repo/variant_helper.dart';
import '../../../domain/core/money.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/variant_picker.dart';
import '../home/home_screen.dart' show dashboardProvider;
import '../purchase/purchase_screen.dart' show suppliersProvider;
import '../stock/stock_screen.dart' show productsProvider;

/// Kesim emirleri (BRIEF §5 · FLOWS §9).
///
/// Mal ana depodan sanal "Kesimde" konumuna geçer: satılamaz ama stok
/// değerinde görünür ve maliyetini aynen taşır (D-07).
class CuttingScreen extends ConsumerWidget {
  const CuttingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(cuttingOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kesim Emirleri')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SendToCuttingScreen()),
        ),
        icon: const Icon(Icons.content_cut),
        label: const Text('Kesime gönder'),
      ),
      body: orders.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(cuttingOrdersProvider),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.content_cut,
                title: 'Kesimde mal yok',
                description:
                    'Kesime gönderilen mal burada görünür ve dönüşü buradan '
                    'kaydedilir.',
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final order = list[i];
                  final open =
                      order.status == CuttingStatus.atCutter ||
                      order.status == CuttingStatus.partial ||
                      order.status == CuttingStatus.preparing;
                  return ListTile(
                    title: Text(order.docNo),
                    subtitle: Text(
                      '${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(order.sentDate))}'
                      ' · ${_statusLabel(order.status)}'
                      ' · ${TrFormat.volume(order.sourceVolumeTotal)}',
                      style: context.labelStyle,
                    ),
                    trailing: open
                        ? TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ReceiveCuttingScreen(orderId: order.id),
                              ),
                            ),
                            child: const Text('Dönüş al'),
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    CuttingStatus.preparing => 'Hazırlanıyor',
    CuttingStatus.atCutter => 'Kesimhanede',
    CuttingStatus.partial => 'Kısmi dönüş',
    CuttingStatus.completed => 'Tamamlandı',
    _ => 'İptal',
  };
}

final cuttingOrdersProvider = FutureProvider.autoDispose<List<CuttingOrder>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.cuttingOrders)
        ..orderBy([(o) => OrderingTerm.desc(o.sentDate)])
        ..limit(50))
      .get();
});

// ------------------------------------------------------------ kesime gönder

/// Kesime gönderilebilecek parti (ana depoda, kalan adedi olan).
final class CuttableBatch {
  final String batchId;
  final String label;
  final int remainingPieces;
  final Volume remainingVolume;

  const CuttableBatch({
    required this.batchId,
    required this.label,
    required this.remainingPieces,
    required this.remainingVolume,
  });
}

/// Kesim parti bazında çalışır: hangi partinin malı gittiyse maliyeti de
/// onunla gider (D-07). Bu yüzden varyant değil **parti** seçilir.
final cuttableBatchesProvider = FutureProvider.autoDispose<List<CuttableBatch>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  final mainLocation = await db.locationId(LocationCode.mainWarehouse);

  final batches =
      await (db.select(db.inventoryBatches)
            ..where(
              (b) =>
                  b.locationId.equals(mainLocation) &
                  b.remainingPieces.isBiggerThanValue(0),
            )
            ..orderBy([(b) => OrderingTerm.asc(b.receivedAt)]))
          .get();

  final products = await db.select(db.products).get();
  final names = {for (final p in products) p.id: p.name};
  final variants = await db.select(db.productVariants).get();
  final byId = {for (final v in variants) v.id: v};

  return [
    for (final batch in batches)
      if (byId[batch.variantId] case final variant?)
        CuttableBatch(
          batchId: batch.id,
          label:
              '${names[variant.productId] ?? "—"} · '
              '${TrFormat.dimensions(variant.width, variant.height, variant.thickness)}',
          remainingPieces: batch.remainingPieces,
          remainingVolume: batch.remainingVolume,
        ),
  ];
});

class SendToCuttingScreen extends ConsumerStatefulWidget {
  const SendToCuttingScreen({super.key});

  @override
  ConsumerState<SendToCuttingScreen> createState() =>
      _SendToCuttingScreenState();
}

class _SendToCuttingScreenState extends ConsumerState<SendToCuttingScreen> {
  final _sources = <({CuttableBatch batch, int pieces})>[];
  String? _cutterId;
  String? _error;
  bool _saving = false;
  String _commandId = const Uuid().v7();

  Future<void> _addSource(List<CuttableBatch> batches) async {
    final batch = await showModalBottomSheet<CuttableBatch>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListView(
        children: [
          for (final b in batches)
            ListTile(
              title: Text(b.label),
              subtitle: Text(
                '${TrFormat.pieces(b.remainingPieces)} · '
                '${TrFormat.volume(b.remainingVolume)}',
              ),
              onTap: () => Navigator.of(context).pop(b),
            ),
        ],
      ),
    );
    if (batch == null || !mounted) return;

    final controller = TextEditingController();
    final pieces = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(batch.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Gönderilen adet',
            helperText: 'Partide ${batch.remainingPieces} adet var',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final value = TrFormat.parsePieces(controller.text);
              if (value == null ||
                  value <= 0 ||
                  value > batch.remainingPieces) {
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (pieces == null || !mounted) return;

    setState(() {
      _sources.add((batch: batch, pieces: pieces));
      _error = null;
    });
  }

  Future<void> _save() async {
    final cutterId = _cutterId;
    if (cutterId == null || _sources.isEmpty) {
      setState(() => _error = 'Kesimhane ve en az bir parti gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(cuttingRepositoryProvider.future);
      await repo.sendToCutting(
        cutterSupplierId: cutterId,
        sentDate: DateTime.now(),
        sources: [
          for (final s in _sources)
            CuttingSourceInput(batchId: s.batch.batchId, pieces: s.pieces),
        ],
        ctx: OperationContext(
          commandType: 'CUTTING_SEND',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(cuttingOrdersProvider);
      ref.invalidate(cuttableBatchesProvider);
      ref.invalidate(inStockVariantsProvider);
      ref.invalidate(dashboardProvider);
      setState(() => _commandId = const Uuid().v7());
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kesim emri oluşturuldu')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final batches = ref.watch(cuttableBatchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kesime gönder')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: suppliers.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorState(error: e),
              data: (list) {
                final cutters = list
                    .where((s) => s.type == SupplierType.cutter)
                    .toList();
                if (cutters.isEmpty) {
                  return const EmptyState(
                    icon: Icons.factory_outlined,
                    title: 'Kesimhane tanımlı değil',
                    description:
                        'Önce tipi "Kesimhane" olan bir tedarikçi ekleyin.',
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: _cutterId,
                  decoration: const InputDecoration(labelText: 'Kesimhane'),
                  items: [
                    for (final s in cutters)
                      DropdownMenuItem(value: s.id, child: Text(s.title)),
                  ],
                  onChanged: (v) => setState(() => _cutterId = v),
                );
              },
            ),
          ),
          Expanded(
            child: _sources.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Kesime gönderilecek partileri ekleyin.',
                        textAlign: TextAlign.center,
                        style: context.labelStyle,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _sources.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => ListTile(
                      title: Text(_sources[i].batch.label),
                      subtitle: Text(TrFormat.pieces(_sources[i].pieces)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _sources.removeAt(i)),
                      ),
                    ),
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
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _addSource(batches.value ?? const []),
                    icon: const Icon(Icons.add),
                    label: const Text('Parti ekle'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_saving || _sources.isEmpty) ? null : _save,
                    child: const Text('Gönder'),
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

// ---------------------------------------------------------------- dönüş al

class ReceiveCuttingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ReceiveCuttingScreen({super.key, required this.orderId});

  @override
  ConsumerState<ReceiveCuttingScreen> createState() =>
      _ReceiveCuttingScreenState();
}

class _ReceiveCuttingScreenState extends ConsumerState<ReceiveCuttingScreen> {
  final _results =
      <
        ({
          String productId,
          String label,
          Dimension w,
          Dimension h,
          Dimension t,
          int pieces,
        })
      >[];
  final _fee = TextEditingController();
  final _freight = TextEditingController();
  String? _error;
  bool _saving = false;
  String _commandId = const Uuid().v7();

  @override
  void dispose() {
    _fee.dispose();
    _freight.dispose();
    super.dispose();
  }

  Future<void> _addResult() async {
    final products = ref.read(productsProvider).value ?? const [];
    if (products.isEmpty) return;

    final result =
        await showDialog<
          ({
            String productId,
            String label,
            Dimension w,
            Dimension h,
            Dimension t,
            int pieces,
          })
        >(
          context: context,
          builder: (context) => _ResultDialog(products: products),
        );
    if (result == null || !mounted) return;
    setState(() {
      _results.add(result);
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_results.isEmpty) {
      setState(() => _error = 'En az bir dönüş satırı ekleyin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = await ref.read(databaseProvider.future);
      final inputs = <CuttingResultInput>[];
      for (final r in _results) {
        inputs.add(
          CuttingResultInput(
            variantId: await db.ensureVariant(
              productId: r.productId,
              width: r.w,
              height: r.h,
              thickness: r.t,
            ),
            pieces: r.pieces,
          ),
        );
      }

      final repo = await ref.read(cuttingRepositoryProvider.future);
      await repo.receiveFromCutting(
        orderId: widget.orderId,
        returnedAt: DateTime.now(),
        results: inputs,
        cuttingFeeNet: TrFormat.parseMoney(_fee.text) ?? Money.zero,
        freightNet: TrFormat.parseMoney(_freight.text) ?? Money.zero,
        ctx: OperationContext(
          commandType: 'CUTTING_RECEIVE',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(cuttingOrdersProvider);
      ref.invalidate(cuttableBatchesProvider);
      ref.invalidate(inStockVariantsProvider);
      ref.invalidate(dashboardProvider);
      setState(() => _commandId = const Uuid().v7());
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dönüş kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ürün listesi dialog'da lazım; burada ısıtılır.
    ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kesimden dönüş')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Kesimden dönen ölçüleri girin. Kesim ücreti ve nakliye '
                  'dönen malın maliyetine eklenir; gönderilen ile dönen '
                  'arasındaki fark fire sayılır.',
                  style: context.labelStyle,
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _results.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_results[i].label),
                    subtitle: Text(TrFormat.pieces(_results[i].pieces)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _results.removeAt(i)),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addResult,
                  icon: const Icon(Icons.add),
                  label: const Text('Dönen ölçü ekle'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _fee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Kesim ücreti (TL, KDV hariç)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _freight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Nakliye (TL, KDV hariç)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: (_saving || _results.isEmpty) ? null : _save,
                child: const Text('Dönüşü kaydet'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultDialog extends StatefulWidget {
  final List<Product> products;
  const _ResultDialog({required this.products});

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _thickness = TextEditingController();
  final _pieces = TextEditingController();
  late String _productId = widget.products.first.id;

  @override
  void dispose() {
    for (final c in [_width, _height, _thickness, _pieces]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Dönen ölçü'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _productId,
            decoration: const InputDecoration(labelText: 'Çeşit'),
            items: [
              for (final p in widget.products)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _productId = v!),
          ),
          const SizedBox(height: 12),
          _field(_width, 'En (cm)'),
          _field(_height, 'Boy (cm)'),
          _field(_thickness, 'Kalınlık (cm)'),
          _field(_pieces, 'Adet'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          final w = TrFormat.parseDimension(_width.text);
          final h = TrFormat.parseDimension(_height.text);
          final t = TrFormat.parseDimension(_thickness.text);
          final pieces = TrFormat.parsePieces(_pieces.text);
          if (w == null ||
              h == null ||
              t == null ||
              pieces == null ||
              pieces <= 0) {
            return;
          }
          final name = widget.products
              .firstWhere((p) => p.id == _productId)
              .name;
          Navigator.of(context).pop((
            productId: _productId,
            label: '$name · ${TrFormat.dimensions(w, h, t)}',
            w: w,
            h: h,
            t: t,
            pieces: pieces,
          ));
        },
        child: const Text('Ekle'),
      ),
    ],
  );

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );
}
