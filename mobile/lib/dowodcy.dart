// Panele dowódców: d-ca kompanii (DCA_KP) i d-ca jednostki (DCA_JEDN).
// Jeden ekran z sekcjami - d-ca jednostki widzi tylko zatwierdzanie i ogłoszenia.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'logowanie.dart';
import 'pchor.dart';

class PanelDowodcy extends StatefulWidget {
  const PanelDowodcy({super.key, required this.rola});

  final String rola;

  @override
  State<PanelDowodcy> createState() => _PanelDowodcyState();
}

class _PanelDowodcyState extends State<PanelDowodcy> {
  final _teraz = DateTime.now();

  late Future<List<Map<String, dynamic>>> _konta;
  late Future<List<Map<String, dynamic>>> _ogloszenia;
  late Future<List<Map<String, dynamic>>> _wnioski;
  late Future<List<Map<String, dynamic>>> _wzory;
  late Future<List<Map<String, dynamic>>> _grafiki;

  bool get _dcaKp => widget.rola == 'DCA_KP';

  @override
  void initState() {
    super.initState();
    _wczytaj();
  }

  void _wczytaj() {
    _konta = pobierzOczekujace();
    _ogloszenia = pobierzOgloszenia();
    if (_dcaKp) {
      _wnioski = wnioskiKompanii();
      _wzory = pobierzWzory();
      _grafiki = pobierzGrafiki(_teraz.month, _teraz.year);
    }
  }

  // Wykonuje akcję, pokazuje komunikat i odświeża ekran.
  Future<void> _zrob(Future<void> Function() akcja, String gotowe) async {
    try {
      await akcja();
      if (!mounted) return;
      pokazKomunikat(context, gotowe);
      setState(_wczytaj);
    } catch (e) {
      if (mounted) pokazKomunikat(context, opisBledu(e));
    }
  }

