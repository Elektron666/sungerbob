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
import '../../widgets/signature.dart';

/// Kurulum sihirbazı (BRIEF §7).
///
/// Yeni başla / Yedekten geri yükle → kullanıcı adı ve PIN → yedek şifresi →
/// firma bilgileri → KDV ve fiyat modu → maliyet yöntemi → Drive (atlanabilir)
/// → açılış işlemleri (atlanabilir).
///
/// **Mock veri yoktur**: sihirbaz yalnızca ayar yazar, hareket üretmez.
class SetupWizardScreen extends ConsumerStatefulWidget {
  /// Demo girişin kullandığı PIN. Ayarlar'dan değiştirilebilir.
  static const demoPin = '0000';

  /// Demo girişin yedek şifresi. Kurallara uyar; kullanıcı Ayarlar'dan
  /// kendi şifresini belirleyene kadar yedekler bununla açılır.
  static const demoBackupPassword = 'demo1234';

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
    'Kullanıcı adı',
    // PIN kendi adımında: tuş takımı ekranı paylaşınca alt sırası
    // kesiliyor ve kullanıcı kurulumu bitiremiyor.
    'PIN',
    'Yedek şifresi',
    'Firma bilgileri',
    'KDV ve fiyat modu',
    'Maliyet yöntemi',
    'Google Drive',
    'Açılış işlemleri',
  ];

  /// Devam edilemiyorsa **nedeni**; edilebiliyorsa `null`.
  ///
  /// Kapalı bir düğmeyi sebepsiz göstermek kullanıcıyı çıkmaza sokar —
  /// eksiğin ne olduğu ekranda yazar.
  String? get _blockedReason {
    switch (_step) {
      case 1:
        if (_draft.userName.trim().isEmpty) return 'Kullanıcı adı girin';
      case 2:
        if (_draft.pin.length < PinPad.pinLength) return 'PIN 4 haneli olmalı';
        if (_draft.pinConfirm.length < PinPad.pinLength) {
          return 'PIN\'i bir kez daha girin';
        }
        if (_draft.pin != _draft.pinConfirm) return 'PIN\'ler aynı değil';
      case 3:
        final error = BackupPasswordRules.validate(_draft.backupPassword);
        if (error != null) return error;
        if (_draft.backupPassword != _draft.backupPasswordConfirm) {
          return 'Yedek şifreleri aynı değil';
        }
      case 4:
        if (_draft.companyName.trim().isEmpty) return 'Firma adı girin';
    }
    return null;
  }

  bool get _canContinue => _blockedReason == null;

  /// Düğme yanında gösterilecek ipucu; tuş takımı zaten uyarıyorsa boş.
  String? get _hintText {
    final reason = _blockedReason;
    return reason == _pinPadError ? null : reason;
  }

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
              // PIN adımı kaydırmaya bağımlı olmamalı: tuş takımının bir
              // sırası ekranın altında kalırsa kullanıcı o tuşlara basamaz
              // ve kurulumu bitiremez. Bu adım kalan alanı doldurur, tuşlar
              // ona göre ölçeklenir.
              child: _step == 2
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _pinStep(),
                    )
                  : SingleChildScrollView(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // İpucu **kendi satırında ve sabit yükseklikte** durur.
                  //
                  // Daha önce düğmelerle aynı satırdaydı: yanına bir düğme
                  // eklenince dar bir sütuna sıkışıp altı satıra sarıyor,
                  // alt barı şişiriyor ve tuş takımının alt sıralarını
                  // ekrandan taşırıyordu — kullanıcı PIN'i giremiyordu.
                  SizedBox(
                    height: 20,
                    child: _hintText == null
                        ? null
                        : Text(
                            _hintText!,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.labelStyle,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_isSkippable(_step))
                        TextButton(
                          onPressed: _saving ? null : _next,
                          child: const Text('Atla'),
                        ),
                      if (_step == 2 &&
                          (_draft.pin.isNotEmpty ||
                              _draft.pinConfirm.isNotEmpty))
                        TextButton(
                          onPressed: _saving ? null : _resetPin,
                          child: const Text('Sıfırla'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: (_canContinue && !_saving) ? _next : null,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _step == _titles.length - 1 ? 'Bitir' : 'Devam',
                              ),
                      ),
                    ],
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
  static bool _isSkippable(int step) => step == 7 || step == 8;

  Widget _body() => switch (_step) {
    0 => _startStep(),
    1 => _userNameStep(),
    2 => _pinStep(),
    3 => _backupPasswordStep(),
    4 => _companyStep(),
    5 => _vatStep(),
    6 => _costingStep(),
    7 => _driveStep(),
    _ => _openingStep(),
  };

  // ----------------------------------------------------------------- adımlar

  Widget _startStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 32),
      // Pirinç ince çizgi — markanın tek süs öğesi.
      Center(
        child: Container(
          width: 40,
          height: 1.5,
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Sünger',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displayMedium,
      ),
      const SizedBox(height: 6),
      Text(
        'STOK & CARİ',
        textAlign: TextAlign.center,
        style: context.eyebrowStyle,
      ),
      const SizedBox(height: 20),
      Text(
        'Verileriniz yalnızca bu telefonda, şifreli olarak tutulur.',
        textAlign: TextAlign.center,
        style: context.labelStyle,
      ),
      const SizedBox(height: 36),
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
      const SizedBox(height: 24),
      Center(
        child: TextButton.icon(
          onPressed: _saving ? null : _startDemo,
          icon: const Icon(Icons.bolt_outlined, size: 18),
          label: const Text('Demo ile hızlı gir'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Kurulumu atlar, uygulamayı boş kayıt defteriyle açar. '
          'PIN 0000, sonradan Ayarlar\'dan değiştirilir.',
          textAlign: TextAlign.center,
          style: context.labelStyle,
        ),
      ),
    ],
  );

  /// **Demo giriş** — kurulumu atlayıp doğrudan uygulamayı açar.
  ///
  /// Denemek isteyen kullanıcıyı sekiz adımlık formda bekletmemek için.
  /// Gerçek bir kurulum yapar (PIN, yedek şifresi, firma adı yazılır);
  /// tek farkı değerleri sormaması.
  ///
  /// **Sahte veri üretmez** — kayıt defteri boş açılır. Uygulama gerçek
  /// işletme verisiyle çalışır; demo diye uydurma satış ve cari yazmak,
  /// sonradan gerçek kayıtlarla karışma riski taşır.
  Future<void> _startDemo() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      await settings.setPin(SetupWizardScreen.demoPin);
      await settings.saveUserName('Demo');
      await settings.saveCompany(const CompanySettings(name: 'Demo İşletme'));
      await ref
          .read(backupPasswordStoreProvider)
          .write(SetupWizardScreen.demoBackupPassword);
      await settings.markSetupCompleted();

      ref.invalidate(setupCompletedProvider);
      ref.read(appLockProvider.notifier).unlock();
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e';
      });
    }
  }

  /// PIN girişi iki aşamalı: önce belirle, sonra doğrula. Aşama **açıkça**
  /// tutulur — `pin.length` gibi dolaylı bir işaretten çıkarılırsa hızlı
  /// basışta yanlış alana yazılır.
  bool _confirmingPin = false;

  void _pressPinDigit(String digit) => setState(() {
    if (_confirmingPin) {
      if (_draft.pinConfirm.length < PinPad.pinLength) {
        _draft.pinConfirm += digit;
      }
      return;
    }
    if (_draft.pin.length < PinPad.pinLength) _draft.pin += digit;
    if (_draft.pin.length == PinPad.pinLength) _confirmingPin = true;
  });

  /// Geri silme **yalnızca son haneyi** siler. Doğrulama boşken bir adım
  /// geri gidilir; ilk PIN'in tamamı silinmez.
  void _pinBackspace() => setState(() {
    if (_confirmingPin) {
      if (_draft.pinConfirm.isEmpty) {
        _confirmingPin = false;
        _draft.pin = _dropLast(_draft.pin);
      } else {
        _draft.pinConfirm = _dropLast(_draft.pinConfirm);
      }
      return;
    }
    _draft.pin = _dropLast(_draft.pin);
  });

  void _resetPin() => setState(() {
    _draft.pin = '';
    _draft.pinConfirm = '';
    _confirmingPin = false;
  });

  static String _dropLast(String value) =>
      value.isEmpty ? value : value.substring(0, value.length - 1);

  /// Tuş takımının kendi hata metni. Düğme yanındaki ipucu bunu
  /// tekrarlamaz — aynı uyarıyı iki yerde göstermek gürültüdür.
  String? get _pinPadError =>
      _draft.pinConfirm.length == PinPad.pinLength &&
          _draft.pinConfirm != _draft.pin
      ? 'PIN\'ler aynı değil'
      : null;

  Widget _userNameStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      TextFormField(
        initialValue: _draft.userName,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Kullanıcı adı',
          helperText: 'Belgelerde ve audit kayıtlarında görünür',
        ),
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (v) => setState(() => _draft.userName = v),
      ),
      const SizedBox(height: 20),
      Text(
        'Tek kullanıcılı bir uygulama; bu ad belgelerin altında ve işlem '
        'geçmişinde görünür.',
        style: context.labelStyle,
      ),
    ],
  );

  /// PIN kendi ekranında: tuş takımı kalan alanın tamamını alır.
  Widget _pinStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: PinPad(
          title: _confirmingPin ? 'PIN tekrar' : '4 haneli PIN belirleyin',
          subtitle: _confirmingPin
              ? 'Aynı PIN\'i bir kez daha girin'
              : 'Uygulamayı her açışınızda sorulur',
          value: _confirmingPin ? _draft.pinConfirm : _draft.pin,
          errorText: _pinPadError,
          onDigit: _pressPinDigit,
          onBackspace: _pinBackspace,
        ),
      ),
      // Parmak izi seçeneği tuş takımının alanını yemesin diye tek satır.
      SwitchListTile(
        value: _draft.biometric,
        onChanged: (v) => setState(() => _draft.biometric = v),
        title: const Text('Parmak izi ile aç'),
        dense: true,
        contentPadding: EdgeInsets.zero,
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
      const DesignSignature(),
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
