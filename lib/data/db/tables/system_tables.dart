import 'package:drift/drift.dart';

/// Sistem, kimlik ve log tabloları (ERD §2).

@TableIndex(name: 'idx_users_username', columns: {#username}, unique: true)
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().withLength(min: 1, max: 60)();
  TextColumn get displayName => text().withLength(min: 1, max: 120)();
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();
  BoolColumn get biometricEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Roles extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Permissions extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get description => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class RolePermissions extends Table {
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get permissionId => text().references(Permissions, #id)();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get firstSeenAt => integer()();
  IntColumn get lastSeenAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Anahtar-değer ayarları (ERD §2 tablosu).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Yıl bazlı, boşluksuz belge numarası (BRIEF §3.11).
@TableIndex(
  name: 'idx_docseq_type_year',
  columns: {#docType, #year},
  unique: true,
)
class DocumentSequences extends Table {
  TextColumn get id => text()();
  TextColumn get docType => text()();
  IntColumn get year => integer()();
  IntColumn get lastNumber => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (doc_type IN ('STS','ALS','THS','TKL','IAD','KSM','ODM','SYM','FIR','VRM','GDR'))",
    'CHECK (last_number >= 0)',
  ];
}

/// 🔒 append-only. Birincil anahtar istemcide üretilen UUID'dir; aynı UUID
/// ikinci kez gelirse INSERT çakışır ve işlem tekrarlanmaz (BRIEF §3.9, D-09).
class CommandLog extends Table {
  TextColumn get id => text()();
  TextColumn get commandType => text()();
  TextColumn get payloadHash => text()();
  TextColumn get resultRefType => text().nullable()();
  TextColumn get resultRefId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 🔒 append-only (SPEC §24).
@TableIndex(name: 'idx_audit_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_audit_entity', columns: {#entityType, #entityId})
class AuditLogs extends Table {
  TextColumn get id => text()();
  IntColumn get occurredAt => integer()();
  TextColumn get actorUserId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get summary => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get commandId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 🔒 append-only. Yedek alma/yükleme geçmişi (BRIEF §6).
@TableIndex(name: 'idx_backuplog_occurred', columns: {#occurredAt})
class BackupLog extends Table {
  TextColumn get id => text()();
  IntColumn get occurredAt => integer()();
  TextColumn get kind => text()();
  TextColumn get trigger => text()();
  TextColumn get destination => text()();
  TextColumn get fileName => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get sha256 => text().nullable()();
  IntColumn get schemaVersion => integer()();
  TextColumn get appVersion => text()();
  TextColumn get result => text()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('BACKUP','RESTORE'))",
    "CHECK (trigger IN ('MANUAL','AUTO_DAILY','AUTO_STARTUP','PRE_RISK','PRE_MIGRATION'))",
    "CHECK (destination IN ('LOCAL','DRIVE','SHARE'))",
    "CHECK (result IN ('OK','FAIL'))",
  ];
}
