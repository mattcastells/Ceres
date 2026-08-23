import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/reminder.dart';
import '../../domain/services/reminder_service.dart';

/// Recordatorios con notificaciones locales de Android.
///
/// Locales y no push: son horarios que la persona eligió, no eventos del
/// servidor. Así funcionan sin conexión, sin cuenta y sin que la app tenga que
/// despertar por la red.
class AndroidReminderScheduler implements ReminderScheduler {
  AndroidReminderScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'ceres_recordatorios';

  /// Se inicializa una vez en el arranque. Devuelve `null` si la plataforma no
  /// soporta notificaciones, para que el resto de la app lo trate como
  /// "no disponible" en vez de romperse.
  static Future<AndroidReminderScheduler?> create() async {
    try {
      tzdata.initializeTimeZones();
      // Sin la zona del dispositivo, "a las 21:00" sería a las 21:00 UTC.
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      final plugin = FlutterLocalNotificationsPlugin();
      final ready = await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      if (ready == false) return null;
      return AndroidReminderScheduler(plugin);
    } on Object {
      return null;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> hasPermission() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<void> apply(List<Reminder> reminders) async {
    await cancelAll();
    if (!await hasPermission()) return;

    for (final reminder in reminders) {
      if (!reminder.enabled) continue;
      for (final time in reminder.times) {
        await _schedule(reminder.kind, time);
      }
    }
  }

  Future<void> _schedule(ReminderKind kind, ReminderTime time) async {
    await _plugin.zonedSchedule(
      id: time.idFor(kind),
      title: kind.title,
      body: kind.body,
      scheduledDate: _nextOccurrence(time),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Recordatorios',
          channelDescription: 'Avisos de agua y de registro de comidas.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // Inexacta a propósito: la exacta exige SCHEDULE_EXACT_ALARM, que Google
      // restringe a alarmas y calendarios. Para "acordate de tomar agua" da
      // igual que suene 10:00 o 10:03, y así no se pide un permiso sensible.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repite todos los días a la misma hora.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// La próxima vez que caiga esa hora. Si ya pasó hoy, mañana.
  tz.TZDateTime _nextOccurrence(ReminderTime time) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
