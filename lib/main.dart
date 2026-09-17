import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/documents/pdf_documents.dart';
import 'ui/app_router.dart';
import 'ui/format/tr_format.dart';
import 'ui/providers/app_providers.dart';
import 'ui/screens/lock/pin_lock_screen.dart';
import 'ui/screens/setup/setup_wizard_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrFormat.ensureInitialized();
  // Türkçe karakterli PDF fontu (BRIEF §2). Yüklenmezse belgelerde
  // ş, ğ, İ, ı basılamaz.
  await PdfDocuments.loadBundledFonts(rootBundle.load);
  runApp(const ProviderScope(child: SungerApp()));
}

class SungerApp extends ConsumerStatefulWidget {
  const SungerApp({super.key});

  @override
  ConsumerState<SungerApp> createState() => _SungerAppState();
}

class _SungerAppState extends ConsumerState<SungerApp>
    with WidgetsBindingObserver {
  late final _router = buildRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Arka plana alınınca kilitlenir (BRIEF §5).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(appLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Sünger',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    routerConfig: _router,
    builder: (context, child) => _Gate(child: child ?? const SizedBox()),
  );
}

/// Kurulum ve kilit kapısı. Uygulama ancak ikisi de geçildikten sonra görünür.
class _Gate extends ConsumerWidget {
  final Widget child;
  const _Gate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(appLockProvider)) {
        AppGate.unknown => const Scaffold(body: LoadingState()),
        AppGate.setup => const SetupWizardScreen(),
        AppGate.locked => const PinLockScreen(),
        AppGate.ready => child,
      };
}
