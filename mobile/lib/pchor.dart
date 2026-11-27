// Panel podchorążego: 5 zakładek z dolnym paskiem.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'logowanie.dart';
import 'powiadomienia.dart';

const _dniTygodnia = [
  'Poniedziałek',
  'Wtorek',
  'Środa',
  'Czwartek',
  'Piątek',
  'Sobota',
  'Niedziela',
];

const miesiaceNazwy = [
  'Styczeń',
  'Luty',
  'Marzec',
  'Kwiecień',
  'Maj',
  'Czerwiec',
  'Lipiec',
  'Sierpień',
  'Wrzesień',
  'Październik',
  'Listopad',
  'Grudzień',
];

class PanelPchora extends StatefulWidget {
  const PanelPchora({super.key});

  @override
  State<PanelPchora> createState() => _PanelPchoraState();
}

class _PanelPchoraState extends State<PanelPchora> {
  int _zakladka = 2; //zakladka startowa

  static const _tytuly = ['Służby', 'Wnioski', 'Start', 'Plan zajęć', 'Profil'];

  @override
  void initState() {
    super.initState();
    // przypomnienia o zajęciach - jak się nie uda (np. brak internetu), aplikacja działa dalej
    zaplanujPrzypomnienia().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ekrany = [
      const ZakladkaSluzby(),
      const ZakladkaWnioski(),
      const ZakladkaStart(),
      const ZakladkaPlan(),
      const ZakladkaProfil(),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_tytuly[_zakladka])),
      body: ekrany[_zakladka],
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

// ---------------------------------------------------------------- wspólne kawałki (używane też w dowodcy.dart)

// FutureBuilder z kółkiem ładowania i komunikatem błędu, żeby nie pisać tego w każdej zakładce.
class Wczytywanie<T> extends StatelessWidget {
  const Wczytywanie({super.key, required this.dane, required this.zbuduj});

  final Future<T> dane;
  final Widget Function(T) zbuduj;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: dane,
      builder: (context, stan) {
        if (stan.hasError) {
          final blad = stan.error!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(opisBledu(blad)),
                // token wygasł albo konto zablokowane - wracamy do logowania
                if (blad is BladApi && blad.kod == 401)
                  TextButton(
                    onPressed: () => wyloguj(context),
                    child: const Text('Zaloguj ponownie'),
                  ),
              ],
            ),
          );
        }
        if (!stan.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return zbuduj(stan.data as T);
      },
    );
  }
}

class Naglowek extends StatelessWidget {
  const Naglowek(this.tekst, {super.key, this.akcja});

  final String tekst;
  final Widget? akcja;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tekst.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ?akcja,
        ],
      ),
    );
  }
}

Color kolorStatusu(String status) => switch (status) {
  'ZAAKCEPTOWANY' => Colors.green.shade700,
  'ODRZUCONY' => const Color(0xFFDC143C),
  'ROZPATRYWANY' => Colors.orange.shade800,
  _ => Colors.grey.shade700,
};

void pokazKomunikat(BuildContext context, String tekst) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tekst)));
}

// Otwiera plik z backendu i pokazuje błąd, jeśli się nie da.
Future<void> otworz(BuildContext context, String sciezka, String nazwa) async {
  try {
    await otworzPlik(sciezka, nazwa);
  } catch (e) {
    if (context.mounted) pokazKomunikat(context, opisBledu(e));
  }
}

// Pasek "< Listopad 2026 >" do przełączania dni / miesięcy.
class Przelacznik extends StatelessWidget {
  const Przelacznik({
    super.key,
    required this.tekst,
    required this.wstecz,
    required this.dalej,
    this.naKlik,
  });

