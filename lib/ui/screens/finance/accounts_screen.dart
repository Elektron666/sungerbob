import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/party_repository.dart';
import '../../../data/repo/payment_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../home/home_screen.dart' show dashboardProvider;
import 'payment_screen.dart' show AccountBalance, cashAccountBalancesProvider;

/// Kasa & Banka (SPEC §16).
///
/// "Kasada ne var?" sorusunun tek cevabı. Toplam en üstte; hesaplar altında.
/// Virman buradan yapılır — para kasadan bankaya geçtiğinde cari etkilenmez,
/// yalnızca yer değiştirir.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cashAccountBalancesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasa & Banka'),
        actions: [
          IconButton(
            tooltip: 'Yeni hesap',
            icon: const Icon(Icons.add),
            onPressed: () => _openAccountForm(context, ref),
          ),
        ],
      ),
      body: accounts.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(cashAccountBalancesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Hesap yok',
              description: 'Nakit ve havale işlemleri için bir hesap açın.',
              action: FilledButton(
                onPressed: () => _openAccountForm(context, ref),
                child: const Text('Hesap aç'),
              ),
            );
          }

          final total = list.fold(Money.zero, (sum, a) => sum + a.balance);

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radius + 4),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOPLAM MEVCUT', style: context.eyebrowStyle),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          TrFormat.moneyWithCurrency(total),
                          style: context.bigNumberStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader(title: 'Hesaplar'),
              for (final account in list)
                ListTile(
                  leading: Icon(_iconFor(account.kind)),
                  title: Text(account.name),
                  subtitle: Text(
                    _typeLabel(account.kind),
                    style: context.labelStyle,
                  ),
                  trailing: Text(
                    TrFormat.moneyWithCurrency(account.balance),
                    style: context.numberStyle,
                  ),
                ),
              if (list.length > 1) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => _openTransfer(context, ref, list),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Hesaplar arası virman'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
    CashAccountType.bank => Icons.account_balance,
    CashAccountType.pos => Icons.credit_card,
    _ => Icons.payments,
  };

  static String _typeLabel(String type) => switch (type) {
    CashAccountType.bank => 'Banka',
    CashAccountType.pos => 'POS',
    _ => 'Kasa',
  };

  Future<void> _openAccountForm(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AccountFormSheet(),
    );
    if (created ?? false) ref.invalidate(cashAccountBalancesProvider);
  }

  Future<void> _openTransfer(
    BuildContext context,
    WidgetRef ref,
    List<AccountBalance> accounts,
  ) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TransferSheet(accounts: accounts),
    );
    if (done ?? false) {
      ref.invalidate(cashAccountBalancesProvider);
      ref.invalidate(dashboardProvider);
    }
  }
}

// ------------------------------------------------------------- hesap açma

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet();

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _name = TextEditingController();
  final _bank = TextEditingController();
  final _iban = TextEditingController();
  String _type = CashAccountType.cash;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _bank, _iban]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Hesap adı girin');
      return;
    }

    setState(() => _saving = true);
    try {
      final db = await ref.read(databaseProvider.future);
      // Kod unvandan türetilir; cari kartlarla aynı kural.
      final base = PartyRepository.codeFromTitle(name);
      var code = base;
      for (var i = 2; i < 100; i++) {
        final clash = await (db.select(
          db.cashAccounts,
        )..where((a) => a.code.equals(code))).getSingleOrNull();
        if (clash == null) break;
        code = '$base$i';
      }

      await db
          .into(db.cashAccounts)
          .insert(
            CashAccountsCompanion.insert(
              id: uuid.v7(),
              code: code,
              name: name,
              type: _type,
              bankName: Value(
                _bank.text.trim().isEmpty ? null : _bank.text.trim(),
              ),
              iban: Value(_iban.text.trim().isEmpty ? null : _iban.text.trim()),
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Yeni hesap', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Hesap adı',
            errorText: _error,
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: CashAccountType.cash, label: Text('Kasa')),
            ButtonSegment(value: CashAccountType.bank, label: Text('Banka')),
            ButtonSegment(value: CashAccountType.pos, label: Text('POS')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        if (_type != CashAccountType.cash) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _bank,
            decoration: const InputDecoration(labelText: 'Banka adı'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _iban,
            decoration: const InputDecoration(labelText: 'IBAN'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Hesabı aç'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ virman

class _TransferSheet extends ConsumerStatefulWidget {
  final List<AccountBalance> accounts;
  const _TransferSheet({required this.accounts});

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _commandId = uuid.v7();
  final _amount = TextEditingController();
  late String _from = widget.accounts.first.id;
  late String _to = widget.accounts.last.id;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = TrFormat.parseMoney(_amount.text);
    final missing = switch (null) {
      _ when _from == _to => 'Aynı hesaba virman yapılamaz',
      _ when amount == null || !amount.isPositive => 'Tutar girin',
      _ => null,
    };
    if (missing != null || amount == null) {
      setState(() => _error = missing ?? 'Eksik alan var');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = PaymentRepository(await ref.read(databaseProvider.future));
      await repo.transfer(
        fromAccountId: _from,
        toAccountId: _to,
        amount: amount,
        docDate: DateTime.now(),
        ctx: OperationContext(commandType: 'TRANSFER', commandId: _commandId),
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Virman', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Para hesaplar arasında yer değiştirir; cari bakiyeler etkilenmez.',
          style: context.labelStyle,
        ),
        const SizedBox(height: 20),
        _accountField('Çıkan hesap', _from, (v) => setState(() => _from = v!)),
        const SizedBox(height: 16),
        _accountField('Giren hesap', _to, (v) => setState(() => _to = v!)),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Tutar (TL)',
            errorText: _error,
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Virmanı kaydet'),
        ),
      ],
    ),
  );

  Widget _accountField(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final a in widget.accounts)
        DropdownMenuItem(
          value: a.id,
          child: Text(
            '${a.name} · ${TrFormat.moneyWithCurrency(a.balance)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
  );
}
