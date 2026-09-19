import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/product_repository.dart';
import '../../../data/repo/quote_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../data/repo/variant_helper.dart';
import '../../../domain/core/money.dart';
import '../../../domain/core/quantity.dart';
import '../../../domain/service/vat.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/party_picker.dart';
import '../../widgets/product_picker.dart';
import '../stock/stock_screen.dart' show productsProvider;

/// Teklif oluşturma (SPEC §10 · FLOWS §5).
///
/// Teklif listesi ve "satışa çevir" hazırdı ama teklifi **yazacak** ekran
/// yoktu; yani liste hiç dolmuyordu.
///
/// Teklif stoğa dokunmaz. Bu yüzden ölçü serbesttir: müşteri elde olmayan
/// bir ölçüyü sorabilir ve ona da fiyat verilir. Ölçü ilk kez giriliyorsa
/// varyantı kaydederken açılır.
class QuoteFormScreen extends ConsumerStatefulWidget {
  const QuoteFormScreen({super.key});

  @override
  ConsumerState<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

/// Ekranda duran, henüz kaydedilmemiş teklif satırı.
final class _DraftLine {
  final String productId;
  final String productName;
  final String unit;
  final Dimension width;
  final Dimension height;
  final Dimension thickness;
  final int pieces;
  final Volume volume;
  final UnitPrice unitPrice;
  final Rate vatRate;

  const _DraftLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.width,
    required this.height,
    required this.thickness,
    required this.pieces,
    required this.volume,
    required this.unitPrice,
    required this.vatRate,
  });

  bool get isFoam => ProductUnit.hasDimensions(unit);

  String get title => isFoam
      ? '$productName · ${TrFormat.dimensions(width, height, thickness)}'
      : productName;

  String get quantityText => isFoam
      ? '${TrFormat.pieces(pieces)} · ${TrFormat.volume(volume)} · '
            '${TrFormat.unitPrice(unitPrice)}'
      : '${TrFormat.quantity(volume, unit)} · '
            '${TrFormat.unitPriceFor(unitPrice, unit)}';

  VatLine get vat => VatCalculator.excluding(
    volume: volume,
    unitPrice: unitPrice,
    vatRate: vatRate,
  );
}

class _QuoteFormScreenState extends ConsumerState<QuoteFormScreen> {
  /// Form açılışında üretilir; çift dokunmada teklif tekrarlanmasın diye
  /// kaydetme boyunca AYNI kalır (BRIEF §3.9).
  final _commandId = uuid.v7();
  final _note = TextEditingController();

  String? _customerId;
  DateTime? _validUntil;

  /// Ayarlardaki KDV oranı; okunana kadar %20 varsayılır (D-32).
  Rate _vatRate = Rate.percent('20');
  final _lines = <_DraftLine>[];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Money get _net =>
      _lines.fold(Money.zero, (total, line) => total + line.vat.net);
  Money get _vat =>
      _lines.fold(Money.zero, (total, line) => total + line.vat.vat);
  Money get _gross =>
      _lines.fold(Money.zero, (total, line) => total + line.vat.gross);

  /// Eksik olan neyse adıyla söylenir; toplu "şunlar gerekli" mesajı değil.
  String? get _blockedReason {
    if (_customerId == null) return 'Müşteri seçin';
    if (_lines.isEmpty) return 'En az bir kalem ekleyin';
    return null;
  }

  Future<void> _addLine() async {
    final line = await showModalBottomSheet<_DraftLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineSheet(vatRate: _vatRate),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Teklif ne zamana kadar geçerli?',
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = await ref.read(databaseProvider.future);
      final lines = <QuoteLineInput>[];
      for (final line in _lines) {
        lines.add(
          QuoteLineInput(
            variantId: await _variantOf(db, line),
            pieces: line.pieces,
            volume: line.volume,
            unitPriceM3: line.unitPrice,
            vatRate: line.vatRate,
          ),
        );
      }

      await QuoteRepository(db).create(
        QuoteInput(
          customerId: _customerId!,
          docDate: DateTime.now(),
          validUntil: _validUntil,
          priceMode: PriceMode.excl,
          lines: lines,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
        OperationContext(commandType: 'QUOTE_CREATE', commandId: _commandId),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  /// Ölçü daha önce görülmediyse varyant burada açılır — teklif stoğa
  /// dokunmadığı için ölçünün stokta olması gerekmez.
  Future<String> _variantOf(AppDatabase db, _DraftLine line) async {
    if (!line.isFoam) {
      return (await ProductRepository(db).singleVariantOf(line.productId)).id;
    }
    return db.ensureVariant(
      productId: line.productId,
      width: line.width,
      height: line.height,
      thickness: line.thickness,
    );
  }

  @override
  Widget build(BuildContext context) {
    _vatRate = ref.watch(documentDefaultsProvider).value?.vatRate ?? _vatRate;
    final blocked = _blockedReason;

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni teklif')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          PartyPicker(
            supplier: false,
            label: 'Müşteri',
            value: _customerId,
            onChanged: (id) => setState(() => _customerId = id),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(
              _validUntil == null
                  ? 'Geçerlilik tarihi yok'
                  : 'Geçerli: ${TrFormat.date(_validUntil)}',
            ),
            subtitle: Text(
              'Süresi dolan teklif listede kendiliğinden işaretlenir.',
              style: context.labelStyle,
            ),
            trailing: TextButton(
              onPressed: _pickValidUntil,
              child: Text(_validUntil == null ? 'Seç' : 'Değiştir'),
            ),
          ),
          const SizedBox(height: 8),
          Text('KALEMLER', style: context.eyebrowStyle),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Henüz kalem yok. Teklif stoğa dokunmaz; elinde olmayan bir '
                'ölçüye de fiyat verebilirsin.',
                style: context.labelStyle,
              ),
            )
          else
            for (var i = 0; i < _lines.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(_lines[i].title),
                  subtitle: Text(
                    _lines[i].quantityText,
                    style: context.labelStyle,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        TrFormat.moneyWithCurrency(_lines[i].vat.gross),
                        style: context.numberStyle,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _lines.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Kalem ekle'),
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row(
                      context,
                      'KDV hariç',
                      TrFormat.moneyWithCurrency(_net),
                    ),
                    _row(context, 'KDV', TrFormat.moneyWithCurrency(_vat)),
                    const Divider(),
                    _row(
                      context,
                      'GENEL TOPLAM',
                      TrFormat.moneyWithCurrency(_gross),
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Not (opsiyonel)',
              helperText: 'Teklif belgesinde görünür',
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
            onPressed: _saving || blocked != null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Kaydediliyor…' : 'Teklifi kaydet'),
          ),
          if (blocked != null) ...[
            const SizedBox(height: 8),
            Text(blocked, style: context.labelStyle),
          ],
        ],
      ),
    );
  }

  /// Etiket esner, rakam esnemez (dar telefonda taşmayı önler).
  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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

