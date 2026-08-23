// La persistencia relacional: que lo que sube sea lo que baja.
//
// Lo que se prueba acá no es "el cliente llama a Supabase" —eso necesita un
// servidor— sino el contrato que sí podemos verificar en frío: que la puerta
// no deje escribir antes de decidir qué hacer con lo remoto, que un teléfono
// vacío no pise la base, y que el documento que devuelve la lectura tenga la
// forma que `LocalStore` sabe leer. Esa forma es el punto de todo: si se
// desalinea, los datos vuelven mutilados y nadie se entera.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/relational_sync_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/domain/services/relational_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements AuthGateway {
  AuthAccount? account = const AuthAccount(id: 'u1', email: 'yo@test');

  @override
  AuthAccount? get currentAccount => account;
  @override
  bool get hasSession => account != null;
  @override
  Stream<AuthAccount?> get changes => const Stream<AuthAccount?>.empty();
  @override
  Future<AuthAccount> signIn({required String email, required String password}) =>
      throw UnimplementedError();
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

class _FakeClient implements RelationalSyncClient {
  int pushes = 0;
  int pulls = 0;
  Map<String, dynamic>? paraTraer;
  AppError? fallaCon;

  @override
  Future<Map<String, int>> push({
    required String userId,
    required LocalStore store,
  }) async {
    if (fallaCon != null) throw fallaCon!;
    pushes++;
    return <String, int>{'meals': store.meals.length};
  }

