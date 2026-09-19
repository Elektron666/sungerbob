import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../domain/core/quantity.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Ayarlar ve kurulum durumu.
///
/// Ayarlar anahtar-değer tablosunda durur; tipli erişim burada toplanır.
final class SettingsRepository {
  final AppDatabase db;
  const SettingsRepository(this.db);

  // --------------------------------------------------------- kurulum

  static const _setupCompleted = 'setup_completed';
  static const _pinHash = 'pin_hash';
  static const _pinSalt = 'pin_salt';
  static const _biometric = 'biometric_enabled';
  static const _costingLocked = 'costing_method_locked_at';

  Future<bool> isSetupCompleted() async =>
      await _get(_setupCompleted) == 'true';

  Future<void> markSetupCompleted() => _set(_setupCompleted, 'true');

  // ------------------------------------------------------------- PIN

  /// PIN'i tuzlu SHA-256 ile saklar. Düz metin hiçbir yerde durmaz.
  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    await _set(_pinSalt, salt);
    await _set(_pinHash, _hashPin(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _get(_pinSalt);
    final hash = await _get(_pinHash);
    if (salt == null || hash == null) return false;
    return _hashPin(pin, salt) == hash;
  }

  Future<bool> hasPin() async => await _get(_pinHash) != null;

  Future<bool> isBiometricEnabled() async => await _get(_biometric) == 'true';
  Future<void> setBiometricEnabled(bool value) =>
      _set(_biometric, value.toString());

  static String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _randomSalt() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  // ------------------------------------------------------- iş ayarları

  Future<String> costingMethod() async =>
      await _get('costing_method') ?? CostingMethod.fifo;

  /// Maliyet yöntemi ilk stok hareketinden sonra **kilitlenir** (BRIEF §3.6).
  Future<bool> isCostingMethodLocked() async {
    if (await _get(_costingLocked) != null) return true;
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM stock_movements')
        .getSingle();
    return row.read<int>('c') > 0;
  }

  /// Yöntemi değiştirir. Kilitliyse **riskli işlemdir**: çağıran taraf önce
  /// yedek almalı ve kullanıcıdan onay istemelidir.
  Future<void> setCostingMethod(String method, OperationContext ctx) =>
      db.runOperation(ctx, () async {
        final wasLocked = await isCostingMethodLocked();
        final previous = await costingMethod();

        await _set('costing_method', method);
        if (wasLocked) {
          await _set(_costingLocked, '${ctx.nowMs}');
        }

        await db.writeAudit(
          ctx,
          entityType: 'settings',
          entityId: 'costing_method',
          action: 'SETTING_CHANGE',
          summary:
              'Maliyet yöntemi $previous → $method'
              '${wasLocked ? " (kilitliyken değiştirildi)" : ""}',
          beforeJson: '{"costing_method":"$previous"}',
          afterJson: '{"costing_method":"$method"}',
        );
      });

  Future<String> defaultPriceMode() async =>
      await _get('default_price_mode') ?? 'EXCL';

  Future<void> setDefaultPriceMode(String mode) =>
      _set('default_price_mode', mode);

  Future<Rate> defaultVatRate() async => Rate.fromStored(
    int.tryParse(await _get('default_vat_rate') ?? '2000') ?? 2000,
  );

  /// Oran ×100 ölçeğinde saklanır: %20 → 2000.
  Future<void> setDefaultVatRate(int storedRate) =>
      _set('default_vat_rate', '$storedRate');

  /// Belgelerde ve audit kayıtlarında görünen kullanıcı adı.
  Future<String> userName() async => await _get('user_name') ?? '';
  Future<void> saveUserName(String value) => _set('user_name', value);

  Future<List<Rate>> allowedVatRates() async {
    final raw = await _get('allowed_vat_rates') ?? '[0,100,1000,2000]';
    final list = (jsonDecode(raw) as List).cast<int>();
    return list.map(Rate.fromStored).toList();
  }

  // ------------------------------------------------------------ firma

  Future<CompanySettings> company() async => CompanySettings(
    name: await _get('company_name') ?? '',
    address: await _get('company_address'),
    phone: await _get('company_phone'),
    taxOffice: await _get('company_tax_office'),
    taxNumber: await _get('company_tax_number'),
    logoPath: await _get('company_logo_path'),
  );

  Future<void> saveCompany(CompanySettings value) async {
    await _set('company_name', value.name);
    await _setNullable('company_address', value.address);
    await _setNullable('company_phone', value.phone);
    await _setNullable('company_tax_office', value.taxOffice);
    await _setNullable('company_tax_number', value.taxNumber);
    await _setNullable('company_logo_path', value.logoPath);
  }

  // ---------------------------------------------------------- yedekleme

  Future<String> backupTime() async =>
      await _get('backup_auto_time') ?? '20:00';
  Future<void> setBackupTime(String value) => _set('backup_auto_time', value);

  Future<int> offsiteWarnDays() async =>
      int.tryParse(await _get('backup_offsite_warn_days') ?? '3') ?? 3;

  Future<void> setOffsiteWarnDays(int days) =>
      _set('backup_offsite_warn_days', '$days');

  Future<bool> backupWifiOnly() async =>
      await _get('backup_wifi_only') != 'false';
  Future<void> setBackupWifiOnly(bool value) =>
      _set('backup_wifi_only', value.toString());

  Future<String?> driveFolderId() => _get('drive_folder_id');
  Future<void> setDriveFolderId(String id) => _set('drive_folder_id', id);

  Future<DateTime?> lastAutoBackupDate() async {
    final raw = await _get('last_auto_backup_date');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastAutoBackupDate(DateTime value) =>
      _set('last_auto_backup_date', value.toIso8601String());

  // ------------------------------------------------------------ altyapı

  Future<String?> _get(String key) async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<void> _setNullable(String key, String? value) =>
      _set(key, value ?? '');
}

final class CompanySettings {
  final String name;
  final String? address;
  final String? phone;
  final String? taxOffice;
  final String? taxNumber;
  final String? logoPath;

  const CompanySettings({
    required this.name,
    this.address,
    this.phone,
    this.taxOffice,
    this.taxNumber,
    this.logoPath,
  });
}
