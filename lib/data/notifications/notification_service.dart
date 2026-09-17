import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'due_date_notifier.dart';

/// Yerel bildirimlerin platform tarafı (BRIEF §5).
///
/// Hangi bildirimlerin gerektiği `DueDateNotifier`'da saf Dart ile
/// hesaplanır; burada yalnızca **zamanlama** yapılır.
///
/// Bildirimler her yeniden hesaplamada tamamen silinip yeniden kurulur.
/// Alternatif — tek tek güncellemek — vadesi değişen veya tahsil edilen bir
/// evrakın eski bildiriminin cihazda kalmasına yol açardı.
final class NotificationService {
  final FlutterLocalNotificationsPlugin plugin;

  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'vade';
  static const _channelName = 'Vade hatırlatmaları';
  static const _channelDescription =
      'Çek, senet ve satış vadelerinden bir gün önce hatırlatır';

  bool _initialized = false;

  /// Uygulama açılışında bir kez çağrılır.
  Future<void> initialize({void Function(String route)? onTapRoute}) async {
    if (_initialized) return;

    // Zamanlanmış bildirim yerel saat dilimi ister; `timezone` veritabanı
    // yüklenmeden `tz.local` UTC kalır ve bildirimler saatinden şaşar.
    tzdata.initializeTimeZones();

    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) onTapRoute?.call(route);
      },
    );
    _initialized = true;
  }

  /// Android 13+ bildirim izni ve tam zamanlı alarm izni.
  ///
  /// İzin verilmezse bildirim kurulmaz; uygulamanın geri kalanı çalışmaya
  /// devam eder — vade takibi ana sayfadan da görülebiliyor.
  Future<bool> requestPermissions() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;

    final granted = await android.requestNotificationsPermission() ?? false;
    if (granted) await android.requestExactAlarmsPermission();
    return granted;
  }

  /// Bekleyen tüm vade bildirimlerini yeniden kurar.
  Future<int> reschedule(List<PendingNotification> pending) async {
    await plugin.cancelAll();

    var scheduled = 0;
    for (final item in pending) {
      final when = tz.TZDateTime.from(item.scheduledAt, tz.local);
      // Geçmişe bildirim kurulamaz; ara sırada geçmiş olanlar atlanır.
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) continue;

      await plugin.zonedSchedule(
        id: _notificationId(item.id),
        title: item.title,
        body: item.body,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: item.route,
      );
      scheduled++;
    }
    return scheduled;
  }

  Future<void> cancelAll() => plugin.cancelAll();

  /// Bildirim kimliği 32 bitlik tamsayı olmalı; UUID'den kararlı bir sayı
  /// türetilir. Aynı evrak her zaman aynı kimliği alır.
  static int notificationIdFor(String key) => _notificationId(key);

  static int _notificationId(String key) {
    // FNV-1a 32 bit.
    var hash = 0x811c9dc5;
    for (final code in key.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Android bildirim kimliği işaretli 32 bit; üst biti düşür.
    return hash & 0x7FFFFFFF;
  }
}
