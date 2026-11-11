// Panele dowódców: d-ca kompanii (DCA_KP) i d-ca jednostki (DCA_JEDN).
import 'package:flutter/material.dart';

import 'api.dart';
import 'logowanie.dart';

class PanelDowodcy extends StatefulWidget {
  const PanelDowodcy({super.key, required this.rola});

  final String rola;

  @override
  State<PanelDowodcy> createState() => _PanelDowodcyState();
}

class _PanelDowodcyState extends State<PanelDowodcy> {
  List<Map<String, dynamic>> _konta = [];
  bool _ladowanie = true;

  @override
  void initState() {
    super.initState();
    _wczytaj();
  }

  void _pokaz(String tekst) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tekst)));

  Future<void> _wczytaj() async {
    try {
      final konta = await pobierzOczekujace();
      if (mounted) setState(() => _konta = konta);
    } catch (e) {
      if (mounted) _pokaz(opisBledu(e));
    } finally {
      if (mounted) setState(() => _ladowanie = false);
    }
  }

  Future<void> _rozpatrz(Map<String, dynamic> konto, bool zatwierdz) async {
    try {
      if (zatwierdz) {
        await zatwierdzKonto(konto['id']);
      } else {
        await odrzucKonto(konto['id']);
      }
      if (!mounted) return;
      setState(() => _konta.remove(konto));
      _pokaz(zatwierdz ? 'Konto zatwierdzone.' : 'Konto odrzucone.');
    } catch (e) {
      if (mounted) _pokaz(opisBledu(e));
    }
  }

  // Np. "kpr. · 3 kompania · WCY23KB1S0 · jan@wat.edu.pl"
  String _opis(Map<String, dynamic> k) => [
    if (k['rank'] != null) k['rank'],
    if (k['company_number'] != null) '${k['company_number']} kompania',
    if (k['study_group'] != null) k['study_group'],
    k['email'],
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final jednostka = widget.rola == 'DCA_JEDN';

    return Scaffold(
      appBar: AppBar(
        title: Text(jednostka ? 'Dowódca jednostki' : 'Dowódca kompanii'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Wyloguj',
            onPressed: () => wyloguj(context),
          ),
        ],
      ),
      body: _ladowanie
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _wczytaj,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    jednostka
                        ? 'Dowódcy kompanii do zatwierdzenia'
                        : 'Podchorążowie do zatwierdzenia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_konta.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('Brak kont oczekujących.'),
                    ),
                  for (final k in _konta)
                    Card(
                      child: ListTile(
                        title: Text('${k['first_name']} ${k['last_name']}'),
                        subtitle: Text(_opis(k)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              tooltip: 'Zatwierdź',
                              onPressed: () => _rozpatrz(k, true),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              tooltip: 'Odrzuć',
                              onPressed: () => _rozpatrz(k, false),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
