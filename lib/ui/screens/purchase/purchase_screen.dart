import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/product_repository.dart';
import '../../../data/repo/purchase_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../data/repo/variant_helper.dart';
import '../../../domain/core/quantity.dart';
import '../../../domain/service/vat.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/party_picker.dart';
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

  /// Seçili ürünün birimi. İnce malzemede ölçü sorulmaz (D-22).
  String _unit = ProductUnit.m3;
  bool get _isFoam => _unit == ProductUnit.m3;
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

  /// Miktar. Süngerde ölçüden hesaplanan m³; ince malzemede girilen
  /// miktarın kendisi (1 birim = 1).
  Volume? get _volume {
    final pieces = TrFormat.parsePieces(_piecesController.text);
    if (pieces == null || pieces <= 0) return null;

    if (!_isFoam) return Volume.parse('$pieces');

    final w = TrFormat.parseDimension(_widthController.text);
    final h = TrFormat.parseDimension(_heightController.text);
    final t = TrFormat.parseDimension(_thicknessController.text);
    if (w == null || h == null || t == null) return null;

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

    // Eksik olanı **adıyla** söyle. "Şunlar gerekli" diye hepsini sıralamak
    // kullanıcıya hangisinin eksik olduğunu bulduramıyor.
    final missing = switch (null) {
      _ when supplierId == null => 'Tedarikçi seçin',
      _ when productId == null => 'Sünger çeşidi seçin',
      _ when volume == null =>
        _isFoam ? 'En, boy, kalınlık ve adet girin' : 'Miktar girin',
      _ when pieces == null || pieces <= 0 => 'Adet girin',
      _ when price == null =>
        'Birim fiyat (${ProductUnit.priceLabel(_unit)}) girin',
      _ => null,
    };
    if (missing != null ||
        supplierId == null ||
        productId == null ||
        volume == null ||
        price == null ||
        pieces == null) {
      setState(() => _error = missing ?? 'Eksik alan var');
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
  ///
  /// İnce malzemenin ölçüsü yoktur; varyantı ürün kartıyla birlikte
  /// açılmıştır, o kullanılır.
  Future<String> _ensureVariant(AppDatabase db, String productId) async {
    if (!_isFoam) {
      return (await ProductRepository(db).singleVariantOf(productId)).id;
    }
    return db.ensureVariant(
      productId: productId,
      width: TrFormat.parseDimension(_widthController.text)!,
      height: TrFormat.parseDimension(_heightController.text)!,
      thickness: TrFormat.parseDimension(_thicknessController.text)!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final volume = _volume;
    final price = TrFormat.parseUnitPrice(_priceController.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Stok Girişi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartyPicker(
            supplier: true,
            label: 'Tedarikçi',
            value: _supplierId,
            onChanged: (id) => setState(() => _supplierId = id),
          ),
          const SizedBox(height: 16),
          _ProductPicker(
            selectedId: _productId,
            onSelected: (id, unit) => setState(() {
              _productId = id;
              _unit = unit;
            }),
          ),
          const SizedBox(height: 24),
          // Ölçü yalnızca süngerde sorulur; çivinin eni boyu olmaz.
          if (_isFoam) ...[
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
          ],
          Row(
            children: [
              Expanded(
                child: _numField(
                  _piecesController,
                  _isFoam ? 'Adet' : 'Miktar (${ProductUnit.label(_unit)})',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField(
                  _priceController,
                  ProductUnit.priceLabel(_unit),
                ),
              ),
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

  /// Etiket + rakam satırı.
  ///
  /// Etiket esner, rakam esnemez: dar telefonda uzun bir tutar satırı
  /// taşırıyordu. Kısaltılacaksa etiket kısaltılır, rakam değil.
  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: context.numberStyle),
      ],
    ),
  );
}

class _ProductPicker extends ConsumerWidget {
  final String? selectedId;

  /// Ürünle birlikte **birimi** de bildirir: ekran ölçü soracak mı,
  /// miktarı hangi birimde isteyecek, buna göre karar verir.
  final void Function(String id, String unit) onSelected;

  const _ProductPicker({required this.selectedId, required this.onSelected});

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
        decoration: const InputDecoration(labelText: 'Sünger çeşidi'),
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
