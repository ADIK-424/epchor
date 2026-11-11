// Panele dowódców: d-ca kompanii (DCA_KP) i d-ca jednostki (DCA_JEDN).
import 'package:flutter/material.dart';

class PanelDowodcy extends StatelessWidget {
  const PanelDowodcy({super.key, required this.rola});

  final String rola;

  @override
  Widget build(BuildContext context) {
    final tytul = rola == 'DCA_JEDN' ? 'Dowódca jednostki' : 'Dowódca kompanii';
    return Scaffold(
      appBar: AppBar(title: Text(tytul)),
      body: const Center(
        child: Text('Tu będzie zatwierdzanie kont i ogłoszenia.'),
      ),
    );
  }
}
