// Wszystkie zapytania do backendu ePchor.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

// 10.0.2.2 to z emulatora Androida adres komputera, na którym działa backend.
const adresApi = 'http://10.0.2.2:8000';

// Token z logowania. Na razie tylko w pamięci, po zamknięciu aplikacji znika.
String? token;

class Kompania {
  final int id;
  final int numer;
  final int batalion;

  Kompania(this.id, this.numer, this.batalion);

  String get nazwa => '$numer kompania ($batalion batalion)';
}

// Błąd zwrócony przez backend, z komunikatem do pokazania użytkownikowi.
class BladApi implements Exception {
  final String komunikat;
  final int kod; // kod HTTP, np. 401 = trzeba się zalogować od nowa

  BladApi(this.komunikat, [this.kod = 0]);

  @override
  String toString() => komunikat;
}

// "2026-11-27T19:40:12.123" -> "27.11.2026 19:40"
String data(String? iso, {bool zGodzina = true}) {
  if (iso == null) return '';
  final d = DateTime.parse(iso);
  String dwa(int x) => x.toString().padLeft(2, '0');
  final dzien = '${dwa(d.day)}.${dwa(d.month)}.${d.year}';
  return zGodzina ? '$dzien ${dwa(d.hour)}:${dwa(d.minute)}' : dzien;
}

// ---------------------------------------------------------------- konta

Future<List<Kompania>> pobierzKompanie() async {
  final lista = await _get('/companies') as List;
  return [
    for (final k in lista) Kompania(k['id'], k['number'], k['battalion']),
  ];
}

// Loguje i zwraca rolę: PCHOR, DCA_KP albo DCA_JEDN.
Future<String> zaloguj(String email, String haslo) async {
  final dane = await _post('/login', {'email': email, 'password': haslo});
  token = dane['access_token'];
  return dane['role'];
}

Future<void> zarejestruj({
  required String email,
  required String haslo,
  required String rola,
  required String imie,
  required String nazwisko,
  required int kompaniaId,
  String? stopien,
  String? grupa,
}) async {
  await _post('/register', {
    'email': email,
    'password': haslo,
    'role': rola,
    'first_name': imie,
    'last_name': nazwisko,
    'company_id': kompaniaId,
    'rank': stopien,
    'study_group': grupa,
  });
}

Future<Map<String, dynamic>> pobierzMnie() async => await _get('/me');

// Konta czekające na zatwierdzenie przez zalogowanego dowódcę.
Future<List<Map<String, dynamic>>> pobierzOczekujace() async =>
    _lista(await _get('/pending'));

Future<void> zatwierdzKonto(int id) => _post('/users/$id/approve', {});

Future<void> odrzucKonto(int id) => _post('/users/$id/reject', {});

// ---------------------------------------------------------------- ogłoszenia

Future<List<Map<String, dynamic>>> pobierzOgloszenia() async =>
    _lista(await _get('/announcements'));

Future<void> dodajOgloszenie(String tytul, String tresc) =>
    _post('/announcements', {'title': tytul, 'body': tresc});

Future<void> usunOgloszenie(int id) => _wyslij('DELETE', '/announcements/$id');

Future<void> oznaczPrzeczytane(int id) => _post('/announcements/$id/read', {});

// ---------------------------------------------------------------- plan zajęć

Future<List<Map<String, dynamic>>> pobierzPlan(
  DateTime dzien, {
  int dni = 1,
}) async {
  final d = dzien.toIso8601String().substring(0, 10);
  return _lista(await _get('/plan?dzien=$d&dni=$dni'));
}

// ---------------------------------------------------------------- wnioski i wzory

Future<void> zlozWniosek(String tytul, PlatformFile plik) =>
    _wyslijPlik('POST', '/requests', plik, {'title': tytul});

Future<List<Map<String, dynamic>>> mojeWnioski() async =>
    _lista(await _get('/requests/mine'));

Future<List<Map<String, dynamic>>> wnioskiKompanii() async =>
    _lista(await _get('/requests'));

Future<void> zmienStatusWniosku(int id, String status, String? komentarz) =>
    _wyslij('PATCH', '/requests/$id', {'status': status, 'comment': komentarz});

Future<List<Map<String, dynamic>>> pobierzWzory() async =>
    _lista(await _get('/templates'));

