/// CSV dışa aktarma (SPEC §25).
///
/// Excel doğrudan açar. `excel` paketi yerine CSV seçildi çünkü o paket
/// `xml` ve `archive` sürümlerinde `pdf` ve yedekleme ile çakışıyor
/// (DECISIONS SK-10). PDF, BRIEF §5'te açıkça isteniyor ve öncelikli.
abstract final class CsvExport {
  /// Türkçe Excel ayraç olarak **noktalı virgül** bekler; virgül ondalık
  /// ayırıcı olduğu için alan ayracı olamaz.
  static const separator = ';';

  /// UTF-8 BOM: Excel'in Türkçe karakterleri doğru göstermesi için şart.
  static const bom = '﻿';

  static String build({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final buffer = StringBuffer(bom);
    buffer.writeln(headers.map(escape).join(separator));
    for (final row in rows) {
      buffer.writeln(row.map(escape).join(separator));
    }
    return buffer.toString();
  }

  /// Ayraç, tırnak veya satır sonu içeren alanları tırnaklar.
  static String escape(String value) {
    final needsQuotes =
        value.contains(separator) ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
