import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repo/analytics_queries.dart';
import '../../../domain/core/money.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'period_sales_chart.dart';
import 'report_export.dart';

/// Raporlar (SPEC §19, §20, §25).
///
/// Tüm kâr ve ciro rakamları **KDV hariçtir** (BRIEF §3.4).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Raporlar'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Kârlılık'),
              Tab(text: 'Satış grafiği'),
              Tab(text: 'Ürünler'),
              Tab(text: 'Müşteriler'),
              Tab(text: 'Vadeler'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProfitabilityTab(),
            _PeriodTab(),
            _ProductTab(),
            _CustomerTab(),
            _DueTab(),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- dönem seçimi

/// Rapor dönemi. Varsayılan: içinde bulunulan ay.
final reportRangeProvider =
    NotifierProvider<ReportRangeNotifier, DateTimeRange>(
      ReportRangeNotifier.new,
    );

class ReportRangeNotifier extends Notifier<DateTimeRange> {
  @override
  DateTimeRange build() => thisMonth();

  static DateTimeRange thisMonth({DateTime? now}) {
    final today = now ?? DateTime.now();
    return DateTimeRange(
      start: DateTime(today.year, today.month),
      // Ayın son gününün sonuna kadar.
      end: DateTime(
        today.year,
        today.month + 1,
      ).subtract(const Duration(milliseconds: 1)),
    );
  }

  static DateTimeRange thisYear({DateTime? now}) {
    final today = now ?? DateTime.now();
    return DateTimeRange(
      start: DateTime(today.year),
      end: DateTime(today.year + 1).subtract(const Duration(milliseconds: 1)),
    );
  }

  void set(DateTimeRange range) => state = range;
}

class _RangeBar extends ConsumerWidget {
  const _RangeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${TrFormat.date(range.start)} – ${TrFormat.date(range.end)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(reportRangeProvider.notifier)
                .set(ReportRangeNotifier.thisMonth()),
            child: const Text('Bu ay'),
          ),
          TextButton(
            onPressed: () => ref
                .read(reportRangeProvider.notifier)
                .set(ReportRangeNotifier.thisYear()),
            child: const Text('Bu yıl'),
          ),
          IconButton(
            tooltip: 'Tarih aralığı seç',
            icon: const Icon(Icons.date_range),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                initialDateRange: range,
                locale: const Locale('tr', 'TR'),
              );
              if (picked != null) {
                ref.read(reportRangeProvider.notifier).set(picked);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ kârlılık

final profitabilityProvider = FutureProvider.autoDispose((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final range = ref.watch(reportRangeProvider);
  return db.profitability(from: range.start, to: range.end);
});

class _ProfitabilityTab extends ConsumerWidget {
  const _ProfitabilityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(profitabilityProvider);
    final hideCost = ref.watch(hideCostProvider);

    return Column(
      children: [
        const _RangeBar(),
        Expanded(
          child: report.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(profitabilityProvider),
            ),
            data: (r) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MoneyRow(label: 'Ciro (KDV hariç)', value: r.revenue),
                _MoneyRow(
                  label: 'Satılan malın maliyeti',
                  value: r.costOfGoods,
                  hidden: hideCost,
                ),
                const Divider(),
                _MoneyRow(
                  label: 'Brüt kâr',
                  value: r.grossProfit,
                  hidden: hideCost,
                  emphasis: true,
                ),
                if (r.grossMarginPercent != null)
                  _TextRow(
                    label: 'Brüt kâr marjı',
                    value: hideCost
                        ? '••••'
                        : '%${TrFormat.percent(r.grossMarginPercent)}',
                  ),
                const Divider(),
                _MoneyRow(label: 'İadeler', value: r.returns),
                _MoneyRow(label: 'Fire', value: r.waste, hidden: hideCost),
                _MoneyRow(
                  label: 'Maliyet farkları',
                  value: r.costAdjustments,
                  hidden: hideCost,
                ),
                _MoneyRow(label: 'Giderler', value: r.expenses),
                const Divider(),
                _MoneyRow(
                  label: 'Net kâr',
                  value: r.netProfit,
                  hidden: hideCost,
                  emphasis: true,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => shareProfitabilityCsv(
                    context,
                    report: r,
                    range: ref.read(reportRangeProvider),
                  ),
                  icon: const Icon(Icons.table_view),
                  label: const Text('CSV olarak paylaş'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- satış grafiği

final periodSalesProvider = FutureProvider.autoDispose((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final range = ref.watch(reportRangeProvider);
  // Bir aydan uzun aralıklarda ay, kısa aralıklarda gün kırılımı.
  final granularity = range.duration > const Duration(days: 62)
      ? 'month'
      : 'day';
  return (
    granularity: granularity,
    rows: await db.salesByPeriod(
      from: range.start,
      to: range.end,
      granularity: granularity,
    ),
  );
});

class _PeriodTab extends ConsumerWidget {
  const _PeriodTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(periodSalesProvider);
    final hideCost = ref.watch(hideCostProvider);

    return Column(
      children: [
        const _RangeBar(),
        Expanded(
          child: data.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(periodSalesProvider),
            ),
            data: (d) => d.rows.isEmpty
                ? const EmptyState(
                    icon: Icons.show_chart,
                    title: 'Bu dönemde satış yok',
                    description: 'Tarih aralığını değiştirin veya satış girin.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SizedBox(
                        height: 260,
                        child: PeriodSalesChart(
                          rows: d.rows,
                          granularity: d.granularity,
                          showProfit: !hideCost,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final row in d.rows)
                        ListTile(
                          dense: true,
                          title: Text(
                            d.granularity == 'month'
                                ? TrFormat.monthYear(row.period)
                                : TrFormat.date(row.period),
                          ),
                          subtitle: Text('${row.count} satış'),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                TrFormat.moneyWithCurrency(row.net),
                                style: context.numberStyle,
                              ),
                              SensitiveValue(
                                hidden: hideCost,
                                value: 'kâr ${TrFormat.money(row.profit)}',
                                style: context.labelStyle,
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => sharePeriodSalesCsv(
                          context,
                          rows: d.rows,
                          granularity: d.granularity,
                        ),
                        icon: const Icon(Icons.table_view),
                        label: const Text('CSV olarak paylaş'),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- ürün analizi

final productAnalysisProvider = FutureProvider.autoDispose((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return db.productAnalysis();
});

class _ProductTab extends ConsumerWidget {
  const _ProductTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(productAnalysisProvider);
    final hideCost = ref.watch(hideCostProvider);

    return data.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(productAnalysisProvider),
      ),
      data: (rows) => rows.isEmpty
          ? const EmptyState(
              icon: Icons.category_outlined,
              title: 'Henüz ürün hareketi yok',
              description: 'Alış ve satış girdikçe burası dolar.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final p in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _TextRow(
                            label: 'Stokta',
                            value:
                                '${TrFormat.volume(p.currentVolume)} · ${TrFormat.pieces(p.currentPieces)}',
                          ),
                          _TextRow(
                            label: 'Satılan',
                            value: TrFormat.volume(p.soldVolume),
                          ),
                          _MoneyRow(label: 'Ciro', value: p.revenue),
                          _MoneyRow(
                            label: 'Brüt kâr',
                            value: p.grossProfit,
                            hidden: hideCost,
                          ),
                          _TextRow(
                            label: 'Ort. maliyet',
                            value: hideCost
                                ? '••••'
                                : TrFormat.unitPrice(p.averageCost),
                          ),
                          _TextRow(
                            label: 'Ort. satış',
                            value: TrFormat.unitPrice(p.averageSalePrice),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => shareProductAnalysisCsv(context, rows: rows),
                  icon: const Icon(Icons.table_view),
                  label: const Text('CSV olarak paylaş'),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------- müşteri analizi

/// Bütün müşterilerin analizi, cirosu büyükten küçüğe.
///
/// `customerAnalysis` Faz 4'te yazılmıştı ama hiçbir ekrandan
/// çağrılmıyordu (SK-22): "hangi müşteri ne kadar aldı, ne kadar kâr
/// bıraktı, ne kadar geç ödüyor" sorusunun cevabı yoktu.
final customerAnalysisProvider =
    FutureProvider.autoDispose<List<CustomerAnalysis>>((ref) async {
      final db = await ref.watch(databaseProvider.future);
      final customers = await (db.select(
        db.customers,
      )..where((c) => c.isActive.equals(true))).get();

      final result = <CustomerAnalysis>[];
      for (final customer in customers) {
        result.add(await db.customerAnalysis(customer.id));
      }

      // Hiç alışveriş yapmamış cariyi raporda göstermek gürültüdür.
      result.removeWhere((a) => a.totalSales.isZero && a.currentDebt.isZero);
      result.sort((a, b) => b.totalSales.stored.compareTo(a.totalSales.stored));
      return result;
    });

class _CustomerTab extends ConsumerWidget {
  const _CustomerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(customerAnalysisProvider);
    final hideCost = ref.watch(hideCostProvider);

    return data.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(customerAnalysisProvider),
      ),
      data: (rows) => rows.isEmpty
          ? const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Henüz müşteri hareketi yok',
              description: 'Satış girdikçe burası dolar.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final c in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _MoneyRow(
                            label: 'Ciro (KDV hariç)',
                            value: c.totalSales,
                          ),
                          _MoneyRow(
                            label: 'Brüt kâr',
                            value: c.grossProfit,
                            hidden: hideCost,
                          ),
                          _TextRow(
                            label: 'Aldığı hacim',
                            value: TrFormat.volume(c.totalVolume),
                          ),
                          _MoneyRow(
                            label: 'Tahsil edilen',
                            value: c.totalCollected,
                          ),
                          _MoneyRow(
                            label: 'Güncel borç',
                            value: c.currentDebt,
                            emphasis: true,
                          ),
                          if (c.topProductName != null)
                            _TextRow(
                              label: 'En çok aldığı',
                              value: c.topProductName!,
                            ),
                          _TextRow(
                            label: 'Son satış',
                            value: c.lastSaleAt == null
                                ? '—'
                                : TrFormat.date(c.lastSaleAt),
                          ),
                          // Toptancının asıl sorusu: parasını ne zaman
                          // alıyor. Vade değil, gerçekleşen ödeme süresi.
                          _TextRow(
                            label: 'Ort. ödeme süresi',
                            value: c.averagePaymentDays == null
                                ? 'henüz kapanmış belge yok'
                                : '${c.averagePaymentDays} gün',
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      shareCustomerAnalysisCsv(context, rows: rows),
                  icon: const Icon(Icons.table_view),
                  label: const Text('CSV olarak paylaş'),
                ),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------- vade raporu

final dueInstrumentsProvider = FutureProvider.autoDispose((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final now = DateTime.now();
  return db.instrumentsDueReport(
    from: now.subtract(const Duration(days: 365)),
    to: now.add(const Duration(days: 90)),
  );
});

class _DueTab extends ConsumerWidget {
  const _DueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dueInstrumentsProvider);
    final today = DateTime.now();

    return data.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(dueInstrumentsProvider),
      ),
      data: (rows) => rows.isEmpty
          ? const EmptyState(
              icon: Icons.event_available,
              title: 'Vadesi yaklaşan evrak yok',
            )
          : ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = rows[i];
                final due = DateTime.fromMillisecondsSinceEpoch(it.dueDate);
                final overdue = due.isBefore(
                  DateTime(today.year, today.month, today.day),
                );
                return ListTile(
                  leading: Icon(
                    it.kind == 'CEK' ? Icons.receipt_long : Icons.description,
                    color: overdue ? Theme.of(context).colorScheme.error : null,
                  ),
                  title: Text('${it.kind} · ${it.serialNo ?? '—'}'),
                  subtitle: Text(
                    '${TrFormat.date(due)}${overdue ? " · vadesi geçti" : ""}',
                  ),
                  trailing: Text(
                    TrFormat.moneyWithCurrency(it.amount),
                    style: context.numberStyle,
                  ),
                );
              },
            ),
    );
  }
}

// ------------------------------------------------------------------ parçalar

class _MoneyRow extends StatelessWidget {
  final String label;
  final Money value;
  final bool hidden;
  final bool emphasis;

  const _MoneyRow({
    required this.label,
    required this.value,
    this.hidden = false,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    // Etiket esner ve gerekirse kırpılır; rakam asla kırpılmaz. Uzun
    // etiketler ve büyük yazı tipi ayarında satır taşıyordu.
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: emphasis
                ? Theme.of(context).textTheme.titleSmall
                : context.labelStyle,
          ),
        ),
        const SizedBox(width: 12),
        SensitiveValue(
          hidden: hidden,
          value: TrFormat.moneyWithCurrency(value),
          style: emphasis
              ? context.numberStyle.copyWith(fontWeight: FontWeight.w600)
              : context.numberStyle,
        ),
      ],
    ),
  );
}

class _TextRow extends StatelessWidget {
  final String label;
  final String value;

  const _TextRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    // `_MoneyRow`'dan farkı: buradaki değer rakam değil **metin** olabilir
    // (ürün adı, "henüz kapanmış belge yok"). Bu yüzden iki taraf da esner;
    // para satırında rakam asla kırpılmaz, burada kırpılabilir.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: context.labelStyle,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.numberStyle,
          ),
        ),
      ],
    ),
  );
}
