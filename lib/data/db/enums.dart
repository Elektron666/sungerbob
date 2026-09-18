/// Veritabanında TEXT olarak saklanan enum'lar (DECISIONS D-17).
/// Yedek dosyası elle incelenebilir kalsın diye kod yerine okunabilir metin.
library;

abstract final class LocationCode {
  static const mainWarehouse = 'ANA_DEPO';
  static const cutting = 'KESIMDE';
  static const all = [mainWarehouse, cutting];
}

/// Ürünün satış ve stok birimi.
///
/// Sünger m³ ile döner; **ince malzeme** (çivi, yapıştırıcı, zikzak yay,
/// tela) adet, kilo, kutu, litre veya metre ile. Birim ürün kartında
/// sabittir ve ilk stok hareketinden sonra değiştirilemez — geçmiş
/// hareketlerin birimi değişirse maliyet anlamını yitirir.
abstract final class ProductUnit {
  /// Metreküp — sünger. Varsayılan.
  static const m3 = 'M3';
  static const piece = 'ADET';
  static const kilogram = 'KG';
  static const box = 'KUTU';
  static const litre = 'LITRE';
  static const metre = 'METRE';

  static const all = [m3, piece, kilogram, box, litre, metre];

  /// Ölçü (en/boy/kalınlık) yalnızca m³ ürünlerde sorulur.
  static bool hasDimensions(String unit) => unit == m3;

  /// Ekranlarda gösterilen kısa ad.
  static String label(String unit) => switch (unit) {
    m3 => 'm³',
    piece => 'adet',
    kilogram => 'kg',
    box => 'kutu',
    litre => 'lt',
    metre => 'm',
    _ => unit.toLowerCase(),
  };

  /// "TL/m³", "TL/adet" gibi birim fiyat etiketi.
  static String priceLabel(String unit) => 'TL/${label(unit)}';
}

abstract final class VariantKind {
  static const plate = 'PLAKA';
  static const block = 'BLOK';
  static const all = [plate, block];
}

abstract final class SupplierType {
  static const factory = 'FABRIKA';
  static const cutter = 'KESIMHANE';
  static const carrier = 'NAKLIYE';
  static const other = 'DIGER';
  static const all = [factory, cutter, carrier, other];
}

abstract final class CostingMethod {
  static const fifo = 'FIFO';
  static const weightedAverage = 'WEIGHTED_AVERAGE';
  static const all = [fifo, weightedAverage];
}

abstract final class MovementType {
  static const purchaseIn = 'PURCHASE_IN';
  static const saleOut = 'SALE_OUT';
  static const saleReturnIn = 'SALE_RETURN_IN';
  static const purchaseReturnOut = 'PURCHASE_RETURN_OUT';
  static const countIn = 'COUNT_IN';
  static const countOut = 'COUNT_OUT';
  static const wasteOut = 'WASTE_OUT';
  static const transferOut = 'TRANSFER_OUT';
  static const transferIn = 'TRANSFER_IN';
  static const cuttingOut = 'CUTTING_OUT';
  static const cuttingIn = 'CUTTING_IN';
  static const openingIn = 'OPENING_IN';
  static const reversal = 'REVERSAL';

  static const all = [
    purchaseIn,
    saleOut,
    saleReturnIn,
    purchaseReturnOut,
    countIn,
    countOut,
    wasteOut,
    transferOut,
    transferIn,
    cuttingOut,
    cuttingIn,
    openingIn,
    reversal,
  ];

  /// Stoğa giren hareketler (pozitif adet/hacim).
  static const inbound = [
    purchaseIn,
    saleReturnIn,
    countIn,
    transferIn,
    cuttingIn,
    openingIn,
  ];

  /// Stoktan çıkan hareketler (negatif adet/hacim).
  static const outbound = [
    saleOut,
    purchaseReturnOut,
    countOut,
    wasteOut,
    transferOut,
    cuttingOut,
  ];
}

abstract final class DocStatus {
  static const active = 'ACTIVE';
  static const cancelled = 'CANCELLED';
  static const all = [active, cancelled];
}

