import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/core/text_normalize.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'unit_of_work.dart';

/// Cari kartları: müşteri ve tedarikçi oluşturma.
///
/// Bunlar olmadan uygulama hiçbir iş yapamaz — alış tedarikçi, satış müşteri
/// ister. Kart açma akışı bu yüzden **her yerden ulaşılabilir** olmalıdır.
///
/// Kod (`code`) benzersizdir ve kullanıcıya sorulmaz: elle kod girdirmek hem
/// yavaş hem de çakışmaya açıktır. Başlıktan türetilir, gerekirse sonuna
/// sayı eklenir.
final class PartyRepository {
  final AppDatabase db;
  const PartyRepository(this.db);

  Future<String> createCustomer({
    required String title,
    required OperationContext ctx,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? taxOffice,
    String? taxNumber,
    Rate? defaultDiscountRate,
    Money? riskLimit,
    int paymentTermDays = 0,
    String? note,
  }) => db.runOperation(ctx, () async {
    final id = uuid.v7();
    final clean = title.trim();

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            code: await _uniqueCode(clean, _customerCodeExists),
            title: clean,
            titleNormalized: normalizeTurkish(clean),
            contactPerson: Value(_orNull(contactPerson)),
            phone: Value(_orNull(phone)),
            email: Value(_orNull(email)),
            address: Value(_orNull(address)),
            taxOffice: Value(_orNull(taxOffice)),
            taxNumber: Value(_orNull(taxNumber)),
            defaultDiscountRate: Value(defaultDiscountRate ?? Rate.zero),
            riskLimit: Value(riskLimit ?? Money.zero),
            paymentTermDays: Value(paymentTermDays),
            note: Value(_orNull(note)),
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'customer',
      entityId: id,
      action: 'CREATE',
      summary: 'Müşteri açıldı: $clean',
    );
    return id;
  });

  Future<String> createSupplier({
    required String title,
    required String type,
    required OperationContext ctx,
    String? contactPerson,
    String? phone,
    String? address,
    String? taxOffice,
    String? taxNumber,
    int paymentTermDays = 0,
    String? note,
  }) => db.runOperation(ctx, () async {
    final id = uuid.v7();
    final clean = title.trim();

    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            code: await _uniqueCode(clean, _supplierCodeExists),
            title: clean,
            titleNormalized: normalizeTurkish(clean),
            type: type,
            contactPerson: Value(_orNull(contactPerson)),
            phone: Value(_orNull(phone)),
            address: Value(_orNull(address)),
            taxOffice: Value(_orNull(taxOffice)),
            taxNumber: Value(_orNull(taxNumber)),
            paymentTermDays: Value(paymentTermDays),
            note: Value(_orNull(note)),
          ),
        );

    await db.writeAudit(
      ctx,
      entityType: 'supplier',
      entityId: id,
      action: 'CREATE',
      summary: 'Tedarikçi açıldı (${_typeLabel(type)}): $clean',
    );
    return id;
  });

  // -------------------------------------------------------------- kod üretimi

  /// Başlıktan okunabilir bir kod türetir: "Öz Sünger A.Ş." → `OZSUNGER`.
  /// Aynı kod varsa sonuna sayı eklenir.
  static String codeFromTitle(String title) {
    final ascii = normalizeTurkish(title).toUpperCase();
    final letters = ascii.replaceAll(RegExp('[^A-Z0-9]'), '');
    if (letters.isEmpty) return 'CARI';
    return letters.substring(0, letters.length < 10 ? letters.length : 10);
  }

  Future<String> _uniqueCode(
    String title,
    Future<bool> Function(String) exists,
  ) async {
    final base = codeFromTitle(title);
    if (!await exists(base)) return base;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base$i';
      if (!await exists(candidate)) return candidate;
    }
    // Buraya düşmek için aynı adla 1000 kart gerekir; yine de benzersiz kal.
    return '$base-${uuid.v7().substring(0, 8)}';
  }

  Future<bool> _customerCodeExists(String code) async =>
      await (db.select(
        db.customers,
      )..where((c) => c.code.equals(code))).getSingleOrNull() !=
      null;

  Future<bool> _supplierCodeExists(String code) async =>
      await (db.select(
        db.suppliers,
      )..where((s) => s.code.equals(code))).getSingleOrNull() !=
      null;

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _typeLabel(String type) => switch (type) {
    SupplierType.factory => 'Fabrika',
    SupplierType.cutter => 'Kesimhane',
    SupplierType.carrier => 'Nakliye',
    _ => 'Diğer',
  };
}
