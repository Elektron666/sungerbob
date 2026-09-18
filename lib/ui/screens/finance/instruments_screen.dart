import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/instrument_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../home/home_screen.dart' show dashboardProvider;
import 'payment_screen.dart' show cashAccountBalancesProvider;

/// Çek & Senet portföyü (SPEC §15 · BRIEF §5).
///
/// Toptan süngercilikte para büyük ölçüde evrakla döner; bu ekran "elimde ne
/// var, ne zaman ödenecek" sorusunun cevabıdır. Vadesi geçen ve yaklaşan
/// evrak üstte vurgulanır.
///
/// Durum geçişleri **iş kuralıyla sınırlıdır** (enums.dart): portföydeki bir
/// çek bankaya verilebilir veya ciro edilebilir ama doğrudan "tahsil edildi"
/// yapılamaz. Ekran yalnızca izin verilen geçişleri gösterir.
class InstrumentsScreen extends ConsumerWidget {
  const InstrumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Çek & Senet'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Alınan'),
              Tab(text: 'Verilen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _InstrumentList(direction: InstrumentDirection.incoming),
            _InstrumentList(direction: InstrumentDirection.outgoing),
          ],
        ),
      ),
    );
  }
}

final instrumentsProvider = FutureProvider.autoDispose
    .family<List<Instrument>, String>((ref, direction) async {
      final db = await ref.watch(databaseProvider.future);
      return (db.select(db.instruments)
            ..where((i) => i.direction.equals(direction))
            ..orderBy([(i) => OrderingTerm.asc(i.dueDate)]))
          .get();
    });

class _InstrumentList extends ConsumerWidget {
  final String direction;
  const _InstrumentList({required this.direction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(instrumentsProvider(direction));
    final incoming = direction == InstrumentDirection.incoming;

    return items.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(instrumentsProvider(direction)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: incoming ? 'Alınan evrak yok' : 'Verilen evrak yok',
            description: incoming
                ? 'Tahsilatta çek veya senet aldığında burada görünür.'
                : 'Ödemede çek veya senet verdiğinde burada görünür.',
          );
        }

        // Portföy toplamı: yalnızca elde duran evrak sayılır.
        final open = list.where(
          (i) => incoming
              ? InstrumentStatus.inPortfolio.contains(i.currentStatus)
              : i.currentStatus == InstrumentStatus.issued,
        );
        final total = open.fold(Money.zero, (sum, i) => sum + i.amount);

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _PortfolioTotal(
              label: incoming ? 'PORTFÖYDE' : 'VERİLEN, ÖDENMEMİŞ',
              total: total,
              count: open.length,
            ),
            for (final item in list)
              _InstrumentTile(instrument: item, incoming: incoming),
          ],
        );
      },
    );
  }
}

class _PortfolioTotal extends StatelessWidget {
  final String label;
  final Money total;
  final int count;

  const _PortfolioTotal({
    required this.label,
    required this.total,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.eyebrowStyle),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              TrFormat.moneyWithCurrency(total),
              style: context.bigNumberStyle,
            ),
          ),
          const SizedBox(height: 2),
          Text('$count adet', style: context.labelStyle),
        ],
      ),
    );
  }
}

class _InstrumentTile extends ConsumerWidget {
  final Instrument instrument;
  final bool incoming;

