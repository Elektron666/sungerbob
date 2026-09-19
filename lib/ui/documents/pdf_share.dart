import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/app_database.dart';
import '../../data/documents/pdf_documents.dart';
import '../../data/repo/settings_repository.dart';
import '../../data/repo/stock_queries.dart';
import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../format/tr_format.dart';

/// PDF belgelerinin arayüze bağlandığı yer.
///
/// `PdfDocuments` Faz 3'te yazıldı, testleri de vardı — ama hiçbir ekrandan
/// çağrılmıyordu. BRIEF §5 "WhatsApp'a doğrudan paylaşılır" diyor;
/// paylaşılamayan bir belge, olmayan bir belgedir.

/// Ayarlardaki firma bilgisi; logo varsa dosyadan okunur.
Future<CompanyInfo> companyInfoOf(AppDatabase db) async {
  final settings = await SettingsRepository(db).company();

  Uint8List? logo;
  final path = settings.logoPath;
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    // Logo silinmiş olabilir; belge logosuz da üretilebilmeli.
    if (file.existsSync()) logo = await file.readAsBytes();
  }

  return CompanyInfo(
    name: settings.name.isEmpty ? 'Sünger Stok & Cari' : settings.name,
    address: settings.address,
    phone: settings.phone,
    taxOffice: settings.taxOffice,
    taxNumber: settings.taxNumber,
    logo: logo,
  );
}

/// Üretilen PDF'i paylaşım sayfasına verir (WhatsApp, e-posta, kaydet).
Future<void> sharePdf(
  BuildContext context, {
  required String fileName,
  required Uint8List bytes,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
  }
}

/// Satış fişi PDF'i.
Future<Uint8List> buildSaleReceipt(AppDatabase db, String saleId) async {
  final sale = await (db.select(
    db.sales,
  )..where((s) => s.id.equals(saleId))).getSingle();
  final customer = await (db.select(
    db.customers,
  )..where((c) => c.id.equals(sale.customerId))).getSingle();

  return PdfDocuments.salesReceipt(
    company: await companyInfoOf(db),
    docNo: sale.docNo,
    docDate: DateTime.fromMillisecondsSinceEpoch(sale.docDate),
    customerTitle: customer.title,
    dueDate: sale.dueDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sale.dueDate!),
    lines: await _lines(
      db,
      table: 'sale_items',
      parentKey: 'sale_id',
      id: saleId,
    ),
    subtotalNet: sale.subtotalNet,
    vatTotal: sale.vatTotal,
    grandTotal: sale.grandTotal,
    note: sale.note,
  );
}

/// Teklif PDF'i.
Future<Uint8List> buildQuotePdf(AppDatabase db, String quoteId) async {
  final quote = await (db.select(
    db.salesQuotes,
  )..where((q) => q.id.equals(quoteId))).getSingle();
  final customer = await (db.select(
    db.customers,
  )..where((c) => c.id.equals(quote.customerId))).getSingle();

  return PdfDocuments.quote(
    company: await companyInfoOf(db),
    docNo: quote.docNo,
    docDate: DateTime.fromMillisecondsSinceEpoch(quote.docDate),
    customerTitle: customer.title,
    validUntil: quote.validUntil == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(quote.validUntil!),
    lines: await _lines(
      db,
      table: 'sales_quote_items',
      parentKey: 'sales_quote_id',
      id: quoteId,
    ),
    subtotalNet: quote.subtotalNet,
    vatTotal: quote.vatTotal,
    grandTotal: quote.grandTotal,
    note: quote.note,
  );
}

/// Cari ekstre PDF'i.
Future<Uint8List> buildCustomerStatement(
  AppDatabase db,
  String customerId, {
  DateTime? asOf,
}) async {
  final customer = await (db.select(
    db.customers,
  )..where((c) => c.id.equals(customerId))).getSingle();

  final entries =
      await (db.select(db.customerLedger)
            ..where((l) => l.customerId.equals(customerId))
            ..orderBy([(l) => OrderingTerm.asc(l.occurredAt)]))
          .get();

  return PdfDocuments.customerStatement(
    company: await companyInfoOf(db),
    customerTitle: customer.title,
    asOf: asOf ?? DateTime.now(),
    entries: [
      for (final e in entries)
        (
          date: DateTime.fromMillisecondsSinceEpoch(e.occurredAt),
          description: e.description ?? e.docType,
          amount: e.amount,
        ),
    ],
    balance: await db.customerBalance(customerId),
  );
}