  Future<PlatformFile?> _wybierzPlik(List<String> rozszerzenia) =>
      FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: rozszerzenia,
      );

  Future<bool> _potwierdz(String pytanie) async {
    final tak = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(pytanie),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nie'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tak'),
          ),
        ],
      ),
    );
    return tak == true;
  }

  // ---------------------------------------------------------------- ogłoszenia

  Future<void> _noweOgloszenie() async {
    final tytul = TextEditingController();
    final tresc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _dcaKp ? 'Ogłoszenie dla kompanii' : 'Ogłoszenie dla jednostki',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tytul,
              decoration: const InputDecoration(labelText: 'Tytuł'),
            ),
            TextField(
              controller: tresc,
              decoration: const InputDecoration(labelText: 'Treść'),
              minLines: 3,
              maxLines: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Opublikuj'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (tytul.text.trim().isEmpty || tresc.text.trim().isEmpty) {
      if (mounted) pokazKomunikat(context, 'Tytuł i treść nie mogą być puste.');
      return;
    }
    await _zrob(
      () => dodajOgloszenie(tytul.text.trim(), tresc.text.trim()),
      'Ogłoszenie dodane.',
    );
  }

  // ---------------------------------------------------------------- wnioski

  Future<void> _rozpatrzWniosek(Map<String, dynamic> w) async {
    var status = w['status'] == 'ZŁOŻONY' ? 'ROZPATRYWANY' : w['status'];
    final komentarz = TextEditingController(text: w['comment'] ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, ustaw) => AlertDialog(
          title: Text(w['title']),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w['author']} · ${data(w['created_at'])}'),
              TextButton.icon(
                onPressed: () => otworz(
                  context,
                  '/requests/${w['id']}/file',
                  w['file_name'],
                ),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Otwórz wniosek'),
              ),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in [
                    'ROZPATRYWANY',
                    'ZAAKCEPTOWANY',
                    'ODRZUCONY',
                  ])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (s) => ustaw(() => status = s!),
              ),
              TextField(
                controller: komentarz,
                decoration: const InputDecoration(
                  labelText: 'Komentarz (opcjonalnie)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final tekst = komentarz.text.trim();
    await _zrob(
      () => zmienStatusWniosku(w['id'], status, tekst.isEmpty ? null : tekst),
      'Status wniosku zmieniony.',
    );
  }

  // ---------------------------------------------------------------- grafik służb

  Future<void> _wgrajGrafik() async {
    // do wyboru: bieżący i następny miesiąc
    final miesiace = [
      DateTime(_teraz.year, _teraz.month),
      DateTime(_teraz.year, _teraz.month + 1),
    ];
    var miesiac = miesiace.first;
    final komentarz = TextEditingController();
    PlatformFile? plik;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, ustaw) => AlertDialog(
          title: const Text('Grafik służb'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<DateTime>(
                initialValue: miesiac,
                decoration: const InputDecoration(labelText: 'Miesiąc'),
                items: [
                  for (final m in miesiace)
                    DropdownMenuItem(
                      value: m,
                      child: Text('${miesiaceNazwy[m.month - 1]} ${m.year}'),
                    ),
                ],
                onChanged: (m) => ustaw(() => miesiac = m!),
              ),
              TextField(
                controller: komentarz,
                decoration: const InputDecoration(
                  labelText: 'Komentarz (opcjonalnie)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await _wybierzPlik(['pdf', 'xlsx', 'xls']);
                  if (p != null) ustaw(() => plik = p);
                },
                icon: const Icon(Icons.attach_file),
                label: Text(plik?.name ?? 'Wybierz plik (PDF / Excel)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wgraj'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (plik == null) {
      if (mounted) pokazKomunikat(context, 'Nie wybrano pliku.');
      return;
    }

    final tekst = komentarz.text.trim();
    await _zrob(
      () => wgrajGrafik(
        miesiac.month,
        miesiac.year,
        tekst.isEmpty ? null : tekst,
        plik!,
      ),
      'Grafik wgrany.',
    );
  }

  // ---------------------------------------------------------------- wzory wniosków

  Future<void> _nowyWzor() async {
    final nazwa = TextEditingController();
    PlatformFile? plik;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, ustaw) => AlertDialog(
          title: const Text('Nowy wzór wniosku'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nazwa,
                decoration: const InputDecoration(
                  labelText: 'Nazwa (np. Wniosek o przepustkę)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await _wybierzPlik(['docx', 'doc']);
                  if (p != null) ustaw(() => plik = p);
                },
                icon: const Icon(Icons.attach_file),
                label: Text(plik?.name ?? 'Wybierz plik Word'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Dodaj'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nazwa.text.trim().isEmpty || plik == null) {
      if (mounted) pokazKomunikat(context, 'Podaj nazwę i wybierz plik.');
      return;
    }
    await _zrob(() => dodajWzor(nazwa.text.trim(), plik!), 'Wzór dodany.');
  }

  Future<void> _akcjaWzoru(Map<String, dynamic> w, String akcja) async {
    switch (akcja) {
      case 'otworz':
        await otworz(context, '/templates/${w['id']}/file', w['file_name']);
      case 'podmien':
        final plik = await _wybierzPlik(['docx', 'doc']);
        if (plik != null) {
          await _zrob(
            () => aktualizujWzor(w['id'], plik),
            'Wzór zaktualizowany.',
          );
        }
      case 'usun':
        if (await _potwierdz('Usunąć wzór "${w['name']}"?')) {
          await _zrob(() => usunWzor(w['id']), 'Wzór usunięty.');
        }
    }
  }

  // ---------------------------------------------------------------- ekran

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dcaKp ? 'Dowódca kompanii' : 'Dowódca jednostki'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Wyloguj',
            onPressed: () => wyloguj(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_wczytaj),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Naglowek(
              _dcaKp
                  ? 'Podchorążowie do zatwierdzenia'
                  : 'Dowódcy kompanii do zatwierdzenia',
            ),
            Wczytywanie(dane: _konta, zbuduj: _listaKont),
            Naglowek(
              'Ogłoszenia',
              akcja: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nowe ogłoszenie',
                onPressed: _noweOgloszenie,
              ),
            ),
            Wczytywanie(dane: _ogloszenia, zbuduj: _listaOgloszen),
            if (_dcaKp) ...[
              const Naglowek('Wnioski kompanii'),
              Wczytywanie(dane: _wnioski, zbuduj: _listaWnioskow),
              Naglowek(
                'Grafik służb',
                akcja: IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: 'Wgraj grafik',
                  onPressed: _wgrajGrafik,
                ),
              ),
              Wczytywanie(dane: _grafiki, zbuduj: _listaGrafikow),
              Naglowek(
                'Wzory wniosków',
                akcja: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Nowy wzór',
                  onPressed: _nowyWzor,
                ),
              ),
              Wczytywanie(dane: _wzory, zbuduj: _listaWzorow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _listaKont(List<Map<String, dynamic>> konta) {
    if (konta.isEmpty) {
      return const ListTile(title: Text('Brak kont oczekujących.'));
    }
    return Column(
      children: [
        for (final k in konta)
          ListTile(
            title: Text('${k['first_name']} ${k['last_name']}'),
            subtitle: Text(
              [
                if (k['rank'] != null) k['rank'],
                if (k['company_number'] != null)
                  '${k['company_number']} kompania',
                if (k['study_group'] != null) k['study_group'],
                k['email'],
              ].join(' · '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Zatwierdź',
                  onPressed: () => _zrob(
                    () => zatwierdzKonto(k['id']),
                    'Konto zatwierdzone.',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFDC143C)),
                  tooltip: 'Odrzuć',
                  onPressed: () =>
                      _zrob(() => odrzucKonto(k['id']), 'Konto odrzucone.'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _listaOgloszen(List<Map<String, dynamic>> ogloszenia) {
    if (ogloszenia.isEmpty) {
      return const ListTile(title: Text('Brak ogłoszeń.'));
    }
    return Column(
      children: [
        for (final o in ogloszenia)
          ListTile(
            title: Text(o['title']),
            subtitle: Text(
              '${o['body']}\n'
              '${o['company_number'] == null ? 'cała jednostka' : '${o['company_number']} kompania'}'
              ' · ${data(o['created_at'])}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: o['mine'] || !_dcaKp
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Usuń',
                    onPressed: () async {
                      if (await _potwierdz('Usunąć ogłoszenie?')) {
                        await _zrob(
                          () => usunOgloszenie(o['id']),
                          'Ogłoszenie usunięte.',
                        );
                      }
                    },
                  )
                : null,
          ),
      ],
    );
  }

  Widget _listaWnioskow(List<Map<String, dynamic>> wnioski) {
    if (wnioski.isEmpty) {
      return const ListTile(title: Text('Brak wniosków.'));
    }
    return Column(
      children: [
        for (final w in wnioski)
          ListTile(
            title: Text(w['title']),
            subtitle: Text('${w['author']} · ${data(w['created_at'])}'),
            trailing: Text(
              w['status'],
              style: TextStyle(
                color: kolorStatusu(w['status']),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            onTap: () => _rozpatrzWniosek(w),
          ),
      ],
    );
  }

  Widget _listaGrafikow(List<Map<String, dynamic>> grafiki) {
    final moje = grafiki.where((g) => g['own']).toList();
    final nazwaMiesiaca =
        '${miesiaceNazwy[_teraz.month - 1].toLowerCase()} ${_teraz.year}';
    if (moje.isEmpty) {
      return ListTile(title: Text('Brak grafiku na $nazwaMiesiaca.'));
    }
    return Column(
      children: [
        for (final g in moje)
          ListTile(
            leading: const Icon(Icons.event_note),
            title: Text('Grafik na $nazwaMiesiaca'),
            subtitle: Text(
              [
                g['file_name'],
                if (g['comment'] != null) g['comment'],
              ].join(' · '),
            ),
            onTap: () =>
                otworz(context, '/duties/${g['id']}/file', g['file_name']),
          ),
      ],
    );
  }

  Widget _listaWzorow(List<Map<String, dynamic>> wzory) {
    if (wzory.isEmpty) {
      return const ListTile(title: Text('Brak wzorów - dodaj pierwszy (+).'));
    }
    return Column(
      children: [
        for (final w in wzory)
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(w['name']),
            subtitle: Text(
              '${w['file_name']} · ${data(w['updated_at'], zGodzina: false)}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (a) => _akcjaWzoru(w, a),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'otworz', child: Text('Otwórz')),
                PopupMenuItem(value: 'podmien', child: Text('Podmień plik')),
                PopupMenuItem(value: 'usun', child: Text('Usuń')),
              ],
            ),
          ),
      ],
    );
  }
}