  @override
  Future<Map<String, dynamic>?> pull({
    required String userId,
    required LocalStore store,
  }) async {
    pulls++;
    if (fallaCon != null) throw fallaCon!;
    return paraTraer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late LocalRepository repo;
  late _FakeClient client;
  late _FakeAuth auth;

  RelationalSyncService build() => RelationalSyncService(
    client: client,
    auth: auth,
    store: store,
    debounce: Duration.zero,
  );

  Future<void> cargarUnaComida() async {
    await repo.saveMeal(
      Meal(
        id: 'm1',
        slot: MealSlot.lunch,
        eatenAt: DateTime(2026, 7, 29, 13),
        localDate: DateTime(2026, 7, 29),
        name: 'Milanesa',
        items: const <MealItem>[
          MealItem(
            id: 'i1',
            name: 'Milanesa',
            quantity: 1,
            unit: 'unidad',
            kcal: 300,
            proteinG: 20,
            carbsG: 15,
            fatG: 16,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.signIn('yo@test');
    client = _FakeClient();
    auth = _FakeAuth();
  });

  group('la puerta antes de escribir', () {
    test('sin abrirla no escribe nada', () async {
      await cargarUnaComida();
      final service = build();

      service.markDirty();
      await service.push();

      expect(client.pushes, 0);
      service.dispose();
    });

    test('se abre aunque la lectura falle por red', () async {
      // Si quedara cerrada por un problema de conexión, la app dejaría de
      // persistir para siempre y en silencio.
      client.fallaCon = const AppError(
        code: ApiErrorCode.offline,
        message: 'sin conexión',
      );
      final service = build();

      await service.openAfterPull(apply: (_) async {});

      expect(service.canPush, isTrue);
      service.dispose();
    });

    test('con datos locales también trae, y reconcilia en vez de pisar', () async {
      // Este test decía lo contrario —"con datos locales no trae nada"— y era
      // correcto mientras el documento era la fuente de verdad. Al darla vuelta
      // hay que traer siempre, si no la misma cuenta abierta en dos lados
      // diverge y no se vuelve a encontrar.
      //
      // La preocupación que protegía el test viejo, "pisar lo local es el mismo
      // error al revés", sigue en pie: lo que cambió es cómo se protege. Ahora
      // se reconcilia, y `document_merge_test.dart` prueba que reconciliar no
      // puede dejar menos registros de los que había.
      await cargarUnaComida();
      client.paraTraer = <String, dynamic>{
        'profile': <String, dynamic>{},
        'meals': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'de-otro-dispositivo',
            'slot': 'dinner',
            'loggedAt': '2026-07-31T21:00:00.000Z',
            'localDate': '2026-07-31T00:00:00.000Z',
            'items': <Map<String, dynamic>>[],
            'source': 'manual',
            'syncStatus': 'synced',
            'createdAt': '2026-07-31T21:00:00.000Z',
            'updatedAt': '2026-07-31T21:00:00.000Z',
          },
        ],
      };
      final service = build();

      final traido = await service.openAfterPull(apply: repo.importDocument);

      expect(traido, isTrue);
      // La local sigue estando y la del otro dispositivo se sumó.
      expect(store.meals, hasLength(2));
      service.dispose();
    });
  });

  group('un teléfono vacío no vacía la base', () {
    test('sin datos locales no escribe, aunque la puerta esté abierta', () async {
      final service = build();
      await service.openAfterPull(apply: (_) async {});

      await service.push();

      expect(client.pushes, 0);
      service.dispose();
    });

    test('con un registro real sí escribe', () async {
      final service = build();
      await service.openAfterPull(apply: (_) async {});
      await cargarUnaComida();

      await service.push();

      expect(client.pushes, 1);
      expect(service.state, isA<SyncIdle>());
      service.dispose();
    });
  });

  group('el documento que devuelve la base lo entiende el store', () {
    test('una comida traída de las tablas se lee entera', () async {
      // Es el contrato central: la lectura relacional devuelve la misma forma
      // que el documento local, así que la reconstruye el mismo lector
      // tolerante y no hay un segundo lugar donde equivocarse.
      client.paraTraer = <String, dynamic>{
        'schemaVersion': LocalStore.schemaVersion,
        'profile': <String, dynamic>{
          'id': 'u1',
          'biologicalSex': 'male',
          'activityLevel': 'moderate',
          'timezone': 'America/Argentina/Buenos_Aires',
          'unitSystem': 'metric',
          'themeMode': 'system',
          'locale': 'es',
          'exerciseCreditPercentage': 0,
          'exerciseCreditEnabled': true,
          'showNetCalories': false,
          'createdAt': '2026-07-01T10:00:00.000',
          'updatedAt': '2026-07-01T10:00:00.000',
        },
        'meals': <dynamic>[
          <String, dynamic>{
            'id': 'm9',
            'slot': 'dinner',
            'loggedAt': '2026-07-29T21:00:00.000Z',
            'localDate': '2026-07-29',
            'name': 'Guiso',
            'source': 'manual',
            'isFavorite': false,
            'syncStatus': 'synced',
            'createdAt': '2026-07-29T21:00:00.000Z',
            'updatedAt': '2026-07-29T21:00:00.000Z',
            'items': <dynamic>[
              <String, dynamic>{
                'id': 'i9',
                'name': 'Guiso de lentejas',
                'quantity': 1,
                'unit': 'porcion',
                'kcal': 420,
                'proteinG': 18,
                'carbsG': 60,
                'fatG': 10,
                'position': 0,
              },
            ],
          },
        ],
        'weightLogs': <dynamic>[
          <String, dynamic>{
            'id': 'w9',
            'weightKg': 81.4,
            'localDate': '2026-07-29',
            'loggedAt': '2026-07-29T09:00:00.000Z',
            'source': 'manual',
            'syncStatus': 'synced',
          },
        ],
      };

      final service = build();
      final traido = await service.openAfterPull(apply: repo.importDocument);

      expect(traido, isTrue);
      expect(store.meals, hasLength(1));
      expect(store.meals.first.title, 'Guiso');
      expect(store.meals.first.items.first.kcal, 420);
      expect(store.weightLogs.first.weightKg, 81.4);
      expect(store.lastRestore.isClean, isTrue,
          reason: 'si la forma no coincide, los datos vuelven mutilados');
      service.dispose();
    });

    test('la base sin contenido no borra lo que hay en el teléfono', () async {
      await cargarUnaComida();
      client.paraTraer = null; // el cliente devuelve null cuando no hay filas
      final service = build();

      await service.openAfterPull(apply: repo.importDocument);

      expect(store.meals, hasLength(1));
      service.dispose();
    });
  });

  test('un fallo de escritura no rompe nada y queda dicho', () async {
    final service = build();
    await service.openAfterPull(apply: (_) async {});
    await cargarUnaComida();
    client.fallaCon = const AppError(
      code: ApiErrorCode.server,
      message: 'la base dijo que no',
    );

    await service.push();

    expect(service.state, isA<SyncFailed>());
    // El dato sigue en el teléfono: la persistencia local no depende de esto.
    expect(store.meals, hasLength(1));
    service.dispose();
  });

  // Traer al volver a la app, no solo al arrancarla.
  //
  // Antes esto pasaba una sola vez, en el arranque en frío. En el navegador da
  // igual —recargar es arrancar— pero en el teléfono significaba que un cambio
  // hecho desde otro dispositivo aparecía recién cuando Android mataba el
  // proceso y la app volvía a abrir de cero, que puede tardar días.
  group('releer al volver a primer plano', () {
    test('sin haber abierto la puerta todavía, no se adelanta', () async {
      final service = build();

      final traido = await service.refresh(apply: (_) async {});

      expect(traido, isFalse);
      expect(client.pulls, 0, reason: 'del primer arranque se ocupa openAfterPull');
      service.dispose();
    });

    test('con la app abierta vuelve a consultar', () async {
      final service = build();
      await service.openAfterPull(apply: repo.importDocument);
      expect(client.pulls, 1);

      client.paraTraer = <String, dynamic>{
        'profile': <String, dynamic>{},
        'meals': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cargada-en-otro-lado',
            'slot': 'dinner',
            'loggedAt': '2026-07-31T21:00:00.000Z',
            'localDate': '2026-07-31T00:00:00.000Z',
            'items': <Map<String, dynamic>>[],
            'source': 'manual',
            'syncStatus': 'synced',
            'createdAt': '2026-07-31T21:00:00.000Z',
            'updatedAt': '2026-07-31T21:00:00.000Z',
          },
        ],
      };

      final traido = await service.refresh(
        apply: repo.importDocument,
        minInterval: Duration.zero,
      );

      expect(traido, isTrue);
      expect(client.pulls, 2);
      expect(store.meals, hasLength(1), reason: 'entró lo del otro dispositivo');
      service.dispose();
    });

    test('no sale a la red en cada vuelta corta', () async {
      final service = build();
      await service.openAfterPull(apply: (_) async {});

      // Abrir la cámara y volver son dos `resumed` seguidos.
      await service.refresh(apply: (_) async {});
      await service.refresh(apply: (_) async {});
      await service.refresh(apply: (_) async {});

      expect(client.pulls, 1, reason: 'solo el del arranque');
      service.dispose();
    });

    test('una consulta fallida también cuenta para el freno', () async {
      final service = build();
      await service.openAfterPull(apply: (_) async {});
      client.fallaCon = const AppError(
        code: ApiErrorCode.offline,
        message: 'sin conexión',
      );

      final primero = await service.refresh(
        apply: (_) async {},
        minInterval: Duration.zero,
      );
      final segundo = await service.refresh(apply: (_) async {});

      expect(primero, isFalse);
      expect(segundo, isFalse);
      // Sin conexión no se reintenta a los tirones cada vez que se vuelve.
      expect(client.pulls, 2);
      service.dispose();
    });
  });

