import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/payment_repository.dart';
import '../../../data/repo/stock_queries.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/party_picker.dart';
import '../home/home_screen.dart' show dashboardProvider;

/// Tedarikçiye ödeme (BRIEF §3.10).
///
/// Tahsilatın aynadaki görüntüsü: para dışarı çıkar, tedarikçi borcu azalır.
/// Eşleştirme en eski borçtan başlar (FIFO), repository tarafında yapılır.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  /// Form açılışında üretilir; aynı ödeme iki kez işlenmez (BRIEF §3.12).
  final _commandId = uuid.v7();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String? _supplierId;
  String _method = PaymentMethod.cash;
  String? _accountId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _needsAccount => PaymentMethod.needsAccount.contains(_method);

  Future<void> _save() async {
    final supplierId = _supplierId;
    final amount = TrFormat.parseMoney(_amountController.text);

    final missing = switch (null) {
      _ when supplierId == null => 'Tedarikçi seçin',
      _ when amount == null || !amount.isPositive => 'Tutar girin',
      _ when _needsAccount && _accountId == null => 'Kasa/banka hesabı seçin',
      _ => null,
    };
    if (missing != null || supplierId == null || amount == null) {
      setState(() => _error = missing ?? 'Eksik alan var');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = PaymentRepository(await ref.read(databaseProvider.future));
      await repo.paySupplier(
        SupplierPaymentInput(
          supplierId: supplierId,
          docDate: DateTime.now(),
          amount: amount,
          method: _method,
          cashAccountId: _needsAccount ? _accountId : null,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
        OperationContext(
          commandType: 'SUPPLIER_PAYMENT',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(supplierBalanceProvider);
      ref.invalidate(cashAccountBalancesProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ödeme kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ödeme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartyPicker(
            supplier: true,
            label: 'Tedarikçi',
            value: _supplierId,
            onChanged: (id) => setState(() {
              _supplierId = id;
              _error = null;
            }),
          ),
          // Ne kadar borcu var? Ödeme tutarını yazarken en çok gereken bilgi.
          if (_supplierId case final id?) ...[
            const SizedBox(height: 8),
            _SupplierDebt(supplierId: id),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tutar (TL)',
              helperText: 'En eski borçtan başlayarak kapatılır',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 20),
          Text('ÖDEME ŞEKLİ', style: context.eyebrowStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                PaymentMethod.cash: 'Nakit',
                PaymentMethod.transfer: 'Havale',
                PaymentMethod.card: 'Kart',
                PaymentMethod.check: 'Çek',
                PaymentMethod.note: 'Senet',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _method == entry.key,
                  onSelected: (_) => setState(() {
                    _method = entry.key;
                    _error = null;
                  }),
                ),
            ],
          ),
          if (_needsAccount) ...[
            const SizedBox(height: 16),
            _AccountPicker(
              value: _accountId,
              onChanged: (id) => setState(() {
                _accountId = id;
                _error = null;
              }),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Çek veya senetle ödeme, Çek & Senet ekranından verilen evrak '
              'olarak kaydedilir.',
              style: context.labelStyle,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Açıklama (opsiyonel)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Ödemeyi kaydet'),
          ),
        ),
      ),
    );
  }
}

/// Tedarikçinin güncel borcu.
final supplierBalanceProvider = FutureProvider.autoDispose
    .family<Money, String>((ref, supplierId) async {
      final db = await ref.watch(databaseProvider.future);
      return db.supplierBalance(supplierId);
    });

class _SupplierDebt extends ConsumerWidget {
  final String supplierId;
  const _SupplierDebt({required this.supplierId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(supplierBalanceProvider(supplierId));
    final scheme = Theme.of(context).colorScheme;

    return balance.when(
      loading: () =>
          const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radius - 4),
        ),
        child: Row(
          children: [
            Expanded(child: Text('Güncel borç', style: context.labelStyle)),
            Text(TrFormat.moneyWithCurrency(value), style: context.numberStyle),
          ],
        ),
      ),
    );
  }
}

/// Kasa/banka hesapları ve bakiyeleri.
final class AccountBalance {
  final String id;
  final String name;
  final String kind;
  final Money balance;

  const AccountBalance({
    required this.id,
    required this.name,
    required this.kind,
    required this.balance,
  });
}

final cashAccountBalancesProvider =
    FutureProvider.autoDispose<List<AccountBalance>>((ref) async {
      final db = await ref.watch(databaseProvider.future);
      final accounts = await (db.select(
        db.cashAccounts,
      )..where((a) => a.isActive.equals(true))).get();

      return [
        for (final account in accounts)
          AccountBalance(
            id: account.id,
            name: account.name,
            kind: account.type,
            balance: await db.accountBalance(account.id),
          ),
      ];
    });

class _AccountPicker extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _AccountPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cashAccountBalancesProvider);

    return accounts.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (list) => DropdownButtonFormField<String>(
        initialValue: list.any((a) => a.id == value) ? value : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kasa / Banka'),
        hint: const Text('Hesap seçin'),
        items: [
          for (final account in list)
            DropdownMenuItem(
              value: account.id,
              child: Text(
                '${account.name} · ${TrFormat.moneyWithCurrency(account.balance)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
