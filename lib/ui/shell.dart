import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (label: 'Yedek Al', route: '/backup', icon: Icons.backup),
      (label: 'Yedekten Yükle', route: '/restore', icon: Icons.restore),
      (label: 'Yedekler', route: '/backups', icon: Icons.folder),
      (label: 'Ayarlar', route: '/settings', icon: Icons.settings),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Menü')),
      body: ListView(
        children: [
          for (final item in items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(item.route),
            ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Teklifler, Kesim Emirleri, Sayım, Fire, Raporlar'),
            subtitle: Text('Faz 3 ve Faz 4 ile gelecek'),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
