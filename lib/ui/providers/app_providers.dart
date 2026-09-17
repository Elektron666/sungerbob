import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Uygulama kilidi durumu.
final appLockProvider = NotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);

class AppLockNotifier extends Notifier<bool> {
  /// true = kilitli
  @override
  bool build() => true;

  void unlock() => state = false;
  void lock() => state = true;
}