/// Belge kalemleri; satış ve teklif aynı kolonları taşır.
Future<List<DocumentLine>> _lines(
  AppDatabase db, {
  required String table,
  required String parentKey,
  required String id,
}) async {
  final rows = await db
      .customSelect(
        '''
    SELECT i.pieces, i.volume, i.unit_price_m3, i.net_total, i.vat_total,
           i.gross_total, pr.name AS product, pr.unit AS unit,
           v.width, v.height, v.thickness
    FROM $table i
    JOIN product_variants v ON v.id = i.variant_id
    JOIN products pr ON pr.id = v.product_id
    WHERE i.$parentKey = ?
    ORDER BY i.line_no
    ''',
        variables: [Variable.withString(id)],
        readsFrom: {db.productVariants, db.products},
      )
      .get();

  return [
    for (final r in rows)
      DocumentLine(
        description: _describe(
          r.read<String>('product'),
          r.read<int>('width'),
          r.read<int>('height'),
          r.read<int>('thickness'),
        ),
        pieces: r.read<int>('pieces'),
        volume: Volume.fromStored(r.read<int>('volume')),
        unitPrice: UnitPrice.fromStored(r.read<int>('unit_price_m3')),
        net: Money.fromStored(r.read<int>('net_total')),
        vat: Money.fromStored(r.read<int>('vat_total')),
        gross: Money.fromStored(r.read<int>('gross_total')),
      ),
  ];
}

/// Ölçüsüz malzemede ölçü yazılmaz (D-22).
String _describe(String product, int w, int h, int t) {
  if (w == 0 && h == 0 && t == 0) return product;
  return '$product · '
      '${TrFormat.dimensions(Dimension.fromStored(w), Dimension.fromStored(h), Dimension.fromStored(t))}';
}

/// Dosya adı: `SatisFisi_STS-2026-0001.pdf` gibi.
String pdfFileName(String prefix, String docNo) =>
    '${prefix}_${docNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}.pdf';

/// Kesim emri PDF'i — kesimhaneye gönderilen ölçü listesi.
///
/// Fiyat içermez: kesimhanenin görmesi gereken yalnızca ölçü ve adettir.
/// Kâğıda basılıp malın üstüne konur ya da WhatsApp'tan gönderilir.
Future<Uint8List> buildCuttingOrderPdf(AppDatabase db, String orderId) async {
  final order = await (db.select(
    db.cuttingOrders,
  )..where((o) => o.id.equals(orderId))).getSingle();

  final cutter = await (db.select(
    db.suppliers,
  )..where((s) => s.id.equals(order.cutterSupplierId))).getSingleOrNull();

  Future<List<({String description, int pieces})>> rowsOf(
    String table,
    String parentKey,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT x.pieces, pr.name AS product,
             v.width, v.height, v.thickness
      FROM $table x
      JOIN product_variants v ON v.id = x.variant_id
      JOIN products pr ON pr.id = v.product_id
      WHERE x.$parentKey = ?
      ''',
          variables: [Variable.withString(orderId)],
          readsFrom: {db.productVariants, db.products},
        )
        .get();
    return [
      for (final r in rows)
        (
          description: _describe(
            r.read<String>('product'),
            r.read<int>('width'),
            r.read<int>('height'),
            r.read<int>('thickness'),
          ),
          pieces: r.read<int>('pieces'),
        ),
    ];
  }

  return PdfDocuments.cuttingOrder(
    company: await companyInfoOf(db),
    docNo: order.docNo,
    sentDate: DateTime.fromMillisecondsSinceEpoch(order.sentDate),
    cutterTitle: cutter?.title ?? '—',
    sources: await rowsOf('cutting_order_sources', 'cutting_order_id'),
    targets: await rowsOf('cutting_order_plan_items', 'cutting_order_id'),
    note: order.note,
  );
}
