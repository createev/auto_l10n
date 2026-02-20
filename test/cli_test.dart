import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CLI generate', () {
    late Directory tempDir;
    late Directory codeDir;
    late Directory outDir;
    late String packageRoot;

    setUpAll(() {
      packageRoot = Directory.current.path;
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('auto_l10n_cli_');
      codeDir = Directory('${tempDir.path}/lib');
      await codeDir.create(recursive: true);
      outDir = Directory('${tempDir.path}/out');
      await outDir.create(recursive: true);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('from-code: scans Text literals and writes app_en.arb', () async {
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(MaterialApp(home: Scaffold(body: Text('Hello World'))));
  Text("Bar");
}
''');
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);

      final arbPath = '${outDir.path}/app_en.arb';
      expect(File(arbPath).existsSync(), isTrue);
      final arb = jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Hello World'], 'Hello World');
      expect(arb['Bar'], 'Bar');
      expect(arb['@@locale'], 'en');
    });

    test('from-code: without --service does not translate', () async {
      await File('${codeDir.path}/main.dart').writeAsString("Text('Only one');");
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 0);
      expect(File('${outDir.path}/app_en.arb').existsSync(), isTrue);
      expect(File('${outDir.path}/app_ru.arb').existsSync(), isFalse);
    });

    test('from-code: with --service=mock writes target locale ARB', () async {
      await File('${codeDir.path}/main.dart').writeAsString("Text('Hi');");
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
          '--service=mock',
          '--target-langs=ru',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 0);
      final ruPath = '${outDir.path}/app_ru.arb';
      expect(File(ruPath).existsSync(), isTrue);
      final arb = jsonDecode(File(ruPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Hi'], '[ru] Hi');
      expect(arb['@@locale'], 'ru');
    });

    test('from-arb: reads source ARB and with --service=mock writes target', () async {
      final l10nDir = Directory('${tempDir.path}/l10n');
      await l10nDir.create(recursive: true);
      await File('${l10nDir.path}/app_en.arb').writeAsString('''
{"@@locale":"en","greeting":"Hello","farewell":"Bye"}
''');
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--from=arb',
          '--input-path=${l10nDir.path}/app_en.arb',
          '--output-path=${outDir.path}',
          '--service=mock',
          '--target-langs=de',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 0);
      final dePath = '${outDir.path}/app_de.arb';
      expect(File(dePath).existsSync(), isTrue);
      final arb = jsonDecode(File(dePath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['greeting'], '[de] Hello');
      expect(arb['farewell'], '[de] Bye');
      expect(arb['@@locale'], 'de');
    });

    test('from-arb: no --service exits 0 and does not create target ARB', () async {
      final l10nDir = Directory('${tempDir.path}/l10n');
      await l10nDir.create(recursive: true);
      await File('${l10nDir.path}/app_en.arb').writeAsString('{"@@locale":"en","a":"A"}');
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--from=arb',
          '--input-path=${l10nDir.path}/app_en.arb',
          '--output-path=${outDir.path}',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('No --service'));
      expect(File('${outDir.path}/app_de.arb').existsSync(), isFalse);
    });

    test('requires --api-key for deepl', () async {
      await File('${codeDir.path}/main.dart').writeAsString("Text('x');");
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
          '--service=deepl',
          '--target-langs=ru',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('api-key'));
    });

    test('from-code: non-existent input-path exits 1', () async {
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${tempDir.path}/nonexistent_lib',
          '--output-path=${outDir.path}',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('not found'));
    });

    test('from-arb: source ARB with no translatable keys exits 1', () async {
      final l10nDir = Directory('${tempDir.path}/l10n');
      await l10nDir.create(recursive: true);
      await File('${l10nDir.path}/app_en.arb').writeAsString('{"@@locale":"en"}');
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--from=arb',
          '--input-path=${l10nDir.path}/app_en.arb',
          '--output-path=${outDir.path}',
          '--service=mock',
          '--target-langs=de',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('No translatable keys'));
    });

    test('from-code: --force overwrites existing key in source ARB', () async {
      await File('${codeDir.path}/main.dart').writeAsString("Text('Original');");
      final result1 = await Process.run(
        'dart',
        ['run', 'auto_l10n', '--input-path=${codeDir.path}', '--output-path=${outDir.path}'],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result1.exitCode, 0);
      final arb1 = jsonDecode(File('${outDir.path}/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
      expect(arb1['Original'], 'Original');

      await File('${codeDir.path}/main.dart').writeAsString("Text('Changed');");
      final result2 = await Process.run(
        'dart',
        ['run', 'auto_l10n', '--input-path=${codeDir.path}', '--output-path=${outDir.path}', '--force'],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result2.exitCode, 0);
      final arb2 = jsonDecode(File('${outDir.path}/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
      expect(arb2['Changed'], 'Changed');
      // --force overwrites/adds keys from current code; old keys may remain
      expect(arb2['@@locale'], 'en');
    });

    test('target-langs equal to source-lang is skipped', () async {
      await File('${codeDir.path}/main.dart').writeAsString("Text('Hi');");
      final result = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
          '--service=mock',
          '--source-lang=en',
          '--target-langs=en,ru',
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result.exitCode, 0);
      expect(File('${outDir.path}/app_ru.arb').existsSync(), isTrue);
      final ruArb = jsonDecode(File('${outDir.path}/app_ru.arb').readAsStringSync()) as Map<String, dynamic>;
      expect(ruArb['Hi'], '[ru] Hi');
    });
  });
}
