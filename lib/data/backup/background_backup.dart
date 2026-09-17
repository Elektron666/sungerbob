import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../db/app_database.dart';
import '../db/connection.dart';
import '../db/database_key.dart';
import '../db/enums.dart';
import '../notifications/due_date_notifier.dart';
import '../notifications/notification_service.dart';
import '../repo/settings_repository.dart';
import 'auto_backup.dart';
import 'backup_password_store.dart';
import 'backup_service.dart';

/// Arka plan görevleri (BRIEF §4.3).
///
/// Günlük yedek ve vade bildirimleri, uygulama kapalıyken de çalışmalıdır.
/// Android bunu ayrı bir isolate'te koşturur: Riverpod grafiği orada yoktur,
/// bu yüzden görev veritabanını ve servisleri kendisi kurar.
///
/// Yedek şifresi güvenli depodan okunur (SK-13); yoksa görev **sessizce
/// çıkar** — kullanıcı kurulumu bitirmemiştir, yedek alınacak veri de yoktur.
abstract final class BackgroundTasks {
  static const dailyBackupTask = 'gunluk-yedek';
  static const dailyBackupUnique = 'sungerbob-gunluk-yedek';

  /// Uygulama açılışında bir kez çağrılır.
  static Future<void> initialize() =>
      Workmanager().initialize(callbackDispatcher);

  /// Günlük yedeği planlar.
  ///
  /// Android tam zamanlı periyodik görev garanti etmez; en az 15 dakikalık
  /// aralık zorunludur ve sistem uygun gördüğünde çalıştırır. Bu yüzden görev
  /// saatlik koşar ve **yedek saatinin gelip gelmediğine `AutoBackupPolicy`
  /// karar verir** — geç kalan bir koşu yine de yedeği alır.
  static Future<void> scheduleDailyBackup() async {
    await Workmanager().registerPeriodicTask(
      dailyBackupUnique,
      dailyBackupTask,
      frequency: const Duration(hours: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
      ),
    );
  }

  static Future<void> cancelDailyBackup() =>
      Workmanager().cancelByUniqueName(dailyBackupUnique);
}

/// Arka plan isolate'inin giriş noktası.
///
/// `@pragma('vm:entry-point')` şart: release derlemesinde ağaç budama bu
/// fonksiyonu atarsa görev hiç çalışmaz.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    return runBackgroundBackup();
  });
}

/// Görevin gövdesi — test edilebilmesi için ayrı.
///
/// Her zaman `true` veya `false` döner; istisna sızdırmaz. Arka plan görevi
/// hata verirse Android onu yeniden dener, bu da yedek fırtınasına yol açar.
Future<bool> runBackgroundBackup({DateTime? now}) async {
  AppDatabase? db;
  try {
    final password = await SecureBackupPasswordStore().read();
    if (password == null) return true; // Kurulum bitmemiş.

    final keyStore = SecureStorageKeyStore();
    if (!await keyStore.exists()) return true;

    db = await AppDatabaseFactory.open(keyStore);
    final settings = SettingsRepository(db);
    if (!await settings.isSetupCompleted()) return true;

    final docs = await getApplicationDocumentsDirectory();
    final service = BackupService(
      db: db,
      databaseFile: await AppDatabaseFactory.databaseFile(),
      backupDirectory: Directory(p.join(docs.path, 'yedekler')),
      keyStore: keyStore,
    );

    final policy = AutoBackupPolicy(backup: service, settings: settings);
    if (await policy.isScheduledTime(now: now)) {
      await policy.runAutoBackup(
        password: password,
        trigger: BackupTrigger.autoDaily,
        now: now,
      );
    }

    // Vade bildirimleri her koşuda tazelenir: tahsil edilen bir evrakın
    // bildirimi ertesi gün çalmasın (BRIEF §5).
    final notifications = NotificationService();
    await notifications.initialize();
    await notifications.reschedule(
      await DueDateNotifier(db).pendingNotifications(now: now),
    );

    return true;
  } catch (_) {
    // Yeniden denemek yedek fırtınası yaratır; bir sonraki saatlik koşu
    // zaten tekrar dener.
    return true;
  } finally {
    await db?.close();
  }
}
