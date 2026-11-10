// Panel podchorążego
import 'package:flutter/material.dart';

class PanelPchora extends StatefulWidget {
  const PanelPchora({super.key});

  @override
  State<PanelPchora> createState() => _PanelPchoraState();
}

class _PanelPchoraState extends State<PanelPchora> {
  int _zakladka = 2; //zakladka startowa

  static const _tytuly = ['Służby', 'Wnioski', 'Start', 'Plan zajęć', 'Profil'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tytuly[_zakladka])),
      body: Center(child: Text('Tu będzie: ${_tytuly[_zakladka]}')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _zakladka,
        onDestinationSelected: (i) => setState(() => _zakladka = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            label: 'Służby',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            label: 'Wnioski',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}