import 'dart:convert';

/// `.sbk` içindeki `manifest.json` (BACKUP.md §1.1).
///
/// Geri yükleme önizlemesi ve şema sürümü kontrolü buradan okunur.
final class BackupManifest {
  final int formatVersion;
  final String appVersion;
  final int appBuild;
  final int schemaVersion;
  final DateTime createdAt;
  final String deviceId;
  final String deviceName;
  final String costingMethod;
  final DateTime? lastTransactionAt;
  final Map<String, int> tableCounts;

  /// `database.db` dosyasının SHA-256 özeti.
  final String contentSha256;

  const BackupManifest({
    required this.appVersion,
    required this.appBuild,
    required this.schemaVersion,
    required this.createdAt,
    required this.deviceId,
    required this.deviceName,
    required this.costingMethod,
    required this.tableCounts,
    required this.contentSha256,
    this.lastTransactionAt,
    this.formatVersion = 1,
  });

  Map<String, dynamic> toJson() => {
    'format_version': formatVersion,
    'app_version': appVersion,
    'app_build': appBuild,
    'schema_version': schemaVersion,
    'created_at': createdAt.toIso8601String(),
    'created_at_epoch_ms': createdAt.millisecondsSinceEpoch,
    'device_id': deviceId,
    'device_name': deviceName,
    'costing_method': costingMethod,
    'last_transaction_at': lastTransactionAt?.toIso8601String(),
    'table_counts': tableCounts,
    'content_sha256': contentSha256,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static BackupManifest decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return BackupManifest(
      formatVersion: map['format_version'] as int? ?? 1,
      appVersion: map['app_version'] as String,
      appBuild: map['app_build'] as int? ?? 0,
      schemaVersion: map['schema_version'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      deviceId: map['device_id'] as String? ?? '',
      deviceName: map['device_name'] as String? ?? '',
      costingMethod: map['costing_method'] as String? ?? 'FIFO',
      lastTransactionAt: map['last_transaction_at'] == null
          ? null
          : DateTime.parse(map['last_transaction_at'] as String),
      tableCounts: (map['table_counts'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v as int),
      ),
      contentSha256: map['content_sha256'] as String,
    );
  }

  /// Önizlemede gösterilen özet sayılar.
  int get customerCount => tableCounts['customers'] ?? 0;
  int get productCount => tableCounts['products'] ?? 0;
  int get saleCount => tableCounts['sales'] ?? 0;
  int get collectionCount => tableCounts['collections'] ?? 0;
}