  const _InstrumentTile({required this.instrument, required this.incoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final due = DateTime.fromMillisecondsSinceEpoch(instrument.dueDate);
    final today = DateTime.now();
    final daysLeft = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;

    final settled = _isSettled(instrument.currentStatus);
    final overdue = !settled && daysLeft < 0;
    final soon = !settled && daysLeft >= 0 && daysLeft <= 7;

    return ListTile(
      leading: Icon(
        instrument.kind == InstrumentKind.check
            ? Icons.receipt_long
            : Icons.description,
        color: overdue
            ? scheme.error
            : soon
            ? scheme.tertiary
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${_kindLabel(instrument.kind)} · ${instrument.serialNo ?? 'seri no yok'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            TrFormat.moneyWithCurrency(instrument.amount),
            style: context.numberStyle,
          ),
        ],
      ),
      subtitle: Text(
        '${TrFormat.date(due)} · ${_statusLabel(instrument.currentStatus)}'
        '${overdue
            ? ' · ${-daysLeft} gün gecikti'
            : soon
            ? ' · $daysLeft gün kaldı'
            : ''}',
        style: context.labelStyle.copyWith(
          color: overdue ? scheme.error : null,
        ),
      ),
      trailing: settled ? null : const Icon(Icons.chevron_right, size: 18),
      onTap: settled ? null : () => _openActions(context, ref),
    );
  }

  static bool _isSettled(String status) => const [
    InstrumentStatus.collected,
    InstrumentStatus.returned,
    InstrumentStatus.bounced,
    InstrumentStatus.paid,
    InstrumentStatus.takenBack,
  ].contains(status);

  Future<void> _openActions(BuildContext context, WidgetRef ref) async {
    final allowed = incoming
        ? InstrumentStatus.incomingTransitions[instrument.currentStatus] ??
              const <String>[]
        : InstrumentStatus.outgoingTransitions[instrument.currentStatus] ??
              const <String>[];

    if (allowed.isEmpty) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_kindLabel(instrument.kind)} · '
                      '${TrFormat.moneyWithCurrency(instrument.amount)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            for (final status in allowed)
              ListTile(
                leading: Icon(_actionIcon(status)),
                title: Text(_actionLabel(status)),
                onTap: () => Navigator.of(context).pop(status),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Tahsil ve ödeme kasaya girer/çıkar; hangi hesaba işleneceği sorulur.
    String? accountId;
    if (picked == InstrumentStatus.collected ||
        picked == InstrumentStatus.paid) {
      accountId = await _askAccount(context, ref);
      if (accountId == null) return;
    }
    try {
      final repo = InstrumentRepository(
        await ref.read(databaseProvider.future),
      );
      await repo.changeStatus(
        instrumentId: instrument.id,
        toStatus: picked,
        cashAccountId: accountId,
        ctx: OperationContext(commandType: 'INSTRUMENT_STATUS'),
      );

      ref.invalidate(instrumentsProvider(instrument.direction));
      ref.invalidate(cashAccountBalancesProvider);
      ref.invalidate(dashboardProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${_actionLabel(picked)} olarak işlendi')),
      );
    } on InvalidInstrumentTransitionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('İşlenemedi: $e')));
    }
  }

  Future<String?> _askAccount(BuildContext context, WidgetRef ref) async {
    final accounts = await ref.read(cashAccountBalancesProvider.future);
    if (accounts.isEmpty) return null;
    if (accounts.length == 1) return accounts.first.id;
    if (!context.mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Hangi hesaba işlensin?'),
            ),
            for (final a in accounts)
              ListTile(
                title: Text(a.name),
                trailing: Text(TrFormat.moneyWithCurrency(a.balance)),
                onTap: () => Navigator.of(context).pop(a.id),
              ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(String kind) =>
      kind == InstrumentKind.check ? 'Çek' : 'Senet';

  static String _statusLabel(String status) => switch (status) {
    InstrumentStatus.portfolio => 'Portföyde',
    InstrumentStatus.atBank => 'Bankada',
    InstrumentStatus.collected => 'Tahsil edildi',
    InstrumentStatus.endorsed => 'Ciro edildi',
    InstrumentStatus.bounced => 'Karşılıksız',
    InstrumentStatus.returned => 'İade edildi',
    InstrumentStatus.issued => 'Verildi',
    InstrumentStatus.paid => 'Ödendi',
    _ => 'Geri alındı',
  };

  static String _actionLabel(String status) => switch (status) {
    InstrumentStatus.atBank => 'Bankaya ver',
    InstrumentStatus.collected => 'Tahsil edildi',
    InstrumentStatus.endorsed => 'Ciro et',
    InstrumentStatus.bounced => 'Karşılıksız çıktı',
    InstrumentStatus.returned => 'Müşteriye iade et',
    InstrumentStatus.paid => 'Ödendi',
    _ => 'Geri aldım',
  };

  static IconData _actionIcon(String status) => switch (status) {
    InstrumentStatus.atBank => Icons.account_balance,
    InstrumentStatus.collected || InstrumentStatus.paid => Icons.check_circle,
    InstrumentStatus.endorsed => Icons.forward,
    InstrumentStatus.bounced => Icons.error_outline,
    _ => Icons.undo,
  };
}
