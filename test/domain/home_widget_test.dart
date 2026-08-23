// Qué muestra el widget de la pantalla de inicio del teléfono.
//
// El widget lo dibuja el launcher, con la app cerrada, leyendo lo último que la
// app dejó guardado. Eso trae un riesgo propio: un número viejo mostrado como
// si fuera de hoy. La defensa está partida en dos y las dos mitades se prueban
// donde viven — acá, que el texto y la **fecha** salgan del cálculo del día; en
// Kotlin, que un dato de otra fecha no se muestre.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/home_widget_publisher.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/activity.dart';
import 'package:ceres/domain/models/goal.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/models/summaries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El dato del widget incluye un `staleLabel` con la fecha escrita en palabras
  // —"Lo último guardado es del miércoles 30 de julio"—, así que el payload pasó
  // a depender de los símbolos de fecha, igual que el resto de la app.
  setUpAll(() => initializeDateFormatting(appLocale));

  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  Future<void> conObjetivo(int kcal) => repo.saveGoal(
    Goal(
      id: 'g-1',
      goalType: GoalType.maintain,
      rateKgPerWeek: 0,
      baseCalorieTarget: kcal,
      targetMethod: TargetMethod.manual,
      proteinG: 120,
      carbsG: 220,
      fatG: 70,
      macroMethod: 'default',
      startsOn: today().subtract(const Duration(days: 1)),
    ),
  );

  Future<void> conComida({required int kcal}) => repo.saveMeal(
    Meal(
      id: 'm-$kcal',
      slot: MealSlot.lunch,
      eatenAt: DateTime.now(),
      localDate: today(),
      items: <MealItem>[
        MealItem(
          id: 'i-$kcal',
          name: 'Plato',
          quantity: 1,
          unit: 'porción',
          kcal: kcal,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          position: 0,
        ),
      ],
      source: MealSource.manual,
      syncStatus: SyncStatus.synced,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  test('el dato lleva la fecha del día que describe', () async {
    await conObjetivo(2000);
    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()), glasses: 0, waterGoal: 8);

    // Sin esto el widget no puede saber si lo que tiene guardado sigue valiendo.
    expect(payload['date'], isoDate(today()));
  });

  test('sin comidas, quedan todas las calorías del objetivo', () async {
    await conObjetivo(2000);
    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()), glasses: 0, waterGoal: 8);

    expect(payload['value'], '2.000');
    expect(payload['label'], 'kcal restantes');
    // El "Comió X de Y" se sacó del widget: es la misma cuenta que el número
    // grande, contada al revés, y ocupaba una línea entera.
    expect(payload.containsKey('detail'), isFalse);
  });

  test('pasarse del objetivo se cuenta, no se reta', () async {
    await conObjetivo(2000);
    await repo.saveMeal(
      Meal(
        id: 'm-1',
        slot: MealSlot.lunch,
        eatenAt: DateTime.now(),
        localDate: today(),
        items: <MealItem>[
          const MealItem(
            id: 'i-1',
            name: 'Asado',
            quantity: 400,
            unit: 'g',
            kcal: 2300,
            proteinG: 90,
            carbsG: 0,
            fatG: 180,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        syncStatus: SyncStatus.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()), glasses: 0, waterGoal: 8);

    // El valor va en positivo y lo que cambia es la palabra: las mismas que usa
    // Inicio, sin rojo ni reto (D-17).
    expect(payload['value'], '300');
    expect(payload['label'], 'kcal de más');
  });

  test('sin objetivo no se inventa un número', () {
    // La app siempre tiene un objetivo de referencia
    // (`LocalRepository.defaultCalorieTarget`), así que este día no lo produce
    // el repositorio: es la guarda. Con `baseTarget` en 0, "te quedan −1.123"
    // sería un número que no significa nada, y el widget no tiene pantalla
    // donde aclararlo.
    final sinObjetivo = DailySummary(
      date: today(),
      baseTarget: 0,
      consumedKcal: 1123,
      exerciseEstimatedKcal: 0,
      exerciseAppliedKcal: 0,
      creditPercentage: 0,
      creditEnabled: false,
      macros: const MacroSet(
        protein: MacroProgress(current: 0, target: 0),
        carbs: MacroProgress(current: 0, target: 0),
        fat: MacroProgress(current: 0, target: 0),
      ),
      meals: const <Meal>[],
      activities: const <Activity>[],
      activityTotals: const ActivityTotals(minutes: 0, sessions: 0),
      isRestDay: false,
    );

    final payload = HomeWidgetPublisher.payloadFor(sinObjetivo, glasses: 0, waterGoal: 8);

    expect(payload['value'], '—');
    expect(payload['label'], 'Sin objetivo configurado');
    expect(payload['waterMax'], 40);
  });

  test('el agua viaja como cuenta, para que el widget dibuje las gotas', () {
    final payload = HomeWidgetPublisher.payloadFor(
      repo.daily(today()),
      glasses: 6,
      waterGoal: 8,
    );

    // Números y no texto: de esto el widget decide **cuántas** gotas pinta, no
    // cómo se escribe un número.
    expect(payload['waterGlasses'], 6);
    expect(payload['waterGoal'], 8);
  });

  test('los macros llevan su etiqueta escrita y cuánta barra pintar', () async {
    await conObjetivo(2000);
    await repo.saveMeal(
      Meal(
        id: 'm-1',
        slot: MealSlot.lunch,
        eatenAt: DateTime.now(),
        localDate: today(),
        items: <MealItem>[
          const MealItem(
            id: 'i-1',
            name: 'Pollo',
            quantity: 200,
            unit: 'g',
            kcal: 330,
            proteinG: 60,
            carbsG: 0,
            fatG: 8,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        syncStatus: SyncStatus.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final payload = HomeWidgetPublisher.payloadFor(
      repo.daily(today()),
      glasses: 0,
      waterGoal: 8,
    );

    // El objetivo del fixture: 120 g de proteína.
    expect(payload['proteinLabel'], 'P 60/120');
    expect(payload['proteinPercent'], 50);
    expect(payload['carbsLabel'], 'C 0/220');
    expect(payload['carbsPercent'], 0);
    expect(payload['fatLabel'], 'G 8/70');
  });

  test('pasarse de un macro llena la barra pero no la desborda', () async {
    await conObjetivo(2000);
    await repo.saveMeal(
      Meal(
        id: 'm-1',
        slot: MealSlot.dinner,
        eatenAt: DateTime.now(),
        localDate: today(),
        items: <MealItem>[
          const MealItem(
            id: 'i-1',
            name: 'Suplemento',
            quantity: 1,
            unit: 'unidad',
            kcal: 720,
            proteinG: 180,
            carbsG: 0,
            fatG: 0,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        syncStatus: SyncStatus.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final payload = HomeWidgetPublisher.payloadFor(
      repo.daily(today()),
      glasses: 0,
      waterGoal: 8,
    );

    // La barra se recorta —una desbordada no dibuja nada legible— pero la
    // etiqueta dice los gramos de verdad, así que el exceso se sigue viendo.
    expect(payload['proteinPercent'], 100);
    expect(payload['proteinLabel'], 'P 180/120');
  });

  test('publicar sin plataforma nativa no revienta', () async {
    // En un test no hay canal del lado de Android. El widget es una comodidad:
    // no puede hacer fallar el registro de una comida.
    await conObjetivo(2000);
    await const HomeWidgetPublisher().publish(repo.daily(today()), glasses: 3, waterGoal: 8);
  });

  // ── La barra del día (rediseño §1) ──────────────────────────────────────

  group('la barra del día', () {
    test('sale del consumido sobre el objetivo', () async {
      await conObjetivo(2000);
      await conComida(kcal: 500);

      final payload = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
      );

      expect(payload['caloriesPercent'], 25);
      expect(payload['intakeLabel'], '500 de 2.000');
    });

    test('sin objetivo llega en −1 y el widget la esconde', () {
      // El día sin objetivo se arma a mano por lo mismo que el de más arriba:
      // el repositorio siempre devuelve uno de referencia, así que esto es la
      // guarda y no un caso que se pueda producir desde la app.
      //
      // Cero sería una barra vacía **dibujada**, o sea un número inventado con
      // forma de cuenta. −1 es "acá no hay nada que dibujar".
      final payload = HomeWidgetPublisher.payloadFor(
        DailySummary(
          date: today(),
          baseTarget: 0,
          consumedKcal: 1123,
          exerciseEstimatedKcal: 0,
          exerciseAppliedKcal: 0,
          creditPercentage: 0,
          creditEnabled: false,
          macros: const MacroSet(
            protein: MacroProgress(current: 0, target: 0),
            carbs: MacroProgress(current: 0, target: 0),
            fat: MacroProgress(current: 0, target: 0),
          ),
          meals: const <Meal>[],
          activities: const <Activity>[],
          activityTotals: const ActivityTotals(minutes: 0, sessions: 0),
          isRestDay: false,
        ),
        glasses: 0,
        waterGoal: 8,
      );

      expect(payload['caloriesPercent'], -1);
      expect(payload['intakeLabel'], '');
    });

    test('pasarse la llena, no la desborda ni la pinta de otro color', () async {
      await conObjetivo(2000);
      await conComida(kcal: 2600);

      final payload = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
      );

      expect(payload['caloriesPercent'], 100);
      // Lo que cambia al pasarse es la palabra, y nada más.
      expect(payload['label'], 'kcal de más');
    });
  });

  // ── Los extras del tamaño grande (rediseño §3.3) ────────────────────────

  group('los extras', () {
    test('un día sin nada los manda vacíos, y el widget esconde esa línea', () async {
      await conObjetivo(2000);

      final payload = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
      );

      // "Actividad 0 min" ocupa el mismo lugar que un dato y no es uno.
      expect(payload['activityLabel'], '');
      expect(payload['sleepLabel'], '');
      expect(payload['streakLabel'], '');
    });

    test('el sueño llega escrito desde acá, no formateado en Kotlin', () async {
      await conObjetivo(2000);

      final payload = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
        sleepMinutes: 432,
      );

      expect(payload['sleepLabel'], 'Sueño 7 h 12 min');
    });
  });

  // ── La racha ────────────────────────────────────────────────────────────

  group('la racha', () {
    String dia(int atras) =>
        isoDate(today().subtract(Duration(days: atras)));

    test('cuenta los días seguidos hacia atrás', () {
      final dias = <String>{dia(0), dia(1), dia(2), dia(4)};
      expect(HomeWidgetPublisher.streakDays(dias, today()), 3);
    });

    test('si hoy todavía no hay nada, no se corta: cuenta desde ayer', () {
      // Cortarla a las 00:01 sería castigar a alguien por no haber desayunado
      // todavía, y una racha que se pierde durmiendo no se quiere mirar.
      final dias = <String>{dia(1), dia(2), dia(3)};
      expect(HomeWidgetPublisher.streakDays(dias, today()), 3);
    });

    test('sin nada, ni ayer ni hoy, es cero', () {
      expect(HomeWidgetPublisher.streakDays(<String>{dia(3)}, today()), 0);
      expect(HomeWidgetPublisher.streakDays(<String>{}, today()), 0);
    });

    test('un día suelto no se muestra como racha', () async {
      await conObjetivo(2000);

      final unSoloDia = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
        daysWithRecords: <String>{dia(0)},
      );
      expect(unSoloDia['streakLabel'], '');

      final dosDias = HomeWidgetPublisher.payloadFor(
        repo.daily(today()),
        glasses: 0,
        waterGoal: 8,
        daysWithRecords: <String>{dia(0), dia(1)},
      );
      expect(dosDias['streakLabel'], 'Racha 2 días');
    });
  });

  test('el aviso de dato viejo lleva fecha absoluta, no "ayer"', () async {
    await conObjetivo(2000);

    final payload = HomeWidgetPublisher.payloadFor(
      repo.daily(today()),
      glasses: 0,
      waterGoal: 8,
    );

    // El widget lo va a mostrar en un día que todavía no sabemos cuál es: si
    // dijera "ayer", pasado mañana estaría mintiendo.
    expect(payload['staleLabel'], contains(longDay(today())));
    expect(payload['staleLabel'], isNot(contains('Ayer')));
  });
}
