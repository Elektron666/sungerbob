import 'package:drift/drift.dart';

import '../../domain/core/money.dart';
import '../../domain/core/quantity.dart';
import '../../domain/service/vat.dart';

/// Ölçekli tamsayı ↔ domain tipi dönüştürücüleri (ARCHITECTURE §3).
///
/// Veritabanında ondalık yoktur; her değer `INTEGER` olarak durur.

class MoneyConverter extends TypeConverter<Money, int> {
  const MoneyConverter();
  @override
  Money fromSql(int fromDb) => Money.fromStored(fromDb);
  @override
  int toSql(Money value) => value.stored;
}

class VolumeConverter extends TypeConverter<Volume, int> {
  const VolumeConverter();
  @override
  Volume fromSql(int fromDb) => Volume.fromStored(fromDb);
  @override
  int toSql(Volume value) => value.stored;
}

class UnitPriceConverter extends TypeConverter<UnitPrice, int> {
  const UnitPriceConverter();
  @override
  UnitPrice fromSql(int fromDb) => UnitPrice.fromStored(fromDb);
  @override
  int toSql(UnitPrice value) => value.stored;
}

class DimensionConverter extends TypeConverter<Dimension, int> {
  const DimensionConverter();
  @override
  Dimension fromSql(int fromDb) => Dimension.fromStored(fromDb);
  @override
  int toSql(Dimension value) => value.stored;
}

class RateConverter extends TypeConverter<Rate, int> {
  const RateConverter();
  @override
  Rate fromSql(int fromDb) => Rate.fromStored(fromDb);
  @override
  int toSql(Rate value) => value.stored;
}

class PriceModeConverter extends TypeConverter<PriceMode, String> {
  const PriceModeConverter();
  @override
  PriceMode fromSql(String fromDb) => PriceMode.fromCode(fromDb);
  @override
  String toSql(PriceMode value) => value.code;
}
