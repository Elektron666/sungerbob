import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';
import '../db/app_database.dart';
import '../db/enums.dart';
import 'sale_repository.dart';
import 'unit_of_work.dart';

final class QuoteLineInput {
  final String variantId;
  final int pieces;
  final Volume volume;
  final UnitPrice listPriceM3;
  final UnitPrice unitPriceM3;
  final Rate vatRate;
  final Rate discountRate;

  const QuoteLineInput({
    required this.variantId,
    required this.pieces,
    required this.volume,
    required this.unitPriceM3,
    required this.vatRate,
    UnitPrice? listPriceM3,
    this.discountRate = Rate.zero,
  }) : listPriceM3 = listPriceM3 ?? unitPriceM3;
}

final class QuoteInput {
  final String customerId;
  final DateTime docDate;
  final DateTime? validUntil;
  final PriceMode priceMode;
  final List<QuoteLineInput> lines;
  final String? note;

  const QuoteInput({
    required this.customerId,
    required this.docDate,
    required this.priceMode,
    required this.lines,
    this.validUntil,
    this.note,
  });
}

/// Teklif zaten satışa dönüştürülmüş.
final class QuoteAlreadyConvertedException implements Exception {
  final String quoteId;
  final String saleId;
  const QuoteAlreadyConvertedException(this.quoteId, this.saleId);

  @override
  String toString() => 'Bu teklif zaten satışa dönüştürülmüş (satış $saleId).';
}

/// Teklif durumu izin verilmeyen bir duruma taşınmak istendi.
final class InvalidQuoteTransitionException implements Exception {
  final String from;
  final String to;
  const InvalidQuoteTransitionException(this.from, this.to);

  @override
  String toString() =>
      '${QuoteStatus.label(from)} durumundaki teklif '
      '"${QuoteStatus.label(to)}" yapılamaz.';
}

/// Fiyat teklifi (SPEC §15).
///
/// **Teklif oluşturulması stoktan ürün DÜŞMEZ.** Stok yalnızca satışa
/// dönüştürüldüğünde düşer.
final class QuoteRepository {
  final AppDatabase db;
  const QuoteRepository(this.db);

  Future<String> create(QuoteInput input, OperationContext ctx) =>
      db.runOperation(ctx, () async {
        final quoteId = uuid.v7();
        final docNo = await db.nextDocumentNumber(
          DocPrefix.quote,
          input.docDate.year,
        );

        final vatLines = [
          for (final line in input.lines)
            VatCalculator.forMode(
              mode: input.priceMode,
              volume: line.volume,
              unitPrice: line.unitPriceM3,
              vatRate: line.vatRate,
              discountRate: line.discountRate,
            ),
        ];

        await db
            .into(db.salesQuotes)
            .insert(
              SalesQuotesCompanion.insert(
                id: quoteId,
                docNo: docNo,
                customerId: input.customerId,
                docDate: input.docDate.millisecondsSinceEpoch,
                validUntil: Value(input.validUntil?.millisecondsSinceEpoch),
                priceMode: input.priceMode,
                subtotalNet: sumMoney(vatLines.map((v) => v.net)),
                vatTotal: sumMoney(vatLines.map((v) => v.vat)),
                grandTotal: sumMoney(vatLines.map((v) => v.gross)),
                createdAt: ctx.nowMs,
                note: Value(input.note),
              ),
            );

        for (var i = 0; i < input.lines.length; i++) {
          final line = input.lines[i];
          final vat = vatLines[i];
          await db
              .into(db.salesQuoteItems)
              .insert(
                SalesQuoteItemsCompanion.insert(
                  id: uuid.v7(),
                  salesQuoteId: quoteId,
                  lineNo: i + 1,
                  variantId: line.variantId,
                  pieces: line.pieces,
                  volume: line.volume,
                  listPriceM3: line.listPriceM3,
                  discountRate: Value(line.discountRate),
                  unitPriceM3: line.unitPriceM3,
                  netTotal: vat.net,
                  vatRate: line.vatRate,
                  vatTotal: vat.vat,
                  grossTotal: vat.gross,
                ),
              );
        }

        await db.writeAudit(
          ctx,
          entityType: 'sales_quote',
          entityId: quoteId,
          action: 'CREATE',
          summary: 'Teklif $docNo oluşturuldu',
        );
        return quoteId;
      });

