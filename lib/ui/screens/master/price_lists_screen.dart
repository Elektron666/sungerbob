import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/price_list_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Fiyat listeleri (SPEC §13, §30.11).
///
/// Zam yapmanın yolu burası: baz TL/m³ girilir, her çeşidin fiyatı kendi
/// katsayısıyla hesaplanır. **Eski versiyon silinmez**, arşivlenir; geçmiş
/// satışlar kendi versiyonuna bağlı olduğu için geçmiş kâr etkilenmez.
class PriceListsScreen extends ConsumerWidget {
  const PriceListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(priceListsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiyat Listeleri')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newVersion(context, ref),
        icon: const Icon(Icons.trending_up),
        label: const Text('Yeni fiyat listesi'),
      ),
      body: lists.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(priceListsProvider),
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.price_change_outlined,
                title: 'Henüz fiyat listesi yok',
                description:
                    'Baz metreküp fiyatını gir; her çeşidin fiyatı kendi '
                    'katsayısıyla hesaplansın.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final l = list[i];
                  final active = l.status == 'ACTIVE';
                  return ListTile(
                    leading: Icon(
                      active ? Icons.check_circle : Icons.inventory_2_outlined,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text('v${l.versionNo} · ${l.name}'),
                    subtitle: Text(
                      'Baz ${TrFormat.unitPrice(l.basePriceM3)} · '
                      '${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(l.validFrom))}'
                      '${active ? ' · yürürlükte' : ' · arşiv'}',
                      style: context.labelStyle,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _newVersion(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PriceListFormScreen()),
    );
    if (created == true) ref.invalidate(priceListsProvider);
  }
}

final priceListsProvider = FutureProvider.autoDispose<List<PriceList>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(
    db.priceLists,
  )..orderBy([(l) => OrderingTerm.desc(l.versionNo)])).get();
});

/// Yeni versiyon: baz fiyat + yuvarlama → **önizleme** → onay.
///
/// Önizleme zorunlu: zam, listedeki her ürünün fiyatını aynı anda değiştirir.
/// Kullanıcının "hangi ürün kaça çıkıyor" sorusunu onaylamadan önce görmesi
/// gerekir (BRIEF §5).
class PriceListFormScreen extends ConsumerStatefulWidget {
  const PriceListFormScreen({super.key});

  @override
  ConsumerState<PriceListFormScreen> createState() =>
      _PriceListFormScreenState();
}

class _PriceListFormScreenState extends ConsumerState<PriceListFormScreen> {
  /// Form açılışında üretilir; çift dokunmada versiyon iki kez açılmasın.
  final _commandId = uuid.v7();
  final _base = TextEditingController();
  final _name = TextEditingController();

  String _rounding = RoundingRule.none;
  DateTime _validFrom = DateTime.now();
  List<PricePreviewRow>? _preview;
  bool _loadingPreview = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _base.dispose();
    _name.dispose();
    super.dispose();
  }

  UnitPrice? get _basePrice => TrFormat.parseUnitPrice(_base.text);

  Future<void> _refreshPreview() async {
    final base = _basePrice;
    if (base == null) {
      setState(() => _preview = null);
      return;
    }

    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final rows = await PriceListRepository(db)
          .preview(basePrice: base, roundingRule: _rounding);
      if (!mounted) return;
      setState(() {
        _preview = rows;
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingPreview = false;
      });
    }
  }

  Future<void> _pickValidFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validFrom,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Yeni fiyatlar ne zaman geçerli olsun?',
    );
    if (picked != null) setState(() => _validFrom = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      await PriceListRepository(db).createVersion(
        basePrice: _basePrice!,
        name: _name.text.trim().isEmpty
            ? 'Fiyat listesi ${TrFormat.date(_validFrom)}'
            : _name.text.trim(),
        validFrom: _validFrom,
        roundingRule: _rounding,
        ctx: OperationContext(
          commandType: 'PRICE_LIST_CREATE',
          commandId: _commandId,
        ),
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

  /// Eksik olan neyse adıyla söylenir.
  String? get _blockedReason {
    if (_basePrice == null) return 'Baz metreküp fiyatını girin';
    if (_preview == null) return 'Önce önizlemeyi görün';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blockedReason;
    final rows = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni fiyat listesi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _base,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Baz fiyat (TL/m³)',
              helperText: 'Beyaz süngerin fiyatı; katsayı 1,00 kabul edilir',
            ),
            // Fiyat her değiştiğinde önizleme kendiliğinden tazelenmez:
            // her tuşta 12 ürünü yeniden hesaplamak yerine kullanıcı
            // "Önizle" deyince hesaplanır.
            onChanged: (_) => setState(() => _preview = null),
          ),
          const SizedBox(height: 24),
          Text('YUVARLAMA', style: context.eyebrowStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rule in RoundingRule.all)
                ChoiceChip(
                  label: Text(_roundingLabel(rule)),
                  selected: _rounding == rule,
                  onSelected: (_) => setState(() {
                    _rounding = rule;
                    _preview = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('Geçerlilik: ${TrFormat.date(_validFrom)}'),
            trailing: TextButton(
              onPressed: _pickValidFrom,
              child: const Text('Değiştir'),
            ),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Liste adı (opsiyonel)',
              helperText: 'Boş bırakılırsa tarihten türetilir',
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _basePrice == null || _loadingPreview
                ? null
                : _refreshPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_loadingPreview ? 'Hesaplanıyor…' : 'Önizle'),
          ),
          if (rows != null) ...[
            const SizedBox(height: 16),
            Text('YENİ FİYATLAR', style: context.eyebrowStyle),
            const SizedBox(height: 8),
            for (final row in rows) _PreviewTile(row: row),
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
            onPressed: _saving || blocked != null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Kaydediliyor…' : 'Listeyi yürürlüğe al'),
          ),
          const SizedBox(height: 8),
          Text(
            blocked ??
                'Önceki liste silinmez, arşivlenir. Geçmiş satışlar kendi '
                    'versiyonuna bağlı kalır.',
            style: context.labelStyle,
          ),
        ],
      ),
    );
  }

  static String _roundingLabel(String rule) => switch (rule) {
    RoundingRule.nearest1 => 'En yakın 1 TL',
    RoundingRule.nearest5 => 'En yakın 5 TL',
    RoundingRule.nearest10 => 'En yakın 10 TL',
    _ => 'Yuvarlama yok',
  };
}

/// Tek ürünün eski ↔ yeni fiyatı ve değişim yüzdesi.
class _PreviewTile extends StatelessWidget {
  final PricePreviewRow row;

  const _PreviewTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final change = row.changePercent;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.productName, overflow: TextOverflow.ellipsis),
                Text(
                  row.oldPrice == null
                      ? 'İlk fiyat'
                      : 'Eski ${TrFormat.unitPrice(row.oldPrice!)}',
                  style: context.labelStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                TrFormat.unitPrice(row.newPrice),
                style: context.numberStyle,
              ),
              if (change != null)
                Text(
                  TrFormat.percent(change),
                  style: context.labelStyle.copyWith(
                    // İndirim kırmızı: zam beklenirken düşen fiyat
                    // gözden kaçmamalı.
                    color: change < Decimal.zero ? scheme.error : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
