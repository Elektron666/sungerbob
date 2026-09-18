import 'package:go_router/go_router.dart';

import 'screens/backup/backup_screen.dart';
import 'screens/backup/restore_screen.dart';
import 'screens/finance/collection_screen.dart';
import 'screens/documents/documents_screen.dart';
import 'screens/finance/customers_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/master/parties_screen.dart';
import 'screens/opening/opening_screen.dart';
import 'screens/ops/count_screen.dart';
import 'screens/ops/cutting_screen.dart';
import 'screens/ops/quotes_screen.dart';
import 'screens/ops/waste_screen.dart';
import 'screens/purchase/purchase_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/sale/quick_sale_screen.dart';
import 'screens/settings/drive_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/stock/stock_screen.dart';
import 'shell.dart';

/// Yönlendirme (BRIEF §7 · docs/SCREENS.md).
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/stock', builder: (_, _) => const StockScreen()),
        GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
        GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
      ],
    ),
    GoRoute(
      path: '/customers/:id',
      builder: (_, state) =>
          CustomerLedgerScreen(customerId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/sale/new', builder: (_, _) => const QuickSaleScreen()),
    GoRoute(path: '/purchase/new', builder: (_, _) => const PurchaseScreen()),
    GoRoute(
      path: '/collection/new',
      builder: (_, _) => const CollectionScreen(),
    ),
    GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
    GoRoute(path: '/backups', builder: (_, _) => const BackupListScreen()),
    GoRoute(path: '/restore', builder: (_, _) => const RestoreScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/settings/drive', builder: (_, _) => const DriveScreen()),
    GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
    GoRoute(path: '/opening', builder: (_, _) => const OpeningScreen()),
    GoRoute(
      path: '/sales',
      builder: (_, _) => const DocumentsScreen(sales: true),
    ),
    GoRoute(
      path: '/purchases',
      builder: (_, _) => const DocumentsScreen(sales: false),
    ),
    GoRoute(path: '/suppliers', builder: (_, _) => const SuppliersScreen()),
    GoRoute(path: '/quotes', builder: (_, _) => const QuotesScreen()),
    GoRoute(path: '/cutting', builder: (_, _) => const CuttingScreen()),
    GoRoute(
      path: '/cutting/new',
      builder: (_, _) => const SendToCuttingScreen(),
    ),
    GoRoute(path: '/count', builder: (_, _) => const CountScreen()),
    GoRoute(path: '/waste', builder: (_, _) => const WasteScreen()),
  ],
);
