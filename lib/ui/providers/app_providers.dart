import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import '../../data/backup/auto_backup.dart';
import '../../data/backup/backup_password_store.dart';
import '../../data/backup/backup_service.dart';
import '../../data/db/app_database.dart';
import '../../data/db/connection.dart';
import '../../data/db/database_key.dart';
import '../../data/repo/collection_repository.dart';
import '../../data/repo/integrity_service.dart';
import '../../data/repo/opening_repository.dart';
import '../../data/repo/payment_repository.dart';
import '../../data/repo/price_list_repository.dart';
import '../../data/repo/purchase_repository.dart';
import '../../data/repo/return_repository.dart';
import '../../data/repo/reversal_repository.dart';
import '../../data/repo/sale_repository.dart';
import '../../data/repo/instrument_repository.dart';
import '../../data/repo/cutting_repository.dart';
import '../../data/repo/quote_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../data/repo/stock_ops_repository.dart';

/// Uygulama genelindeki bağımlılıklar.
///
/// Ekranlar repository'lere doğrudan değil, bu sağlayıcılar üzerinden erişir
/// (ARCHITECTURE §2.3).

final databaseKeyStoreProvider = Provider<DatabaseKeyStore>(
  (ref) => SecureStorageKeyStore(),
);

/// Şifreli veritabanı. Uygulama ömrü boyunca tek örnek.
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabaseFactory.open(ref.watch(databaseKeyStoreProvider));
  ref.onDispose(db.close);
  return db;
});

/// Yedekleme servisi.
final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final dbFile = await AppDatabaseFactory.databaseFile();
  final docs = await getApplicationDocumentsDirectory();
  final backupDir = Directory(p.join(docs.path, 'yedekler'));

  return BackupService(
    db: db,
    databaseFile: dbFile,
    backupDirectory: backupDir,
    keyStore: ref.watch(databaseKeyStoreProvider),
  );
});

// ------------------------------------------------------------ repository'ler

final purchaseRepositoryProvider = FutureProvider(
  (ref) async => PurchaseRepository(await ref.watch(databaseProvider.future)),
);

final saleRepositoryProvider = FutureProvider(
  (ref) async => SaleRepository(await ref.watch(databaseProvider.future)),
);

final collectionRepositoryProvider = FutureProvider(
  (ref) async => CollectionRepository(await ref.watch(databaseProvider.future)),
);

final paymentRepositoryProvider = FutureProvider(
  (ref) async => PaymentRepository(await ref.watch(databaseProvider.future)),
);

final returnRepositoryProvider = FutureProvider(
  (ref) async => ReturnRepository(await ref.watch(databaseProvider.future)),
);

final reversalRepositoryProvider = FutureProvider(
  (ref) async => ReversalRepository(await ref.watch(databaseProvider.future)),
);

final instrumentRepositoryProvider = FutureProvider(
  (ref) async => InstrumentRepository(await ref.watch(databaseProvider.future)),
);

final openingRepositoryProvider = FutureProvider(
  (ref) async => OpeningRepository(await ref.watch(databaseProvider.future)),
);

final priceListRepositoryProvider = FutureProvider(
  (ref) async => PriceListRepository(await ref.watch(databaseProvider.future)),
);

final integrityServiceProvider = FutureProvider(
  (ref) async => IntegrityService(await ref.watch(databaseProvider.future)),
);

final stockOpsRepositoryProvider = FutureProvider(
  (ref) async => StockOpsRepository(await ref.watch(databaseProvider.future)),
);

final cuttingRepositoryProvider = FutureProvider(
  (ref) async => CuttingRepository(await ref.watch(databaseProvider.future)),
);

final quoteRepositoryProvider = FutureProvider(
  (ref) async => QuoteRepository(await ref.watch(databaseProvider.future)),
);

final settingsRepositoryProvider = FutureProvider(
  (ref) async => SettingsRepository(await ref.watch(databaseProvider.future)),
);

