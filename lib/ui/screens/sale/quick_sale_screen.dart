import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repo/sale_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/costing/costing_engine.dart';
import '../../../domain/core/quantity.dart';
import '../../../domain/service/vat.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../finance/customers_screen.dart';
import '../home/home_screen.dart';
import '../stock/stock_screen.dart';

/// Hızlı satış (BRIEF §7) — hedef: tipik satış 30 saniyenin altında.
///
/// Akış: müşteri → çeşit → ölçü → adet → özet → kaydet.
class QuickSaleScreen extends ConsumerStatefulWidget {
  const QuickSaleScreen({super.key});

  @override
  ConsumerState<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends ConsumerState<QuickSaleScreen> {
  /// Form açılışında üretilir; çift dokunmada işlem tekrarlanmasın diye
  /// kaydetme boyunca AYNI kalır (BRIEF §3.9).
  final _commandId = uuid.v7();

  CustomerRow? _customer;
  String? _productId;
  StockCell? _variant;
  int _pieces = 1;
  PriceMode _priceMode = PriceMode.excl;
  final _priceController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Volume get _volume {
    final cell = _variant;
    if (cell == null || cell.pieces == 0) return Volume.zero;
    return Volume(cell.volume.stored ~/ cell.pieces * _pieces);
  }

  UnitPrice? get _unitPrice => TrFormat.parseUnitPrice(_priceController.text);

  VatLine? get _line {
    final price = _unitPrice;
    if (price == null || _volume.isZero) return null;
    return VatCalculator.forMode(
      mode: _priceMode,
      volume: _volume,
      unitPrice: price,
      vatRate: Rate.percent('20'),
    );
  }

  Future<void> _save({bool riskApproved = false}) async {
    final customer = _customer;
    final variant = _variant;
    final price = _unitPrice;
    if (customer == null || variant == null || price == null) {
      setState(() => _error = 'Müşteri, ölçü ve fiyat gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(saleRepositoryProvider.future);
      await repo.create(
        SaleInput(
          customerId: customer.id,
          docDate: DateTime.now(),
          priceMode: _priceMode,
          riskLimitApproved: riskApproved,
          lines: [
            SaleLineInput(
              variantId: variant.variantId,
              pieces: _pieces,
              volume: _volume,
              unitPriceM3: price,
              vatRate: Rate.percent('20'),
            ),
          ],
        ),
        OperationContext(commandType: 'SALE_CREATE', commandId: _commandId),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(customerBalancesProvider);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Satış kaydedildi')));
    } on RiskLimitExceededException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final approved = await _confirmRiskLimit(e);
      if (approved && mounted) await _save(riskApproved: true);
    } on InsufficientStockException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmRiskLimit(RiskLimitExceededException e) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Risk limiti aşılıyor'),
        content: m.Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mevcut bakiye: ${TrFormat.moneyWithCurrency(e.balance)}'),
            Text(
              'Portföydeki evrak: '
              '${TrFormat.moneyWithCurrency(e.pendingInstruments)}',
            ),
            Text('Bu satış: ${TrFormat.moneyWithCurrency(e.newTotal)}'),
            const SizedBox(height: 8),
            Text('Limit: ${TrFormat.moneyWithCurrency(e.limit)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yine de sat'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final hideCost = ref.watch(hideCostProvider);
    final line = _line;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hızlı Satış'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<PriceMode>(
              segments: const [
                ButtonSegment(value: PriceMode.excl, label: Text('Hariç')),
                ButtonSegment(value: PriceMode.incl, label: Text('Dahil')),
              ],
              selected: {_priceMode},
              onSelectionChanged: (s) => setState(() => _priceMode = s.first),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CustomerPicker(
            selected: _customer,
            onSelected: (c) => setState(() => _customer = c),
          ),
          const SizedBox(height: 24),
          _ProductChips(
            selectedId: _productId,
            onSelected: (id) => setState(() {
              _productId = id;
              _variant = null;
            }),
          ),
          if (_productId != null) ...[
            const SizedBox(height: 16),
            _VariantPicker(
              productId: _productId!,
              selected: _variant,
              onSelected: (v) => setState(() {
                _variant = v;
                _pieces = 1;
              }),
            ),
          ],
          if (_variant != null) ...[
            const SizedBox(height: 24),
            _PieceStepper(
              value: _pieces,
              max: _variant!.pieces,
              onChanged: (v) => setState(() => _pieces = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'TL/m³',
                helperText: 'Virgül veya nokta kullanabilirsiniz',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            _SummaryCard(volume: _volume, line: line, hideCost: hideCost),
          ],
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
            // Kaydet butonu işlem sürerken devre dışı (BRIEF §3.9).
            onPressed: _saving || line == null ? null : () => _save(),
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
}

class _CustomerPicker extends ConsumerWidget {
  final CustomerRow? selected;
  final ValueChanged<CustomerRow> onSelected;

  const _CustomerPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerBalancesProvider);

    return customers.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (rows) => DropdownButtonFormField<String>(
        initialValue: selected?.id,
        decoration: const InputDecoration(labelText: 'Müşteri'),
        items: [
          for (final row in rows)
            DropdownMenuItem(
              value: row.id,
              child: Text(
                '${row.title} · ${TrFormat.moneyWithCurrency(row.balance)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          onSelected(rows.firstWhere((r) => r.id == id));
        },
      ),
    );
  }
}

class _ProductChips extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _ProductChips({required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);

    return products.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (list) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final product in list)
            ChoiceChip(
              label: Text(product.name),
              selected: product.id == selectedId,
              onSelected: (_) => onSelected(product.id),
            ),
        ],
      ),
    );
  }
}

