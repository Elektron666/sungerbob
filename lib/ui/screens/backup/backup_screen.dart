import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/backup/backup_models.dart';
import '../../../data/db/enums.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';
import '../home/backup_status_band.dart';

/// "Yedek Al" ekranı (BRIEF §4.2).
///
/// Tek dokunuşla dosya oluşturulur, ardından iki seçenek sunulur:
/// Google Drive'a yükle veya Paylaş/Kaydet.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _passwordController = TextEditingController();
  bool _running = false;
  BackupResult? _result;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createBackup() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Yedek şifrenizi girin.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final service = await ref.read(backupServiceProvider.future);
      final result = await service.createBackup(
        password: _passwordController.text,
        trigger: BackupTrigger.manual,
      );
      if (!mounted) return;
      setState(() => _result = result);
      ref.invalidate(backupStatusProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _share() async {
    final result = _result;
    if (result == null) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(result.file.path)],
        subject: 'Sünger yedeği',
        text: 'Sünger uygulaması yedeği — açmak için yedek şifreniz gerekir.',
      ),
    );

    // Paylaşım cihaz dışı yedek sayılır (BRIEF §4.4).
    final service = await ref.read(backupServiceProvider.future);
    await service.createBackup(
      password: _passwordController.text,
      trigger: BackupTrigger.manual,
      destination: BackupDestination.share,
    );
    ref.invalidate(backupStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Yedek Al')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Yedek dosyası şifrelidir. Yedek şifrenizi bilen biri '
                      'onu başka bir telefonda açabilir; bilmeyen açamaz.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Yedek şifresi',
              helperText: 'Kurulumda belirlediğiniz şifre',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _running ? null : _createBackup,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup),
            label: Text(_running ? 'Yedek alınıyor…' : 'Yedek Al'),
          ),
          if (result != null) ...[
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: scheme.primary),
                        const SizedBox(width: 8),
                        const Text('Yedek alındı'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(result.file.uri.pathSegments.last),
                    Text(
                      '${TrFormat.fileSize(result.sizeBytes)} · '
                      '${result.manifest.tableCounts.values.fold(0, (a, b) => a + b)} kayıt',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Yedeği telefon dışına çıkarın — telefon kaybolursa '
                      'yalnızca dışarıdaki kopya işe yarar.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showDriveNotice(context),
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text("Drive'a yükle"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _share,
                            icon: const Icon(Icons.share),
                            label: const Text('Paylaş / Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showDriveNotice(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Google Drive bağlı değil'),
        content: const Text(
          'Drive yedeklemesi için önce Ayarlar → Yedek ve Drive bölümünden '
          'Google hesabınızı bağlayın. O zamana kadar "Paylaş / Kaydet" ile '
          'yedeği WhatsApp veya e-posta ile telefon dışına çıkarabilirsiniz.',
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

/// "Yedekler" ekranı (BRIEF §4.6).
class BackupListScreen extends ConsumerWidget {
  const BackupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(localBackupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Yedekler')),
      body: backups.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (files) {
          if (files.isEmpty) {
            return const EmptyState(
              icon: Icons.backup_outlined,
              title: 'Henüz yedek yok',
              description:
                  'Veri yalnızca bu telefonda duruyor. İlk yedeğinizi alın '
                  've telefon dışına çıkarın.',
            );
          }
          return ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = files[index];
              final stat = file.statSync();
              return ListTile(
                leading: const Icon(Icons.description),
                title: Text(file.uri.pathSegments.last),
                subtitle: Text(
                  '${TrFormat.dateTime(stat.modified)} · '
                  '${TrFormat.fileSize(stat.size)} · Cihaz',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => _onAction(context, ref, file, action),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Paylaş')),
                    PopupMenuItem(value: 'restore', child: Text('Geri yükle')),
                    PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    File file,
    String action,
  ) async {
    switch (action) {
      case 'share':
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      case 'restore':
        if (context.mounted) {
          Navigator.of(context).pushNamed('/restore', arguments: file.path);
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Yedeği sil'),
            content: Text(
              '${file.uri.pathSegments.last} silinecek. '
              'Bu yedeğin başka bir kopyası yoksa geri alınamaz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil'),
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          file.deleteSync();
          ref.invalidate(localBackupsProvider);
        }
    }
  }
}

final localBackupsProvider = FutureProvider.autoDispose<List<File>>((
  ref,
) async {
  final service = await ref.watch(backupServiceProvider.future);
  return service.localBackups();
});
