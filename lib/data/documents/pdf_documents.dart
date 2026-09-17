import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';

/// Belgede görünecek firma bilgileri (Ayarlar'dan).
final class CompanyInfo {
  final String name;
  final String? address;
  final String? phone;
  final String? taxOffice;
  final String? taxNumber;
  final Uint8List? logo;

  const CompanyInfo({
    required this.name,
    this.address,
    this.phone,
    this.taxOffice,
    this.taxNumber,
    this.logo,
  });
}

/// Belge satırı.
final class DocumentLine {
  final String description;
  final int pieces;
  final Volume volume;
  final UnitPrice unitPrice;
  final Money net;
  final Money vat;
  final Money gross;

  const DocumentLine({
    required this.description,
    required this.pieces,
    required this.volume,
    required this.unitPrice,
    required this.net,
    required this.vat,
    required this.gross,
  });
}

/// PDF belgeleri: teklif, satış/sevk fişi, cari ekstre, kesim emri
/// (BRIEF §5). WhatsApp'a doğrudan paylaşılır.
///
/// **Türkçe karakter desteği için gömülü font şart.** PDF'in varsayılan
/// Helvetica'sı ş, ğ, İ, ı karakterlerini basmaz. Font `assets/fonts/`
/// altından yüklenir; yoksa belge yine üretilir ama uyarı düşülür.
abstract final class PdfDocuments {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Türkçe karakterli fontu yükler. `main()` başında bir kez çağrılır.
  static void useFonts({required pw.Font regular, required pw.Font bold}) {
    _regular = regular;
    _bold = bold;
  }

  /// Gömülü Noto Sans'ı varlıklardan yükler (BRIEF §2).
  ///
  /// Font yüklenmezse belgeler yine üretilir ama ş, ğ, İ, ı karakterleri
  /// basılamaz — bu yüzden `main()` içinde çağrılması şarttır.
  static Future<void> loadBundledFonts(
    Future<ByteData> Function(String) loadAsset,
  ) async {
    if (_regular != null) return;
    final regular = await loadAsset('assets/fonts/NotoSans-Regular.ttf');
    final bold = await loadAsset('assets/fonts/NotoSans-Bold.ttf');
    useFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }

  static bool get hasTurkishFont => _regular != null;

  static pw.ThemeData _theme() => _regular == null
      ? pw.ThemeData.base()
      : pw.ThemeData.withFont(base: _regular!, bold: _bold ?? _regular!);

  /// Satış / sevk fişi.
  static Future<Uint8List> salesReceipt({
    required CompanyInfo company,
    required String docNo,
    required DateTime docDate,
    required String customerTitle,
    required List<DocumentLine> lines,
    required Money subtotalNet,
    required Money vatTotal,
    required Money grandTotal,
    DateTime? dueDate,
    String? note,
  }) => _build(
    title: 'SATIŞ FİŞİ',
    company: company,
    docNo: docNo,
    docDate: docDate,
    counterpartyLabel: 'Müşteri',
    counterpartyName: customerTitle,
    dueDate: dueDate,
    lines: lines,
    subtotalNet: subtotalNet,
    vatTotal: vatTotal,
    grandTotal: grandTotal,
    note: note,
  );

  /// Fiyat teklifi.
  static Future<Uint8List> quote({
    required CompanyInfo company,
    required String docNo,
    required DateTime docDate,
    required String customerTitle,
    required List<DocumentLine> lines,
    required Money subtotalNet,
    required Money vatTotal,
    required Money grandTotal,
    DateTime? validUntil,
    String? note,
  }) => _build(
    title: 'FİYAT TEKLİFİ',
    company: company,
    docNo: docNo,
    docDate: docDate,
    counterpartyLabel: 'Müşteri',
    counterpartyName: customerTitle,
    dueDate: validUntil,
    dueDateLabel: 'Geçerlilik',
    lines: lines,
    subtotalNet: subtotalNet,
    vatTotal: vatTotal,
    grandTotal: grandTotal,
    note: note,
  );

