// Foto de perfil: se pone y se ve en el acto (sin servidor queda la ruta del
// teléfono), y se puede quitar del todo.

import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  test('sin servidor la foto queda con la ruta del teléfono', () async {
    await repo.setProfilePhoto('/data/user/0/io.ceres.app/cache/yo.jpg');
    expect(repo.profile.avatarPath, '/data/user/0/io.ceres.app/cache/yo.jpg');
  });

  test('quitar la foto la deja en null, no en la anterior', () async {
    await repo.setProfilePhoto('/data/user/0/io.ceres.app/cache/yo.jpg');
    await repo.setProfilePhoto(null);
    expect(repo.profile.avatarPath, isNull);
  });

  test('cambiar otro dato del perfil no toca la foto', () async {
    await repo.setProfilePhoto('/data/user/0/io.ceres.app/cache/yo.jpg');
    await repo.updateProfile(repo.profile.copyWith(displayName: 'Mati'));
    expect(repo.profile.avatarPath, '/data/user/0/io.ceres.app/cache/yo.jpg');
  });
}
