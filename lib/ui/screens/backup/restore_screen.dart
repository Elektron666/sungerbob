import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup/backup_models.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';

/// "Yedekten Yükle" (BRIEF §4.5).
///
/// Akış: kaynak seç → şifre → doğrulama → **önizleme** → tek onay.
/// Önizlemeye kadar hiçbir şey değişmez; onaydan sonra da atomik değişime
/// gelinmediği sürece mevcut veri korunur.
class RestoreScreen extends ConsumerStatefulWidget {
  final String? initialFilePath;

  const RestoreScreen({super.key, this.initialFilePath});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _passwordController = TextEditingController();
  File? _file;
  BackupPreview? _preview;
  bool _busy = false;
  String? _error;
  RestoreResult? _done;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _file = File(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Yedek dosyası seçin',
    );
    final path = picked?.path;
    if (path == null) return;
    setState(() {
      _file = File(path);
      _preview = null;
      _error = null;
    });
  }

  Future<void> _loadPreview() async {
    final file = _file;
    if (file == null) {
      setState(() => _error = 'Önce bir yedek dosyası seçin.');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Yedek şifresini girin.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = await ref.read(backupServiceProvider.future);
      final preview = await service.inspect(file, _passwordController.text);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = _file;
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = await ref.read(backupServiceProvider.future);
      final db = await ref.read(databaseProvider.future);
      final result = await service.restore(
        file: file,
        password: _passwordController.text,
        closeDatabase: db.close,
      );
      if (!mounted) return;
      setState(() => _done = result);
      // Uygulama kendini yeniden başlatır: veritabanı sağlayıcısı yenilenir.
      ref.invalidate(databaseProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_done != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Geri yükleme tamamlandı')),
        body: _RestoreSummary(result: _done!),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Yedekten Yükle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Geri yükleme telefondaki mevcut verilerin yerine geçer. '
                      'Yükleme öncesi otomatik güvenlik yedeği alınır.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open),
            title: Text(
              _file == null
                  ? 'Yedek dosyası seç'
                  : _file!.uri.pathSegments.last,
            ),
            subtitle: _file == null
                ? const Text('Cihazdaki veya indirdiğiniz .sbk dosyası')
                : null,
            trailing: OutlinedButton(
              onPressed: _pickFile,
              child: const Text('Seç'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Yedek şifresi'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_preview == null)
            FilledButton.icon(
              onPressed: _busy ? null : _loadPreview,
              icon: const Icon(Icons.search),
              label: const Text('Yedeği incele'),
            )
          else
            _PreviewCard(preview: _preview!, busy: _busy, onConfirm: _restore),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final BackupPreview preview;
  final bool busy;
  final VoidCallback onConfirm;

  const _PreviewCard({
    required this.preview,
    required this.busy,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manifest = preview.manifest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yedek bilgileri',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _row(context, 'Tarih', TrFormat.dateTime(manifest.createdAt)),
                _row(context, 'Cihaz', manifest.deviceName),
                _row(context, 'Uygulama sürümü', manifest.appVersion),
                _row(
                  context,
                  'Son işlem',
                  TrFormat.dateTime(manifest.lastTransactionAt),
                ),
                const Divider(height: 24),
                _comparison(
                  context,
                  'Müşteri',
                  manifest.customerCount,
                  preview.currentCounts['customers'] ?? 0,
                ),
                _comparison(
                  context,
                  'Ürün',
                  manifest.productCount,
                  preview.currentCounts['products'] ?? 0,
                ),
                _comparison(
                  context,
                  'Satış',
                  manifest.saleCount,
                  preview.currentCounts['sales'] ?? 0,
                ),
                _comparison(
                  context,
                  'Tahsilat',
                  manifest.collectionCount,
                  preview.currentCounts['collections'] ?? 0,
                ),
              ],
            ),
          ),
        ),
        if (preview.warningText != null) ...[
          const SizedBox(height: 16),
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      preview.warningText!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : onConfirm,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restore),
          label: Text(busy ? 'Geri yükleniyor…' : 'Geri Yükle'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value),
      ],
    ),
  );

  Widget _comparison(
    BuildContext context,
    String label,
    int backup,
    int current,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Yedek', style: Theme.of(context).textTheme.bodySmall),
                Text(TrFormat.count(backup)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Şu an', style: Theme.of(context).textTheme.bodySmall),
                Text(TrFormat.count(current)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestoreSummary extends StatelessWidget {
  final RestoreResult result;

  const _RestoreSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.check_circle, size: 64, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Geri yükleme tamamlandı',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yüklenen yedek: '
                  '${TrFormat.dateTime(result.manifest.createdAt)}',
                ),
                if (result.migrationApplied) ...[
                  const SizedBox(height: 8),
                  const Text('Veritabanı bu sürüme güncellendi.'),
                ],
                const SizedBox(height: 16),
                Text(
                  'Yükleme öncesi güvenlik yedeği:\n'
                  '${result.safetyBackup.uri.pathSegments.last}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Yanlış yedeği yüklediyseniz Menü → Yedekler ekranından bu '
                  'güvenlik yedeğine dönebilirsiniz.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