  /// Durum değiştirir (gönderildi, kabul, ret).
  ///
  /// Geçiş kuralı `QuoteStatus.transitions`'ta; kural burada da denetlenir
  /// çünkü ekranın izin verilmeyeni göstermemesi, iş kuralının kendisi
  /// değildir.
  Future<void> setStatus({
    required String quoteId,
    required String status,
    required OperationContext ctx,
  }) => db.runOperation(ctx, () async {
    final quote = await (db.select(
      db.salesQuotes,
    )..where((q) => q.id.equals(quoteId))).getSingle();

    final allowed = QuoteStatus.transitions[quote.status] ?? const [];
    if (!allowed.contains(status)) {
      throw InvalidQuoteTransitionException(quote.status, status);
    }

    await (db.update(db.salesQuotes)..where((q) => q.id.equals(quoteId))).write(
      SalesQuotesCompanion(status: Value(status)),
    );
    await db.writeAudit(
      ctx,
      entityType: 'sales_quote',
      entityId: quoteId,
      action: 'STATUS_CHANGE',
      summary: 'Teklif durumu: $status',
    );
  });

  /// **Tek butonla satışa dönüştür** (SPEC §15).
  ///
  /// Teklif satırları satışa kopyalanır; stok ve maliyet normal satış
  /// kurallarıyla işlenir. Teklif silinmez, `CONVERTED` olur ve satışa
  /// referans verir.
  Future<String> convertToSale({
    required String quoteId,
    required OperationContext ctx,
    DateTime? docDate,
    DateTime? dueDate,
    bool riskLimitApproved = false,
  }) async {
    final quote = await (db.select(
      db.salesQuotes,
    )..where((q) => q.id.equals(quoteId))).getSingle();

    if (quote.convertedSaleId != null) {
      throw QuoteAlreadyConvertedException(quoteId, quote.convertedSaleId!);
    }

    final items =
        await (db.select(db.salesQuoteItems)
              ..where((i) => i.salesQuoteId.equals(quoteId))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNo)]))
            .get();

    final saleId = await SaleRepository(db).create(
      SaleInput(
        customerId: quote.customerId,
        docDate: docDate ?? DateTime.now(),
        dueDate: dueDate,
        priceMode: quote.priceMode,
        salesQuoteId: quoteId,
        riskLimitApproved: riskLimitApproved,
        lines: [
          for (final item in items)
            SaleLineInput(
              variantId: item.variantId,
              pieces: item.pieces,
              volume: item.volume,
              listPriceM3: item.listPriceM3,
              unitPriceM3: item.unitPriceM3,
              vatRate: item.vatRate,
              discountRate: item.discountRate,
            ),
        ],
      ),
      ctx,
    );

    // Satış başarılıysa teklifi işaretle.
    await (db.update(db.salesQuotes)..where((q) => q.id.equals(quoteId))).write(
      SalesQuotesCompanion(
        status: const Value(QuoteStatus.converted),
        convertedSaleId: Value(saleId),
      ),
    );

    return saleId;
  }

  /// Geçerlilik tarihi geçmiş teklifleri işaretler.
  Future<int> expireOverdue({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return (db.update(db.salesQuotes)..where(
          (q) =>
              q.validUntil.isSmallerThanValue(reference) &
              q.status.isIn([QuoteStatus.draft, QuoteStatus.sent]),
        ))
        .write(const SalesQuotesCompanion(status: Value(QuoteStatus.expired)));
  }
}
