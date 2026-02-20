import 'package:flutter_test/flutter_test.dart';

import 'package:auto_l10n_example/main.dart';

void main() {
  testWidgets('Example app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Hello World'), findsOneWidget);
    expect(find.text('Welcome to auto_l10n'), findsOneWidget);
  });
}
