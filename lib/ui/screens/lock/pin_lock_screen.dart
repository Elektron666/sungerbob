import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/pin_pad.dart';

/// Uygulama kilidi (BRIEF §5).
///
/// Uygulama her açılışta ve arka plandan dönüşte kilitlidir. Yanlış PIN
/// denemeleri artan gecikmeyle cezalandırılır; veri **silinmez** — tek
/// kullanıcılı bir cihazda silme, yanlışlıkla veri kaybı riskidir (D-04).
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _error;
  int _attempts = 0;
  bool _busy = false;

  /// 5 yanlış denemeden sonra 30 saniye beklenir.
  static const _lockAfter = 5;
  static const _cooldown = Duration(seconds: 30);
  DateTime? _blockedUntil;

  Duration get _remainingBlock {
    final until = _blockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _digit(String digit) {
    if (_pin.length >= PinPad.pinLength || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == PinPad.pinLength) _verify();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    if (_remainingBlock > Duration.zero) {
      setState(() {
        _error =
            '${_remainingBlock.inSeconds} saniye sonra tekrar deneyebilirsiniz';
        _pin = '';
      });
      return;
    }

    setState(() => _busy = true);
    final settings = await ref.read(settingsRepositoryProvider.future);
    final ok = await settings.verifyPin(_pin);
    if (!mounted) return;

    if (ok) {
      _attempts = 0;
      ref.read(appLockProvider.notifier).unlock();
      setState(() {
        _busy = false;
        _pin = '';
        _error = null;
      });
      return;
    }

    _attempts++;
    setState(() {
      _busy = false;
      _pin = '';
      if (_attempts >= _lockAfter) {
        _blockedUntil = DateTime.now().add(_cooldown);
        _attempts = 0;
        _error =
            'Çok fazla yanlış deneme. ${_cooldown.inSeconds} saniye bekleyin.';
      } else {
        _error = 'PIN hatalı (${_lockAfter - _attempts} deneme kaldı)';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: _busy
                ? const LoadingState()
                : PinPad(
                    title: 'PIN',
                    subtitle: 'Devam etmek için PIN girin',
                    value: _pin,
                    errorText: _error,
                    onDigit: _digit,
                    onBackspace: _backspace,
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Maliyeti gizle" modunu kapatmak için PIN sorar (BRIEF §5).
///
/// Doğru PIN girilirse `true` döner.
Future<bool> askPin(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _PinDialog(),
  );
  return result ?? false;
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog();

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  String _pin = '';
  String? _error;

  void _digit(String digit) {
    if (_pin.length >= PinPad.pinLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == PinPad.pinLength) _verify();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    final settings = await ref.read(settingsRepositoryProvider.future);
    final ok = await settings.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _pin = '';
        _error = 'PIN hatalı';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: SingleChildScrollView(
      child: PinPad(
        title: 'PIN gerekli',
        subtitle: 'Maliyetleri göstermek için PIN girin',
        value: _pin,
        errorText: _error,
        onDigit: _digit,
        onBackspace: _backspace,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Vazgeç'),
      ),
    ],
  );
}