  // Reconstruir una comida desde sus filas.
  //
  // Acá vivió el bug de la comida clonada: recalcular con IA le pone ids nuevos
  // a todos los ítems, el push escribía la generación nueva al lado de la vieja
  // —un upsert no borra— y el pull rearmaba la comida con las dos. Borrar los
  // duplicados en el teléfono no tocaba la tabla, así que volvían en el
  // arranque siguiente, y en el siguiente.
  group('los ítems de una comida', () {
    Map<String, dynamic> fila(String id, int posicion, String nombre) =>
        <String, dynamic>{'id': id, 'position': posicion, 'name': nombre};

    test('se ordenan por posición, no por lo que devuelva la base', () {
      final salida = itemsDeLaComida(<Map<String, dynamic>>[
        fila('c', 2, 'Postre'),
        fila('a', 0, 'Risotto'),
        fila('b', 1, 'Chocolate blanco'),
      ]);

      expect(
        salida.map((i) => i['name']),
        <String>['Risotto', 'Chocolate blanco', 'Postre'],
      );
    });

    test('dos generaciones de ítems dejan una sola, la más reciente', () {
      // Como vienen ordenadas por `updated_at`, la vieja va primero y la
      // recalculada después. Gana la que se tocó último, que es la corregida.
      final salida = itemsDeLaComida(<Map<String, dynamic>>[
        fila('vieja-0', 0, 'Risotto 150 g'),
        fila('vieja-1', 1, 'Chocolate blanco'),
        fila('nueva-0', 0, 'Risotto 250 g'),
        fila('nueva-1', 1, 'Chocolate blanco'),
      ]);

      expect(salida, hasLength(2));
      expect(salida.map((i) => i['id']), <String>['nueva-0', 'nueva-1']);
    });

    test('un recálculo que agrega un ítem no lo pierde', () {
      final salida = itemsDeLaComida(<Map<String, dynamic>>[
        fila('vieja-0', 0, 'Risotto'),
        fila('nueva-0', 0, 'Risotto'),
        fila('nueva-1', 1, 'Chocolate aireado'),
      ]);

      expect(salida.map((i) => i['id']), <String>['nueva-0', 'nueva-1']);
    });

    test('dos ítems distintos con posiciones distintas no se tocan', () {
      // Comer dos veces lo mismo es legal y tiene que sobrevivir: lo que se
      // colapsa es la posición repetida, no el nombre repetido.
      final salida = itemsDeLaComida(<Map<String, dynamic>>[
        fila('a', 0, 'Chocolate aireado'),
        fila('b', 1, 'Chocolate aireado'),
      ]);

      expect(salida, hasLength(2));
    });

    test('una fila sin posición legible se conserva', () {
      final salida = itemsDeLaComida(<Map<String, dynamic>>[
        fila('a', 0, 'Risotto'),
        <String, dynamic>{'id': 'rara', 'position': null, 'name': 'Postre'},
      ]);

      expect(salida, hasLength(2));
      expect(salida.last['id'], 'rara');
    });
  });
}
