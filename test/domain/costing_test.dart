import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sungerbob/domain/costing/costing_engine.dart';
import 'package:sungerbob/domain/costing/batch_view.dart';
import 'package:sungerbob/domain/core/money.dart';
import 'package:sungerbob/domain/core/quantity.dart';

/// Altın Senaryo partileri (docs/GOLDEN_SCENARIO.md).
BatchView batch(String id, String pieces, String vol, String unitCost,
        {int seq = 0}) =>
    BatchView(
      id: id,
      variantId: 'v10',
      productId: 'beyaz',
      receivedAt: DateTime.utc(2026, 9, seq == 0 ? 1 : seq),
      sequence: seq,
      remainingPieces: int.parse(pieces),
      remainingVolume: Volume.parse(vol),
      realUnitCost: UnitPrice.parse(unitCost),
    );

void main() {
  group('FIFO tüketimi (Altın Senaryo 3)', () {
    test('60 adet: A1\'den 50 + B\'den 10 → maliyet 51.282,00', () {
      final a1 = batch('A1', '50', '14', '3030', seq: 1);
      final b = batch('B', '30', '8.4', '3165', seq: 15);

      final r = CostingEngine.fifo(
        batches: [a1, b],
        requiredPieces: 60,
        requiredVolume: Volume.parse('16.8'),
      );

      expect(r.totalCost, Money.parse('51282'));
      expect(r.allocations.length, 2);

      expect(r.allocations[0].batchId, 'A1');
      expect(r.allocations[0].pieces, 50);
      expect(r.allocations[0].volume, Volume.parse('14'));
      expect(r.allocations[0].cost, Money.parse('42420'));
      expect(r.allocations[0].sequenceNo, 0);

      expect(r.allocations[1].batchId, 'B');
      expect(r.allocations[1].pieces, 10);
      expect(r.allocations[1].volume, Volume.parse('2.8'));
      expect(r.allocations[1].cost, Money.parse('8862'));
      expect(r.allocations[1].sequenceNo, 1);
    });

    test('tek partiden karşılanır', () {
      final r = CostingEngine.fifo(
        batches: [batch('B', '30', '8.4', '3165', seq: 15)],
        requiredPieces: 1,
        requiredVolume: Volume.parse('0.28'),
      );
      expect(r.totalCost, Money.parse('886.20')); // Altın Senaryo 6 (sayım)
      expect(r.allocations.single.batchId, 'B');
    });

    test('fire: A2\'den 2 adet → 848,40 (Altın Senaryo 7)', () {
      final a2 = BatchView(
        id: 'A2',
        variantId: 'v5',
        productId: 'beyaz',
        receivedAt: DateTime.utc(2026, 9, 1),
        sequence: 1,
        remainingPieces: 40,
        remainingVolume: Volume.parse('5.6'),
        realUnitCost: UnitPrice.parse('3030'),
      );
      final r = CostingEngine.fifo(
        batches: [a2],
        requiredPieces: 2,
        requiredVolume: Volume.parse('0.28'),
      );
      expect(r.totalCost, Money.parse('848.40'));
    });

    test('giriş tarihi sırasına göre tüketir, liste sırasına göre değil', () {
      final yeni = batch('YENI', '100', '28', '9999', seq: 20);
      final eski = batch('ESKI', '10', '2.8', '1000', seq: 2);
      final r = CostingEngine.fifo(
        batches: [yeni, eski], // bilerek ters sırada verildi
        requiredPieces: 10,
        requiredVolume: Volume.parse('2.8'),
      );
      expect(r.allocations.single.batchId, 'ESKI');
    });

    test('stok yetersizse InsufficientStockException — negatif stok YASAK', () {
      expect(
        () => CostingEngine.fifo(
          batches: [batch('B', '30', '8.4', '3165', seq: 15)],
          requiredPieces: 31,
          requiredVolume: Volume.parse('8.68'),
        ),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('hiç parti yoksa da reddeder', () {
      expect(
        () => CostingEngine.fifo(
          batches: const [],
          requiredPieces: 1,
          requiredVolume: Volume.parse('0.28'),
        ),
        throwsA(isA<InsufficientStockException>()),
      );
    });
  });

  group('Ağırlıklı ortalama (Altın Senaryo Ek A)', () {
    test('ürün bazında: (59.388 + 26.586) / 28 m³ = 3.070,5000 TL/m³', () {
      final a1 = batch('A1', '50', '14', '3030', seq: 1);
      final a2 = BatchView(
        id: 'A2',
        variantId: 'v5',
        productId: 'beyaz',
        receivedAt: DateTime.utc(2026, 9, 1),
        sequence: 1,
        remainingPieces: 40,
        remainingVolume: Volume.parse('5.6'),
        realUnitCost: UnitPrice.parse('3030'),
      );
      final b = batch('B', '30', '8.4', '3165', seq: 15);

      final avg = CostingEngine.weightedAverageUnitCost([a1, a2, b]);
      expect(avg, UnitPrice.parse('3070.5'));
    });

    test('satış maliyeti 16,8 m³ × 3.070,5000 = 51.584,40', () {
      final a1 = batch('A1', '50', '14', '3030', seq: 1);
      final a2 = BatchView(
        id: 'A2', variantId: 'v5', productId: 'beyaz',
        receivedAt: DateTime.utc(2026, 9, 1), sequence: 1,
        remainingPieces: 40, remainingVolume: Volume.parse('5.6'),
        realUnitCost: UnitPrice.parse('3030'),
      );
      final b = batch('B', '30', '8.4', '3165', seq: 15);

      final r = CostingEngine.weightedAverage(
        batches: [a1, b],
        productBatches: [a1, a2, b],
        requiredPieces: 60,
        requiredVolume: Volume.parse('16.8'),
      );
      expect(r.totalCost, Money.parse('51584.40'));
    });

    test('fiziksel tüketim yine FIFO sırasıyla olur', () {
      final a1 = batch('A1', '50', '14', '3030', seq: 1);
      final b = batch('B', '30', '8.4', '3165', seq: 15);
      final r = CostingEngine.weightedAverage(
        batches: [a1, b],
        productBatches: [a1, b],
        requiredPieces: 60,
        requiredVolume: Volume.parse('16.8'),
      );
      expect(r.allocations.map((a) => a.batchId).toList(), ['A1', 'B']);
      expect(r.allocations[0].pieces, 50);
      expect(r.allocations[1].pieces, 10);
      // Dağıtılan maliyetlerin toplamı, toplam maliyete eşit olmalı.
      expect(sumMoney(r.allocations.map((a) => a.cost)), r.totalCost);
    });

    test('kalan yoksa ortalama sıfır', () {
      expect(CostingEngine.weightedAverageUnitCost(const []), UnitPrice.zero);
    });
  });

  group('Masraf dağıtımı (BRIEF §3.7)', () {
    test('Altın Senaryo 1: nakliye 1.960 → gerçek maliyet 3.030,0000 TL/m³', () {
      final r = CostingEngine.allocatePurchaseExpense(
        expense: Money.parse('1960'),
        lines: [
          ExpenseTarget(volume: Volume.parse('14'), bareCost: Money.parse('41020')),
          ExpenseTarget(volume: Volume.parse('5.6'), bareCost: Money.parse('16408')),
        ],
      );
      expect(r[0], Money.parse('1400'));
      expect(r[1], Money.parse('560'));

      // A1: (41.020 + 1.400) / 14 = 3.030,0000
      final a1Real = UnitPrice.fromDecimal(
          ((Money.parse('41020') + r[0]).tl / Volume.parse('14').m3)
              .toDecimal(scaleOnInfinitePrecision: 8));
      expect(a1Real, UnitPrice.parse('3030'));

      // A2: (16.408 + 560) / 5,6 = 3.030,0000
      final a2Real = UnitPrice.fromDecimal(
          ((Money.parse('16408') + r[1]).tl / Volume.parse('5.6').m3)
              .toDecimal(scaleOnInfinitePrecision: 8));
      expect(a2Real, UnitPrice.parse('3030'));
    });

    test('sonradan gelen masraf: stok / satılmış ayrımı', () {
      // Parti 10 m³ girdi, 4 m³ satıldı, 6 m³ stokta. Masraf 1.000 TL.
      final split = CostingEngine.splitLateExpense(
        expenseShare: Money.parse('1000'),
        totalInVolume: Volume.parse('10'),
        remainingVolume: Volume.parse('6'),
      );
      expect(split.toStock, Money.parse('600'));
      expect(split.toAdjustment, Money.parse('400'));
      expect(split.toStock + split.toAdjustment, Money.parse('1000'));
    });

    test('tamamı satılmışsa hepsi maliyet farkına gider', () {
      final split = CostingEngine.splitLateExpense(
        expenseShare: Money.parse('500'),
        totalInVolume: Volume.parse('10'),
        remainingVolume: Volume.zero,
      );
      expect(split.toStock, Money.zero);
      expect(split.toAdjustment, Money.parse('500'));
    });

    test('hiç satılmamışsa hepsi partinin maliyetine girer', () {
      final split = CostingEngine.splitLateExpense(
        expenseShare: Money.parse('500'),
        totalInVolume: Volume.parse('10'),
        remainingVolume: Volume.parse('10'),
      );
      expect(split.toStock, Money.parse('500'));
      expect(split.toAdjustment, Money.zero);
    });
  });

  group('Fason kesim maliyeti (Altın Senaryo Ek C)', () {
    test('12.600,00 / 3,6 m³ → hedefler 8.820,00 ve 3.780,00', () {
      final r = CostingEngine.allocateCutting(
        sourceCost: Money.parse('11600'),
        cuttingFee: Money.parse('1000'),
        freight: Money.zero,
        sourceVolume: Volume.parse('4'),
        targets: [Volume.parse('2.52'), Volume.parse('1.08')],
      );
      expect(r.totalCost, Money.parse('12600'));
      expect(r.unitCost, UnitPrice.parse('3500'));
      expect(r.targetCosts, [Money.parse('8820'), Money.parse('3780')]);
      expect(r.wasteVolume, Volume.parse('0.4'));
      expect(sumMoney(r.targetCosts), Money.parse('12600'));
    });

    test('hedef m³ kaynağı aşarsa reddedilir', () {
      expect(
        () => CostingEngine.allocateCutting(
          sourceCost: Money.parse('11600'),
          cuttingFee: Money.parse('1000'),
          freight: Money.zero,
          sourceVolume: Volume.parse('4'),
          targets: [Volume.parse('5')],
        ),
        throwsA(isA<CuttingVolumeException>()),
      );
    });

    test('nakliye de maliyete girer', () {
      final r = CostingEngine.allocateCutting(
        sourceCost: Money.parse('1000'),
        cuttingFee: Money.parse('100'),
        freight: Money.parse('50'),
        sourceVolume: Volume.parse('2'),
        targets: [Volume.parse('1'), Volume.parse('1')],
      );
      expect(r.totalCost, Money.parse('1150'));
      expect(sumMoney(r.targetCosts), Money.parse('1150'));
    });
  });

  group('İade: tüketimin tersinden döner (Altın Senaryo 8)', () {
    test('A1\'den 50 + B\'den 10 tüketildi; 5 adet iade B\'ye döner', () {
      final consumed = [
        CostAllocation(
            batchId: 'A1',
            pieces: 50,
            volume: Volume.parse('14'),
            unitCost: UnitPrice.parse('3030'),
            cost: Money.parse('42420'),
            sequenceNo: 0),
        CostAllocation(
            batchId: 'B',
            pieces: 10,
            volume: Volume.parse('2.8'),
            unitCost: UnitPrice.parse('3165'),
            cost: Money.parse('8862'),
            sequenceNo: 1),
      ];

      final r = CostingEngine.reverseForReturn(
        originalAllocations: consumed,
        returnPieces: 5,
      );

      expect(r.length, 1);
      expect(r.single.batchId, 'B');
      expect(r.single.pieces, 5);
      expect(r.single.volume, Volume.parse('1.4'));
      expect(r.single.cost, Money.parse('4431'));
    });

    test('iade son partiyi aşarsa bir öncekine taşar', () {
      final consumed = [
        CostAllocation(
            batchId: 'A1', pieces: 50, volume: Volume.parse('14'),
            unitCost: UnitPrice.parse('3030'), cost: Money.parse('42420'),
            sequenceNo: 0),
        CostAllocation(
            batchId: 'B', pieces: 10, volume: Volume.parse('2.8'),
            unitCost: UnitPrice.parse('3165'), cost: Money.parse('8862'),
            sequenceNo: 1),
      ];
      final r = CostingEngine.reverseForReturn(
        originalAllocations: consumed,
        returnPieces: 12,
      );
      expect(r.map((a) => a.batchId).toList(), ['B', 'A1']);
      expect(r[0].pieces, 10);
      expect(r[1].pieces, 2);
    });

    test('satılandan fazla iade reddedilir', () {
      final consumed = [
        CostAllocation(
            batchId: 'B', pieces: 10, volume: Volume.parse('2.8'),
            unitCost: UnitPrice.parse('3165'), cost: Money.parse('8862'),
            sequenceNo: 0),
      ];
      expect(
        () => CostingEngine.reverseForReturn(
            originalAllocations: consumed, returnPieces: 11),
        throwsA(isA<ReturnExceedsSoldException>()),
      );
    });
  });
}
