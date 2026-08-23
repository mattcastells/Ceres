// Las comidas que se repiten, que es casi todo lo que come cualquiera.
//
// `favoriteMeals()` existía en el repositorio desde el principio y **ninguna
// pantalla lo leía**: se podía marcar una comida con la estrella y esa estrella
// no servía para nada. Estos tests cubren lo que ahora sí se muestra.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;
  final hoy = today();

  Meal comida(
    String nombre, {
    required MealSlot slot,
    required DateTime fecha,
    int kcal = 300,
  }) => Meal(
    id: '$nombre-${fecha.toIso8601String()}-${slot.wire}',
    slot: slot,
    eatenAt: fecha,
    localDate: dateOnly(fecha),
    name: nombre,
    items: <MealItem>[
      MealItem(
        id: '$nombre-item-${fecha.millisecondsSinceEpoch}',
        name: nombre,
        quantity: 1,
        unit: 'porcion',
        kcal: kcal,
        proteinG: 10,
        carbsG: 30,
        fatG: 8,
        position: 0,
      ),
    ],
    source: MealSource.manual,
    createdAt: fecha,
    updatedAt: fecha,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.signIn('yo@ceres.test');
  });

  test('sin nada registrado no hay nada que repetir', () {
    expect(repo.frequentMeals(limit: 5), isEmpty);
  });

  test('una comida cargada una sola vez no es frecuente', () async {
    await repo.saveMeal(
      comida('Tostado', slot: MealSlot.snack, fecha: hoy),
    );
    expect(repo.frequentMeals(limit: 5), isEmpty);
  });

  test('repetirla la vuelve frecuente, con la versión más reciente', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    await repo.saveMeal(
      comida('Café con leche', slot: MealSlot.breakfast, fecha: ayer, kcal: 150),
    );
    await repo.saveMeal(
      comida('Café con leche', slot: MealSlot.breakfast, fecha: hoy, kcal: 180),
    );

    final frecuentes = repo.frequentMeals(limit: 5);
    expect(frecuentes, hasLength(1));
    expect(frecuentes.first.title, 'Café con leche');
    // La más nueva: es la que tiene las cantidades como las come hoy.
    expect(frecuentes.first.totalKcal, 180);
  });

  test('la estrella gana sobre el conteo', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    // "Milanesa" va dos veces; "Ensalada" una sola, pero con estrella.
    await repo.saveMeal(comida('Milanesa', slot: MealSlot.dinner, fecha: ayer));
    await repo.saveMeal(comida('Milanesa', slot: MealSlot.dinner, fecha: hoy));
    final ensalada = comida('Ensalada', slot: MealSlot.lunch, fecha: hoy);
    await repo.saveMeal(ensalada);
    await repo.toggleMealFavorite(ensalada.id);

    final frecuentes = repo.frequentMeals(limit: 5);
    expect(frecuentes.first.title, 'Ensalada');
    expect(frecuentes.map((m) => m.title), contains('Milanesa'));
  });

  test('el slot ordena pero no esconde', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    // Un café con leche puede ser desayuno o merienda: filtrarlo por slot
    // sería adivinar mal.
    await repo.saveMeal(comida('Café', slot: MealSlot.snack, fecha: ayer));
    await repo.saveMeal(comida('Café', slot: MealSlot.snack, fecha: hoy));
    await repo.saveMeal(comida('Fideos', slot: MealSlot.lunch, fecha: ayer));
    await repo.saveMeal(comida('Fideos', slot: MealSlot.lunch, fecha: hoy));

    final paraAlmuerzo = repo.frequentMeals(slot: MealSlot.lunch, limit: 5);
    expect(paraAlmuerzo.first.title, 'Fideos');
    expect(
      paraAlmuerzo.map((m) => m.title),
      contains('Café'),
      reason: 'esconderlo por estar en otro slot sería adivinar mal',
    );
  });

  test('una comida borrada deja de aparecer', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    final vieja = comida('Pizza', slot: MealSlot.dinner, fecha: ayer);
    final nueva = comida('Pizza', slot: MealSlot.dinner, fecha: hoy);
    await repo.saveMeal(vieja);
    await repo.saveMeal(nueva);
    expect(repo.frequentMeals(limit: 5), hasLength(1));

    await repo.deleteMeal(vieja.id);
    await repo.deleteMeal(nueva.id);
    expect(repo.frequentMeals(limit: 5), isEmpty);
  });

  test('repetir una frecuente la copia al día y al slot pedidos', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    final origen = comida('Guiso', slot: MealSlot.dinner, fecha: ayer);
    await repo.saveMeal(origen);

    final copia = await repo.duplicateMeal(origen.id, hoy, MealSlot.lunch);

    expect(copia.slot, MealSlot.lunch);
    expect(copia.localDate, dateOnly(hoy));
    expect(copia.totalKcal, origen.totalKcal);
    expect(copia.id, isNot(origen.id));
    expect(repo.mealsOn(hoy), hasLength(1));
  });
}