  final String tekst;
  final VoidCallback wstecz;
  final VoidCallback dalej;
  final VoidCallback? naKlik;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: wstecz, icon: const Icon(Icons.chevron_left)),
        Expanded(
          // TextButton tylko gdy da się kliknąć (plan), inaczej zwykły tekst - nie jest wyszarzony
          child: naKlik == null
              ? Text(
                  tekst,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                )
              : TextButton(
                  onPressed: naKlik,
                  child: Text(tekst, style: const TextStyle(fontSize: 16)),
                ),
        ),
        IconButton(onPressed: dalej, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

// ---------------------------------------------------------------- 1. służby

class ZakladkaSluzby extends StatefulWidget {
  const ZakladkaSluzby({super.key});

  @override
  State<ZakladkaSluzby> createState() => _ZakladkaSluzbyState();
}

class _ZakladkaSluzbyState extends State<ZakladkaSluzby> {
  DateTime _miesiac = DateTime(DateTime.now().year, DateTime.now().month);
  bool _mojaKompania = true;
  late Future<List<Map<String, dynamic>>> _grafiki;

  @override
  void initState() {
    super.initState();
    _grafiki = pobierzGrafiki(_miesiac.month, _miesiac.year);
  }

  void _zmienMiesiac(int o) {
    setState(() {
      _miesiac = DateTime(_miesiac.year, _miesiac.month + o);
      _grafiki = pobierzGrafiki(_miesiac.month, _miesiac.year);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Przelacznik(
          tekst: '${miesiaceNazwy[_miesiac.month - 1]} ${_miesiac.year}',
          wstecz: () => _zmienMiesiac(-1),
          dalej: () => _zmienMiesiac(1),
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Moja kompania')),
            ButtonSegment(value: false, label: Text('Inne')),
          ],
          selected: {_mojaKompania},
          onSelectionChanged: (w) => setState(() => _mojaKompania = w.first),
        ),
        Expanded(
          child: Wczytywanie(
            dane: _grafiki,
            zbuduj: (grafiki) {
              final lista = grafiki
                  .where((g) => g['own'] == _mojaKompania)
                  .toList();
              if (lista.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Brak grafiku na ten miesiąc.'),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final g in lista)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_note),
                        title: Text(
                          '${g['company_number']} kompania (${g['battalion']} bat.)',
                        ),
                        subtitle: Text(
                          [
                            g['file_name'],
                            if (g['comment'] != null) g['comment'],
                            'dodano ${data(g['created_at'])}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.download),
                        onTap: () => otworz(
                          context,
                          '/duties/${g['id']}/file',
                          g['file_name'],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 2. wnioski

class ZakladkaWnioski extends StatefulWidget {
  const ZakladkaWnioski({super.key});

  @override
  State<ZakladkaWnioski> createState() => _ZakladkaWnioskiState();
}

class _ZakladkaWnioskiState extends State<ZakladkaWnioski> {
  late Future<List<Map<String, dynamic>>> _wzory;
  late Future<List<Map<String, dynamic>>> _wnioski;

  @override
  void initState() {
    super.initState();
    _wczytaj();
  }

  void _wczytaj() {
    _wzory = pobierzWzory();
    _wnioski = mojeWnioski();
  }

  Future<void> _zlozWniosek() async {
    final wyslano = await showDialog<bool>(
      context: context,
      builder: (_) => const _OknoNowegoWniosku(),
    );
    if (wyslano == true && mounted) {
      pokazKomunikat(context, 'Wniosek wysłany do dowódcy kompanii.');
      setState(_wczytaj);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_wczytaj),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              onPressed: _zlozWniosek,
              icon: const Icon(Icons.upload_file),
              label: const Text('Złóż wniosek (PDF)'),
            ),
          ),
          const Naglowek('Aktualne wzory wniosków'),
          Wczytywanie(
            dane: _wzory,
            zbuduj: (wzory) => Column(
              children: [
                if (wzory.isEmpty)
                  const ListTile(
                    title: Text('Dowódca nie dodał jeszcze wzorów.'),
                  ),
                for (final w in wzory)
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(w['name']),
                    subtitle: Text(
                      'aktualizacja: ${data(w['updated_at'], zGodzina: false)}',
                    ),
                    trailing: const Icon(Icons.download),
                    onTap: () => otworz(
                      context,
                      '/templates/${w['id']}/file',
                      w['file_name'],
                    ),
                  ),
              ],
            ),
          ),
          const Naglowek('Status moich wniosków'),
          Wczytywanie(
            dane: _wnioski,
            zbuduj: (wnioski) => Column(
              children: [
                if (wnioski.isEmpty)
                  const ListTile(title: Text('Nie złożyłeś jeszcze wniosku.')),
                for (final w in wnioski)
                  ListTile(
                    title: Text(w['title']),
                    subtitle: Text(
                      [
                        data(w['created_at']),
                        if (w['comment'] != null && w['comment'] != '')
                          'Komentarz: ${w['comment']}',
                      ].join('\n'),
                    ),
                    trailing: Text(
                      w['status'],
                      style: TextStyle(
                        color: kolorStatusu(w['status']),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => otworz(
                      context,
                      '/requests/${w['id']}/file',
                      w['file_name'],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OknoNowegoWniosku extends StatefulWidget {
  const _OknoNowegoWniosku();

  @override
  State<_OknoNowegoWniosku> createState() => _OknoNowegoWnioskuState();
}

class _OknoNowegoWnioskuState extends State<_OknoNowegoWniosku> {
  final _tytul = TextEditingController();
  PlatformFile? _plik;
  bool _wysylanie = false;

  @override
  void dispose() {
    _tytul.dispose();
    super.dispose();
  }

  Future<void> _wybierzPlik() async {
    final plik = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (plik != null) setState(() => _plik = plik);
  }

  Future<void> _wyslij() async {
    if (_tytul.text.trim().isEmpty || _plik == null) {
      pokazKomunikat(context, 'Wpisz tytuł i wybierz plik PDF.');
      return;
    }
    setState(() => _wysylanie = true);
    try {
      await zlozWniosek(_tytul.text.trim(), _plik!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        pokazKomunikat(context, opisBledu(e));
        setState(() => _wysylanie = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nowy wniosek'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _tytul,
            decoration: const InputDecoration(
              labelText: 'Czego dotyczy (np. przepustka 12.12)',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _wybierzPlik,
            icon: const Icon(Icons.attach_file),
            label: Text(_plik?.name ?? 'Wybierz plik PDF'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _wysylanie ? null : _wyslij,
          child: Text(_wysylanie ? 'Wysyłanie…' : 'Wyślij'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 3. start

class ZakladkaStart extends StatefulWidget {
  const ZakladkaStart({super.key});

  @override
  State<ZakladkaStart> createState() => _ZakladkaStartState();
}

class _ZakladkaStartState extends State<ZakladkaStart> {
  late Future<Map<String, dynamic>> _ja;
  late Future<List<Map<String, dynamic>>> _ogloszenia;
  late Future<List<Map<String, dynamic>>> _dzisiaj;
  late Future<List<Map<String, dynamic>>> _wnioski;

  @override
  void initState() {
    super.initState();
    _wczytaj();
  }

  void _wczytaj() {
    _ja = pobierzMnie();
    _ogloszenia = pobierzOgloszenia();
    _dzisiaj = pobierzPlan(DateTime.now());
    _wnioski = mojeWnioski();
  }

  Future<void> _pokazOgloszenie(Map<String, dynamic> o) async {
    if (!o['read']) {
      oznaczPrzeczytane(o['id']).catchError((_) {});
      setState(() => o['read'] = true);
    }
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(o['title']),
        content: SingleChildScrollView(child: Text(o['body'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dzis = DateTime.now();

    return RefreshIndicator(
      onRefresh: () async => setState(_wczytaj),
      child: ListView(
        children: [
          Wczytywanie(
            dane: _ja,
            zbuduj: (ja) => ListTile(
              title: Text(
                'Cześć, ${ja['rank'] ?? 'pchor.'} ${ja['last_name']}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${_dniTygodnia[dzis.weekday - 1]}, ${data(dzis.toIso8601String(), zGodzina: false)}',
              ),
            ),
          ),
          const Naglowek('Ogłoszenia'),
          Wczytywanie(
            dane: _ogloszenia,
            zbuduj: (lista) => Column(
              children: [
                if (lista.isEmpty)
                  const ListTile(title: Text('Brak ogłoszeń.')),
                // najpierw nowe, potem przeczytane (backend już sortuje od najnowszych)
                for (final o in [
                  ...lista.where((o) => !o['read']),
                  ...lista.where((o) => o['read']),
                ])
                  ListTile(
                    leading: Icon(
                      o['read']
                          ? Icons.drafts_outlined
                          : Icons.mark_email_unread,
                      color: o['read'] ? Colors.grey : const Color(0xFFDC143C),
                    ),
                    title: Text(
                      o['title'],
                      style: TextStyle(
                        fontWeight: o['read']
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text('${o['author']} · ${data(o['created_at'])}'),
                    onTap: () => _pokazOgloszenie(o),
                  ),
              ],
            ),
          ),
          const Naglowek('Zajęcia dzisiaj'),
          Wczytywanie(
            dane: _dzisiaj,
            zbuduj: (zajecia) => Column(
              children: [
                if (zajecia.isEmpty)
                  const ListTile(title: Text('Dziś nie masz zajęć.')),
                for (final z in zajecia) WierszZajec(z),
              ],
            ),
          ),
          const Naglowek('Moje wnioski'),
          Wczytywanie(
            dane: _wnioski,
            zbuduj: (wnioski) => Column(
              children: [
                if (wnioski.isEmpty)
                  const ListTile(title: Text('Brak złożonych wniosków.')),
                for (final w in wnioski.take(3))
                  ListTile(
                    dense: true,
                    title: Text(w['title']),
                    trailing: Text(
                      w['status'],
                      style: TextStyle(
                        color: kolorStatusu(w['status']),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 4. plan zajęć

class WierszZajec extends StatelessWidget {
  const WierszZajec(this.z, {super.key});

  final Map<String, dynamic> z;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        '${z['time_start']}\n${z['time_end']}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      title: Text(z['title']),
      subtitle: Text(
        [
          z['type'],
          if (z['room'] != '') 'sala ${z['room']}',
          if (z['prof'] != '') z['prof'],
        ].join(' · '),
      ),
    );
  }
}

class ZakladkaPlan extends StatefulWidget {
  const ZakladkaPlan({super.key});

  @override
  State<ZakladkaPlan> createState() => _ZakladkaPlanState();
}

class _ZakladkaPlanState extends State<ZakladkaPlan> {
  DateTime _dzien = DateTime.now();
  late Future<List<Map<String, dynamic>>> _zajecia;

  @override
  void initState() {
    super.initState();
    _zajecia = pobierzPlan(_dzien);
  }

  void _ustawDzien(DateTime d) {
    setState(() {
      _dzien = d;
      _zajecia = pobierzPlan(d);
    });
  }

  Future<void> _wybierzDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dzien,
      firstDate: DateTime(2025),
      lastDate: DateTime(2028),
    );
    if (d != null) _ustawDzien(d);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Przelacznik(
          tekst:
              '${_dniTygodnia[_dzien.weekday - 1]}, ${data(_dzien.toIso8601String(), zGodzina: false)}',
          wstecz: () => _ustawDzien(_dzien.subtract(const Duration(days: 1))),
          dalej: () => _ustawDzien(_dzien.add(const Duration(days: 1))),
          naKlik: _wybierzDate,
        ),
        const Divider(height: 1),
        Expanded(
          child: Wczytywanie(
            dane: _zajecia,
            zbuduj: (zajecia) => zajecia.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Brak zajęć tego dnia.'),
                  )
                : ListView(children: [for (final z in zajecia) WierszZajec(z)]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 5. profil

class ZakladkaProfil extends StatefulWidget {
  const ZakladkaProfil({super.key});

  @override
  State<ZakladkaProfil> createState() => _ZakladkaProfilState();
}

class _ZakladkaProfilState extends State<ZakladkaProfil> {
  final _ja = pobierzMnie();

  Future<void> _odswiezPrzypomnienia() async {
    try {
      await zaplanujPrzypomnienia();
      if (mounted) pokazKomunikat(context, 'Przypomnienia ustawione na 7 dni.');
    } catch (e) {
      if (mounted) pokazKomunikat(context, opisBledu(e));
    }
  }

  void _pomoc() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pomoc'),
        content: const Text(
          'Plan zajęć pochodzi z watplan.coobie.dev według grupy podanej przy rejestracji.\n\n'
          'Przypomnienie przychodzi ok. 15 minut przed zajęciami.\n\n'
          'Wnioski trafiają do dowódcy Twojej kompanii, status zmienia się po jego decyzji.\n\n'
          'Problem z kontem? Zgłoś się do dowódcy kompanii.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wczytywanie(
      dane: _ja,
      zbuduj: (ja) => ListView(
        children: [
          const Naglowek('Dane'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text('${ja['first_name']} ${ja['last_name']}'),
            subtitle: Text(ja['rank'] ?? 'stopień nie podany'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text('${ja['company_number']} kompania'),
            subtitle: Text('grupa: ${ja['study_group'] ?? '-'}'),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(ja['email']),
          ),
          const Naglowek('Ustawienia'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Odśwież przypomnienia o zajęciach'),
            onTap: _odswiezPrzypomnienia,
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Pomoc'),
            onTap: _pomoc,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFDC143C)),
            title: const Text('Wyloguj'),
            onTap: () => wyloguj(context),
          ),
        ],
      ),
    );
  }
}