class _VariantPicker extends ConsumerWidget {
  final String productId;
  final StockCell? selected;
  final ValueChanged<StockCell> onSelected;

  const _VariantPicker({
    required this.productId,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrix = ref.watch(
      stockMatrixProvider((productId: productId, location: 'ANA_DEPO')),
    );

    return matrix.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (cells) {
        if (cells.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bu çeşitten stokta mal yok.'),
            ),
          );
        }
        // Stokta olan varyantlar önce, her birinde mevcut adet ve m³.
        return RadioGroup<String>(
          groupValue: selected?.variantId,
          onChanged: (id) {
            if (id == null) return;
            onSelected(cells.firstWhere((c) => c.variantId == id));
          },
          child: m.Column(
            children: [
              for (final cell in cells)
                RadioListTile<String>(
                  value: cell.variantId,
                  title: Text(
                    '${cell.sizeLabel}×${TrFormat.volumeBare(Volume(cell.thickness.stored * 10000))}',
                  ),
                  subtitle: Text(
                    '${TrFormat.pieces(cell.pieces)} · ${TrFormat.volume(cell.volume)}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PieceStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _PieceStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Adet', style: context.labelStyle),
        const Spacer(),
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: context.bigNumberStyle,
          ),
        ),
        IconButton.filledTonal(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: 8),
        Text('/ $max', style: context.labelStyle),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Volume volume;
  final VatLine? line;
  final bool hideCost;

  const _SummaryCard({
    required this.volume,
    required this.line,
    required this.hideCost,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: m.Column(
          children: [
            _row(context, 'Hacim', TrFormat.volume(volume)),
            if (line != null) ...[
              _row(context, 'KDV hariç', TrFormat.moneyWithCurrency(line!.net)),
              _row(context, 'KDV', TrFormat.moneyWithCurrency(line!.vat)),
              const Divider(),
              _row(
                context,
                'GENEL TOPLAM',
                TrFormat.moneyWithCurrency(line!.gross),
                bold: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: bold ? null : context.labelStyle),
        Text(
          value,
          style: bold
              ? context.numberStyle.copyWith(fontWeight: FontWeight.w700)
              : context.numberStyle,
        ),
      ],
    ),
  );
}
