// Punkt startowy aplikacji ePchor
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pchor.dart';

const kolorGranat = Color(0xFF14213D);
const kolorCzerwony = Color(0xFFDC143C);

void main() {
  runApp(const EpchorApp());
}

class EpchorApp extends StatelessWidget {
  const EpchorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ePchor',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kolorGranat,
          primary: kolorGranat,
          secondary: kolorCzerwony,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: kolorGranat,
          foregroundColor: Colors.white,
        ),
      ),
      home: const PanelPchora(),
    );
  }
}
