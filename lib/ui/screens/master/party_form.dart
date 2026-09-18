import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/enums.dart';
import '../../../data/repo/party_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';

/// Müşteri / tedarikçi kartı açma.
///
/// Tek zorunlu alan **unvan**. Geri kalanı sonradan da girilebilir; ilk
/// kaydı yaparken kullanıcıyı uzun bir formda bekletmek işi durdurur.
///
/// Kod kullanıcıya sorulmaz, unvandan türetilir (`PartyRepository`).
class PartyFormScreen extends ConsumerStatefulWidget {
  /// true: tedarikçi, false: müşteri.
  final bool supplier;

  /// Tedarikçi tipi önceden biliniyorsa (ör. kesim ekranından gelindiyse).
  final String? initialSupplierType;

  const PartyFormScreen({
    super.key,
    required this.supplier,
    this.initialSupplierType,
  });

  @override
  ConsumerState<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends ConsumerState<PartyFormScreen> {
  final _title = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxOffice = TextEditingController();
  final _taxNumber = TextEditingController();

  late String _type = widget.initialSupplierType ?? SupplierType.factory;

  /// Unvan doğrulaması **alanın kendisinde** gösterilir; formun dibindeki
  /// bir uyarı gözden kaçıyor.
  String? _titleError;
  String? _error;
  bool _saving = false;

  /// Form açılışında üretilir; aynı kart iki kez açılmaz (BRIEF §3.12).
  final _commandId = const Uuid().v7();

  @override
  void dispose() {
    for (final c in [
      _title,
      _contact,
      _phone,
      _address,
      _taxOffice,
      _taxNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Unvan girin');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _titleError = null;
    });

    try {
      final repo = PartyRepository(await ref.read(databaseProvider.future));
      final id = widget.supplier
          ? await repo.createSupplier(
              title: title,
              type: _type,
              contactPerson: _contact.text,
              phone: _phone.text,
              address: _address.text,
              taxOffice: _taxOffice.text,
              taxNumber: _taxNumber.text,
              ctx: OperationContext(
                commandType: 'SUPPLIER_CREATE',
                commandId: _commandId,
              ),
            )
          : await repo.createCustomer(
              title: title,
              contactPerson: _contact.text,
              phone: _phone.text,
              address: _address.text,
              taxOffice: _taxOffice.text,
              taxNumber: _taxNumber.text,
              ctx: OperationContext(
                commandType: 'CUSTOMER_CREATE',
                commandId: _commandId,
              ),
            );

      if (!mounted) return;
      // Açılır listeler yeni kartı hemen görsün.
      ref.invalidate(suppliersProvider);
      ref.invalidate(customersProvider);
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = widget.supplier ? 'Tedarikçi' : 'Müşteri';

    return Scaffold(
      appBar: AppBar(title: Text('Yeni $noun')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '$noun unvanı',
              helperText: 'Zorunlu. Kod unvandan türetilir.',
              errorText: _titleError,
            ),
            onChanged: (_) => setState(() {
              _error = null;
              _titleError = null;
            }),
          ),
          if (widget.supplier) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tedarikçi tipi'),
              items: const [
                DropdownMenuItem(
                  value: SupplierType.factory,
                  child: Text('Fabrika'),
                ),
                DropdownMenuItem(
                  value: SupplierType.cutter,
                  child: Text('Kesimhane'),
                ),
                DropdownMenuItem(
                  value: SupplierType.carrier,
                  child: Text('Nakliye'),
                ),
                DropdownMenuItem(
                  value: SupplierType.other,
                  child: Text('Diğer'),
                ),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
          ],
          const SizedBox(height: 24),
          Text('İsteğe bağlı', style: context.eyebrowStyle),
          const SizedBox(height: 12),
          _field(_contact, 'Yetkili kişi'),
          _field(_phone, 'Telefon', keyboard: TextInputType.phone),
          _field(_address, 'Adres', lines: 2),
          _field(_taxOffice, 'Vergi dairesi'),
          _field(_taxNumber, 'Vergi / TC no', keyboard: TextInputType.number),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      // Kaydet düğmesi **her zaman görünür**: uzun formun dibinde kalırsa
      // kullanıcı onu aramak zorunda kalıyor.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text('$noun kartını aç'),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: lines,
      textCapitalization: lines > 1
          ? TextCapitalization.sentences
          : TextCapitalization.words,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

/// Yeni kart açar ve kimliğini döndürür; vazgeçilirse `null`.
Future<String?> openPartyForm(
  BuildContext context, {
  required bool supplier,
  String? supplierType,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) =>
        PartyFormScreen(supplier: supplier, initialSupplierType: supplierType),
  ),
);