abstract final class QuoteStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const accepted = 'ACCEPTED';
  static const rejected = 'REJECTED';
  static const expired = 'EXPIRED';
  static const converted = 'CONVERTED';
  static const all = [draft, sent, accepted, rejected, expired, converted];

  /// Elle yapılabilecek durum geçişleri (SPEC §15).
  ///
  /// `CONVERTED` bu haritada yok: satışa çevirme ayrı bir iş işlemidir,
  /// stok ve cari hareketi üretir; durum elle işaretlenerek atlanamaz.
  /// `EXPIRED` de yok — geçerlilik tarihi geçince sistem kendisi koyar.
  static const transitions = <String, List<String>>{
    draft: [sent],
    sent: [accepted, rejected],
    accepted: [],
    rejected: [],
    expired: [],
    converted: [],
  };

  /// Ekranda görünen Türkçe ad.
  static String label(String status) => switch (status) {
    draft => 'Taslak',
    sent => 'Gönderildi',
    accepted => 'Kabul edildi',
    rejected => 'Reddedildi',
    expired => 'Süresi doldu',
    converted => 'Satışa çevrildi',
    _ => status,
  };
}

abstract final class CuttingStatus {
  static const preparing = 'PREPARING';
  static const atCutter = 'AT_CUTTER';
  static const partial = 'PARTIAL';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const all = [preparing, atCutter, partial, completed, cancelled];
}

abstract final class InstrumentKind {
  static const check = 'CHECK';
  static const note = 'NOTE';
  static const all = [check, note];
}

abstract final class InstrumentDirection {
  static const incoming = 'IN';
  static const outgoing = 'OUT';
  static const all = [incoming, outgoing];
}

abstract final class InstrumentStatus {
  // Alınan
  static const portfolio = 'PORTFOLIO';
  static const atBank = 'AT_BANK';
  static const collected = 'COLLECTED';
  static const endorsed = 'ENDORSED';
  static const bounced = 'BOUNCED';
  static const returned = 'RETURNED';
  // Verilen
  static const issued = 'ISSUED';
  static const paid = 'PAID';
  static const takenBack = 'TAKEN_BACK';

  static const all = [
    portfolio,
    atBank,
    collected,
    endorsed,
    bounced,
    returned,
    issued,
    paid,
    takenBack,
  ];

  /// Alınan evrak için geçerli durum geçişleri (ERD §9).
  static const incomingTransitions = <String, List<String>>{
    portfolio: [atBank, endorsed, returned, bounced],
    atBank: [collected, bounced],
    endorsed: [bounced],
    collected: [],
    returned: [],
    bounced: [],
  };

  /// Verilen evrak için geçerli durum geçişleri.
  static const outgoingTransitions = <String, List<String>>{
    issued: [paid, takenBack],
    paid: [],
    takenBack: [],
  };

  /// Portföyde sayılan durumlar.
  static const inPortfolio = [portfolio, atBank];
}

abstract final class PaymentMethod {
  static const cash = 'CASH';
  static const transfer = 'TRANSFER';
  static const card = 'CARD';
  static const check = 'CHECK';
  static const note = 'NOTE';
  static const all = [cash, transfer, card, check, note];

  /// Kasa/banka hesabı gerektiren yöntemler.
  static const needsAccount = [cash, transfer, card];

  /// Evrak kaydı üreten yöntemler.
  static const needsInstrument = [check, note];
}

abstract final class CashAccountType {
  static const cash = 'KASA';
  static const bank = 'BANKA';
  static const pos = 'POS';
  static const all = [cash, bank, pos];
}

abstract final class RoundingRule {
  static const none = 'NONE';
  static const nearest1 = 'NEAREST_1';
  static const nearest5 = 'NEAREST_5';
  static const nearest10 = 'NEAREST_10';
  static const all = [none, nearest1, nearest5, nearest10];
}

/// Alış masrafı türü (nakliye, hamaliye, diğer).
///
/// Elle yazılmış `'NAKLIYE'` metinleriyle dolaşıyordu; enum'a alındı ki
/// şema kısıtı ile kod aynı listeden beslensin (D-23).
abstract final class PurchaseExpenseKind {
  static const freight = 'NAKLIYE';
  static const handling = 'HAMALIYE';
  static const other = 'DIGER';
  static const all = [freight, handling, other];

