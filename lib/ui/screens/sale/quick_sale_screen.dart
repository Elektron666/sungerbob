import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/sale_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/costing/costing_engine.dart';
import '../../../domain/core/quantity.dart';
import '../../../domain/service/vat.dart';
import '../../format/tr_format.dart';
import '../../../data/repo/price_memory.dart';
import '../../providers/app_providers.dart';
import '../master/party_form.dart';
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

  /// Seçili ürünün birimi. Sünger m³ ile döner, ince malzeme kendi
  /// birimiyle (D-22); ekrandaki her etiket buna bakar.
  String _unit = ProductUnit.m3;
  StockCell? _variant;
  int _pieces = 1;

  bool get _isFoam => ProductUnit.hasDimensions(_unit);

  /// Ayarlardaki varsayılanlar (KDV oranı ve fiyat modu). Kullanıcı bu
  /// belgede değiştirebilir ama başlangıç değeri **ayardan** gelir: koda
  /// gömülü %20, Ayarlar'da %10 seçen kullanıcıyı sessizce yanıltıyordu
  /// (D-32).
  PriceMode _priceMode = PriceMode.excl;
  Rate _vatRate = Rate.percent('20');
  bool _defaultsApplied = false;

  /// Kullanıcı fiyat modunu bu belgede kendi eliyle değiştirdi mi?
  ///
  /// Ayar veritabanından **asenkron** gelir; ilk çizimde henüz yoktur.
  /// Kullanıcı o arada moda dokunduysa, ayar geldiğinde seçimini geri almak
  /// olmaz — girdiği rakamın anlamını habersiz değiştirirdi.
  bool _priceModeTouched = false;

  /// Ayar okunduğunda bir kez uygulanır; sonrasında kullanıcının bu belgede
  /// yaptığı değişiklik korunur.
  void _applyDefaults(DocumentDefaults? defaults) {
    if (defaults == null || _defaultsApplied) return;
    _defaultsApplied = true;
    _vatRate = defaults.vatRate;
    if (!_priceModeTouched) _priceMode = defaults.priceMode;
  }

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
      vatRate: _vatRate,
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
              vatRate: _vatRate,
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
    _applyDefaults(ref.watch(documentDefaultsProvider).value);
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
              onSelectionChanged: (s) => setState(() {
                _priceMode = s.first;
                _priceModeTouched = true;
              }),
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
            onSelected: (id, unit) => setState(() {
              _productId = id;
              _unit = unit;
              _variant = null;
            }),
          ),
          if (_productId != null) ...[
            const SizedBox(height: 16),
            _VariantPicker(
              productId: _productId!,
              unit: _unit,
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
              label: _isFoam ? 'Adet' : 'Miktar (${ProductUnit.label(_unit)})',
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
              decoration: InputDecoration(
                labelText: ProductUnit.priceLabel(_unit),
                helperText: 'Virgül veya nokta kullanabilirsiniz',
              ),
              onChanged: (_) => setState(() {}),
            ),
            // Fiyatı yazarken en çok gereken bilgi: bu müşteriye en son
            // kaça satmıştın. Doldurmaz, yalnızca hatırlatır — otomatik
            // doldurmak zam yapılması gereken yerde eski fiyatı sessizce
            // tekrarlardı.
            if (_customer case final customer?)
              _LastPriceHint(
                customerId: customer.id,
                productId: _productId!,
                unit: _unit,
                onUse: (price) => setState(
                  () => _priceController.text = TrFormat.unitPrice(price),
                ),
              ),
            // Liste fiyatı "bugünkü fiyatım ne", son satış "bu müşteriye ne
            // demiştim" sorusunu yanıtlar. İkisi de yalnızca ipucudur.
            _ListPriceHint(
              productId: _productId!,
              unit: _unit,
              onUse: (price) => setState(
                () => _priceController.text = TrFormat.unitPrice(price),
              ),
            ),
            const SizedBox(height: 24),
            _SummaryCard(
              volume: _volume,
              unit: _unit,
              line: line,
              hideCost: hideCost,
            ),
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

  static const _newCustomer = '__yeni_musteri__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerBalancesProvider);

    return customers.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (rows) => DropdownButtonFormField<String>(
        initialValue: rows.any((r) => r.id == selected?.id)
            ? selected?.id
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Müşteri',
          helperText: rows.isEmpty
              ? 'Henüz müşteri yok — listeden ekleyin'
              : null,
        ),
        hint: const Text('Müşteri seçin'),
        items: [
          for (final row in rows)
            DropdownMenuItem(
              value: row.id,
              child: Text(
                '${row.title} · ${TrFormat.moneyWithCurrency(row.balance)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Liste boşken satış yapılamıyordu; kart açmanın yolu buradan.
          const DropdownMenuItem(
            value: _newCustomer,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Yeni müşteri ekle',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        onChanged: (id) async {
          if (id == null) return;
          if (id == _newCustomer) {
            final created = await openPartyForm(context, supplier: false);
            if (created == null) return;
            ref.invalidate(customerBalancesProvider);
            final refreshed = await ref.read(customerBalancesProvider.future);
            final row = refreshed.where((r) => r.id == created).firstOrNull;
            if (row != null) onSelected(row);
            return;
          }
          onSelected(rows.firstWhere((r) => r.id == id));
        },
      ),
    );
  }
}

