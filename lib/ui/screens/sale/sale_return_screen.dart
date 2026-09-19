import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/return_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../documents/documents_screen.dart' show describeLine;

/// Satış iadesi (BRIEF §5, D-12).
///
/// İş kuralı Faz 1'den beri hazırdı ama ekranı yoktu: müşteri malı geri
/// getirdiğinde kullanıcı defterde hiçbir şey yapamıyordu. Satış iptali
/// yerine **iade** doğru iş kuralıdır — orijinal satış değişmez, mal aynı
/// maliyetle geri döner, cariye alacak yazılır.
class SaleReturnScreen extends ConsumerStatefulWidget {
  final String saleId;

  /// Başlıkta görünen "kime, hangi belge" bilgisi.
  final String saleTitle;

  const SaleReturnScreen({
    super.key,
    required this.saleId,
    required this.saleTitle,
  });

  @override
  ConsumerState<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends ConsumerState<SaleReturnScreen> {
  /// Form açılışında üretilir; çift dokunmada iade tekrarlanmasın diye
  /// kaydetme boyunca AYNI kalır (BRIEF §3.9).
  final _commandId = uuid.v7();
  final _reason = TextEditingController();

  /// saleItemId → iade edilecek adet.
  final _quantities = <String, int>{};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasQuantity => _quantities.values.any((v) => v > 0);

  Future<void> _save(List<ReturnableLine> lines) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = await ref.read(databaseProvider.future);
      await ReturnRepository(db).createSaleReturn(
        SaleReturnInput(
          saleId: widget.saleId,
          docDate: DateTime.now(),
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          lines: [
            for (final line in lines)
              if ((_quantities[line.saleItemId] ?? 0) > 0)
                SaleReturnLineInput(
                  saleItemId: line.saleItemId,
                  pieces: _quantities[line.saleItemId]!,
                ),
          ],
        ),
        OperationContext(commandType: 'SALE_RETURN', commandId: _commandId),
      );

      if (!mounted) return;
      // Liste ve stok ekranları yeni gerçeği göstersin.
      ref.invalidate(returnableLinesProvider(widget.saleId));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(returnableLinesProvider(widget.saleId));

    return Scaffold(
      appBar: AppBar(title: const Text('İade al')),
      body: lines.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(returnableLinesProvider(widget.saleId)),
        ),
        data: (list) {
          final open = list.where((l) => !l.isFullyReturned).toList();

          if (open.isEmpty) {
            return const EmptyState(
              icon: Icons.assignment_turned_in_outlined,
              title: 'İade edilecek kalem yok',
              description: 'Bu satışın tamamı zaten iade edilmiş.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(widget.saleTitle, style: context.labelStyle),
              const SizedBox(height: 16),
              for (final line in open)
                _LineTile(
                  line: line,
                  value: _quantities[line.saleItemId] ?? 0,
                  onChanged: (v) =>
                      setState(() => _quantities[line.saleItemId] = v),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'İade sebebi (opsiyonel)',
                  helperText: 'Ör. hatalı ölçü, müşteri beğenmedi',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving || !_hasQuantity ? null : () => _save(open),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.assignment_return),
                label: Text(_saving ? 'Kaydediliyor…' : 'İadeyi kaydet'),
              ),
              if (!_hasQuantity) ...[
                const SizedBox(height: 8),
                Text(
                  'En az bir kalemde iade miktarı girin.',
                  style: context.labelStyle,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tek kalem: ne satıldı, en fazla kaç tane geri alınabilir.
class _LineTile extends StatelessWidget {
  final ReturnableLine line;
  final int value;
  final ValueChanged<int> onChanged;

  const _LineTile({
    required this.line,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final description = describeLine(
      product: line.productName,
      unit: line.unit,
      width: line.width.stored,
      height: line.height.stored,
      thickness: line.thickness.stored,
    );
    final isFoam = ProductUnit.hasDimensions(line.unit);
    String amount(int count) => isFoam
        ? TrFormat.pieces(count)
        : '$count ${ProductUnit.label(line.unit)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 4),
            Text(
              line.returnedPieces == 0
                  ? 'Satılan ${amount(line.soldPieces)} · '
                        '${TrFormat.unitPriceFor(line.unitPrice, line.unit)}'
                  : 'Satılan ${amount(line.soldPieces)} · '
                        '${amount(line.returnedPieces)} iade edilmiş',
              style: context.labelStyle,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('İade', style: context.labelStyle),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: value > 0 ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: context.bigNumberStyle,
                  ),
                ),
                IconButton.filledTonal(
                  // İade satılandan fazla olamaz; kural veritabanında da var
                  // ama kullanıcıya hatayı yaptırmadan söylemek daha iyi.
                  onPressed: value < line.remainingPieces
                      ? () => onChanged(value + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 4),
                Text('/ ${line.remainingPieces}', style: context.labelStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final returnableLinesProvider = FutureProvider.autoDispose
    .family<List<ReturnableLine>, String>((ref, saleId) async {
      final db = await ref.watch(databaseProvider.future);
      return ReturnRepository(db).returnableLines(saleId);
    });
