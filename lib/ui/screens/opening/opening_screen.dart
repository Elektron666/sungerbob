import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repo/unit_of_work.dart';
import '../../../data/repo/variant_helper.dart';
import '../../../domain/core/quantity.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../finance/collection_screen.dart' show cashAccountsProvider;
import '../finance/customers_screen.dart' show customerBalancesProvider;
import '../home/home_screen.dart' show dashboardProvider;
import '../stock/stock_screen.dart' show productsProvider;

/// Açılış işlemleri (FLOWS §1).
///
/// Uygulamaya geçiş anındaki mevcut durumu kaydeder: eldeki stok, müşteri
/// alacakları ve kasa/banka bakiyeleri. Her kayıt normal bir hareket üretir;
/// **mock veri değildir**, geri alınması ancak ters hareketle olur.
class OpeningScreen extends StatelessWidget {
  const OpeningScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Açılış İşlemleri'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Stok'),
            Tab(text: 'Cari'),
            Tab(text: 'Kasa/Banka'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _OpeningStockTab(),
          _OpeningCustomerTab(),
          _OpeningCashTab(),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- açılış stok

class _OpeningStockTab extends ConsumerStatefulWidget {
  const _OpeningStockTab();

  @override
  ConsumerState<_OpeningStockTab> createState() => _OpeningStockTabState();
}

class _OpeningStockTabState extends ConsumerState<_OpeningStockTab> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _thickness = TextEditingController();
  final _pieces = TextEditingController();
  final _cost = TextEditingController();
  String? _productId;
  String? _error;
  bool _saving = false;

  /// Form açılışında üretilir; aynı kayıt iki kez gönderilmez (BRIEF §3.12).
  String _commandId = const Uuid().v7();

  @override
  void dispose() {
    for (final c in [_width, _height, _thickness, _pieces, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Volume? get _volume {
    final w = TrFormat.parseDimension(_width.text);
    final h = TrFormat.parseDimension(_height.text);
    final t = TrFormat.parseDimension(_thickness.text);
    final pieces = TrFormat.parsePieces(_pieces.text);
    if (w == null || h == null || t == null || pieces == null) return null;
    return Volume.fromDimensions(
      width: w,
      height: h,
      thickness: t,
      pieces: pieces,
    );
  }

  Future<void> _save() async {
    final productId = _productId;
    final volume = _volume;
    final pieces = TrFormat.parsePieces(_pieces.text);
    final cost = TrFormat.parseUnitPrice(_cost.text);

    if (productId == null || volume == null || pieces == null || cost == null) {
      setState(() => _error = 'Çeşit, ölçü, adet ve maliyet gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = await ref.read(databaseProvider.future);
      final variantId = await db.ensureVariant(
        productId: productId,
        width: TrFormat.parseDimension(_width.text)!,
        height: TrFormat.parseDimension(_height.text)!,
        thickness: TrFormat.parseDimension(_thickness.text)!,
      );
      final repo = await ref.read(openingRepositoryProvider.future);

      await repo.openingStock(
        variantId: variantId,
        pieces: pieces,
        volume: volume,
        unitCost: cost,
        asOfDate: DateTime.now(),
        ctx: OperationContext(
          commandType: 'OPENING_STOCK',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(productsProvider);
      for (final c in [_width, _height, _thickness, _pieces, _cost]) {
        c.clear();
      }
      setState(() => _commandId = const Uuid().v7());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Açılış stoğu kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Elinizdeki stoğu maliyetiyle girin. Her satır bir açılış partisi '
          'olur ve FIFO sırasında en eski parti sayılır.',
          style: context.labelStyle,
        ),
        const SizedBox(height: 16),
        products.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(error: e),
          data: (list) => DropdownButtonFormField<String>(
            initialValue: _productId,
            decoration: const InputDecoration(labelText: 'Sünger çeşidi'),
            items: [
              for (final product in list)
                DropdownMenuItem(value: product.id, child: Text(product.name)),
            ],
            onChanged: (v) => setState(() => _productId = v),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _numberField(_width, 'En (cm)')),
            const SizedBox(width: 8),
            Expanded(child: _numberField(_height, 'Boy (cm)')),
            const SizedBox(width: 8),
            Expanded(child: _numberField(_thickness, 'Kalınlık (cm)')),
          ],
        ),
        const SizedBox(height: 16),
        _numberField(_pieces, 'Adet'),
        const SizedBox(height: 16),
        _numberField(_cost, 'Birim maliyet (TL/m³, KDV hariç)'),
        const SizedBox(height: 16),
        if (_volume != null)
          Text(
            'Toplam hacim: ${TrFormat.volume(_volume!)}',
            style: context.numberStyle,
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Açılış stoğunu kaydet'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );
}

// ---------------------------------------------------------------- açılış cari

class _OpeningCustomerTab extends ConsumerStatefulWidget {
  const _OpeningCustomerTab();

  @override
  ConsumerState<_OpeningCustomerTab> createState() =>
      _OpeningCustomerTabState();
}

class _OpeningCustomerTabState extends ConsumerState<_OpeningCustomerTab> {
  final _amount = TextEditingController();
  String? _customerId;
  DateTime? _dueDate;
  String? _error;
  bool _saving = false;
  String _commandId = const Uuid().v7();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final customerId = _customerId;
    final amount = TrFormat.parseMoney(_amount.text);

    if (customerId == null || amount == null || !amount.isPositive) {
      setState(() => _error = 'Müşteri ve sıfırdan büyük tutar gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(openingRepositoryProvider.future);
      await repo.openingCustomerBalance(
        customerId: customerId,
        amount: amount,
        asOfDate: DateTime.now(),
        dueDate: _dueDate,
        ctx: OperationContext(
          commandType: 'OPENING_CUSTOMER',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(customerBalancesProvider);
      ref.invalidate(dashboardProvider);
      _amount.clear();
      setState(() {
        _dueDate = null;
        _commandId = const Uuid().v7();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Açılış bakiyesi kaydedildi')),
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
    final customers = ref.watch(customerBalancesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Müşterinin size olan mevcut borcunu girin. Tahsilat yapıldığında '
          'bu bakiye hedef olarak eşleştirilebilir.',
          style: context.labelStyle,
        ),
        const SizedBox(height: 16),
        customers.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(error: e),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  title: 'Henüz müşteri yok',
                  description: 'Önce Cari ekranından müşteri ekleyin.',
                )
              : DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  decoration: const InputDecoration(labelText: 'Müşteri'),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(value: c.id, child: Text(c.title)),
                  ],
                  onChanged: (v) => setState(() => _customerId = v),
                ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Borç tutarı (TL)',
            helperText: 'Cariye brüt yazılır',
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(
            _dueDate == null ? 'Vade (opsiyonel)' : TrFormat.date(_dueDate),
          ),
          trailing: _dueDate == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _dueDate = null),
                ),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now.add(const Duration(days: 730)),
              initialDate: _dueDate ?? now,
              locale: const Locale('tr', 'TR'),
            );
            if (picked != null) setState(() => _dueDate = picked);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Açılış bakiyesini kaydet'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- açılış kasa

class _OpeningCashTab extends ConsumerStatefulWidget {
  const _OpeningCashTab();

  @override
  ConsumerState<_OpeningCashTab> createState() => _OpeningCashTabState();
}

class _OpeningCashTabState extends ConsumerState<_OpeningCashTab> {
  final _amount = TextEditingController();
  String? _accountId;
  String? _error;
  bool _saving = false;
  String _commandId = const Uuid().v7();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final accountId = _accountId;
    final amount = TrFormat.parseMoney(_amount.text);

    if (accountId == null || amount == null) {
      setState(() => _error = 'Hesap ve tutar gerekli.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(openingRepositoryProvider.future);
      await repo.openingCashBalance(
        cashAccountId: accountId,
        amount: amount,
        asOfDate: DateTime.now(),
        ctx: OperationContext(
          commandType: 'OPENING_CASH',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      _amount.clear();
      setState(() => _commandId = const Uuid().v7());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Açılış bakiyesi kaydedildi')),
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
    final accounts = ref.watch(cashAccountsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Kasa ve banka hesaplarınızdaki mevcut tutarı girin.',
          style: context.labelStyle,
        ),
        const SizedBox(height: 16),
        accounts.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(error: e),
          data: (list) => DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Hesap'),
            items: [
              for (final a in list)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Tutar (TL)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Açılış bakiyesini kaydet'),
        ),
      ],
    );
  }
}
