// Przypomnienia o zajęciach: lokalne powiadomienie 15 minut przed każdymi zajęciami.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';

final _powiadomienia = FlutterLocalNotificationsPlugin();

const _kanal = NotificationDetails(
  android: AndroidNotificationDetails(
    'zajecia',
    'Zajęcia',
    channelDescription: 'Przypomnienia 15 minut przed zajęciami',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

// Wywoływane raz przy starcie aplikacji (main.dart).
Future<void> przygotujPowiadomienia() async {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
  await _powiadomienia.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

// Ustawia przypomnienia na najbliższe 7 dni. Stare kasujemy, żeby się nie dublowały.
Future<void> zaplanujPrzypomnienia() async {
  await _powiadomienia
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  final zajecia = await pobierzPlan(DateTime.now(), dni: 7);
  await _powiadomienia.cancelAll();

  final teraz = tz.TZDateTime.now(tz.local);
  var id = 0;
  for (final z in zajecia) {
    final dzien = DateTime.parse(z['date']);
    final godzina = (z['time_start'] as String).split(':');
    final start = tz.TZDateTime(
      tz.local,
      dzien.year,
      dzien.month,
      dzien.day,
      int.parse(godzina[0]),
      int.parse(godzina[1]),
    );
    final kiedy = start.subtract(const Duration(minutes: 15));
    if (kiedy.isBefore(teraz)) continue;

    final sala = z['room'] == '' ? '' : ' · sala ${z['room']}';
    await _powiadomienia.zonedSchedule(
      id: id++,
      title: 'Za 15 min: ${z['title']}',
      body: '${z['time_start']} · ${z['type']}$sala',
      scheduledDate: kiedy,
      notificationDetails: _kanal,
      // bez dokładnych alarmów - Android może przesunąć o chwilę, ale nie trzeba dodatkowej zgody
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
