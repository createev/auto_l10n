import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceholderGuard', () {
    test('{name} is protected and restored', () {
      final (protected, placeholders) =
          PlaceholderGuard.protect('Hello {name}!');

      expect(protected, 'Hello <x id="ph_0"/>!');
      expect(placeholders, ['{name}']);

      final restored =
          PlaceholderGuard.restore('Привет <x id="ph_0"/>!', placeholders);
      expect(restored, 'Привет {name}!');
    });

    test('\$variable is protected and restored', () {
      final (protected, placeholders) =
          PlaceholderGuard.protect('Count: \$count items');

      expect(protected, contains('<x id="ph_0"/>'));
      expect(placeholders, ['\$count']);

      final restored = PlaceholderGuard.restore(protected, placeholders);
      expect(restored, 'Count: \$count items');
    });

    test('multiple placeholders work', () {
      final (protected, placeholders) = PlaceholderGuard.protect(
        'Hello {name}, you have {count} items',
      );

      expect(placeholders.length, 2);
      expect(protected, contains('<x id="ph_0"/>'));
      expect(protected, contains('<x id="ph_1"/>'));

      final restored = PlaceholderGuard.restore(
        'Привет <x id="ph_0"/>, у вас <x id="ph_1"/> товаров',
        placeholders,
      );
      expect(restored, 'Привет {name}, у вас {count} товаров');
    });

    test('{{double braces}} are protected', () {
      final (protected, placeholders) =
          PlaceholderGuard.protect('Value: {{amount}}');

      expect(placeholders.isNotEmpty, true);

      final restored = PlaceholderGuard.restore(protected, placeholders);
      expect(restored, 'Value: {{amount}}');
    });

    test('strings without placeholders pass through unchanged', () {
      final (protected, placeholders) =
          PlaceholderGuard.protect('Hello World');

      expect(protected, 'Hello World');
      expect(placeholders, isEmpty);

      final restored = PlaceholderGuard.restore(protected, placeholders);
      expect(restored, 'Hello World');
    });

    test('restore with empty placeholders list returns text unchanged', () {
      const text = 'Translated text';
      final restored = PlaceholderGuard.restore(text, []);
      expect(restored, text);
    });

    test('mixed placeholder types in one string', () {
      final (protected, placeholders) =
          PlaceholderGuard.protect('Hi {name}, count: \$count, total: {{total}}');

      expect(placeholders.length, 3);
      expect(placeholders, contains('{name}'));
      expect(placeholders, contains('\$count'));
      expect(placeholders, contains('{{total}}'));
      expect(protected, contains('<x id="ph_0"/>'));
      expect(protected, contains('<x id="ph_1"/>'));
      expect(protected, contains('<x id="ph_2"/>'));

      final restored = PlaceholderGuard.restore(
        'Привет <x id="ph_1"/>, всего <x id="ph_2"/>, итого: <x id="ph_0"/>',
        placeholders,
      );
      expect(restored, 'Привет {name}, всего \$count, итого: {{total}}');
    });
  });
}
