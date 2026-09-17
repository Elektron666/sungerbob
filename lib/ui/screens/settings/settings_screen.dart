import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/db/connection.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';

/// Ayarlar (BRIEF §7).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: settings.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (map) => ListView(
          children: [
            const SectionHeader(title: 'İşletme'),
            ListTile(
              leading: const Icon(Icons.percent),
              title: const Text('KDV oranı'),
              subtitle: Text(
                '%${(int.tryParse(map['default_vat_rate'] ?? '2000') ?? 2000) ~/ 100}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.price_check),
              title: const Text('Varsayılan fiyat modu'),
              subtitle: Text(
                map['default_price_mode'] == 'INCL' ? 'KDV Dahil' : 'KDV Hariç',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calculate),
              title: const Text('Maliyet yöntemi'),
              subtitle: Text(
                map['costing_method'] == 'WEIGHTED_AVERAGE'
                    ? 'Ağırlıklı Ortalama'
                    : 'FIFO (İlk giren ilk çıkar)',
              ),
            ),
            const SectionHeader(title: 'Yedekleme'),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Yedek Al'),
              onTap: () => context.push('/backup'),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Yedekten Yükle'),
              onTap: () => context.push('/restore'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Otomatik yedek saati'),
              subtitle: Text(map['backup_auto_time'] ?? '20:00'),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Cihaz dışı yedek uyarı eşiği'),
              subtitle: Text('${map['backup_offsite_warn_days'] ?? '3'} gün'),
            ),
            const SectionHeader(title: 'Bakım'),
            ListTile(
              leading: const Icon(Icons.fact_check),
              title: const Text('Tutarlılık Kontrolü'),
              subtitle: const Text(
                'Stok ve cari bakiyeleri hareketlerden yeniden hesaplar',
              ),
              onTap: () => _runIntegrityCheck(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Veritabanı şifrelemesi'),
              subtitle: Text(
                AppDatabaseFactory.isEncryptionAvailable()
                    ? 'SQLCipher etkin ✓'
                    : 'SQLCipher bulunamadı',
              ),
            ),
            const SectionHeader(title: 'Uygulama'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Sürüm'),
              subtitle: Text('0.1.0 (Faz 2)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runIntegrityCheck(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = await ref.read(integrityServiceProvider.future);
    final report = await service.check();

    if (!context.mounted) return;
    if (report.isClean) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tutarlılık kontrolü temiz ✓')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${report.findings.length} fark bulundu'),
        content: SingleChildScrollView(
          child: Text(report.findings.map((f) => f.toString()).join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

final settingsMapProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  final rows = await db.select(db.settings).get();
  return {for (final s in rows) s.key: s.value};
});
