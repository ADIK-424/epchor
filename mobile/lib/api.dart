// Wszystkie zapytania do backendu ePchor.
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  BladApi(this.komunikat);

  @override
  String toString() => komunikat;
}

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

// Konta czekające na zatwierdzenie przez zalogowanego dowódcę.
Future<List<Map<String, dynamic>>> pobierzOczekujace() async {
  final lista = await _get('/pending') as List;
  return lista.cast<Map<String, dynamic>>();
}

Future<void> zatwierdzKonto(int id) => _post('/users/$id/approve', {});

Future<void> odrzucKonto(int id) => _post('/users/$id/reject', {});

// ---------------------------------------------------------------- pomocnicze

// Nagłówki każdego zapytania. Po zalogowaniu dochodzi token.
Map<String, String> get _naglowki => {
  'Content-Type': 'application/json',
  if (token != null) 'Authorization': 'Bearer $token',
};

Future<dynamic> _get(String sciezka) async {
  final odp = await http.get(
    Uri.parse('$adresApi$sciezka'),
    headers: _naglowki,
  );
  return _odpowiedz(odp);
}

Future<dynamic> _post(String sciezka, Map<String, dynamic> dane) async {
  final odp = await http.post(
    Uri.parse('$adresApi$sciezka'),
    headers: _naglowki,
    body: jsonEncode(dane),
  );
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
  throw BladApi(komunikat);
}