/// Yedek şifresi güvenli depoda; otomatik yedek buradan okur (D-22).
final backupPasswordStoreProvider = Provider<BackupPasswordStore>(
  (ref) => SecureBackupPasswordStore(),
);

final autoBackupPolicyProvider = FutureProvider(
  (ref) async => AutoBackupPolicy(
    backup: await ref.watch(backupServiceProvider.future),
    settings: await ref.watch(settingsRepositoryProvider.future),
  ),
);

// -------------------------------------------------------------- cari kartlar

/// Etkin tedarikçiler. Alış ve kesim ekranları buradan besleniyor.
final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.suppliers)
        ..where((s) => s.isActive.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.title)]))
      .get();
});

/// Etkin müşteriler. Satış ve tahsilat ekranları buradan besleniyor.
final customersProvider = FutureProvider.autoDispose<List<Customer>>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return (db.select(db.customers)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.title)]))
      .get();
});

// ----------------------------------------------------------------- kurulum

/// Kurulum sihirbazı tamamlandı mı? Uygulama açılışında ilk sorulan şey.
final setupCompletedProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return settings.isSetupCompleted();
});

// --------------------------------------------------------------- oturum

/// "Maliyeti gizle" modu (BRIEF §5).
///
/// Açıkken maliyet, kâr ve alış fiyatları ekranda gizlenir — telefonu
/// müşteriye gösterirken. **Kapatmak için PIN gerekir.**
///
/// v1'de bu bir gösterim kontrolüdür; tek kullanıcı ve tek cihaz olduğu için
/// güvenlik sınırı değildir (DECISIONS D-04).
final hideCostProvider = NotifierProvider<HideCostNotifier, bool>(
  HideCostNotifier.new,
);

class HideCostNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Gizlemeyi açar — PIN gerektirmez.
  void hide() => state = true;

  /// Gizlemeyi kapatır. Çağıran taraf önce PIN doğrulamalıdır.
  void revealAfterPinVerified() => state = false;
}

/// Uygulama giriş kapısı: kurulum mu, kilit mi, uygulama mı?
///
/// Uygulama her açılışta kilitlidir (BRIEF §5). Kurulum tamamlanmadıysa
/// kilit değil sihirbaz gösterilir.
enum AppGate { unknown, setup, locked, ready }

final appLockProvider = NotifierProvider<AppLockNotifier, AppGate>(
  AppLockNotifier.new,
);

class AppLockNotifier extends Notifier<AppGate> {
  @override
  AppGate build() {
    unawaited(_resolve());
    return AppGate.unknown;
  }

  Future<void> _resolve() async {
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      final done = await settings.isSetupCompleted() && await settings.hasPin();
      state = done ? AppGate.locked : AppGate.setup;
    } catch (_) {
      // Veritabanı açılamadıysa kurulumdan başlamak tek güvenli seçenek.
      state = AppGate.setup;
    }
  }

  /// PIN doğrulandıktan veya kurulum bittikten sonra.
  void unlock() => state = AppGate.ready;

  /// Arka plana alınınca veya kullanıcı kilitleyince.
  void lock() {
    if (state == AppGate.ready) state = AppGate.locked;
  }
}

/// Belge girişinde kullanılan varsayılanlar (Ayarlar → İşletme).
///
/// Ekranlar KDV oranını koda gömülü %20 olarak tutuyordu: kullanıcı
/// Ayarlar'da %10 seçse bile her satış %20 hesaplıyordu. Para hesabının
/// ayarı görmezden gelmesi kabul edilemez (D-32).
final class DocumentDefaults {
  final Rate vatRate;
  final PriceMode priceMode;

  const DocumentDefaults({required this.vatRate, required this.priceMode});
}

final documentDefaultsProvider = FutureProvider<DocumentDefaults>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return DocumentDefaults(
    vatRate: await settings.defaultVatRate(),
    priceMode: await settings.defaultPriceMode() == 'INCL'
        ? PriceMode.incl
        : PriceMode.excl,
  );
});
