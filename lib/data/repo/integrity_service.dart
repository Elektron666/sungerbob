import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../db/app_database.dart';

/// Tek bir tutarsızlık bulgusu.
final class IntegrityFinding {
  final String check;
  final String entityType;
  final String entityId;
  final String expected;
  final String actual;
  final String message;

  const IntegrityFinding({
    required this.check,
    required this.entityType,
    required this.entityId,
    required this.expected,
    required this.actual,
    required this.message,
  });

  @override
  String toString() => '[$check] $entityType $entityId: '
      'beklenen $expected, bulunan $actual — $message';
}

final class IntegrityReport {
  final List<IntegrityFinding> findings;
  final DateTime checkedAt;

  const IntegrityReport({required this.findings, required this.checkedAt});

  bool get isClean => findings.isEmpty;
}

/// `checkIntegrity()` (BRIEF §3.5, ARCHITECTURE §6.1).
///
/// Parti kalanlarını ve bakiyeleri **hareketlerden yeniden hesaplayıp**
/// saklananlarla karşılaştırır. Fark bulursa rapor eder — kendiliğinden
/// düzeltmez; düzeltme ters hareketle ve kullanıcı onayıyla yapılır.
///
/// Ayarlar'dan elle çalıştırılır; **her yedek yüklemesinden sonra otomatik**
/// çalışır (BRIEF §4.5).
final class IntegrityService {
  final AppDatabase db;
  const IntegrityService(this.db);

  Future<IntegrityReport> check() async {
    final findings = <IntegrityFinding>[];
    await _checkBatchRemainders(findings);
    await _checkVariantStock(findings);
    await _checkNegativeRemainders(findings);
    await _checkInstrumentStatus(findings);
    await _checkForeignKeys(findings);
    return IntegrityReport(findings: findings, checkedAt: DateTime.now());
  }

  /// Parti kalanı = giren − (tüketilen − iade edilen).
  Future<void> _checkBatchRemainders(List<IntegrityFinding> findings) async {
    final rows = await db.customSelect('''
      SELECT b.id, b.in_pieces, b.in_volume, b.remaining_pieces, b.remaining_volume,
        COALESCE((
          SELECT SUM(CASE WHEN sm.pieces < 0 THEN ca.pieces ELSE -ca.pieces END)
          FROM cost_allocations ca
          JOIN stock_movements sm ON sm.id = ca.movement_id
          WHERE ca.batch_id = b.id
        ), 0) AS consumed_pieces,
        COALESCE((
          SELECT SUM(CASE WHEN sm.pieces < 0 THEN ca.volume ELSE -ca.volume END)
          FROM cost_allocations ca
          JOIN stock_movements sm ON sm.id = ca.movement_id
          WHERE ca.batch_id = b.id
        ), 0) AS consumed_volume
      FROM inventory_batches b
      ''', readsFrom: {db.inventoryBatches, db.costAllocations, db.stockMovements}).get();

    for (final r in rows) {
      final expectedPieces = r.read<int>('in_pieces') - r.read<int>('consumed_pieces');
      final actualPieces = r.read<int>('remaining_pieces');
      if (expectedPieces != actualPieces) {
        findings.add(IntegrityFinding(
          check: 'parti_kalan_adet',
          entityType: 'inventory_batch',
          entityId: r.read<String>('id'),
          expected: '$expectedPieces adet',
          actual: '$actualPieces adet',
          message: 'Parti kalanı hareketlerle uyuşmuyor',
        ));
      }

      final expectedVolume =
          Volume.fromStored(r.read<int>('in_volume') - r.read<int>('consumed_volume'));
      final actualVolume = Volume.fromStored(r.read<int>('remaining_volume'));
      if (expectedVolume != actualVolume) {
        findings.add(IntegrityFinding(
          check: 'parti_kalan_hacim',
          entityType: 'inventory_batch',
          entityId: r.read<String>('id'),
          expected: '$expectedVolume',
          actual: '$actualVolume',
          message: 'Parti hacmi hareketlerle uyuşmuyor',
        ));
      }
    }
  }

