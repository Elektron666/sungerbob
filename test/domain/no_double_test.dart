@Tags(['guard'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BRIEF §2: para ve m³ hesabında `double` kullanmak YASAK.
/// BRIEF §2: `domain` katmanı Flutter'a bağımlı olamaz.
///
/// Bu testler kaynağı tarar; lint kuralları CI'da sessizce atlanabildiği için
/// koruma `flutter test` ile her koşuda çalışır (DECISIONS D-19).
void main() {
  final domainDir = Directory('lib/domain');
  final dataDir = Directory('lib/data');

  List<File> dartFiles(Directory d) => d.existsSync()
      ? d
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))
            .where((f) => !f.path.endsWith('.drift.dart'))
            .toList()
      : <File>[];

  test('domain ve data katmanında double/num kullanılmıyor', () {
    final offenders = <String>[];
    final banned = RegExp(
      r'(^|[^\w])(double|num)\s+\w+|\.toDouble\(\)|double\.parse|num\.parse',
    );

    for (final file in [...dartFiles(domainDir), ...dartFiles(dataDir)]) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('ignore: allowed-double')) continue;
        if (banned.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Para ve m³ hesabında double YASAK (BRIEF §2). Bulunanlar:\n'
          '${offenders.join('\n')}',
    );
  });

  test('domain katmanı Flutter\'a bağımlı değil', () {
    final offenders = <String>[];
    for (final file in dartFiles(domainDir)) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'''import\s+['"]package:(flutter|drift)/''')
            .hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'domain saf Dart kalmalı (BRIEF §2). Bulunanlar:\n'
          '${offenders.join('\n')}',
    );
  });

  test('yuvarlama yalnızca rounding.dart içinde tanımlı', () {
    final offenders = <String>[];
    for (final file in [...dartFiles(domainDir), ...dartFiles(dataDir)]) {
      if (file.path.endsWith('rounding.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('ignore: allowed-double')) continue;
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (RegExp(r'\.round\(\)|\.ceil\(\)|toStringAsFixed\(')
            .hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Tek yuvarlama kaynağı roundHalfUp (BRIEF §3.3). Bulunanlar:\n'
          '${offenders.join('\n')}',
    );
  });
}
