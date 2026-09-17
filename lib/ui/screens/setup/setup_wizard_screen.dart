import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/backup/backup_password_store.dart';
import '../../../data/db/enums.dart';
import '../../../data/repo/settings_repository.dart';
import '../../../data/repo/unit_of_work.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_pad.dart';

/// Kurulum sihirbazı (BRIEF §7).
///
/// Yeni başla / Yedekten geri yükle → kullanıcı adı ve PIN → yedek şifresi →
/// firma bilgileri → KDV ve fiyat modu → maliyet yöntemi → Drive (atlanabilir)
/// → açılış işlemleri (atlanabilir).
///
/// **Mock veri yoktur**: sihirbaz yalnızca ayar yazar, hareket üretmez.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  final _draft = _SetupDraft();
  int _step = 0;
  bool _saving = false;
  String? _saveError;

  static const _titles = [
    'Başlangıç',
    'Kullanıcı ve PIN',
    'Yedek şifresi',
    'Firma bilgileri',
    'KDV ve fiyat modu',
    'Maliyet yöntemi',
    'Google Drive',
    'Açılış işlemleri',
  ];

  bool get _canContinue => switch (_step) {
    1 =>
      _draft.userName.trim().isNotEmpty &&
          _draft.pin.length == 4 &&
          _draft.pin == _draft.pinConfirm,
    2 =>
      BackupPasswordRules.isValid(_draft.backupPassword) &&
          _draft.backupPassword == _draft.backupPasswordConfirm,
    3 => _draft.companyName.trim().isNotEmpty,
    _ => true,
  };

  void _next() {
    if (_step == _titles.length - 1) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      await settings.setPin(_draft.pin);
      await settings.setBiometricEnabled(_draft.biometric);
      await settings.saveCompany(
        CompanySettings(
          name: _draft.companyName.trim(),
          address: _draft.address.trim().isEmpty ? null : _draft.address.trim(),
          phone: _draft.phone.trim().isEmpty ? null : _draft.phone.trim(),
          taxOffice: _draft.taxOffice.trim().isEmpty
              ? null
              : _draft.taxOffice.trim(),
          taxNumber: _draft.taxNumber.trim().isEmpty
              ? null
              : _draft.taxNumber.trim(),
        ),
      );
      await settings.saveUserName(_draft.userName.trim());
      await settings.setDefaultVatRate(_draft.vatRate);
      await settings.setDefaultPriceMode(_draft.priceMode);
      await settings.setCostingMethod(
        _draft.costingMethod,
        OperationContext(commandType: 'SETUP_COSTING_METHOD'),
      );

      await ref.read(backupPasswordStoreProvider).write(_draft.backupPassword);

      await settings.markSetupCompleted();
      ref.invalidate(setupCompletedProvider);
      ref.read(appLockProvider.notifier).unlock();

      if (!mounted) return;
      if (_draft.openingBalances) {
        context.go('/opening');
      } else {
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_step]),
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _titles.length),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _body(),
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Kurulum tamamlanamadı: $_saveError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_isSkippable(_step))
                    TextButton(
                      onPressed: _saving ? null : _next,
                      child: const Text('Atla'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_canContinue && !_saving) ? _next : null,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step == _titles.length - 1 ? 'Bitir' : 'Devam'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Drive ve açılış işlemleri atlanabilir (BRIEF §7).
  static bool _isSkippable(int step) => step == 6 || step == 7;

  Widget _body() => switch (_step) {
    0 => _startStep(),
    1 => _pinStep(),
    2 => _backupPasswordStep(),
    3 => _companyStep(),
    4 => _vatStep(),
    5 => _costingStep(),
    6 => _driveStep(),
    _ => _openingStep(),
  };

  // ----------------------------------------------------------------- adımlar

  Widget _startStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      Icon(
        Icons.inventory_2_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'Sünger Stok & Cari',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        'Verileriniz yalnızca bu telefonda, şifreli olarak tutulur.',
        textAlign: TextAlign.center,
        style: context.labelStyle,
      ),
      const SizedBox(height: 32),
      Card(
        child: ListTile(
          leading: const Icon(Icons.play_arrow),
          title: const Text('Yeni başla'),
          subtitle: const Text('Boş bir kayıt defteriyle kurulum'),
          onTap: () => setState(() => _step = 1),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Yedekten geri yükle'),
          subtitle: const Text('Elinizdeki .sbk dosyası ve yedek şifresiyle'),
          onTap: () => context.push('/restore'),
        ),
      ),
    ],
  );

  Widget _pinStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: _draft.userName,
        decoration: const InputDecoration(
          labelText: 'Kullanıcı adı',
          helperText: 'Belgelerde ve audit kayıtlarında görünür',
        ),
        textCapitalization: TextCapitalization.words,
        onChanged: (v) => setState(() => _draft.userName = v),
      ),
      const SizedBox(height: 24),
      PinPad(
        title: _draft.pin.length < 4 ? '4 haneli PIN belirleyin' : 'PIN tekrar',
        subtitle: _draft.pin.length < 4
            ? 'Uygulamayı her açışınızda sorulur'
            : 'Aynı PIN\'i bir kez daha girin',
        value: _draft.pin.length < 4 ? _draft.pin : _draft.pinConfirm,
        errorText:
            _draft.pinConfirm.length == 4 && _draft.pinConfirm != _draft.pin
            ? 'PIN\'ler aynı değil'
            : null,
        onChanged: (v) => setState(() {
          if (_draft.pin.length < 4) {
            _draft.pin = v;
          } else {
            _draft.pinConfirm = v;
            if (v.isEmpty) _draft.pin = '';
          }
        }),
      ),
      SwitchListTile(
        value: _draft.biometric,
        onChanged: (v) => setState(() => _draft.biometric = v),
        title: const Text('Parmak izi ile aç'),
        subtitle: const Text('Cihaz destekliyorsa PIN yerine kullanılır'),
      ),
    ],
  );

  Widget _backupPasswordStep() {
    final error = _draft.backupPassword.isEmpty
        ? null
        : BackupPasswordRules.validate(_draft.backupPassword);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.warning_amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bu şifreyi bir yere yazın. Unutursanız yedekleriniz '
                    'açılamaz — kurtarma yolu yoktur.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          initialValue: _draft.backupPassword,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Yedek şifresi',
            helperText: 'En az 8 karakter, harf ve rakam',
            errorText: error,
          ),
          onChanged: (v) => setState(() => _draft.backupPassword = v),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _draft.backupPasswordConfirm,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Yedek şifresi tekrar',
            errorText:
                _draft.backupPasswordConfirm.isNotEmpty &&
                    _draft.backupPasswordConfirm != _draft.backupPassword
                ? 'Şifreler aynı değil'
                : null,
          ),
          onChanged: (v) => setState(() => _draft.backupPasswordConfirm = v),
        ),
      ],
    );
  }

  Widget _companyStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: _draft.companyName,
        decoration: const InputDecoration(labelText: 'Firma adı'),
        textCapitalization: TextCapitalization.words,
        onChanged: (v) => setState(() => _draft.companyName = v),
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: _draft.address,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Adres'),
        onChanged: (v) => _draft.address = v,
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: _draft.phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Telefon'),
        onChanged: (v) => _draft.phone = v,
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: _draft.taxOffice,
        decoration: const InputDecoration(labelText: 'Vergi dairesi'),
        onChanged: (v) => _draft.taxOffice = v,
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: _draft.taxNumber,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Vergi / TC no'),
        onChanged: (v) => _draft.taxNumber = v,
      ),
    ],
  );

  Widget _vatStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Varsayılan KDV oranı', style: context.labelStyle),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('%0')),
          ButtonSegment(value: 100, label: Text('%1')),
          ButtonSegment(value: 1000, label: Text('%10')),
          ButtonSegment(value: 2000, label: Text('%20')),
        ],
        selected: {_draft.vatRate},
        onSelectionChanged: (s) => setState(() => _draft.vatRate = s.first),
      ),
      const SizedBox(height: 32),
      Text('Varsayılan fiyat modu', style: context.labelStyle),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'EXCL', label: Text('KDV Hariç')),
          ButtonSegment(value: 'INCL', label: Text('KDV Dahil')),
        ],
        selected: {_draft.priceMode},
        onSelectionChanged: (s) => setState(() => _draft.priceMode = s.first),
      ),
      const SizedBox(height: 16),
      Text(
        'KDV Dahil modda girdiğiniz tutar aynen korunur; KDV içinden '
        'hesaplanır. Maliyet, kâr ve ciro her zaman KDV hariçtir.',
        style: context.labelStyle,
      ),
    ],
  );

  Widget _costingStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RadioGroup<String>(
        groupValue: _draft.costingMethod,
        onChanged: (v) => setState(() => _draft.costingMethod = v!),
        child: const Column(
          children: [
            Card(
              child: RadioListTile<String>(
                value: CostingMethod.fifo,
                title: Text('FIFO — İlk giren ilk çıkar'),
                subtitle: Text(
                  'Her alış bir parti. Satışta en eski parti tüketilir.',
                ),
              ),
            ),
            Card(
              child: RadioListTile<String>(
                value: CostingMethod.weightedAverage,
                title: Text('Ağırlıklı ortalama'),
                subtitle: Text('Çeşit bazında ortalama m³ maliyeti.'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Yöntem ilk stok hareketinden sonra kilitlenir. Sonradan değiştirmek '
        'geçmiş maliyetleri etkilemez ama riskli bir işlemdir.',
        style: context.labelStyle,
      ),
    ],
  );

  Widget _driveStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Icon(
        Icons.cloud_upload_outlined,
        size: 56,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'Yedekler telefonda tutulur. Telefon kaybolursa veriler de kaybolur; '
        'bu yüzden yedeği Google Drive\'a da yüklemenizi öneririz.',
        textAlign: TextAlign.center,
        style: context.labelStyle,
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => context.push('/settings/drive'),
        icon: const Icon(Icons.link),
        label: const Text('Google Drive bağla'),
      ),
      const SizedBox(height: 8),
      Text(
        'Sonradan Ayarlar → Yedek ve Drive bölümünden da bağlayabilirsiniz.',
        textAlign: TextAlign.center,
        style: context.labelStyle,
      ),
    ],
  );

  Widget _openingStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Text(
        'Kurulum tamam. İsterseniz şimdi açılış bakiyelerini girebilirsiniz: '
        'mevcut stok, müşteri alacakları, tedarikçi borçları, kasa ve banka.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      SwitchListTile(
        value: _draft.openingBalances,
        onChanged: (v) => setState(() => _draft.openingBalances = v),
        title: const Text('Bitirince açılış ekranını aç'),
        subtitle: const Text(
          'Sonradan Menü → Açılış İşlemleri\'nden de yapılır',
        ),
      ),
    ],
  );
}

final class _SetupDraft {
  String userName = '';
  String pin = '';
  String pinConfirm = '';
  bool biometric = false;

  String backupPassword = '';
  String backupPasswordConfirm = '';

  String companyName = '';
  String address = '';
  String phone = '';
  String taxOffice = '';
  String taxNumber = '';

  int vatRate = 2000;
  String priceMode = 'EXCL';
  String costingMethod = CostingMethod.fifo;

  bool openingBalances = false;
}
