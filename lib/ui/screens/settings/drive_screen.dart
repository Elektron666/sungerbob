import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/db/enums.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';
import '../home/backup_status_band.dart'
    show BackupStatus, backupStatusProvider;

/// Cihaz dışı yedek (BRIEF §4.4).
///
/// Telefon kaybolursa veriler de kaybolur; bu yüzden yedeğin başka bir yerde
/// de durması gerekir. Şu an bu, sistem paylaşım menüsüyle yapılır — Drive,
/// e-posta, WhatsApp veya bir bilgisayara aktarım, hepsi aynı kapıya çıkar.
///
/// Doğrudan Google Drive API entegrasyonu için, uygulamanın **yayın imzasına
/// bağlı** bir OAuth istemci kimliği gerekir; imzalama anahtarı yalnızca
/// GitHub Secrets'ta durduğu için bu kimlik burada üretilemez
/// (DECISIONS SK-12).
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backupStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cihaz dışı yedek')),
      body: status.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: s.daysSinceOffsite == null || s.shouldWarn
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      s.shouldWarn ? Icons.warning_amber : Icons.check_circle,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.daysSinceOffsite == null
                            ? 'Yedeğiniz hiç cihaz dışına çıkarılmamış. '
                                  'Telefon kaybolursa tüm veri kaybolur.'
                            : 'Son cihaz dışı yedek ${s.daysSinceOffsite} gün önce.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader(title: 'Nasıl çalışır'),
            const ListTile(
              leading: Icon(Icons.looks_one_outlined),
              title: Text('Yedek Al ekranından yedek alın'),
            ),
            const ListTile(
              leading: Icon(Icons.looks_two_outlined),
              title: Text('Paylaş düğmesiyle Drive uygulamasını seçin'),
            ),
            const ListTile(
              leading: Icon(Icons.looks_3_outlined),
              title: Text('Yedek şifrenizi ayrı bir yerde saklayın'),
              subtitle: Text(
                'Dosya ve şifre aynı yerde durursa şifrelemenin anlamı kalmaz',
              ),
            ),
            const SectionHeader(title: 'Yedekler'),
            ..._recentBackups(context, ref, s),
          ],
        ),
      ),
    );
  }

  List<Widget> _recentBackups(
    BuildContext context,
    WidgetRef ref,
    BackupStatus status,
  ) {
    if (status.lastBackupAt == null) {
      return const [
        ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Henüz yedek alınmamış'),
          subtitle: Text('Menü → Yedek Al'),
          enabled: false,
        ),
      ];
    }

    return [
      ListTile(
        leading: const Icon(Icons.schedule),
        title: const Text('Son yedek'),
        subtitle: Text(TrFormat.dateTime(status.lastBackupAt)),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () => _shareLatest(context, ref),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Son yedeği paylaş'),
        ),
      ),
    ];
  }

  Future<void> _shareLatest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final files = service.localBackups();
      if (files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Paylaşılacak yedek dosyası yok')),
        );
        return;
      }

      final latest = files.first;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(latest.path)],
          subject: 'Sünger yedeği',
          text: 'Açmak için yedek şifreniz gerekir.',
        ),
      );
      await service.recordOffsiteCopy(
        file: latest,
        destination: BackupDestination.share,
      );
      ref.invalidate(backupStatusProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
    }
  }
}
