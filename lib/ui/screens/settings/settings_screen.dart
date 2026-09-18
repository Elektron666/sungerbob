import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/db/connection.dart';
import '../../providers/app_providers.dart';
import '../../startup.dart';
import '../../widgets/common.dart';
import '../../widgets/signature.dart';

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
            // Bu üç satır yalnızca gösteriliyordu; kurulum sihirbazından
            // sonra değiştirmenin yolu yoktu. Oran değişince belgeler de
            // yeni oranla hesaplanır (D-32).
            ListTile(
              leading: const Icon(Icons.percent),
              title: const Text('KDV oranı'),
              subtitle: Text(
                '%${(int.tryParse(map['default_vat_rate'] ?? '2000') ?? 2000) ~/ 100}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _pickVatRate(
                context,
                ref,
                int.tryParse(map['default_vat_rate'] ?? '2000') ?? 2000,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.price_check),
              title: const Text('Varsayılan fiyat modu'),
              subtitle: Text(
                map['default_price_mode'] == 'INCL' ? 'KDV Dahil' : 'KDV Hariç',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () =>
                  _pickPriceMode(context, ref, map['default_price_mode']),
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
              onTap: () => _pickBackupTime(
                context,
                ref,
                map['backup_auto_time'] ?? '20:00',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Cihaz dışı yedek'),
              subtitle: const Text('Drive, e-posta veya bilgisayara aktarım'),
              onTap: () => context.push('/settings/drive'),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('Cihaz dışı yedek uyarı eşiği'),
              subtitle: Text('${map['backup_offsite_warn_days'] ?? '3'} gün'),
            ),
            const SectionHeader(title: 'Bildirimler'),
            const _NotificationStatusTile(),
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
            const SectionHeader(title: 'Hakkında'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Sürüm'),
              subtitle: Text('0.1.0'),
            ),
            const ListTile(
              leading: Icon(Icons.draw_outlined),
              title: Text('Tasarım'),
              subtitle: Text(
                '${DesignSignature.designer} tarafından tasarlanmıştır',
              ),
            ),
            const DesignSignature(),
          ],
        ),
      ),
    );
  }

  /// Otomatik yedek saati. Değişiklik bir sonraki arka plan koşusunda
  /// geçerli olur; görev saatlik koşup saati kendisi kontrol eder.
  Future<void> _pickBackupTime(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 20,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked == null) return;

    final settings = await ref.read(settingsRepositoryProvider.future);
    await settings.setBackupTime(
      '${picked.hour.toString().padLeft(2, '0')}:'
      '${picked.minute.toString().padLeft(2, '0')}',
    );
    ref.invalidate(settingsMapProvider);
  }

  /// KDV oranı seçimi. SPEC'in izin verdiği oranlar: %0, %1, %10, %20.
  Future<void> _pickVatRate(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Varsayılan KDV oranı'),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.of(context).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final rate in const [0, 100, 1000, 2000])
                  RadioListTile<int>(
                    value: rate,
                    title: Text('%${rate ~/ 100}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;

    final settings = await ref.read(settingsRepositoryProvider.future);
    await settings.setDefaultVatRate(picked);
    ref.invalidate(settingsMapProvider);
    // Belge ekranları oranı buradan okur; tazelenmezse eski oranla
    // hesaplamaya devam ederdi.
    ref.invalidate(documentDefaultsProvider);
  }

  Future<void> _pickPriceMode(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Varsayılan fiyat modu'),
        children: [
          RadioGroup<String>(
            groupValue: current ?? 'EXCL',
            onChanged: (v) => Navigator.of(context).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in const {
                  'EXCL': 'KDV Hariç',
                  'INCL': 'KDV Dahil',
                }.entries)
                  RadioListTile<String>(
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;

    final settings = await ref.read(settingsRepositoryProvider.future);
    await settings.setDefaultPriceMode(picked);
    ref.invalidate(settingsMapProvider);
    ref.invalidate(documentDefaultsProvider);
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

/// Bildirim izni ve kurulu vade bildirimi sayısı (BRIEF §5).
class _NotificationStatusTile extends ConsumerWidget {
  const _NotificationStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(startupTasksProvider);

    return report.when(
      loading: () => const ListTile(
        leading: Icon(Icons.notifications_outlined),
        title: Text('Vade bildirimleri'),
        subtitle: Text('Kontrol ediliyor…'),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.notifications_off_outlined),
        title: const Text('Vade bildirimleri'),
        subtitle: Text('Kurulamadı: $e'),
      ),
      data: (r) => ListTile(
        leading: Icon(
          r.notificationsAllowed
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
        ),
        title: const Text('Vade bildirimleri'),
        subtitle: Text(
          r.notificationsAllowed
              ? '${r.scheduledNotifications} bildirim kurulu · '
                    'vadeden bir gün önce 09:00'
              : 'Bildirim izni verilmedi. Vadeler yine de '
                    'Raporlar → Vadeler\'den görülebilir.',
        ),
        trailing: const Icon(Icons.refresh),
        onTap: () => ref.invalidate(startupTasksProvider),
      ),
    );
  }
}
