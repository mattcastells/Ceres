// Lo que ve un pal tiene que ser lo que hay, y eso son cuatro cosas que hasta
// acá no se cumplían:
//
// 1. Un cambio en un día pasado —cargar el almuerzo de ayer, corregir una
//    porción, borrar una comida vieja— también se publica. Antes se publicaba
//    solo `today()`, así que esas fechas quedaban congeladas en el momento en
//    que habían sido hoy.
// 2. Un día sin novedades no se vuelve a subir.
// 3. Un número fuera del rango que acepta la tabla se recorta en vez de hacer
//    fallar el `insert` entero, que era cómo un día dejaba de actualizarse para
//    siempre y en silencio.
// 4. Una subida que falla se reintenta sola.

import 'dart:convert';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/remote/pals_client.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/pal.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/domain/services/pal_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthGateway {
  AuthAccount? account = const AuthAccount(id: 'u1', email: 'yo@test');

  @override
  AuthAccount? get currentAccount => account;
  @override
  bool get hasSession => account != null;
  @override
  Stream<AuthAccount?> get changes => const Stream<AuthAccount?>.empty();
  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
  @override
  Future<void> signOut() async => account = null;
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
}

/// Un `PalsClient` de mentira. Se implementa la clase como interfaz —su
/// constructor pide un `SupabaseClient` de verdad— y solo tienen cuerpo los dos
/// métodos que usa el publicador.
class _FakeClient implements PalsClient {
  final List<List<Map<String, dynamic>>> subidas =
      <List<Map<String, dynamic>>>[];
  PalSharingPrefs prefs = const PalSharingPrefs();
  AppError? failWith;

  @override
  Future<PalSharingPrefs> mySharingPrefs() async => prefs;

  @override
  Future<void> publishDays(List<PalDay> days) async {
    if (failWith != null) throw failWith!;
    subidas.add(<Map<String, dynamic>>[for (final d in days) d.toRow()]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa acá');
}

/// Las comidas de cada fecha, para poder cambiar una del pasado a mano.
final Map<String, List<PalMeal>> _meals = <String, List<PalMeal>>{};

int _activityMinutes = 0;
int _activityCount = 0;
int? _waterGlasses;

PalDay _build(DateTime date, PalSharingPrefs prefs) => PalDay(
  userId: 'u1',
  date: date,
  meals: _meals[isoDate(date)] ?? const <PalMeal>[],
  activityMinutes: _activityMinutes,
  activityCount: _activityCount,
  waterGlasses: prefs.water ? _waterGlasses : null,
);

List<String> _fechasDe(List<Map<String, dynamic>> subida) =>
    <String>[for (final row in subida) row['local_date'] as String];

void main() {
  late _FakeClient client;
  late _FakeAuth auth;
  late PalPublisher publisher;

  setUp(() {
    _meals.clear();
    _activityMinutes = 0;
    _activityCount = 0;
    _waterGlasses = null;
    client = _FakeClient();
    auth = _FakeAuth();
    publisher = PalPublisher(
      client: client,
      auth: auth,
      buildDay: _build,
      debounce: Duration.zero,
    );
  });

  tearDown(() => publisher.dispose());

  test('la primera publicación sube la ventana entera', () async {
    await publisher.publish();

    expect(client.subidas, hasLength(1));
    expect(client.subidas.single, hasLength(PalPublisher.windowDays + 1));
    expect(_fechasDe(client.subidas.single), contains(isoDate(today())));
  });

  test('un día sin novedades no se vuelve a subir', () async {
    await publisher.publish();
    await publisher.publish();

    // La segunda no encontró nada distinto: ni siquiera hubo pedido.
    expect(client.subidas, hasLength(1));
  });

  test('cambiar un día pasado publica ese día, no el de hoy', () async {
    await publisher.publish();

    final anteayer = today().subtract(const Duration(days: 2));
    _meals[isoDate(anteayer)] = const <PalMeal>[
      PalMeal(slot: MealSlot.lunch, name: 'Milanesa con puré', kcal: 720),
    ];
    await publisher.publish();

    expect(client.subidas, hasLength(2));
    expect(_fechasDe(client.subidas.last), <String>[isoDate(anteayer)]);
    expect(
      (client.subidas.last.single['meals']! as List<dynamic>).single,
      containsPair('name', 'Milanesa con puré'),
    );
  });

  test('borrar la comida de un día pasado también viaja', () async {
    final ayer = today().subtract(const Duration(days: 1));
    _meals[isoDate(ayer)] = const <PalMeal>[
      PalMeal(slot: MealSlot.dinner, name: 'Pizza', kcal: 900),
    ];
    await publisher.publish();

    _meals.remove(isoDate(ayer));
    await publisher.publish();

    expect(_fechasDe(client.subidas.last), <String>[isoDate(ayer)]);
    expect(client.subidas.last.single['meals'], isEmpty);
  });

  test('los números fuera de rango se recortan en vez de romper la fila', () async {
    _activityMinutes = 3000;
    _activityCount = 80;
    _waterGlasses = 99;
    client.prefs = const PalSharingPrefs(water: true);

    await publisher.publish();

    final fila = client.subidas.single.first;
    expect(fila['activity_minutes'], PalDay.maxActivityMinutes);
    expect(fila['activity_count'], PalDay.maxActivityCount);
    expect(fila['water_glasses'], PalDay.maxWaterGlasses);
  });

  test('una subida que falla se reintenta con el próximo cambio', () async {
    client.failWith = const AppError(
      code: ApiErrorCode.offline,
      message: 'sin conexión',
    );
    await publisher.publish();
    expect(client.subidas, isEmpty);

    client.failWith = null;
    await publisher.publish();

    // Nada quedó marcado como subido mientras el servidor rechazaba, así que
    // el segundo intento manda la ventana entera y no solo lo nuevo.
    expect(client.subidas.single, hasLength(PalPublisher.windowDays + 1));
  });

  test('sin sesión no se publica nada', () async {
    auth.account = null;
    await publisher.publish();
    expect(client.subidas, isEmpty);
  });

  test('otra cuenta en el mismo teléfono vuelve a subir todo', () async {
    await publisher.publish();
    auth.account = const AuthAccount(id: 'u2', email: 'otro@test');

    await publisher.publish();

    expect(client.subidas, hasLength(2));
    expect(client.subidas.last, hasLength(PalPublisher.windowDays + 1));
  });

  test('la proyección no lleva ítems de comida ni peso', () async {
    _meals[isoDate(today())] = const <PalMeal>[
      PalMeal(slot: MealSlot.lunch, name: 'Milanesa con puré', kcal: 720),
    ];
    await publisher.publish();

    final fila = client.subidas.single.firstWhere(
      (row) => row['local_date'] == isoDate(today()),
    );
    final json = jsonEncode(fila);
    expect(json, isNot(contains('proteinG')));
    expect(json, isNot(contains('weight')));
    expect(fila.keys, isNot(contains('items')));
  });
}
