import 'package:decimal/decimal.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/core/scales.dart';

/// Türkçe yerelleştirme: tarih `dd.MM.yyyy`, sayı `1.234,56` (BRIEF §2).
///
/// Girişlerde **hem virgül hem nokta** ondalık ayırıcı kabul edilir; sahada
/// klavyeye göre ikisi de kullanılıyor.
abstract final class TrFormat {
  static const locale = 'tr_TR';
  static const emptyPlaceholder = '—';

  static bool _initialized = false;

  /// Tarih biçimlendirmesi için yerel veriyi yükler. `main()` başında ve
  /// testlerde bir kez çağrılır; ikinci çağrı ücretsizdir.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await initializeDateFormatting(locale);
    Intl.defaultLocale = locale;
    _initialized = true;
  }

  static final _money = NumberFormat('#,##0.00', locale);
  static final _integer = NumberFormat('#,##0', locale);
  // Desenler tamamen sayısal olduğu için yerel veri yüklenmeden de doğru
  // çalışır; ay adı gerektiren biçimler ensureInitialized() ister.
  static final _date = DateFormat('dd.MM.yyyy');
  static final _dateTime = DateFormat('dd.MM.yyyy HH:mm');
  static final _time = DateFormat('HH:mm');

  /// "Eylül 2026" — rapor başlıkları için; ensureInitialized() gerektirir.
  static String monthYear(DateTime value) =>
      DateFormat('MMMM yyyy', locale).format(value);

  // ------------------------------------------------------------ gösterim

  static String money(Money value) => _money.format(value.tl.toDouble());

  static String moneyWithCurrency(Money value) => '${money(value)} TL';

  /// m³ — altı haneye kadar, sondaki gereksiz sıfırlar atılır.
  static String volume(Volume value) =>
      '${_trimZeros(value.m3, Scales.volume)} m³';

  static String volumeBare(Volume value) => _trimZeros(value.m3, Scales.volume);

  static String unitPrice(UnitPrice value) =>
      '${_money.format(value.perM3.toDouble())} TL/m³';

  static String platePrice(UnitPrice value) =>
      '${_money.format(value.perM3.toDouble())} TL/plaka';

  static String rate(Rate value) =>
      '%${_trimZeros(value.percent, Scales.rate)}';

  /// Hesaplanmış yüzde (kâr marjı gibi). null ise tanımsız.
  static String percent(Decimal? value) {
    if (value == null) return emptyPlaceholder;
    return '%${_money.format(value.toDouble())}';
  }

  static String pieces(int value) => '${_integer.format(value)} adet';

  static String count(int value) => _integer.format(value);

  static String dimensions(Dimension w, Dimension h, Dimension t) =>
      '${_trimZeros(w.cm, Scales.dimension)}×'
      '${_trimZeros(h.cm, Scales.dimension)}×'
      '${_trimZeros(t.cm, Scales.dimension)}';

  static String date(DateTime? value) =>
      value == null ? emptyPlaceholder : _date.format(value);

  static String dateTime(DateTime? value) =>
      value == null ? emptyPlaceholder : _dateTime.format(value);

  static String time(DateTime? value) =>
      value == null ? emptyPlaceholder : _time.format(value);

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${_money.format(bytes / 1024)} KB';
    }
    return '${_money.format(bytes / (1024 * 1024))} MB';
  }

  /// "bugün 20:00", "dün 14:32", "17.09.2026 14:32"
  static String relativeDateTime(DateTime? value, {DateTime? now}) {
    if (value == null) return 'hiç';
    final reference = now ?? DateTime.now();
    final days = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).difference(DateTime(value.year, value.month, value.day)).inDays;
    return switch (days) {
      0 => 'bugün ${_time.format(value)}',
      1 => 'dün ${_time.format(value)}',
      _ => _dateTime.format(value),
    };
  }

  // -------------------------------------------------------------- giriş

  /// Kullanıcı girişini `Decimal`'e çevirir. Hem `3,5` hem `3.5` çalışır;
  /// binlik ayracı, boşluk ve "TL" eki temizlenir. Geçersizse null.
  static Decimal? parseDecimal(String? input) {
    if (input == null) return null;

    var text = input.trim().replaceAll(
      RegExp(r'\s|tl|m³|₺', caseSensitive: false),
      '',
    );
    if (text.isEmpty) return null;

    final commas = ','.allMatches(text).length;
    final dots = '.'.allMatches(text).length;

    if (commas > 0 && dots > 0) {
      // "1.234,56" → sonda gelen ondalık ayırıcıdır, diğeri binliktir.
      final decimalSeparator = text.lastIndexOf(',') > text.lastIndexOf('.')
          ? ','
          : '.';
      final groupSeparator = decimalSeparator == ',' ? '.' : ',';
      if (!_hasValidGrouping(text, groupSeparator, decimalSeparator)) {
        return null;
      }
      text = text
          .replaceAll(groupSeparator, '')
          .replaceAll(decimalSeparator, '.');
    } else if (commas > 1) {
      // "1,234,567" ancak düzgün gruplanmışsa binlik ayracıdır;
      // "1,2,3" gibi bozuk girişler sessizce kabul edilmemeli.
      if (!_hasValidGrouping(text, ',', null)) return null;
      text = text.replaceAll(',', '');
    } else if (dots > 1) {
      if (!_hasValidGrouping(text, '.', null)) return null;
      text = text.replaceAll('.', '');
    } else if (commas == 1) {
      text = text.replaceAll(',', '.');
    }

    return Decimal.tryParse(text);
  }

  static Money? parseMoney(String? input) {
    final value = parseDecimal(input);
    return value == null ? null : Money.fromDecimal(value);
  }

  static Volume? parseVolume(String? input) {
    final value = parseDecimal(input);
    return value == null ? null : Volume.fromDecimal(value);
  }

  static UnitPrice? parseUnitPrice(String? input) {
    final value = parseDecimal(input);
    return value == null ? null : UnitPrice.fromDecimal(value);
  }

  static Dimension? parseDimension(String? input) {
    final value = parseDecimal(input);
    return value == null
        ? null
        : Dimension((value * Decimal.fromInt(100)).toBigInt().toInt());
  }

  static Rate? parseRate(String? input) {
    final value = parseDecimal(input);
    return value == null
        ? null
        : Rate((value * Decimal.fromInt(100)).toBigInt().toInt());
  }

  static int? parsePieces(String? input) =>
      parseDecimal(input)?.toBigInt().toInt();

  // ------------------------------------------------------------ yardımcı

  /// Binlik gruplaması geçerli mi? `1.234.567` evet, `1.2.3` hayır.
  static bool _hasValidGrouping(
    String text,
    String groupSeparator,
    String? decimalSeparator,
  ) {
    final integerPart = decimalSeparator == null
        ? text
        : text.substring(0, text.lastIndexOf(decimalSeparator));
    final group = RegExp.escape(groupSeparator);
    return RegExp('^-?\\d{1,3}($group\\d{3})+\$').hasMatch(integerPart);
  }

  /// Sondaki gereksiz sıfırları atar: 14,000000 → "14" · 0,280000 → "0,28"
  static String _trimZeros(Decimal value, int maxDecimals) {
    var text = value.toStringAsFixed(maxDecimals); // ignore: allowed-double
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      text = text.replaceAll(RegExp(r'\.$'), '');
    }
    return text.replaceAll('.', ',');
  }
}
