import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/documents/pdf_documents.dart';
import 'ui/app_router.dart';
import 'ui/format/tr_format.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrFormat.ensureInitialized();
  // Türkçe karakterli PDF fontu (BRIEF §2). Yüklenmezse belgelerde
  // ş, ğ, İ, ı basılamaz.
  await PdfDocuments.loadBundledFonts(rootBundle.load);
  runApp(const ProviderScope(child: SungerApp()));
}

class SungerApp extends StatefulWidget {
  const SungerApp({super.key});

  @override
  State<SungerApp> createState() => _SungerAppState();
}

class _SungerAppState extends State<SungerApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Sünger',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    routerConfig: _router,
  );
}
