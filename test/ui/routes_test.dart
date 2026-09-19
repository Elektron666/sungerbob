import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sungerbob/ui/app_router.dart';

/// **Ölü bağlantı avcısı.**
///
/// Ana sayfadaki büyüteç bir zamanlar `/search`'e gidiyordu ama rota
/// tanımlı değildi: düğme hiçbir şey yapmıyordu ve kimse fark etmedi.
/// Arama sonuçları da olmayan iki rotaya bağlıydı. Elle tutulan bir rota
/// listesi bunu yakalayamaz — yeni bir düğme eklendiğinde listeye
/// eklemeyi unutursun.
///
/// Bu test kaynağı tarar: `context.push('/…')`, `context.go('/…')` ve
/// menü tablolarındaki `route: '/…'` ne varsa bulur ve hepsinin
/// yönlendiricide karşılığı olduğunu doğrular.
void main() {
  test('gidilen her rota tanımlı — ölü bağlantı yok', () {
    final defined = <String>{};
    void collect(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) defined.add(route.path);
        collect(route.routes);
      }
    }

    collect(buildRouter().configuration.routes);
    expect(defined, isNotEmpty, reason: 'yönlendirici boş okundu');

    final navigation = RegExp(
      r"""(?:context\.(?:push|go|replace)|route:\s*)\(?\s*'(/[^']*)'""",
    );

    final targets = <String, String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final m in navigation.allMatches(file.readAsStringSync())) {
        targets[m.group(1)!] = file.path;
      }
    }

    expect(
      targets,
      isNotEmpty,
      reason: 'hiç gezinme bulunamadı — tarama bozulmuş olabilir',
    );

    for (final entry in targets.entries) {
      expect(
        _matches(entry.key, defined),
        isTrue,
        reason:
            '${entry.value} dosyası ${entry.key} rotasına gidiyor ama '
            'yönlendiricide böyle bir rota yok (ölü bağlantı).',
      );
    }
  });
}

/// Hedef yol, tanımlı rotalardan birine uyuyor mu?
///
/// `/customers/${row.id}` gibi değişken içeren parçalar, tanımdaki
/// `:id` yer tutucusuna denk gelir.
bool _matches(String target, Set<String> defined) {
  final targetParts = target.split('/');
  return defined.any((route) {
    final parts = route.split('/');
    if (parts.length != targetParts.length) return false;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].startsWith(':')) continue;
      if (targetParts[i].contains(r'$')) continue;
      if (parts[i] != targetParts[i]) return false;
    }
    return true;
  });
}
