import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repo/dashboard_queries.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';
import 'backup_status_band.dart';

/// Ana Sayfa (BRIEF §7 + SPEC §18).
///
/// İşletmenin durumunu birkaç saniyede anlatır. Üstte yedek durum bandı,
/// altında büyük hızlı işlem butonları ve kartlar.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardProvider);
    final hideCost = ref.watch(hideCostProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sünger'),
        actions: [
          IconButton(
            tooltip: hideCost ? 'Maliyeti göster' : 'Maliyeti gizle',
            icon: Icon(hideCost ? Icons.visibility_off : Icons.visibility),
            onPressed: () => _toggleHideCost(context, ref, hideCost),
          ),
          IconButton(
            tooltip: 'Ara',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardProvider),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const BackupStatusBand(),
            const _QuickActions(),
            switch (snapshot) {
              AsyncData(:final value) => _DashboardCards(
                data: value,
                hideCost: hideCost,
              ),
              AsyncError(:final error) => SizedBox(
                height: 240,
                child: ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(dashboardProvider),
                ),
              ),
              _ => const SizedBox(height: 240, child: LoadingState()),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHideCost(
    BuildContext context,
    WidgetRef ref,
    bool currentlyHidden,
  ) async {
    if (!currentlyHidden) {
      ref.read(hideCostProvider.notifier).hide();
      return;
    }
    // Kapatmak için PIN gerekir (BRIEF §5).
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (ok ?? false) {
      ref.read(hideCostProvider.notifier).revealAfterPinVerified();
    }
  }
}

/// Ana sayfadaki gösterge verisi.
final dashboardProvider = FutureProvider.autoDispose((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return db.dashboardSnapshot();
});

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    // SPEC §22'nin büyük hızlı işlem butonları.
    const actions = [
      (label: '+ SATIŞ', route: '/sale/new', icon: Icons.point_of_sale),
      (label: '+ STOK GİRİŞİ', route: '/purchase/new', icon: Icons.inventory),
      (label: '+ TAHSİLAT', route: '/collection/new', icon: Icons.payments),
      (label: 'STOK SORGULA', route: '/stock', icon: Icons.grid_view),
      (label: 'CARİ SORGULA', route: '/customers', icon: Icons.people),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final action in actions)
            SizedBox(
              width: 160,
              height: 64,
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(action.route),
                icon: Icon(action.icon),
                label: Text(action.label, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardCards extends StatelessWidget {
  final DashboardSnapshot data;
  final bool hideCost;

  const _DashboardCards({required this.data, required this.hideCost});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String hidden(String value) => hideCost ? '••••' : value;

    final cards = <Widget>[
      StatCard(
        label: 'TOPLAM STOK',
        value: TrFormat.volume(data.totalStockVolume),
        icon: Icons.inventory_2,
      ),
      StatCard(
        label: 'STOK MALİYETİ',
        value: hidden(TrFormat.moneyWithCurrency(data.stockCost)),
        icon: Icons.price_change,
      ),
      StatCard(
        label: 'STOK SATIŞ DEĞERİ',
        value: TrFormat.moneyWithCurrency(data.stockSaleValue),
        icon: Icons.sell,
      ),
      StatCard(
        label: 'BU AY SATIŞ',
        value: TrFormat.moneyWithCurrency(data.monthSales),
        secondary: 'KDV hariç',
        icon: Icons.trending_up,
      ),
      StatCard(
        label: 'BU AY BRÜT KÂR',
        value: hidden(TrFormat.moneyWithCurrency(data.monthGrossProfit)),
        icon: Icons.savings,
      ),
      StatCard(
        label: 'MÜŞTERİLERDEN ALACAK',
        value: TrFormat.moneyWithCurrency(data.receivables),
        icon: Icons.account_balance_wallet,
      ),
      StatCard(
        label: 'TEDARİKÇİ BORCU',
        value: TrFormat.moneyWithCurrency(data.supplierDebt),
        icon: Icons.local_shipping,
      ),
      StatCard(
        label: 'VADESİ GEÇEN',
        value: TrFormat.moneyWithCurrency(data.overdue),
        valueColor: data.overdue.isPositive ? scheme.error : null,
        icon: Icons.schedule,
      ),
      StatCard(
        label: 'KASA & BANKA',
        value: TrFormat.moneyWithCurrency(data.cashAndBank),
        icon: Icons.account_balance,
      ),
      StatCard(
        label: 'ÇEK/SENET PORTFÖYÜ',
        value: TrFormat.moneyWithCurrency(data.instrumentPortfolio),
        icon: Icons.receipt_long,
      ),
      StatCard(
        label: 'KESİMDEKİ MAL',
        value: hidden(TrFormat.moneyWithCurrency(data.cuttingStockValue)),
        icon: Icons.content_cut,
      ),
      StatCard(
        label: 'SERMAYE DAĞILIMI',
        value: hidden(TrFormat.moneyWithCurrency(data.capital)),
        secondary: 'Stok + Kesimde + Alacak + Portföy + Kasa − Borç − Evrak',
        icon: Icons.pie_chart,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 600 ? 3 : 2;
          return GridView.count(
            crossAxisCount: columns,
            childAspectRatio: 1.45,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cards,
          );
        },
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN gerekli'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Maliyet ve kâr bilgilerini göstermek için PIN girin.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: 'PIN', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            // PIN doğrulaması Faz 2'nin kilit ekranıyla ortak servise taşınır.
            if (_controller.text.isEmpty) {
              setState(() => _error = 'PIN girin');
              return;
            }
            Navigator.of(context).pop(true);
          },
          child: const Text('Göster'),
        ),
      ],
    );
  }
}
