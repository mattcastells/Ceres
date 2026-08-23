// Que una foto ocupe una vez lo que tiene que ocupar, y deje de ocupar cuando
// ya no la mira nadie.
//
// Storage es lo único de este proyecto que crece rápido: una foto son ~200 kB
// contra los ~200 bytes de la fila que la nombra. Los tres agujeros que se
// prueban acá no se veían por ningún lado —la app funcionaba igual— y entre los
// tres multiplicaban por varias veces lo que se paga.

import 'dart:io';
import 'dart:typed_data';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/local/photo_normalizer.dart';
import 'package:ceres/data/remote/photo_storage_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/domain/services/photo_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuth implements AuthGateway {
  @override
  AuthAccount? get currentAccount => const AuthAccount(id: 'u1', email: 'yo@t');
  @override
  bool get hasSession => true;
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
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> deleteAccount() async {}
}

/// Guarda a qué rutas se le pidió borrar, que es lo único que hace falta saber.
/// Un Storage que no contesta: es lo que devuelve `remove` sin conexión.
class _SinConexionStorage implements SupabaseStorageClient {
  @override
  StorageFileApi from(String id) => _SinConexionFileApi();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _SinConexionFileApi implements StorageFileApi {
  @override
  Future<List<FileObject>> remove(List<String> paths) =>
      throw const SocketException('sin conexión');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Un Storage al que ya le habían borrado el objeto.
class _NoEstaStorage implements SupabaseStorageClient {
  @override
  StorageFileApi from(String id) => _NoEstaFileApi();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _NoEstaFileApi implements StorageFileApi {
  @override
  Future<List<FileObject>> remove(List<String> paths) =>
      throw const StorageException('Object not found', statusCode: '404');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeStorage implements PhotoStorageClient {
  final List<String> borradas = <String>[];
  AppError? fallaCon;

  @override
  Future<void> remove({
    required PhotoBucket bucket,
    required String path,
  }) async {
    if (fallaCon != null) throw fallaCon!;
    borradas.add(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Meal _meal({
  required String id,
  String? photoPath,
  DateTime? deletedAt,
}) => Meal(
  id: id,
  slot: MealSlot.lunch,
  eatenAt: DateTime(2026, 7, 20, 13),
  localDate: DateTime(2026, 7, 20),
  items: const <MealItem>[],
  source: MealSource.aiPhoto,
  photoPath: photoPath,
  deletedAt: deletedAt,
  createdAt: DateTime(2026, 7, 20, 13),
  updatedAt: DateTime(2026, 7, 20, 13),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStorage storage;
  late LocalRepository repo;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _FakeStorage();
    repo = LocalRepository(
      await LocalStore.open(),
      photos: PhotoSyncService(client: storage, auth: _FakeAuth()),
      onChanged: () {},
    );
  }

  group('las fotos de comidas borradas se van del bucket', () {
    test('una comida borrada hace días pierde su foto', () async {
      await boot();
      repo.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: 'u1/m1.jpg',
          deletedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

      final borradas = await repo.purgeDeletedPhotos();

      expect(borradas, 1);
      expect(storage.borradas, <String>['u1/m1.jpg']);
      // La lápida se queda: es lo que le dice a la reconciliación que esa
      // comida no volvió a aparecer sola. Lo que se va es el megabyte.
      expect(repo.allMeals.single.deletedAt, isNotNull);
      expect(repo.allMeals.single.photoPath, isNull);
    });

    test('lo recién borrado no se toca: la ventana de deshacer manda', () async {
      await boot();
      repo.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: 'u1/m1.jpg',
          deletedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ];

      expect(await repo.purgeDeletedPhotos(), 0);
      expect(storage.borradas, isEmpty);
      expect(repo.allMeals.single.photoPath, 'u1/m1.jpg');
    });

    test('una comida viva conserva su foto, obviamente', () async {
      await boot();
      repo.store.meals = <Meal>[_meal(id: 'm1', photoPath: 'u1/m1.jpg')];

      expect(await repo.purgeDeletedPhotos(), 0);
      expect(storage.borradas, isEmpty);
    });

    test('una ruta local no se manda a borrar al servidor', () async {
      await boot();
      repo.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: '/data/user/0/io.ceres/cache/foto.jpg',
          deletedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

      expect(await repo.purgeDeletedPhotos(), 0);
      expect(storage.borradas, isEmpty);
    });

    test('si el borrado falla, la ruta se conserva y se reintenta', () async {
      await boot();
      repo.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: 'u1/m1.jpg',
          deletedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];
      storage.fallaCon = const AppError(
        code: ApiErrorCode.offline,
        message: 'sin conexión',
      );

      expect(await repo.purgeDeletedPhotos(), 0);
      // Limpiar la ruta sin haber borrado dejaría la foto en el bucket sin nada
      // que la nombre: huérfana para siempre y ahora sin rastro.
      expect(repo.allMeals.single.photoPath, 'u1/m1.jpg');

      storage.fallaCon = null;
      expect(await repo.purgeDeletedPhotos(), 1);
      expect(storage.borradas, <String>['u1/m1.jpg']);
    });

    test('sin conexión, el cliente real avisa en vez de fingir que borró',
        () async {
      // El test de arriba usa un doble que lanza `AppError`, así que probaba la
      // reacción de la purga y no el eslabón que fallaba. El bug estaba **acá**:
      // `PhotoStorageClient.remove` capturaba `on Exception` y no hacía nada,
      // así que un `SocketException` —estar sin conexión— salía como éxito. La
      // purga entonces limpiaba `photoPath` sin haber borrado nada, y la foto
      // quedaba en el bucket sin nada que la nombre: huérfana para siempre.
      final cliente = PhotoStorageClient(_SinConexionStorage());

      await expectLater(
        cliente.remove(bucket: PhotoBucket.meal, path: 'u1/m1.jpg'),
        throwsA(isA<AppError>()),
      );
    });

    test('una foto que ya no está cuenta como borrada', () async {
      // El 404 es el final que la purga buscaba, así que no es un fallo: si
      // lanzara, la ruta no se limpiaría nunca y se reintentaría en cada
      // arranque contra un objeto que no existe.
      final cliente = PhotoStorageClient(_NoEstaStorage());

      await expectLater(
        cliente.remove(bucket: PhotoBucket.meal, path: 'u1/m1.jpg'),
        completes,
      );
    });

    test('pasar dos veces no vuelve a pedir el borrado', () async {
      await boot();
      repo.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: 'u1/m1.jpg',
          deletedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

      await repo.purgeDeletedPhotos();
      await repo.purgeDeletedPhotos();

      // Sin marca no habría con qué distinguir "ya borrada" de "por borrar", y
      // cada arranque saldría a la red por cada comida borrada de la historia.
      expect(storage.borradas, hasLength(1));
    });

    test('sin servidor no hay nada que barrer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final local = LocalRepository(await LocalStore.open(), onChanged: () {});
      local.store.meals = <Meal>[
        _meal(
          id: 'm1',
          photoPath: 'u1/m1.jpg',
          deletedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

      expect(await local.purgeDeletedPhotos(), 0);
      expect(local.allMeals.single.photoPath, 'u1/m1.jpg');
    });
  });

  group('la foto que ya está en el bucket no se vuelve a subir', () {
    test('guardar una comida con ruta remota no la sube de nuevo', () async {
      await boot();

      // Es el caso del análisis por foto: analizar ya la subió, y la pantalla de
      // revisión guarda la comida apuntando a esa copia. `ensureUploaded`
      // reconoce la ruta del bucket y no toca nada — si no, cada foto analizada
      // terminaba guardada dos veces.
      final guardada = await repo.saveMeal(
        _meal(id: 'm1', photoPath: 'u1/analisis.jpg'),
      );

      expect(guardada.photoPath, 'u1/analisis.jpg');
      expect(
        PhotoSyncService.isRemotePath(guardada.photoPath!),
        isTrue,
        reason: 'sigue apuntando a la copia que subió el análisis',
      );
    });
  });

  group('una foto con transparencia no se sube como PNG sin comprimir', () {
    test('se reconoce por los bytes, no por el nombre', () {
      expect(
        PhotoNormalizer.isPng(
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
        ),
        isTrue,
      );
      // Un JPEG empieza con `\xFF\xD8\xFF`.
      expect(
        PhotoNormalizer.isPng(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0])),
        isFalse,
      );
      expect(PhotoNormalizer.isPng(Uint8List.fromList(<int>[0x89])), isFalse);
      expect(PhotoNormalizer.isPng(Uint8List(0)), isFalse);
    });

    test('un archivo que no existe devuelve la misma ruta y no rompe', () async {
      const path = '/no/existe/foto.jpg';
      expect(await PhotoNormalizer.toJpeg(path), path);
    });

    test('un PNG con alfa sale JPEG opaco y pesa una fracción', () async {
      // Lo que devuelve `image_picker` cuando la imagen tiene canal alfa: un
      // PNG de 1024², sin comprimir, con el `imageQuality` ignorado.
      final origen = img.Image(width: 1024, height: 1024, numChannels: 4);
      // Degradado suave **más ruido**, que es a lo que se parece una foto.
      //
      // El primer intento de este test usaba solo el degradado y daba al revés:
      // un degradado perfecto es el mejor caso posible para PNG —los filtros lo
      // dejan en deltas constantes y termina en 7 kB— y el peor para JPEG. Lo
      // que hace grande a un PNG de una foto es el detalle que no se repite;
      // sin ruido, la prueba mide cualquier cosa menos lo que pasa de verdad.
      var semilla = 12345;
      int siguiente() {
        semilla = (semilla * 1103515245 + 12345) & 0x7FFFFFFF;
        return semilla;
      }

      for (var y = 0; y < origen.height; y++) {
        for (var x = 0; x < origen.width; x++) {
          final base = 60 + (x * 120) ~/ origen.width + (y * 60) ~/ origen.height;
          int canal() => (base + siguiente() % 45).clamp(0, 255);
          origen.setPixelRgba(x, y, canal(), canal(), canal(), 255);
        }
      }
      // Una esquina transparente, que es lo que fuerza el PNG.
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          origen.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }

      final dir = await Directory.systemTemp.createTemp('nm-photo-test');
      addTearDown(() => dir.delete(recursive: true));
      final png = File('${dir.path}/captura.png')
        ..writeAsBytesSync(img.encodePng(origen));

      final salida = await PhotoNormalizer.toJpeg(png.path);

      expect(salida, isNot(png.path), reason: 'se escribió un archivo nuevo');
      final bytes = File(salida).readAsBytesSync();
      expect(PhotoNormalizer.isPng(bytes), isFalse);
      expect(bytes.sublist(0, 3), <int>[0xFF, 0xD8, 0xFF], reason: 'es JPEG');

      // El punto entero: el PNG guarda cada píxel y el JPEG no.
      expect(
        bytes.length,
        lessThan(png.lengthSync() ~/ 2),
        reason: 'PNG ${png.lengthSync()} B → JPEG ${bytes.length} B',
      );

      // Y el alfa se compuso sobre blanco en vez de descartarse: descartarlo
      // deja esa esquina negra, que en una captura de pantalla se ve como un
      // manchón.
      final resultado = img.decodeJpg(bytes)!;
      final esquina = resultado.getPixel(10, 10);
      expect(esquina.r, greaterThan(240));
      expect(esquina.g, greaterThan(240));
      expect(esquina.b, greaterThan(240));
    });
  });

  test('hoy() no participa: el corte es por fecha de borrado', () async {
    await boot();
    repo.store.meals = <Meal>[
      _meal(
        id: 'm1',
        photoPath: 'u1/m1.jpg',
        deletedAt: today().subtract(LocalRepository.photoPurgeGrace * 2),
      ),
    ];

    expect(await repo.purgeDeletedPhotos(), 1);
  });
}
