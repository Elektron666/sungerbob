import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';

/// Yedek durum bandı (BRIEF §4.4).
///
/// Normalde "Son yedek: bugün 20:00 · Drive ✓" yazar. Son **cihaz dışı**
/// yedek 3 günden eskiyse kırmızı uyarı bandına ve "Şimdi yedekle" butonuna
/// dönüşür. Veri yalnızca telefonda durduğu için bu uyarı kritiktir.
class BackupStatusBand extends ConsumerWidget {
  const BackupStatusBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backupStatusProvider);

    return status.when(
      loading: () =>
          const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) {
        final scheme = Theme.of(context).colorScheme;
        final warn = value.shouldWarn;

        return Material(
          color: warn ? scheme.errorContainer : scheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => context.push('/backups'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    warn ? Icons.warning_amber_rounded : Icons.cloud_done,
                    color: warn ? scheme.onErrorContainer : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: warn ? scheme.onErrorContainer : null,
                              ),
                        ),
                        Text(
                          value.subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: warn
                                    ? scheme.onErrorContainer
                                    : scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (warn)
                    FilledButton(
                      onPressed: () => context.push('/backup'),
                      child: const Text('Şimdi yedekle'),
                    )
                  else
                    TextButton(
                      onPressed: () => context.push('/backup'),
                      child: const Text('Yedek Al'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class BackupStatus {
  final DateTime? lastBackupAt;
  final int? daysSinceOffsite;
  final bool shouldWarn;

  const BackupStatus({
    required this.shouldWarn,
    this.lastBackupAt,
    this.daysSinceOffsite,
  });

  String get title {
    if (lastBackupAt == null) return 'Henüz hiç yedek alınmadı';
    return 'Son yedek: ${TrFormat.relativeDateTime(lastBackupAt)}';
  }

  String get subtitle {
    if (daysSinceOffsite == null) {
      return 'Telefon dışına hiç yedek alınmadı — telefon kaybolursa veriler gider';
    }
    if (shouldWarn) {
      return 'Son cihaz dışı yedek $daysSinceOffsite gün önce';
    }
    return 'Cihaz dışı yedek güncel ✓';
  }
}

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((
  ref,
) async {
  final service = await ref.watch(backupServiceProvider.future);
  return BackupStatus(
    lastBackupAt: await service.lastBackupAt(),
    daysSinceOffsite: await service.daysSinceOffsiteBackup(),
    shouldWarn: await service.shouldWarnAboutOffsiteBackup(),
  );
});
