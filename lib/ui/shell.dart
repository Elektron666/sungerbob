import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/common.dart';

/// Alt navigasyon: Ana Sayfa · Stok · (+) · Cari · Menü (BRIEF §7).
class AppShell extends StatelessWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  static const _tabs = ['/', '/stock', '/customers', '/menu'];

  int get _index {
    final i = _tabs.indexOf(location);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickActions(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Stok'),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Cari',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Menü'),
        ],
      ),
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in const [
              (label: 'Satış', route: '/sale/new', icon: Icons.point_of_sale),
              (
                label: 'Stok Girişi',
                route: '/purchase/new',
                icon: Icons.inventory,
              ),
              (
                label: 'Tahsilat',
                route: '/collection/new',
                icon: Icons.payments,
              ),
              (label: 'Ödeme', route: '/payment/new', icon: Icons.outbox),
              (
                label: 'Kesime Gönder',
                route: '/cutting/new',
                icon: Icons.content_cut,
              ),
            ])
              ListTile(
                leading: Icon(action.icon),
                title: Text(action.label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push(action.route);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Menü (BRIEF §7).
///
/// Düz bir liste yerine **gruplanmış**: 13 satırı alt alta görmek kullanıcıya
/// "karmaşık ve düzensiz" hissi veriyordu. Başlıklar işin ritmine göre:
/// önce her gün bakılanlar, sonra ara sıra, en sonda kurulum.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  static const _groups = [
    (
      title: 'Kayıtlar',
      items: [
        (label: 'Satışlar', route: '/sales', icon: Icons.receipt_long),
        (label: 'Alışlar', route: '/purchases', icon: Icons.inventory_2),
        (label: 'Teklifler', route: '/quotes', icon: Icons.request_quote),
      ],
    ),
    (
      title: 'Depo',
      items: [
        (label: 'Kesim Emirleri', route: '/cutting', icon: Icons.content_cut),
        (label: 'Sayım', route: '/count', icon: Icons.fact_check),
        (label: 'Fire', route: '/waste', icon: Icons.delete_sweep),
      ],
    ),
    (
      title: 'Para',
      items: [
        (
          label: 'Kasa & Banka',
          route: '/accounts',
          icon: Icons.account_balance_wallet,
        ),
        (label: 'Çek & Senet', route: '/instruments', icon: Icons.receipt_long),
      ],
    ),
    (
      title: 'Cari',
      items: [
        (
          label: 'Tedarikçiler',
          route: '/suppliers',
          icon: Icons.local_shipping,
        ),
        (label: 'Raporlar', route: '/reports', icon: Icons.insights),
      ],
    ),
    (
      title: 'Yedekleme',
      items: [
        (label: 'Yedek Al', route: '/backup', icon: Icons.backup),
        (label: 'Yedekten Yükle', route: '/restore', icon: Icons.restore),
        (label: 'Yedekler', route: '/backups', icon: Icons.folder),
      ],
    ),
    (
      title: 'Kurulum',
      items: [
        (
          label: 'Açılış İşlemleri',
          route: '/opening',
          icon: Icons.flag_outlined,
        ),
        (label: 'Ayarlar', route: '/settings', icon: Icons.settings),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menü')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          for (final group in _groups) ...[
            SectionHeader(title: group.title),
            for (final item in group.items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push(item.route),
              ),
          ],
        ],
      ),
    );
  }
}
