import 'package:flutter_test/flutter_test.dart';

import 'package:epchor/main.dart';

void main() {
  testWidgets('panel pchora pokazuje dolny pasek zakładek', (tester) async {
    await tester.pumpWidget(const EpchorApp());
    expect(find.text('Służby'), findsOneWidget);
  });
}
