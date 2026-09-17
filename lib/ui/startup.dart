import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/background_backup.dart';
import '../data/db/enums.dart';
import '../data/notifications/due_date_notifier.dart';
import '../data/notifications/notification_service.dart';
import 'providers/app_providers.dart';

/// Kilit açıldıktan sonra bir kez çalışan başlangıç işleri (BRIEF §4.3, §5).
///
/// Kilit ekranından önce çalıştırılmaz: kullanıcı doğrulanmadan veriye
/// dokunulmaz ve izin diyalogları PIN ekranının üstüne binmez.
final class StartupTasks {
  final Ref ref;
  const StartupTasks(this.ref);

  /// Sonuç, Ayarlar ekranında gösterilebilsin diye döndürülür.
  Future<StartupReport> run({DateTime? now}) async {
    final settings = await ref.read(settingsRepositoryProvider.future);
    if (!await settings.isSetupCompleted()) {
      return const StartupReport(skippedReason: 'Kurulum tamamlanmadı');
    }

    final notifications = ref.read(notificationServiceProvider);
    var scheduled = 0;
    var notificationsAllowed = false;
    try {
      await notifications.initialize();
      notificationsAllowed = await notifications.requestPermissions();
      if (notificationsAllowed) {
        final db = await ref.read(databaseProvider.future);
        scheduled = await notifications.reschedule(
          await DueDateNotifier(db).pendingNotifications(now: now),
        );
      }
    } catch (_) {
      // Bildirim kurulamadıysa uygulama çalışmaya devam eder; vadeler ana
      // sayfadan ve Raporlar → Vadeler'den zaten görülüyor.
    }

    // Günlük yedeği planla ve gerekiyorsa açılış yedeğini şimdi al.
    var backupTaken = false;
    try {
      await BackgroundTasks.initialize();
      await BackgroundTasks.scheduleDailyBackup();
    } catch (_) {
      // Arka plan görevi kurulamadıysa açılış yedeği yine de alınır.
    }

    try {
      final password = await ref.read(backupPasswordStoreProvider).read();
      if (password != null) {
        final policy = await ref.read(autoBackupPolicyProvider.future);
        if (await policy.shouldBackupOnStartup(now: now)) {
          await policy.runAutoBackup(
            password: password,
            trigger: BackupTrigger.autoStartup,
            now: now,
          );
          backupTaken = true;
        }
      }
    } catch (_) {
      // Yedek alınamadıysa ana sayfadaki yedek durum bandı kırmızı kalır —
      // kullanıcı bunu görür.
    }

    return StartupReport(
      notificationsAllowed: notificationsAllowed,
      scheduledNotifications: scheduled,
      startupBackupTaken: backupTaken,
    );
  }
}

final class StartupReport {
  final bool notificationsAllowed;
  final int scheduledNotifications;
  final bool startupBackupTaken;
  final String? skippedReason;

  const StartupReport({
    this.notificationsAllowed = false,
    this.scheduledNotifications = 0,
    this.startupBackupTaken = false,
    this.skippedReason,
  });
}

final notificationServiceProvider = Provider((ref) => NotificationService());

/// Kilit açıldıktan sonra bir kez izlenir.
final startupTasksProvider = FutureProvider<StartupReport>(
  (ref) => StartupTasks(ref).run(),
);
