import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/data/notifications/notification_service.dart';

/// Bildirim kimliği türetmesi (BRIEF §5).
///
/// Android bildirim kimliği **işaretli 32 bit tamsayı**; UUID doğrudan
/// kullanılamaz. Aynı evrak her zaman aynı kimliği almalı ki vadesi değişen
/// bir bildirim ikinci kez kurulmasın.
void main() {
  test('aynı anahtar her zaman aynı kimliği verir', () {
    final a = NotificationService.notificationIdFor('instrument-abc');
    final b = NotificationService.notificationIdFor('instrument-abc');
    expect(a, b);
  });

  test('farklı anahtarlar farklı kimlik verir', () {
    final a = NotificationService.notificationIdFor('instrument-abc');
    final b = NotificationService.notificationIdFor('instrument-abd');
    expect(a, isNot(b));
  });

  test('kimlik pozitif ve 32 bit sınırında', () {
    for (final key in [
      'instrument-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b',
      'sale-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5c',
      '',
      'çşğüöı',
    ]) {
      final id = NotificationService.notificationIdFor(key);
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7FFFFFFF));
    }
  });

  test('gerçek UUID kümesinde çakışma yok', () {
    final ids = <int>{};
    for (var i = 0; i < 2000; i++) {
      final id = NotificationService.notificationIdFor(
        'instrument-0199a1b2-c3d4-7e5f-8a9b-${i.toString().padLeft(12, '0')}',
      );
      ids.add(id);
    }
    expect(ids.length, 2000);
  });
}
