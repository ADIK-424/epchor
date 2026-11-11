// Ekrany logowania i rejestracji.
import 'package:flutter/material.dart';

import 'api.dart';
import 'dowodcy.dart';
import 'pchor.dart';

// Zamienia błąd z zapytania na tekst dla użytkownika.
String opisBledu(Object e) =>
    e is BladApi ? e.komunikat : 'Brak połączenia z serwerem.';

// Usuwa token i wraca do logowania, czyszcząc historię ekranów.
void wyloguj(BuildContext context) {
  token = null;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const EkranLogowania()),
    (_) => false,
  );
}

String? _wymagane(String? w) =>
    (w == null || w.trim().isEmpty) ? 'Pole wymagane' : null;

String? _poprawnyEmail(String? w) =>
    (w == null || !w.contains('@')) ? 'Podaj poprawny e-mail' : null;

// ---------------------------------------------------------------- logowanie

class EkranLogowania extends StatefulWidget {
  const EkranLogowania({super.key});

  @override
  State<EkranLogowania> createState() => _EkranLogowaniaState();
}

class _EkranLogowaniaState extends State<EkranLogowania> {
  final _formularz = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _haslo = TextEditingController();
  bool _wysylanie = false;

  @override
  void dispose() {
    _email.dispose();
    _haslo.dispose();
    super.dispose();
  }

  Future<void> _zaloguj() async {
    if (!_formularz.currentState!.validate()) return;
    setState(() => _wysylanie = true);
    try {
      final rola = await zaloguj(_email.text.trim(), _haslo.text);
      if (!mounted) return;
      // pushReplacement: przycisk "wstecz" nie wróci już do logowania
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              rola == 'PCHOR' ? const PanelPchora() : PanelDowodcy(rola: rola),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(opisBledu(e))));
    } finally {
      if (mounted) setState(() => _wysylanie = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ePchor')),
      body: Form(
        key: _formularz,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Logowanie',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
              validator: _poprawnyEmail,
            ),
            TextFormField(
              controller: _haslo,
              decoration: const InputDecoration(labelText: 'Hasło'),
              obscureText: true,
              validator: _wymagane,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _wysylanie ? null : _zaloguj,
              child: Text(_wysylanie ? 'Logowanie…' : 'Zaloguj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EkranRejestracji()),
              ),
              child: const Text('Nie masz konta? Zarejestruj się'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- rejestracja

class EkranRejestracji extends StatefulWidget {
  const EkranRejestracji({super.key});

  @override
  State<EkranRejestracji> createState() => _EkranRejestracjiState();
}

class _EkranRejestracjiState extends State<EkranRejestracji> {
  final _formularz = GlobalKey<FormState>();
  final _imie = TextEditingController();
  final _nazwisko = TextEditingController();
  final _stopien = TextEditingController();
  final _grupa = TextEditingController();
  final _email = TextEditingController();
  final _haslo = TextEditingController();

  String _rola = 'PCHOR';
  int? _kompaniaId;
  List<Kompania> _kompanie = [];
  bool _wysylanie = false;

  @override
  void initState() {
    super.initState();
    _wczytajKompanie();
  }

  @override
  void dispose() {
    for (final c in [_imie, _nazwisko, _stopien, _grupa, _email, _haslo]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pokaz(String tekst) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tekst)));

  Future<void> _wczytajKompanie() async {
    try {
      final lista = await pobierzKompanie();
      if (mounted) setState(() => _kompanie = lista);
    } catch (e) {
      if (mounted) _pokaz(opisBledu(e));
    }
  }

  // Puste pole opcjonalne wysyłamy jako null, a nie jako pusty tekst.
  String? _alboNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _zarejestruj() async {
    if (!_formularz.currentState!.validate()) return;
    setState(() => _wysylanie = true);
    try {
      await zarejestruj(
        email: _email.text.trim(),
        haslo: _haslo.text,
        rola: _rola,
        imie: _imie.text.trim(),
        nazwisko: _nazwisko.text.trim(),
        kompaniaId: _kompaniaId!,
        stopien: _alboNull(_stopien),
        grupa: _rola == 'PCHOR' ? _alboNull(_grupa) : null,
      );
      if (!mounted) return;
      _pokaz('Konto utworzone. Poczekaj na zatwierdzenie przez dowódcę.');
      Navigator.of(context).pop(); // powrót do logowania
    } catch (e) {
      if (mounted) _pokaz(opisBledu(e));
    } finally {
      if (mounted) setState(() => _wysylanie = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejestracja')),
      body: Form(
        key: _formularz,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PCHOR', label: Text('Podchorąży')),
                ButtonSegment(value: 'DCA_KP', label: Text('Dowódca kompanii')),
              ],
              selected: {_rola},
              onSelectionChanged: (wybor) =>
                  setState(() => _rola = wybor.first),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _imie,
              decoration: const InputDecoration(labelText: 'Imię'),
              validator: _wymagane,
            ),
            TextFormField(
              controller: _nazwisko,
              decoration: const InputDecoration(labelText: 'Nazwisko'),
              validator: _wymagane,
            ),
            TextFormField(
              controller: _stopien,
              decoration: const InputDecoration(
                labelText: 'Stopień (opcjonalnie)',
              ),
            ),
            if (_rola == 'PCHOR')
              TextFormField(
                controller: _grupa,
                decoration: const InputDecoration(
                  labelText: 'Grupa wydziałowa (np. WCY23KB1S0)',
                ),
              ),
            DropdownButtonFormField<int>(
              initialValue: _kompaniaId,
              decoration: const InputDecoration(labelText: 'Kompania'),
              items: [
                for (final k in _kompanie)
                  DropdownMenuItem(value: k.id, child: Text(k.nazwa)),
              ],
              onChanged: (id) => setState(() => _kompaniaId = id),
              validator: (id) => id == null ? 'Wybierz kompanię' : null,
            ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
              validator: _poprawnyEmail,
            ),
            TextFormField(
              controller: _haslo,
              decoration: const InputDecoration(
                labelText: 'Hasło (min. 8 znaków)',
              ),
              obscureText: true,
              validator: (w) => (w == null || w.length < 8)
                  ? 'Hasło musi mieć co najmniej 8 znaków'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _wysylanie ? null : _zarejestruj,
              child: Text(_wysylanie ? 'Wysyłanie…' : 'Zarejestruj'),
            ),
          ],
        ),
      ),
    );
  }
}
