import 'dart:async';

import '../../core/utils/dates.dart';
import '../../data/remote/pals_client.dart';
import '../enums/enums.dart';
import '../models/pal.dart';
import '../repositories/auth_gateway.dart';

/// Qué avisos de pals quiere esta persona. Viven en el teléfono: son del
/// dispositivo que suena, no de la cuenta.
class PalAlertPrefs {
  const PalAlertPrefs({this.meals = true, this.activity = true});

  /// "Tomás cargó el almuerzo", si vos todavía no cargaste el tuyo.
  final bool meals;

  /// "Julieta registró actividad", si vos todavía no te moviste hoy.
  final bool activity;

  bool get any => meals || activity;

  PalAlertPrefs copyWith({bool? meals, bool? activity}) => PalAlertPrefs(
    meals: meals ?? this.meals,
    activity: activity ?? this.activity,
  );
}

/// Dónde se muestra un aviso. Una interfaz para que el servicio no dependa
/// del plugin de notificaciones y se pueda probar sin Android.
abstract interface class PalAlertSink {
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

/// Avisa cuando un pal carga algo que vos todavía no: es un recordatorio, no
/// un noticiero. Si ya cargaste tu almuerzo, que Tomás cargue el suyo no
/// suena.
///
/// Escucha por Realtime mientras la app está abierta, y al volver a abrirla
/// se pone al día con lo que pasó mientras tanto. Que suene con la app
/// cerrada necesita push desde el servidor (Firebase), que esta versión no
/// tiene.
class PalAlertService {
  PalAlertService({
    required PalsClient client,
    required AuthGateway auth,
    required PalAlertSink sink,
    required Future<PalAlertPrefs> Function() prefs,
    required bool Function(MealSlot slot) loggedSlotToday,
    required bool Function() movedToday,
  }) : _client = client,
       _auth = auth,
       _sink = sink,
       _prefs = prefs,
       _loggedSlotToday = loggedSlotToday,
       _movedToday = movedToday;

  final PalsClient _client;
  final AuthGateway _auth;
  final PalAlertSink _sink;
  final Future<PalAlertPrefs> Function() _prefs;
  final bool Function(MealSlot slot) _loggedSlotToday;
  final bool Function() _movedToday;

  /// Lo último que se vio de cada pal hoy. Un aviso sale solo por lo que
  /// aparece de nuevo respecto de esto.
  final Map<String, PalDay> _seen = <String, PalDay>{};

  /// Lo que ya avisó, para no repetir si el pal edita la misma comida.
  final Set<String> _notified = <String>{};

  final Map<String, String> _names = <String, String>{};

  Future<void> Function()? _stop;
  StreamSubscription<AuthAccount?>? _authSub;
  String? _account;

  /// Los reinicios van en fila. Dos a la vez abrían dos canales con el mismo
  /// nombre, y al cerrar el primero el servidor daba de baja también el
  /// segundo: la app quedaba "suscripta" sin recibir nada.
  Future<void> _queue = Future<void>.value();

  /// Arranca y sigue a la sesión: al entrar escucha, al salir corta.
  void attach() {
    _account = _auth.currentAccount?.id;
    _authSub ??= _auth.changes.listen((account) {
      if (account?.id == _account) return;
      _account = account?.id;
      _scheduleRestart();
    });
    _scheduleRestart();
  }

  void _scheduleRestart() {
    _queue = _queue.then((_) => _restart()).catchError((Object _) {});
  }

  Future<void> _restart() async {
    await _stop?.call();
    _stop = null;
    _seen.clear();
    _notified.clear();
    _names.clear();
    if (_account == null) return;

    try {
      await _refreshNames();
      for (final day in await _client.palDaysOn(today())) {
        _seen[day.userId] = day;
      }
    } on Object {
      // Sin la foto inicial igual se escucha: lo que llegue se compara contra
      // un día vacío, y en el peor caso avisa algo que ya estaba.
    }
    _stop = _client.listenPalDays(
      (day) => unawaited(onPalDay(day)),
      onSubscribed: () => unawaited(_catchUp()),
    );
  }

  /// Lo que publicaron los pals mientras la app no escuchaba. La primera vez
  /// no encuentra nada nuevo (la foto inicial se acaba de sacar); al volver de
  /// segundo plano, sí.
  Future<void> _catchUp() async {
    try {
      for (final day in await _client.palDaysOn(today())) {
        await onPalDay(day);
      }
    } on Object {
      // Sin conexión no hay con qué ponerse al día; el próximo cambio llega
      // igual por el canal.
    }
  }

  Future<void> _refreshNames() async {
    final pals = await _client.list();
    _names
      ..clear()
      ..addEntries(<MapEntry<String, String>>[
        for (final p in pals)
          if (p.status == PalStatus.accepted) MapEntry(p.userId, p.label),
      ]);
  }

  /// Público para los tests: es lo que hace cada fila que llega.
  Future<void> onPalDay(PalDay day) async {
    final now = today();
    if (!isSameDay(day.date, now)) return;

    final before = _seen[day.userId];
    _seen[day.userId] = day;

    final prefs = await _prefs();
    if (!prefs.any) return;

    final newSlots = <MealSlot>{for (final m in day.meals) m.slot}
      ..removeAll(<MealSlot>{
        for (final m in before?.meals ?? <PalMeal>[]) m.slot,
      });
    final moved = day.activityCount > (before?.activityCount ?? 0);
    if (newSlots.isEmpty && !moved) return;

    var name = _names[day.userId];
    if (name == null) {
      try {
        await _refreshNames();
      } on Object {
        return;
      }
      name = _names[day.userId];
      if (name == null) return;
    }

    final date = isoDate(now);
    if (prefs.meals) {
      for (final slot in newSlots) {
        if (_loggedSlotToday(slot)) continue;
        final key = '${day.userId}|$date|${slot.wire}';
        if (!_notified.add(key)) continue;
        await _sink.show(
          id: _idFor(key),
          title: '$name cargó ${_slotPhrase(slot)}',
          body: '¿Ya cargaste lo tuyo?',
        );
      }
    }
    if (prefs.activity && moved && !_movedToday()) {
      final key = '${day.userId}|$date|activity';
      if (_notified.add(key)) {
        await _sink.show(
          id: _idFor(key),
          title: '$name registró actividad',
          body: '¿Te sumás? Cargá la tuya.',
        );
      }
    }
  }

  static String _slotPhrase(MealSlot slot) => switch (slot) {
    MealSlot.breakfast => 'el desayuno',
    MealSlot.lunch => 'el almuerzo',
    MealSlot.dinner => 'la cena',
    MealSlot.snack => 'un snack',
  };

  /// Lejos de los ids de los recordatorios, que son chicos.
  static int _idFor(String key) =>
      100000 + (key.hashCode & 0x7fffffff) % 100000;

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _stop?.call();
  }
}
