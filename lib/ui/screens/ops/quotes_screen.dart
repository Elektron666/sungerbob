import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/quote_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../home/home_screen.dart' show dashboardProvider;

/// Teklifler (SPEC §10 · FLOWS §5).
///
/// Teklif **stok hareketi üretmez**; kabul edilip satışa dönüştürüldüğünde
/// stok ve cari işlenir. Aynı teklif ikinci kez dönüştürülemez.
class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(quotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Teklifler')),
      body: quotes.when(
        loading: () => const LoadingState(),
        error: (e, _) =>
            ErrorState(error: e, onRetry: () => ref.invalidate(quotesProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.request_quote_outlined,
                title: 'Henüz teklif yok',
                description:
                    'Teklif, kabul edilene kadar stoğa dokunmaz. Kabul '
                    'edilince tek dokunuşla satışa dönüşür.',
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final q = list[i];
                  final convertible =
                      q.status == QuoteStatus.draft ||
                      q.status == QuoteStatus.sent ||
                      q.status == QuoteStatus.accepted;
                  return ListTile(
                    title: Text('${q.docNo} · ${q.customerTitle}'),
                    subtitle: Text(
                      '${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(q.docDate))}'
                      ' · ${_statusLabel(q.status)}'
                      '${q.validUntil == null ? "" : " · geçerlilik ${TrFormat.date(DateTime.fromMillisecondsSinceEpoch(q.validUntil!))}"}',
                      style: context.labelStyle,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          TrFormat.moneyWithCurrency(q.grandTotal),
                          style: context.numberStyle,
                        ),
                        if (convertible)
                          TextButton(
                            onPressed: () => _convert(context, ref, q.id),
                            child: const Text('Satışa çevir'),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    QuoteStatus.draft => 'Taslak',
    QuoteStatus.sent => 'Gönderildi',
    QuoteStatus.accepted => 'Kabul edildi',
    QuoteStatus.rejected => 'Reddedildi',
    QuoteStatus.expired => 'Süresi doldu',
    _ => 'Satışa çevrildi',
  };

  Future<void> _convert(
    BuildContext context,
    WidgetRef ref,
    String quoteId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(quoteRepositoryProvider.future);
      await repo.convertToSale(
        quoteId: quoteId,
        ctx: OperationContext(commandType: 'QUOTE_CONVERT'),
      );

      ref.invalidate(quotesProvider);
      ref.invalidate(dashboardProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Teklif satışa çevrildi')),
      );
    } on QuoteAlreadyConvertedException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bu teklif zaten satışa çevrilmiş')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Çevrilemedi: $e')));
    }
  }
}

final class QuoteRow {
  final String id;
  final String docNo;
  final String customerTitle;
  final int docDate;
  final int? validUntil;
  final String status;
  final Money grandTotal;

  const QuoteRow({
    required this.id,
    required this.docNo,
    required this.customerTitle,
    required this.docDate,
    required this.validUntil,
    required this.status,
    required this.grandTotal,
  });
}

final quotesProvider = FutureProvider.autoDispose<List<QuoteRow>>((ref) async {
  final db = await ref.watch(databaseProvider.future);

  // Süresi geçmiş teklifler listelenmeden önce kapatılır (FLOWS §5).
  await QuoteRepository(db).expireOverdue();

  final quotes =
      await (db.select(db.salesQuotes)
            ..orderBy([(q) => OrderingTerm.desc(q.docDate)])
            ..limit(100))
          .get();
  final customers = await db.select(db.customers).get();
  final titles = {for (final c in customers) c.id: c.title};

  return [
    for (final q in quotes)
      QuoteRow(
        id: q.id,
        docNo: q.docNo,
        customerTitle: titles[q.customerId] ?? '—',
        docDate: q.docDate,
        validUntil: q.validUntil,
        status: q.status,
        grandTotal: q.grandTotal,
      ),
  ];
});
