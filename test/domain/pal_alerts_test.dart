// Los avisos de pals son un recordatorio, no un noticiero: suenan por lo que
// el pal carga de nuevo **y vos todavía no**, una sola vez, y solo si el aviso
// está prendido.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/remote/pals_client.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/pal.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/domain/services/pal_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthGateway {
  @override
  AuthAccount? get currentAccount =>
      const AuthAccount(id: 'yo', email: 'yo@test');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeClient implements PalsClient {
  @override
  Future<List<Pal>> list() async => const <Pal>[
    Pal(
      id: 'v1',
      userId: 'tomas',
      displayName: 'Tomás',
      status: PalStatus.accepted,
      isIncoming: false,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Sink implements PalAlertSink {
  final List<String> titles = <String>[];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async => titles.add(title);
}

PalDay _day({
  List<MealSlot> slots = const <MealSlot>[],
  int activities = 0,
  DateTime? date,
}) => PalDay(
  userId: 'tomas',
  date: date ?? today(),
  meals: <PalMeal>[
    for (final s in slots) PalMeal(slot: s, name: 'Algo', kcal: 300),
  ],
  activityMinutes: activities * 30,
  activityCount: activities,
);

void main() {
  late _Sink sink;
  late PalAlertPrefs prefs;
  late Set<MealSlot> mine;
  late bool moved;
  late PalAlertService service;

  setUp(() {
    sink = _Sink();
    prefs = const PalAlertPrefs();
    mine = <MealSlot>{};
    moved = false;
    service = PalAlertService(
      client: _FakeClient(),
      auth: _FakeAuth(),
      sink: sink,
      prefs: () async => prefs,
      loggedSlotToday: mine.contains,
      movedToday: () => moved,
    );
  });

  test('una comida nueva del pal avisa si vos no cargaste esa', () async {
    await service.onPalDay(_day(slots: <MealSlot>[MealSlot.lunch]));
    expect(sink.titles, <String>['Tomás cargó el almuerzo']);
  });

  test('si ya cargaste la tuya, no suena', () async {
    mine.add(MealSlot.lunch);
    await service.onPalDay(_day(slots: <MealSlot>[MealSlot.lunch]));
    expect(sink.titles, isEmpty);
  });

  test('editar la misma comida no vuelve a avisar', () async {
    await service.onPalDay(_day(slots: <MealSlot>[MealSlot.lunch]));
    await service.onPalDay(_day(slots: <MealSlot>[MealSlot.lunch]));
    await service.onPalDay(
      _day(slots: <MealSlot>[MealSlot.lunch, MealSlot.lunch]),
    );
    expect(sink.titles, hasLength(1));
  });

  test('actividad nueva avisa si vos no te moviste', () async {
    await service.onPalDay(_day(activities: 1));
    expect(sink.titles, <String>['Tomás registró actividad']);
  });

  test('si ya te moviste, la actividad del pal no suena', () async {
    moved = true;
    await service.onPalDay(_day(activities: 1));
    expect(sink.titles, isEmpty);
  });

  test('con el aviso apagado no suena nada', () async {
    prefs = const PalAlertPrefs(meals: false, activity: false);
    await service.onPalDay(
      _day(slots: <MealSlot>[MealSlot.dinner], activities: 1),
    );
    expect(sink.titles, isEmpty);
  });

  test('un día que no es hoy no avisa', () async {
    await service.onPalDay(
      _day(
        slots: <MealSlot>[MealSlot.lunch],
        date: today().subtract(const Duration(days: 1)),
      ),
    );
    expect(sink.titles, isEmpty);
  });
}
