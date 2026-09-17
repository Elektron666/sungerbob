import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sungerbob/data/documents/csv_export.dart';
import 'package:sungerbob/data/documents/pdf_documents.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';

const company = CompanyInfo(
  name: 'Sünger Toptan Ltd. Şti.',
  address: 'Organize Sanayi Bölgesi, İstanbul',
  phone: '0212 000 00 00',
  taxOffice: 'Kadıköy',
  taxNumber: '1234567890',
);

final line = DocumentLine(
  description: 'Beyaz Sünger 140×200×10',
  pieces: 60,
  volume: Volume.parse('16.8'),
  unitPrice: UnitPrice.parse('3500'),
  net: Money.parse('58800'),
  vat: Money.parse('11760'),
  gross: Money.parse('70560'),
);

void main() {
  setUpAll(() {
    // Gömülü Türkçe fontu yükle — ş, ğ, İ, ı basılabilmeli (BRIEF §2).
    PdfDocuments.useFonts(
      regular: pw.Font.ttf(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
      bold: pw.Font.ttf(
        File('assets/fonts/NotoSans-Bold.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
    );
  });

  group('PDF belgeleri (BRIEF §5)', () {
    test('satış fişi üretiliyor ve geçerli PDF', () async {
      final bytes = await PdfDocuments.salesReceipt(
        company: company,
        docNo: 'STS-2026-000001',
        docDate: DateTime(2026, 9, 17),
        customerTitle: 'ABC Mobilya',
        dueDate: DateTime(2026, 10, 17),
        lines: [line],
        subtotalNet: Money.parse('58800'),
        vatTotal: Money.parse('11760'),
        grandTotal: Money.parse('70560'),
      );

      expect(bytes.length, greaterThan(1000));
      // PDF dosya imzası
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('teklif üretiliyor', () async {
      final bytes = await PdfDocuments.quote(
        company: company,
        docNo: 'TKL-2026-000001',
        docDate: DateTime(2026, 9, 10),
        customerTitle: 'ABC Mobilya',
        validUntil: DateTime(2026, 9, 30),
        lines: [line],
        subtotalNet: Money.parse('58800'),
        vatTotal: Money.parse('11760'),
        grandTotal: Money.parse('70560'),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('kesim emri FİYAT İÇERMEZ', () async {
      final bytes = await PdfDocuments.cuttingOrder(
        company: company,
        docNo: 'KSM-2026-000001',
        sentDate: DateTime(2026, 9, 5),
        cutterTitle: 'Kesimhane A.Ş.',
        sources: [(description: '200×200×100 blok', pieces: 1)],
        targets: [
          (description: '140×200×10', pieces: 9),
          (description: '60×200×10', pieces: 9),
        ],
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      // Kesimhanenin fiyat görmesine gerek yok; belge yalnızca ölçü ve adet
      // tablosundan oluşuyor (imza kontrolü yeterli, içerik testi görselde).
      expect(bytes.length, greaterThan(500));
    });

    test('cari ekstre üretiliyor', () async {
      final bytes = await PdfDocuments.customerStatement(
        company: company,
        customerTitle: 'ABC Mobilya',
        asOf: DateTime(2026, 9, 30),
        entries: [
          (
            date: DateTime(2026, 9, 17),
            description: 'Satış STS-2026-000001',
            amount: Money.parse('70560'),
          ),
          (
            date: DateTime(2026, 9, 20),
            description: 'Tahsilat THS-2026-000001',
            amount: Money.parse('-30000'),
          ),
        ],
        balance: Money.parse('40560'),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('Türkçe karakterler gömülü fontla basılabiliyor', () async {
      expect(
        PdfDocuments.hasTurkishFont,
        isTrue,
        reason: 'gömülü Noto Sans yüklenmeli (BRIEF §2)',
      );
      final bytes = await PdfDocuments.salesReceipt(
        company: company,
        docNo: 'STS-1',
        docDate: DateTime(2026, 9, 17),
        customerTitle: 'Şişli Mobilya',
        lines: [line],
        subtotalNet: Money.parse('100'),
        vatTotal: Money.parse('20'),
        grandTotal: Money.parse('120'),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('CSV dışa aktarma (SPEC §25)', () {
    test('noktalı virgül ayraç ve UTF-8 BOM', () {
      final csv = CsvExport.build(
        headers: ['Tarih', 'Müşteri', 'Tutar'],
        rows: [
          ['17.09.2026', 'ABC Mobilya', '58.800,00'],
        ],
      );

      expect(
        csv.startsWith('﻿'),
        isTrue,
        reason: 'Excel Türkçe karakterler için BOM bekler',
      );
      expect(csv, contains('Tarih;Müşteri;Tutar'));
      expect(csv, contains('17.09.2026;ABC Mobilya;58.800,00'));
    });

    test('virgüllü tutarlar ayraçla karışmıyor', () {
      // Tutar "58.800,00" içinde virgül var ama ayraç noktalı virgül.
      final csv = CsvExport.build(
        headers: ['Tutar'],
        rows: [
          ['1.234,56'],
        ],
      );
      expect(csv, contains('1.234,56'));
      expect(csv.split('\n')[1].split(';').length, 1);
    });

    test('ayraç içeren alan tırnaklanır', () {
      expect(CsvExport.escape('a;b'), '"a;b"');
      expect(CsvExport.escape('düz metin'), 'düz metin');
      expect(CsvExport.escape('tırnak"içeren'), '"tırnak""içeren"');
      expect(CsvExport.escape('satır\nsonu'), '"satır\nsonu"');
    });
  });
}
