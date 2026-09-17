import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repo/dashboard_queries.dart';
import '../../format/tr_format.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/signature.dart';
import '../lock/pin_lock_screen.dart';
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: GreetingHeader(
                userName: ref.watch(userNameProvider).value,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: DailyQuoteCard(),
            ),
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
            const DesignSignature(),
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
    final ok = await askPin(context);
    if (ok) {
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
    //
    // İlk üçü **iş yaratan** eylemler: dolu ceviz zemin, öne çıkarlar.
    // Son ikisi sorgulama: yalnızca çerçeve. Renk değil, ağırlık farkı.
    const actions = [
      (
        label: 'Satış',
        route: '/sale/new',
        icon: Icons.point_of_sale,
        primary: true,
      ),
      (
        label: 'Stok Girişi',
        route: '/purchase/new',
        icon: Icons.inventory,
        primary: true,
      ),
      (
        label: 'Tahsilat',
        route: '/collection/new',
        icon: Icons.payments,
        primary: true,
      ),
      (
        label: 'Stok Sorgula',
        route: '/stock',
        icon: Icons.grid_view,
        primary: false,
      ),
      (
        label: 'Cari Sorgula',
        route: '/customers',
        icon: Icons.people,
        primary: false,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Dar telefonda iki, geniş ekranda üç sütun.
          final columns = constraints.maxWidth > 560 ? 3 : 2;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: _ActionTile(
                    label: action.label,
                    icon: action.icon,
                    primary: action.primary,
                    onTap: () => context.push(action.route),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Hızlı işlem kartı. Yüksekliği sabit, içi tipografik: ikon üstte küçük,
/// etiket altta — buton değil, tezgâhtaki bir etiket gibi durur.
class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  const _ActionTile({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = primary ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: primary ? scheme.primary : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: primary ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
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

/// Karşılama satırındaki isim (kurulum sihirbazında girilir).
final userNameProvider = FutureProvider.autoDispose<String>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return settings.userName();
});