/// Tek kalem girişi: çeşit, ölçü, miktar, fiyat.
class _LineSheet extends ConsumerStatefulWidget {
  /// Ayarlardaki KDV oranı; kalem bu oranla değerlenir (D-32).
  final Rate vatRate;

  const _LineSheet({required this.vatRate});

  @override
  ConsumerState<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends ConsumerState<_LineSheet> {
  final _width = TextEditingController(text: '140');
  final _height = TextEditingController(text: '200');
  final _thickness = TextEditingController(text: '10');
  final _pieces = TextEditingController();
  final _price = TextEditingController();

  String? _productId;
  String _productName = '';
  String _unit = ProductUnit.m3;

  bool get _isFoam => ProductUnit.hasDimensions(_unit);

  @override
  void dispose() {
    for (final c in [_width, _height, _thickness, _pieces, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Volume? get _volume {
    final pieces = TrFormat.parsePieces(_pieces.text);
    if (pieces == null || pieces <= 0) return null;
    if (!_isFoam) return Volume.parse('$pieces');

    final w = TrFormat.parseDimension(_width.text);
    final h = TrFormat.parseDimension(_height.text);
    final t = TrFormat.parseDimension(_thickness.text);
    if (w == null || h == null || t == null) return null;
    return Volume.fromDimensions(
      width: w,
      height: h,
      thickness: t,
      pieces: pieces,
    );
  }

  String? get _blockedReason {
    if (_productId == null) return 'Çeşit seçin';
    if (_isFoam &&
        (TrFormat.parseDimension(_width.text) == null ||
            TrFormat.parseDimension(_height.text) == null ||
            TrFormat.parseDimension(_thickness.text) == null)) {
      return 'En, boy ve kalınlık girin';
    }
    if (_volume == null) return _isFoam ? 'Adet girin' : 'Miktar girin';
    if (TrFormat.parseUnitPrice(_price.text) == null) {
      return 'Birim fiyat (${ProductUnit.priceLabel(_unit)}) girin';
    }
    return null;
  }

  void _submit() {
    final volume = _volume!;
    final zero = Dimension.fromStored(0);
    Navigator.of(context).pop(
      _DraftLine(
        productId: _productId!,
        productName: _productName,
        unit: _unit,
        width: _isFoam ? TrFormat.parseDimension(_width.text)! : zero,
        height: _isFoam ? TrFormat.parseDimension(_height.text)! : zero,
        thickness: _isFoam ? TrFormat.parseDimension(_thickness.text)! : zero,
        pieces: TrFormat.parsePieces(_pieces.text)!,
        volume: volume,
        unitPrice: TrFormat.parseUnitPrice(_price.text)!,
        vatRate: widget.vatRate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blockedReason;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text('Kalem ekle', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ProductPicker(
              selectedId: _productId,
              onSelected: (id, unit) => setState(() {
                _productId = id;
                _unit = unit;
                _productName =
                    ref
                        .read(productsProvider)
                        .value
                        ?.where((p) => p.id == id)
                        .map((p) => p.name)
                        .firstOrNull ??
                    '';
              }),
            ),
            const SizedBox(height: 16),
            // Ölçü yalnızca süngerde sorulur (D-22).
            if (_isFoam) ...[
              Row(
                children: [
                  Expanded(child: _numField(_width, 'En (cm)')),
                  const SizedBox(width: 8),
                  Expanded(child: _numField(_height, 'Boy (cm)')),
                  const SizedBox(width: 8),
                  Expanded(child: _numField(_thickness, 'Kalınlık')),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: _numField(
                    _pieces,
                    _isFoam ? 'Adet' : 'Miktar (${ProductUnit.label(_unit)})',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // Teklif KDV hariç fiyatla yazılır; KDV özet kartında
                    // ayrıca gösterilir.
                    decoration: InputDecoration(
                      labelText: ProductUnit.priceLabel(_unit),
                      helperText: 'KDV hariç',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: blocked != null ? null : _submit,
              child: const Text('Kalemi ekle'),
            ),
            if (blocked != null) ...[
              const SizedBox(height: 8),
              Text(blocked, style: context.labelStyle),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );
}
