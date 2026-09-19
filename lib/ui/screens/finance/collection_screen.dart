import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/collection_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/party_picker.dart';
import '../home/home_screen.dart';
import 'customers_screen.dart';

/// Tahsilat (SPEC §10 · BRIEF §3.10).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _commandId = uuid.v7();
  final _amountController = TextEditingController();

  String? _customerId;
  String _method = PaymentMethod.cash;
  String? _accountId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final customerId = _customerId;
    final amount = TrFormat.parseMoney(_amountController.text);
    if (customerId == null || amount == null || !amount.isPositive) {
      setState(() => _error = 'Müşteri ve tutar gerekli.');
      return;
    }
    if (PaymentMethod.needsAccount.contains(_method) && _accountId == null) {
      setState(() => _error = 'Kasa veya banka hesabı seçin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = await ref.read(collectionRepositoryProvider.future);
      await repo.create(
        CollectionInput(
          customerId: customerId,
          docDate: DateTime.now(),
          amount: amount,
          method: _method,
          cashAccountId: _accountId,
          instrument: PaymentMethod.needsInstrument.contains(_method)
              ? InstrumentInput(
                  kind: _method == PaymentMethod.check
                      ? InstrumentKind.check
                      : InstrumentKind.note,
                  dueDate: DateTime.now().add(const Duration(days: 30)),
                )
              : null,
        ),
        OperationContext(
          commandType: 'COLLECTION_CREATE',
          commandId: _commandId,
        ),
      );

      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ref.invalidate(customerBalancesProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tahsilat kaydedildi')));
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

    return Scaffold(
      appBar: AppBar(title: const Text('Tahsilat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartyPicker(
            supplier: false,
            label: 'Müşteri',
            value: _customerId,
            onChanged: (id) => setState(() => _customerId = id),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tutar (TL)'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Ödeme yöntemi'),
            items: const [
              DropdownMenuItem(value: PaymentMethod.cash, child: Text('Nakit')),
              DropdownMenuItem(
                value: PaymentMethod.transfer,
                child: Text('Havale/EFT'),
              ),
              DropdownMenuItem(
                value: PaymentMethod.card,
                child: Text('Kredi kartı'),
              ),
              DropdownMenuItem(value: PaymentMethod.check, child: Text('Çek')),
              DropdownMenuItem(value: PaymentMethod.note, child: Text('Senet')),
            ],
            onChanged: (m) => setState(() => _method = m ?? PaymentMethod.cash),
          ),
          if (PaymentMethod.needsAccount.contains(_method)) ...[
            const SizedBox(height: 16),
            accounts.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Kasa / Banka'),
                items: [
                  for (final a in list)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (id) => setState(() => _accountId = id),
              ),
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
          const SizedBox(height: 16),
          Text(
            'Tahsilat, vadesi en erken açık satışlardan başlayarak otomatik '
            'eşleştirilir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final cashAccountsProvider = FutureProvider.autoDispose<List<CashAccount>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(
    db.cashAccounts,
  )..where((a) => a.isActive.equals(true))).get();
});
