// El favorito tiene que valer para los alimentos del catálogo externo, no solo
// para los propios: `favorites()` lee de las tres listas del almacén y el
// toggle escribía en dos.

import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/food.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Food _food(String id, FoodSource source) => Food(
  id: id,
  name: 'Alimento $id',
  source: source,
  servingSize: 100,
  servingUnit: 'g',
  kcal: 100,
  proteinG: 5,
  carbsG: 10,
  fatG: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  test('un alimento propio se puede marcar y desmarcar', () async {
    store.userFoods = <Food>[_food('propio', FoodSource.user)];
    await repo.toggleFoodFavorite('propio');
    expect(repo.favorites().map((f) => f.id), contains('propio'));

    await repo.toggleFoodFavorite('propio');
    expect(repo.favorites(), isEmpty);
  });

  test('uno del catálogo externo también', () async {
    // Lo que llega de Open Food Facts se guarda acá, y era la lista que el
    // toggle no tocaba.
    store.cachedFoods = <Food>[_food('off:779007', FoodSource.off)];
    await repo.toggleFoodFavorite('off:779007');

    expect(repo.favorites().map((f) => f.id), contains('off:779007'));
    expect(repo.byId('off:779007')!.isFavorite, isTrue);
  });

  test('sobrevive a guardar y volver a leer', () async {
    store.cachedFoods = <Food>[_food('off:779007', FoodSource.off)];
    await repo.toggleFoodFavorite('off:779007');

    store.restoreDocument(store.toDocument());
    expect(repo.favorites().map((f) => f.id), contains('off:779007'));
  });

  test('el mismo id en dos listas no queda en estados opuestos', () async {
    // Invertir cada lista por su cuenta lo dejaba marcado en una y
    // desmarcado en la otra.
    store.userFoods = <Food>[_food('mismo', FoodSource.user)];
    store.cachedFoods = <Food>[_food('mismo', FoodSource.off)];

    await repo.toggleFoodFavorite('mismo');
    expect(store.userFoods.first.isFavorite, isTrue);
    expect(store.cachedFoods.first.isFavorite, isTrue);
  });
}
