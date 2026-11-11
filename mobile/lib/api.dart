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
  final odp = await http.get(Uri.parse('$adresApi/companies'));
  _sprawdz(odp);
  final lista = jsonDecode(utf8.decode(odp.bodyBytes)) as List;
  return [
    for (final k in lista) Kompania(k['id'], k['number'], k['battalion']),
  ];
}

// Loguje i zwraca rolę: PCHOR, DCA_KP albo DCA_JEDN.
Future<String> zaloguj(String email, String haslo) async {
  final odp = await _post('/login', {'email': email, 'password': haslo});
  final dane = jsonDecode(utf8.decode(odp.bodyBytes));
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

Future<http.Response> _post(String sciezka, Map<String, dynamic> dane) async {
  final odp = await http.post(
    Uri.parse('$adresApi$sciezka'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(dane),
  );
  _sprawdz(odp);
  return odp;
}

// Jeśli backend odpowiedział błędem (kod 400 i wyżej), rzuca BladApi z jego komunikatem.
void _sprawdz(http.Response odp) {
  if (odp.statusCode < 400) return;
  var komunikat = 'Błąd serwera (${odp.statusCode}).';
  try {
    final detail = jsonDecode(utf8.decode(odp.bodyBytes))['detail'];
    if (detail is String) komunikat = detail;
    if (detail is List) komunikat = 'Sprawdź wpisane dane.';
  } catch (_) {}
  throw BladApi(komunikat);
}
