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
      final arb =
          jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Hello World'], 'Hello World');
      expect(arb['Bar'], 'Bar');
      expect(arb['@@locale'], 'en');
    });

    test('from-code: scans RichText/TextSpan and named UI fields', () async {
      await File('${codeDir.path}/main.dart').writeAsString(r'''
import 'package:flutter/material.dart';

class Benefit {
  final String title;
  final String description;
  const Benefit({required this.title, required this.description});
}

const benefits = [
  Benefit(
    title: 'Pay off debt months earlier',
    description: 'Smart strategies automatically reduce interest',
  ),
];

Widget view() {
  return Column(
    children: [
      RichText(
        text: const TextSpan(
          text: 'Stop guessing. Start ',
          children: [TextSpan(text: 'accelerating')],
        ),
      ),
      const Text('Restore purchases'),
    ],
  );
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
      final arbPath = '${outDir.path}/app_en.arb';
      final arb =
          jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Stop guessing. Start'], 'Stop guessing. Start');
      expect(arb['accelerating'], 'accelerating');
      expect(arb['Pay off debt months earlier'], 'Pay off debt months earlier');
      expect(
        arb['Smart strategies automatically reduce interest'],
        'Smart strategies automatically reduce interest',
      );
      expect(arb['Restore purchases'], 'Restore purchases');
    });

    test('from-code: covers debt-free-box paywall patterns', () async {
      await File('${codeDir.path}/main.dart').writeAsString(r'''
import 'package:flutter/material.dart';

class Benefit {
  final String title;
  final String description;
  const Benefit({required this.title, required this.description});
}

const benefits = [
  Benefit(
    title: 'Pay off debt months earlier',
    description: 'Smart strategies automatically reduce interest',
  ),
];

void _showSnackBar(String message) {}

class Paywall extends StatelessWidget {
  const Paywall({super.key, required this.isBusy});
  final bool isBusy;

  Widget _buildMainTitleLine(String prefix, String highlight, String suffix) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(text: highlight),
          TextSpan(text: suffix),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _showSnackBar('Store is unavailable');
    _showSnackBar('Error: $e');
    const String? msg = null;
    _showSnackBar(
      (msg != null && msg.isNotEmpty) ? msg : 'Purchase failed',
    );
    _showSnackBar(
      (msg != null && msg.isNotEmpty) ? msg : 'No purchases to restore',
    );
    return Column(
      children: [
        _radioRow('None', 'Pay minimums only', Strategy.none),
        _buildMainTitleLine('Stop guessing. Start ', 'accelerating', '.'),
        Text(isBusy ? 'Processing…' : 'Pay Off Debts Faster'),
        const Text('Restore purchases'),
        const Text('Free version includes'),
        const Text('PRO unlocks:'),
      ],
    );
  }
}

enum Strategy { none }
Widget _radioRow(String title, String subtitle, Strategy s) => const SizedBox();
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
      final arbPath = '${outDir.path}/app_en.arb';
      final arb =
          jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Pay off debt months earlier'], 'Pay off debt months earlier');
      expect(
        arb['Smart strategies automatically reduce interest'],
        'Smart strategies automatically reduce interest',
      );
      expect(arb['Stop guessing. Start'], 'Stop guessing. Start');
      expect(arb['accelerating'], 'accelerating');
      expect(arb['Processing…'], 'Processing…');
      expect(arb['Pay Off Debts Faster'], 'Pay Off Debts Faster');
      expect(arb['Restore purchases'], 'Restore purchases');
      expect(arb['Store is unavailable'], 'Store is unavailable');
      expect(arb['Error: \$e'], 'Error: \$e');
      expect(arb['Purchase failed'], 'Purchase failed');
      expect(arb['No purchases to restore'], 'No purchases to restore');
      expect(arb['None'], 'None');
      expect(arb['Pay minimums only'], 'Pay minimums only');
      expect(arb['Free version includes'], 'Free version includes');
      expect(arb['PRO unlocks:'], 'PRO unlocks:');
    });

    test('from-code: resolves static const references used in Text', () async {
      await File('${codeDir.path}/main.dart').writeAsString(r'''
import 'package:flutter/material.dart';

class PaywallStrings {
  static const String moreFeaturesText = 'More Pro features coming.';
  static const String extraMonthly = 'Extra monthly payment';
}

Widget view() {
  return const Column(
    children: [
      Text(PaywallStrings.moreFeaturesText),
      Text(PaywallStrings.extraMonthly),
    ],
  );
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
      final arbPath = '${outDir.path}/app_en.arb';
      final arb =
          jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['More Pro features coming.'], 'More Pro features coming.');
      expect(arb['Extra monthly payment'], 'Extra monthly payment');
    });

    test('from-code: without --service does not translate', () async {
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('Only one'))));
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
      expect(File('${outDir.path}/app_en.arb').existsSync(), isTrue);
      expect(File('${outDir.path}/app_ru.arb').existsSync(), isFalse);
    });

    test('from-code: with --service=mock writes target locale ARB', () async {
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('Hi'))));
}
''');
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
      final arb =
          jsonDecode(File(ruPath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['Hi'], '[ru] Hi');
      expect(arb['@@locale'], 'ru');
    });

    test('from-arb: reads source ARB and with --service=mock writes target',
        () async {
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
      final arb =
          jsonDecode(File(dePath).readAsStringSync()) as Map<String, dynamic>;
      expect(arb['greeting'], '[de] Hello');
      expect(arb['farewell'], '[de] Bye');
      expect(arb['@@locale'], 'de');
    });

    test('from-arb: no --service exits 0 and does not create target ARB',
        () async {
      final l10nDir = Directory('${tempDir.path}/l10n');
      await l10nDir.create(recursive: true);
      await File('${l10nDir.path}/app_en.arb')
          .writeAsString('{"@@locale":"en","a":"A"}');
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
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('x'))));
}
''');
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
      await File('${l10nDir.path}/app_en.arb')
          .writeAsString('{"@@locale":"en"}');
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
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('Original'))));
}
''');
      final result1 = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}'
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result1.exitCode, 0);
      final arb1 =
          jsonDecode(File('${outDir.path}/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(arb1['Original'], 'Original');

      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('Changed'))));
}
''');
      final result2 = await Process.run(
        'dart',
        [
          'run',
          'auto_l10n',
          '--input-path=${codeDir.path}',
          '--output-path=${outDir.path}',
          '--force'
        ],
        workingDirectory: packageRoot,
        runInShell: false,
      );
      expect(result2.exitCode, 0);
      final arb2 =
          jsonDecode(File('${outDir.path}/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(arb2['Changed'], 'Changed');
      // --force overwrites/adds keys from current code; old keys may remain
      expect(arb2['@@locale'], 'en');
    });

    test('target-langs equal to source-lang is skipped', () async {
      await File('${codeDir.path}/main.dart').writeAsString('''
import 'package:flutter/material.dart';
void main() {
  runApp(const MaterialApp(home: Scaffold(body: Text('Hi'))));
}
''');
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
      final ruArb =
          jsonDecode(File('${outDir.path}/app_ru.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(ruArb['Hi'], '[ru] Hi');
    });
  });
}