class _ProductChips extends ConsumerWidget {
  final String? selectedId;

  /// Ürün kimliği ile birlikte birimini de verir — ekranın geri kalanı
  /// etiketleri buna göre yazar.
  final void Function(String id, String unit) onSelected;

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
              label: Text(
                product.unit == ProductUnit.m3
                    ? product.name
                    : '${product.name} · ${ProductUnit.label(product.unit)}',
              ),
              selected: product.id == selectedId,
              onSelected: (_) => onSelected(product.id, product.unit),
            ),
        ],
      ),
    );
  }
}

class _VariantPicker extends ConsumerWidget {
  final String productId;
  final String unit;
  final StockCell? selected;
  final ValueChanged<StockCell> onSelected;

  const _VariantPicker({
    required this.productId,
    required this.unit,
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
                  // İnce malzemenin ölçüsü yoktur; "0×0×0" yazmak yerine
                  // stoktaki miktarı başlığa alıyoruz (D-22).
                  title: Text(
                    ProductUnit.hasDimensions(unit)
                        ? '${cell.sizeLabel}×'
                              '${TrFormat.volumeBare(Volume(cell.thickness.stored * 10000))}'
                        : 'Stok: ${TrFormat.quantity(cell.volume, unit)}',
                  ),
                  subtitle: Text(
                    ProductUnit.hasDimensions(unit)
                        ? '${TrFormat.pieces(cell.pieces)} · '
                              '${TrFormat.volume(cell.volume)}'
                        : TrFormat.quantity(cell.volume, unit),
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
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _PieceStepper({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: context.labelStyle),
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
  final String unit;
  final VatLine? line;
  final bool hideCost;

  const _SummaryCard({
    required this.volume,
    required this.unit,
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
            _row(
              context,
              ProductUnit.hasDimensions(unit) ? 'Hacim' : 'Miktar',
              TrFormat.quantity(volume, unit),
            ),
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
    // Dar telefonda "GENEL TOPLAM" + büyük tutar satıra sığmıyordu.
    // Kısalacak olan etikettir; rakam asla kırpılmaz.
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold ? null : context.labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
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

/// "Son satış: 3.500,0000 TL/m³ · 12.09.2026" — dokununca fiyatı doldurur.
class _LastPriceHint extends ConsumerWidget {
  final String customerId;
  final String productId;
  final String unit;
  final ValueChanged<UnitPrice> onUse;

  const _LastPriceHint({
    required this.customerId,
    required this.productId,
    required this.unit,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(
      lastSalePriceProvider((customerId: customerId, productId: productId)),
    );

    return hint.maybeWhen(
      data: (value) => value == null
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onUse(value.unitPrice),
                icon: const Icon(Icons.history, size: 16),
                label: Text(
                  'Son satış: '
                  '${TrFormat.unitPriceFor(value.unitPrice, unit)} · '
                  '${TrFormat.date(value.date)}',
                ),
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// "Liste fiyatı: 3.500,0000 TL/m³" — dokununca fiyatı doldurur.
class _ListPriceHint extends ConsumerWidget {
  final String productId;
  final String unit;
  final ValueChanged<UnitPrice> onUse;

  const _ListPriceHint({
    required this.productId,
    required this.unit,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(listPriceProvider(productId));

    return hint.maybeWhen(
      data: (value) => value == null
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onUse(value),
                icon: const Icon(Icons.sell_outlined, size: 16),
                label: Text(
                  'Liste fiyatı: ${TrFormat.unitPriceFor(value, unit)}',
                ),
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

final listPriceProvider = FutureProvider.autoDispose.family<UnitPrice?, String>(
  (ref, productId) async {
    final db = await ref.watch(databaseProvider.future);
    return PriceMemory(db).activeListPrice(productId);
  },
);

final lastSalePriceProvider = FutureProvider.autoDispose
    .family<PriceHint?, ({String customerId, String productId})>((
      ref,
      args,
    ) async {
      final db = await ref.watch(databaseProvider.future);
      return PriceMemory(
        db,
      ).lastSalePrice(customerId: args.customerId, productId: args.productId);
    });