  /// Varyant stoğu = SUM(stock_movements) → parti kalanları toplamı.
  Future<void> _checkVariantStock(List<IntegrityFinding> findings) async {
    final rows = await db.customSelect('''
      SELECT sm.variant_id, sm.location_id,
             SUM(sm.pieces) AS movement_pieces,
             COALESCE((
               SELECT SUM(b.remaining_pieces) FROM inventory_batches b
               WHERE b.variant_id = sm.variant_id AND b.location_id = sm.location_id
             ), 0) AS batch_pieces
      FROM stock_movements sm
      GROUP BY sm.variant_id, sm.location_id
      ''', readsFrom: {db.stockMovements, db.inventoryBatches}).get();

    for (final r in rows) {
      final fromMovements = r.read<int>('movement_pieces');
      final fromBatches = r.read<int>('batch_pieces');
      if (fromMovements != fromBatches) {
        findings.add(IntegrityFinding(
          check: 'varyant_stok',
          entityType: 'product_variant',
          entityId: r.read<String>('variant_id'),
          expected: '$fromMovements adet (hareketlerden)',
          actual: '$fromBatches adet (partilerden)',
          message: 'Hareket toplamı ile parti kalanları uyuşmuyor',
        ));
      }
    }
  }

  Future<void> _checkNegativeRemainders(List<IntegrityFinding> findings) async {
    final rows = await (db.select(db.inventoryBatches)
          ..where((b) =>
              b.remainingPieces.isSmallerThanValue(0) |
              b.remainingVolume.isSmallerThanValue(0)))
        .get();

    for (final b in rows) {
      findings.add(IntegrityFinding(
        check: 'negatif_kalan',
        entityType: 'inventory_batch',
        entityId: b.id,
        expected: '>= 0',
        actual: '${b.remainingPieces} adet',
        message: 'Negatif stok — olmaması gerekir (BRIEF §3.8)',
      ));
    }
  }

  /// `instruments.current_status` bir önbellektir; doğrusu olay zincirinin sonu.
  Future<void> _checkInstrumentStatus(List<IntegrityFinding> findings) async {
    final rows = await db.customSelect('''
      SELECT i.id, i.current_status,
             (SELECT e.to_status FROM instrument_events e
              WHERE e.instrument_id = i.id
              ORDER BY e.occurred_at DESC, e.id DESC LIMIT 1) AS last_status
      FROM instruments i
      ''', readsFrom: {db.instruments, db.instrumentEvents}).get();

    for (final r in rows) {
      final last = r.read<String?>('last_status');
      final current = r.read<String>('current_status');
      if (last != null && last != current) {
        findings.add(IntegrityFinding(
          check: 'evrak_durumu',
          entityType: 'instrument',
          entityId: r.read<String>('id'),
          expected: last,
          actual: current,
          message: 'Evrak durumu olay zinciriyle uyuşmuyor',
        ));
      }
    }
  }

  Future<void> _checkForeignKeys(List<IntegrityFinding> findings) async {
    final issues = await db.foreignKeyCheck();
    for (final row in issues) {
      findings.add(IntegrityFinding(
        check: 'yabanci_anahtar',
        entityType: row.data['table']?.toString() ?? '?',
        entityId: row.data['rowid']?.toString() ?? '?',
        expected: 'geçerli referans',
        actual: 'yetim kayıt',
        message: 'Yabancı anahtar bütünlüğü bozuk',
      ));
    }
  }

  /// Cari bakiyenin hareketlerden hesaplanmış hali — ekranda gösterilenle
  /// karşılaştırmak için.
  Future<Money> recomputeCustomerBalance(String customerId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM customer_ledger WHERE customer_id = ?',
      variables: [Variable.withString(customerId)],
      readsFrom: {db.customerLedger},
    ).getSingle();
    return Money.fromStored(row.read<int>('total'));
  }
}
