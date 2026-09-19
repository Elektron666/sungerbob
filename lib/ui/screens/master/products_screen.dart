import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/product_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../stock/stock_screen.dart' show productsProvider;

/// Ürünler — sünger çeşitleri ve **ince malzeme**.
///
/// Uygulama 12 sünger çeşidiyle kurulur ama işletme kendi çeşidini ve
/// yanında sattığı çiviyi, yapıştırıcıyı, zikzak yayı da eklemek ister.
/// Bu ekran olmadan 12 üründen fazlasına çıkılamıyordu.
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ürünler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Yeni ürün'),
      ),
      body: products.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(productsProvider),
        ),
        data: (list) {
          final foam = list.where((p) => p.unit == ProductUnit.m3).toList();
          final other = list.where((p) => p.unit != ProductUnit.m3).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const SectionHeader(title: 'Sünger çeşitleri'),
              for (final p in foam)
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.code} · katsayı ${TrFormat.rate(p.priceCoefficient)}',
                    style: context.labelStyle,
                  ),
                ),
              SectionHeader(
                title: 'İnce malzeme',
                trailing: other.isEmpty
                    ? null
                    : Text('${other.length}', style: context.labelStyle),
              ),
              if (other.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'Çivi, yapıştırıcı, zikzak yay gibi yanında sattığın '
                    'malzemeleri de buraya ekleyebilirsin. Ölçü sorulmaz, '
                    'kendi biriminden (adet, kg, kutu…) girilir.',
                    style: context.labelStyle,
                  ),
                )
              else
                for (final p in other)
                  ListTile(
                    leading: const Icon(Icons.hardware_outlined),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.code} · ${ProductUnit.label(p.unit)}',
                      style: context.labelStyle,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (created != null) ref.invalidate(productsProvider);
  }
}

/// Ürün kartı açma.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _coefficient = TextEditingController(text: '1');
  final _commandId = const Uuid().v7();

  String _unit = ProductUnit.m3;
  String? _nameError;
  String? _error;
  bool _saving = false;

  bool get _isFoam => _unit == ProductUnit.m3;

  @override
  void dispose() {
    for (final c in [_name, _price, _coefficient]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Ürün adı girin');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _nameError = null;
    });

    try {
      final repo = ProductRepository(await ref.read(databaseProvider.future));
      final id = await repo.create(
        name: name,
        unit: _unit,
        priceCoefficient: _isFoam
            ? TrFormat.parseRate(_coefficient.text)
            : null,
        defaultSalePrice: TrFormat.parseUnitPrice(_price.text),
        ctx: OperationContext(
          commandType: 'PRODUCT_CREATE',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _FormAppBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Ürün adı',
              helperText: _isFoam
                  ? 'Ör. Beyaz Sünger 28 DNS'
                  : 'Ör. Sünger Yapıştırıcı, Zikzak Yay',
              errorText: _nameError,
            ),
            onChanged: (_) => setState(() => _nameError = null),
          ),
          const SizedBox(height: 24),
          Text('BİRİM', style: context.eyebrowStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final unit in ProductUnit.all)
                ChoiceChip(
                  label: Text(
                    unit == ProductUnit.m3
                        ? 'm³ (sünger)'
                        : ProductUnit.label(unit),
                  ),
                  selected: _unit == unit,
                  onSelected: (_) => setState(() => _unit = unit),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isFoam
                ? 'Sünger ölçüye göre satılır; en, boy ve kalınlık stok '
                      'girişinde sorulur.'
                : 'İnce malzemede ölçü sorulmaz. Miktar doğrudan '
                      '${ProductUnit.label(_unit)} olarak girilir.',
            style: context.labelStyle,
          ),
          if (_isFoam) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _coefficient,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fiyat katsayısı',
                helperText: 'Beyaz sünger 1,00 kabul edilir (SPEC §13)',
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Varsayılan satış fiyatı (opsiyonel)',
              suffixText: ProductUnit.priceLabel(_unit),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Ürünü kaydet'),
          ),
        ),
      ),
    );
  }
}

class _FormAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _FormAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Yeni ürün'));
}
