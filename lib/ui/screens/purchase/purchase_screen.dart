import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/repo/purchase_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../data/repo/variant_helper.dart';
import '../../../domain/core/quantity.dart';
import '../../../domain/service/vat.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../stock/stock_screen.dart';

/// Stok girişi / alış (SPEC §3, §4 · BRIEF §7).
class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final _commandId = uuid.v7();
  final _piecesController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _freightController = TextEditingController();
  final _widthController = TextEditingController(text: '140');
  final _heightController = TextEditingController(text: '200');
  final _thicknessController = TextEditingController(text: '10');

  String? _supplierId;
  String? _productId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _piecesController,
      _priceController,
      _freightController,
      _widthController,
      _heightController,
      _thicknessController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Volume? get _volume {
    final w = TrFormat.parseDimension(_widthController.text);
    final h = TrFormat.parseDimension(_heightController.text);
    final t = TrFormat.parseDimension(_thicknessController.text);
    final pieces = TrFormat.parsePieces(_piecesController.text);
    if (w == null || h == null || t == null || pieces == null || pieces <= 0) {
      return null;
    }
    return Volume.fromDimensions(
      width: w,
      height: h,
      thickness: t,
      pieces: pieces,
    );
  }

  Future<void> _save() async {
    final supplierId = _supplierId;
    final productId = _productId;
    final volume = _volume;
    final price = TrFormat.parseUnitPrice(_priceController.text);
    final pieces = TrFormat.parsePieces(_piecesController.text);

    if (supplierId == null ||
        productId == null ||
        volume == null ||
        price == null ||
        pieces == null) {
      setState(() => _error = 'Tedarikçi, ürün, ölçü, adet ve fiyat gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = await ref.read(databaseProvider.future);
      final variantId = await _ensureVariant(db, productId);
      final repo = await ref.read(purchaseRepositoryProvider.future);
      final freight = TrFormat.parseMoney(_freightController.text);

      await repo.create(
        PurchaseInput(
          supplierId: supplierId,
          docDate: DateTime.now(),
          priceMode: PriceMode.excl,
          lines: [
            PurchaseLineInput(
              variantId: variantId,
              pieces: pieces,
              volume: volume,
              unitPriceM3: price,
              vatRate: Rate.percent('20'),
            ),
          ],
          expenses: [
            if (freight != null && freight.isPositive)
              PurchaseExpenseInput(kind: 'NAKLIYE', amount: freight),
          ],
        ),
        OperationContext(commandType: 'PURCHASE_CREATE', commandId: _commandId),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(productsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Alış kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Ölçü daha önce görülmediyse varyantı oluşturur.
  Future<String> _ensureVariant(AppDatabase db, String productId) =>
      db.ensureVariant(
        productId: productId,
        width: TrFormat.parseDimension(_widthController.text)!,
        height: TrFormat.parseDimension(_heightController.text)!,
        thickness: TrFormat.parseDimension(_thicknessController.text)!,
      );

  @override
  Widget build(BuildContext context) {
    final volume = _volume;
    final price = TrFormat.parseUnitPrice(_priceController.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Stok Girişi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SupplierPicker(
            selectedId: _supplierId,
            onSelected: (id) => setState(() => _supplierId = id),
          ),
          const SizedBox(height: 16),
          _ProductPicker(
            selectedId: _productId,
            onSelected: (id) => setState(() => _productId = id),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _numField(_widthController, 'En (cm)')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_heightController, 'Boy (cm)')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_thicknessController, 'Kalınlık')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _numField(_piecesController, 'Adet')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_priceController, 'TL/m³')),
            ],
          ),
          const SizedBox(height: 16),
          _numField(_freightController, 'Nakliye (TL, opsiyonel)'),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row(
                    context,
                    'Hacim',
                    volume == null ? '—' : TrFormat.volume(volume),
                  ),
                  _row(
                    context,
                    'Toplam (KDV hariç)',
                    volume == null || price == null
                        ? '—'
                        : TrFormat.moneyWithCurrency(price.times(volume)),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.labelStyle),
        Text(value, style: context.numberStyle),
      ],
    ),
  );
}

class _SupplierPicker extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _SupplierPicker({required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return suppliers.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (list) => list.isEmpty
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Önce bir tedarikçi ekleyin.'),
              ),
            )
          : DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(labelText: 'Tedarikçi'),
              items: [
                for (final s in list)
                  DropdownMenuItem(value: s.id, child: Text(s.title)),
              ],
              onChanged: (id) => id == null ? null : onSelected(id),
            ),
    );
  }
}

class _ProductPicker extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _ProductPicker({required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    return products.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (list) => DropdownButtonFormField<String>(
        initialValue: selectedId,
        decoration: const InputDecoration(labelText: 'Sünger çeşidi'),
        items: [
          for (final p in list)
            DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (id) => id == null ? null : onSelected(id),
      ),
    );
  }
}

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.suppliers)..where((s) => s.isActive.equals(true))).get();
});
