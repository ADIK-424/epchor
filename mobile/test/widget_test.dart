import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epchor/main.dart';
import 'package:epchor/pchor.dart';

void main() {
  testWidgets('aplikacja startuje od ekranu logowania', (tester) async {
    await tester.pumpWidget(const EpchorApp());
    expect(find.text('Zaloguj'), findsOneWidget);
  });

  testWidgets('panel pchora pokazuje dolny pasek zakładek', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PanelPchora()));
    expect(find.text('Służby'), findsOneWidget);
  });
}