  static String label(String kind) => switch (kind) {
    freight => 'Nakliye',
    handling => 'Hamaliye',
    _ => 'Diğer',
  };
}

abstract final class AllocationKey {
  static const volume = 'VOLUME';
  static const amount = 'AMOUNT';
  static const all = [volume, amount];
}

abstract final class LedgerDocType {
  static const sale = 'SALE';
  static const saleReturn = 'SALE_RETURN';
  static const collection = 'COLLECTION';
  static const instrumentIn = 'INSTRUMENT_IN';
  static const instrumentBounced = 'INSTRUMENT_BOUNCED';
  static const purchase = 'PURCHASE';
  static const purchaseReturn = 'PURCHASE_RETURN';
  static const payment = 'PAYMENT';
  static const instrumentOut = 'INSTRUMENT_OUT';
  static const instrumentEndorsed = 'INSTRUMENT_ENDORSED';
  static const cuttingFee = 'CUTTING_FEE';
  static const opening = 'OPENING';
  static const adjustment = 'ADJUSTMENT';
  static const reversal = 'REVERSAL';

  static const customerAll = [
    sale,
    saleReturn,
    collection,
    instrumentIn,
    instrumentBounced,
    opening,
    adjustment,
    reversal,
  ];
  static const supplierAll = [
    purchase,
    purchaseReturn,
    payment,
    instrumentOut,
    instrumentEndorsed,
    cuttingFee,
    opening,
    adjustment,
    reversal,
  ];
}

abstract final class AccountMovementType {
  static const collection = 'COLLECTION';
  static const payment = 'PAYMENT';
  static const transferIn = 'TRANSFER_IN';
  static const transferOut = 'TRANSFER_OUT';
  static const expense = 'EXPENSE';
  static const opening = 'OPENING';
  static const instrumentCollected = 'INSTRUMENT_COLLECTED';
  static const instrumentPaid = 'INSTRUMENT_PAID';
  static const reversal = 'REVERSAL';
  static const all = [
    collection,
    payment,
    transferIn,
    transferOut,
    expense,
    opening,
    instrumentCollected,
    instrumentPaid,
    reversal,
  ];
}

abstract final class BatchSourceType {
  static const purchase = 'PURCHASE';
  static const opening = 'OPENING';
  static const cutting = 'CUTTING';
  static const saleReturn = 'SALE_RETURN';
  static const transfer = 'TRANSFER';
  static const all = [purchase, opening, cutting, saleReturn, transfer];
}

abstract final class DocPrefix {
  static const sale = 'STS';
  static const purchase = 'ALS';
  static const collection = 'THS';
  static const quote = 'TKL';
  static const returnDoc = 'IAD';
  static const cutting = 'KSM';
  static const payment = 'ODM';
  static const stockCount = 'SYM';
  static const waste = 'FIR';
  static const transfer = 'VRM';
  static const expense = 'GDR';
  static const all = [
    sale,
    purchase,
    collection,
    quote,
    returnDoc,
    cutting,
    payment,
    stockCount,
    waste,
    transfer,
    expense,
  ];
}

abstract final class WasteReason {
  static const damaged = 'HASARLI';
  static const cuttingWaste = 'KESIM_FIRESI';
  static const humidity = 'NEM';
  static const other = 'DIGER';
  static const all = [damaged, cuttingWaste, humidity, other];
}

abstract final class BackupKind {
  static const backup = 'BACKUP';
  static const restore = 'RESTORE';
  static const all = [backup, restore];
}

abstract final class BackupTrigger {
  static const manual = 'MANUAL';
  static const autoDaily = 'AUTO_DAILY';
  static const autoStartup = 'AUTO_STARTUP';
  static const preRisk = 'PRE_RISK';
  static const preMigration = 'PRE_MIGRATION';
  static const all = [manual, autoDaily, autoStartup, preRisk, preMigration];
}

abstract final class BackupDestination {
  static const local = 'LOCAL';
  static const drive = 'DRIVE';
  static const share = 'SHARE';
  static const all = [local, drive, share];
}
