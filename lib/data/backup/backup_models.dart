import 'dart:io';

import 'backup_manifest.dart';

/// Yedek alma sonucu.
final class BackupResult {
  final File file;
  final BackupManifest manifest;
  final int sizeBytes;

  const BackupResult({
    required this.file,
    required this.manifest,
    required this.sizeBytes,
  });
}

/// Geri yükleme öncesi önizleme (BACKUP.md §5.2).
final class BackupPreview {
  final BackupManifest manifest;

  /// Mevcut veritabanındaki sayılar — yan yana karşılaştırma için.
  final Map<String, int> currentCounts;
  final DateTime? currentLastTransactionAt;

  const BackupPreview({
    required this.manifest,
    required this.currentCounts,
    this.currentLastTransactionAt,
  });

  /// Yedek mevcut veriden kaç gün eski? Negatifse yedek daha yeni.
  int? get ageInDaysVsCurrent {
    final current = currentLastTransactionAt;
    final backup = manifest.lastTransactionAt;
    if (current == null || backup == null) return null;
    return current.difference(backup).inDays;
  }

  /// Yedek mevcut veriden eskiyse kullanıcıya kırmızı uyarı gösterilir.
  bool get isOlderThanCurrent => (ageInDaysVsCurrent ?? 0) > 0;

  String? get warningText {
    if (!isOlderThanCurrent) return null;
    return 'Bu yedek, telefondaki verilerden $ageInDaysVsCurrent gün eski. '
        'Sonraki işlemler kaybolacak.';
  }
}

/// Geri yükleme sonucu.
final class RestoreResult {
  final BackupManifest manifest;

  /// Yükleme öncesi otomatik alınan güvenlik yedeği (BACKUP.md §5.3).
  final File safetyBackup;

  final bool migrationApplied;

  const RestoreResult({
    required this.manifest,
    required this.safetyBackup,
    required this.migrationApplied,
  });
}

/// Yedek daha yeni bir uygulama sürümünden geliyor — yüklenemez.
final class BackupTooNewException implements Exception {
  final int backupSchemaVersion;
  final int appSchemaVersion;

  const BackupTooNewException({
    required this.backupSchemaVersion,
    required this.appSchemaVersion,
  });

  @override
  String toString() =>
      'Bu yedek daha yeni bir uygulama sürümüyle alınmış '
      '(şema $backupSchemaVersion, bu uygulama $appSchemaVersion). '
      'Önce uygulamayı güncelleyin.';
}

/// SHA-256 tutmadı — dosya değiştirilmiş.
final class BackupIntegrityException implements Exception {
  final String expected;
  final String actual;

  const BackupIntegrityException({
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'Yedek dosyası bozuk: içerik özeti tutmuyor. Mevcut veriniz değişmedi.';
}

/// Geri yükleme sonrası tutarlılık kontrolü fark buldu — yükleme geri alındı.
final class RestoreIntegrityException implements Exception {
  final List<String> findings;
  const RestoreIntegrityException(this.findings);

  @override
  String toString() =>
      'Yedekteki veri tutarsız, yükleme geri alındı:\n'
      '${findings.join('\n')}';
}
