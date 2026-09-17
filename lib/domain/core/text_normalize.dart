/// Türkçe arama normalizasyonu (BRIEF §6, DECISIONS D-18).
///
/// SQLite'ın `LIKE`'ı Türkçe harfleri doğru katlamaz; bu yüzden aranabilir her
/// ad kolonunun yanında normalize edilmiş bir kopya tutulur ve arama onda yapılır.
/// Böylece "sunger" → "Sünger", "ISIK" → "ışık" bulur.
library;

const _map = {
  'İ': 'i',
  'I': 'i',
  'ı': 'i',
  'i': 'i',
  'Ş': 's',
  'ş': 's',
  'Ğ': 'g',
  'ğ': 'g',
  'Ü': 'u',
  'ü': 'u',
  'Ö': 'o',
  'ö': 'o',
  'Ç': 'c',
  'ç': 'c',
};

/// Metni aranabilir biçime çevirir: küçük harf + Türkçe karakter katlama.
String normalizeTurkish(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_map[ch] ?? ch.toLowerCase());
  }
  return buffer.toString();
}