Future<void> dodajWzor(String nazwa, PlatformFile plik) =>
    _wyslijPlik('POST', '/templates', plik, {'name': nazwa});

Future<void> aktualizujWzor(int id, PlatformFile plik) =>
    _wyslijPlik('PUT', '/templates/$id', plik, {});

Future<void> usunWzor(int id) => _wyslij('DELETE', '/templates/$id');

// ---------------------------------------------------------------- grafik służb

Future<List<Map<String, dynamic>>> pobierzGrafiki(int miesiac, int rok) async =>
    _lista(await _get('/duties?month=$miesiac&year=$rok'));

Future<void> wgrajGrafik(
  int miesiac,
  int rok,
  String? komentarz,
  PlatformFile plik,
) => _wyslijPlik('POST', '/duties', plik, {
  'month': '$miesiac',
  'year': '$rok',
  'comment': ?komentarz, // ? = pomiń pole, jeśli komentarz jest null
});

// ---------------------------------------------------------------- pliki

// Pobiera plik z backendu (np. /templates/3/file), zapisuje go w telefonie i otwiera.
Future<void> otworzPlik(String sciezka, String nazwa) async {
  final odp = await http.get(
    Uri.parse('$adresApi$sciezka'),
    headers: _naglowki,
  );
  if (odp.statusCode >= 400) _odpowiedz(odp);

  final folder = await getTemporaryDirectory();
  final plik = File('${folder.path}/$nazwa');
  await plik.writeAsBytes(odp.bodyBytes);

  final wynik = await OpenFilex.open(plik.path);
  if (wynik.type != ResultType.done) {
    throw BladApi('Brak aplikacji do otwarcia pliku $nazwa.');
  }
}

// ---------------------------------------------------------------- pomocnicze

// Nagłówki każdego zapytania. Po zalogowaniu dochodzi token.
Map<String, String> get _naglowki => {
  'Content-Type': 'application/json',
  if (token != null) 'Authorization': 'Bearer $token',
};

List<Map<String, dynamic>> _lista(dynamic json) =>
    (json as List).cast<Map<String, dynamic>>();

Future<dynamic> _get(String sciezka) async {
  final odp = await http.get(
    Uri.parse('$adresApi$sciezka'),
    headers: _naglowki,
  );
  return _odpowiedz(odp);
}

Future<dynamic> _post(String sciezka, Map<String, dynamic> dane) =>
    _wyslij('POST', sciezka, dane);

// POST / PATCH / DELETE z danymi w JSON
Future<dynamic> _wyslij(
  String metoda,
  String sciezka, [
  Map<String, dynamic>? dane,
]) async {
  final zapytanie = http.Request(metoda, Uri.parse('$adresApi$sciezka'))
    ..headers.addAll(_naglowki);
  if (dane != null) zapytanie.body = jsonEncode(dane);
  final odp = await http.Response.fromStream(await zapytanie.send());
  return _odpowiedz(odp);
}

// Wysyła formularz z plikiem (multipart) - tak jak "Choose file" w Swaggerze.
Future<dynamic> _wyslijPlik(
  String metoda,
  String sciezka,
  PlatformFile plik,
  Map<String, String> pola,
) async {
  final zapytanie =
      http.MultipartRequest(metoda, Uri.parse('$adresApi$sciezka'))
        ..fields.addAll(pola)
        ..files.add(
          http.MultipartFile.fromBytes(
            'plik',
            await plik.readAsBytes(),
            filename: plik.name,
          ),
        );
  if (token != null) zapytanie.headers['Authorization'] = 'Bearer $token';
  final odp = await http.Response.fromStream(await zapytanie.send());
  return _odpowiedz(odp);
}

// Zwraca odczytany JSON albo rzuca BladApi, jeśli backend odpowiedział błędem.
dynamic _odpowiedz(http.Response odp) {
  final tresc = jsonDecode(utf8.decode(odp.bodyBytes));
  if (odp.statusCode < 400) return tresc;

  var komunikat = 'Błąd serwera (${odp.statusCode}).';
  if (tresc is Map) {
    final detail = tresc['detail'];
    if (detail is String) komunikat = detail;
    if (detail is List) komunikat = 'Sprawdź wpisane dane.';
  }
  throw BladApi(komunikat, odp.statusCode);
}
