import '../db/enums.dart';
import '../repo/settings_repository.dart';
import 'backup_models.dart';
import 'backup_service.dart';

/// Otomatik yedek kararları (BRIEF §4.3).
///
/// Zamanlama ve tetikleme platforma özgüdür (`workmanager`); **karar mantığı**
/// burada saf tutulur ki test edilebilsin.
final class AutoBackupPolicy {
  final BackupService backup;
  final SettingsRepository settings;

  const AutoBackupPolicy({required this.backup, required this.settings});

  /// Günün ilk açılışında: önceki gün yedeği alınmamışsa yedek al.
  Future<bool> shouldBackupOnStartup({DateTime? now}) async {
    final today = _dayOf(now ?? DateTime.now());
    final last = await settings.lastAutoBackupDate();
    if (last == null) return true;
    return _dayOf(last).isBefore(today);
  }

  /// Günlük zamanlanmış yedek saati geldi mi?
  Future<bool> isScheduledTime({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final configured = await settings.backupTime();
    final parts = configured.split(':');
    if (parts.length != 2) return false;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;

    final scheduled = DateTime(
      reference.year,
      reference.month,
      reference.day,
      hour,
      minute,
    );
    if (reference.isBefore(scheduled)) return false;

    final last = await settings.lastAutoBackupDate();
    return last == null || last.isBefore(scheduled);
  }

  /// Otomatik yedeği alır ve saklama kuralını uygular.
  Future<BackupResult?> runAutoBackup({
    required String password,
    required String trigger,
    DateTime? now,
  }) async {
    final result = await backup.createBackup(
      password: password,
      trigger: trigger,
      now: now,
    );
    await settings.setLastAutoBackupDate(now ?? DateTime.now());
    await backup.applyRetention(now: now);
    return result;
  }

  /// **Riskli işlem öncesi** otomatik yedek (BRIEF §4.3):
  /// geri yükleme, migration, stok sayımı onayı, maliyet yöntemi değişikliği.
  Future<BackupResult> backupBeforeRiskyOperation({
    required String password,
    required String operation,
    DateTime? now,
  }) => backup.createBackup(
    password: password,
    trigger: operation == 'migration'
        ? BackupTrigger.preMigration
        : BackupTrigger.preRisk,
    now: now,
  );

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