  /// Kesim emri — kesimhaneye gönderilen ölçü listesi.
  /// Fiyat içermez; kesimhanenin görmesi gereken yalnızca ölçü ve adettir.
  static Future<Uint8List> cuttingOrder({
    required CompanyInfo company,
    required String docNo,
    required DateTime sentDate,
    required String cutterTitle,
    required List<({String description, int pieces})> sources,
    required List<({String description, int pieces})> targets,
    String? note,
  }) async {
    final doc = pw.Document(theme: _theme());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(company, 'KESİM EMRİ', docNo, sentDate),
            pw.SizedBox(height: 16),
            pw.Text(
              'Kesimhane: $cutterTitle',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'GÖNDERİLEN',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _simpleTable(sources),
            pw.SizedBox(height: 20),
            pw.Text(
              'KESİLECEK ÖLÇÜLER',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _simpleTable(targets),
            if (note != null) ...[
              pw.SizedBox(height: 20),
              pw.Text('Not: $note'),
            ],
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Cari ekstre.
  static Future<Uint8List> customerStatement({
    required CompanyInfo company,
    required String customerTitle,
    required DateTime asOf,
    required List<({DateTime date, String description, Money amount})> entries,
    required Money balance,
  }) async {
    final doc = pw.Document(theme: _theme());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(company, 'CARİ EKSTRE', '', asOf),
          pw.SizedBox(height: 16),
          pw.Text(
            customerTitle,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Tarih', 'Açıklama', 'Tutar'],
            cellAlignments: const {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
            },
            data: [
              for (final e in entries)
                [_date(e.date), e.description, _money(e.amount)],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'BAKİYE: ${_money(balance)} TL '
              '${balance.isPositive ? "BORÇ" : "ALACAK"}',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ------------------------------------------------------------- yardımcı

  static Future<Uint8List> _build({
    required String title,
    required CompanyInfo company,
    required String docNo,
    required DateTime docDate,
    required String counterpartyLabel,
    required String counterpartyName,
    required List<DocumentLine> lines,
    required Money subtotalNet,
    required Money vatTotal,
    required Money grandTotal,
    DateTime? dueDate,
    String dueDateLabel = 'Vade',
    String? note,
  }) async {
    final doc = pw.Document(theme: _theme());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(company, title, docNo, docDate),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '$counterpartyLabel: $counterpartyName',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (dueDate != null) pw.Text('$dueDateLabel: ${_date(dueDate)}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Açıklama',
              'Adet',
              'm³',
              'TL/m³',
              'Tutar',
              'KDV',
              'Toplam',
            ],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              for (var i = 1; i <= 6; i++) i: pw.Alignment.centerRight,
            },
            data: [
              for (final line in lines)
                [
                  line.description,
                  '${line.pieces}',
                  _volume(line.volume),
                  _price(line.unitPrice),
                  _money(line.net),
                  _money(line.vat),
                  _money(line.gross),
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('KDV Hariç: ${_money(subtotalNet)} TL'),
                pw.Text('KDV: ${_money(vatTotal)} TL'),
                pw.SizedBox(height: 4),
                pw.Text(
                  'GENEL TOPLAM: ${_money(grandTotal)} TL',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (note != null) ...[pw.SizedBox(height: 20), pw.Text('Not: $note')],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(
    CompanyInfo company,
    String title,
    String docNo,
    DateTime date,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              company.name,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            if (company.address != null) pw.Text(company.address!),
            if (company.phone != null) pw.Text('Tel: ${company.phone}'),
            if (company.taxOffice != null && company.taxNumber != null)
              pw.Text('${company.taxOffice} V.D. ${company.taxNumber}'),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            if (docNo.isNotEmpty) pw.Text(docNo),
            pw.Text(_date(date)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _simpleTable(
    List<({String description, int pieces})> rows,
  ) => pw.TableHelper.fromTextArray(
    headers: const ['Ölçü', 'Adet'],
    cellAlignments: const {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerRight,
    },
    data: [
      for (final r in rows) [r.description, '${r.pieces}'],
    ],
  );

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  static String _money(Money m) =>
      _group(m.tl.toStringAsFixed(2)); // ignore: allowed-double
  static String _price(UnitPrice p) =>
      _group(p.perM3.toStringAsFixed(2)); // ignore: allowed-double
  static String _volume(Volume v) =>
      _group(v.m3.toStringAsFixed(6)) // ignore: allowed-double
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r',$'), '');

  /// `1234.56` → `1.234,56`
  static String _group(String value) {
    final negative = value.startsWith('-');
    final body = negative ? value.substring(1) : value;
    final parts = body.split('.');
    final digits = parts[0];

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final result = parts.length > 1
        ? '${buffer.toString()},${parts[1]}'
        : buffer.toString();
    return negative ? '-$result' : result;
  }
}
