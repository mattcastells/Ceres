// Actualizar desde adentro de la app.
//
// El aviso de versión nueva mandaba a Configuración → Actualizaciones, y ahí
// había que encontrar el botón entre el número de versión, la fecha, el cuerpo
// del release —o sea la lista de commits del tag— y un enlace a GitHub. Lo que
// se fija acá es lo contrario: que el diálogo diga qué versión viene y cuánto
// pesa, que aceptar baje e instale sin cambiar de pantalla, y que el changelog
// no vuelva a aparecer.

import 'dart:convert';
import 'dart:io';

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/remote/github_releases_client.dart';
import 'package:ceres/domain/models/app_release.dart';
import 'package:ceres/domain/services/update_service.dart';
import 'package:ceres/presentation/providers/update_providers.dart';
import 'package:ceres/presentation/screens/settings/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _notas = 'feat: recalcular con IA\nfix: el día manda, no el id';

/// Un APK chico pero de más de un mega, para que la etiqueta diga "MB" como en
/// la vida real. El cliente compara lo descargado contra este tamaño y descarta
/// lo que no coincide, así que el falso tiene que devolver exactamente esto.
const int _apkBytes = 2 * 1024 * 1024;

/// El release que devuelve la API, con notas bien visibles: si alguna vez
/// vuelven a la pantalla, estos tests lo dicen.
String _releaseJson() => jsonEncode(<String, dynamic>{
  'tag_name': 'v1.16.0',
  'body': _notas,
  'published_at': '2026-08-05T15:04:05Z',
  'assets': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'ceres-1.16.0-universal.apk',
      'size': _apkBytes,
      'browser_download_url': 'https://example.test/ceres-universal.apk',
    },
  ],
});

class _FakeInstaller implements ApkInstaller {
  _FakeInstaller(this.dir);

  final Directory dir;

  String? installed;
  bool allowed = true;
  int settingsOpened = 0;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<String> stagingPath(String fileName) async =>
      '${dir.path}${Platform.pathSeparator}$fileName';

  @override
  Future<void> install(String path) async => installed = path;
}

void main() {
  late Directory dir;
  late _FakeInstaller installer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nm_update_dialog');
    installer = _FakeInstaller(dir);
  });

  tearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows no deja borrar un archivo que todavía tiene un descriptor
      // abierto. Es un temporal del sistema: se limpia solo.
    }
  });

  UpdateService buildService() => UpdateService(
    client: GithubReleasesClient(
      client: MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            _releaseJson(),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response.bytes(List<int>.filled(_apkBytes, 7), 200);
      }),
    ),
    installer: installer,
  );

  Future<UpdateAvailable> available() async {
    final status = await buildService().check(
      current: const AppVersion(1, 15, 0),
    );
    return status as UpdateAvailable;
  }

  Future<void> mostrar(WidgetTester tester, UpdateAvailable status) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          updateServiceProvider.overrideWithValue(buildService()),
        ],
        child: MaterialApp(
          theme: NmAppTheme.dark(),
          locale: const Locale('es', 'AR'),
          home: Scaffold(body: UpdateDialog(available: status)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('dice qué versión viene y cuánto pesa', (tester) async {
    await mostrar(tester, await available());

    expect(find.text('Hay una versión nueva'), findsOneWidget);
    expect(find.textContaining('1.15.0 → 1.16.0'), findsOneWidget);
    expect(find.textContaining('MB'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
  });

  testWidgets('no muestra el changelog ni manda a GitHub', (tester) async {
    await mostrar(tester, await available());

    expect(find.textContaining('recalcular con IA'), findsNothing);
    expect(find.textContaining('Qué cambió'), findsNothing);
    expect(find.textContaining('GitHub'), findsNothing);
  });

  testWidgets('aceptar baja el APK y se lo pasa al instalador', (tester) async {
    await mostrar(tester, await available());

    await tester.tap(find.text('Actualizar'));
    await tester.pump();
    // La descarga escribe a disco de verdad, y el reloj falso de `testWidgets`
    // no hace avanzar el E/S real: hay que devolverle el control al de verdad.
    // De a tandas porque son varios pasos encadenados —bajar, vaciar el buffer,
    // cerrar el archivo, entregárselo al instalador— y cada uno vuelve por el
    // bucle de eventos.
    for (var i = 0; i < 10 && installer.installed == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(installer.installed, isNotNull);
    expect(File(installer.installed!).existsSync(), isTrue);
    expect(find.text('Descargada'), findsOneWidget);
  });

  testWidgets('sin el permiso de instalar, primero lleva a Ajustes', (
    tester,
  ) async {
    // Bajar 25 MB para chocar contra un permiso que se podía pedir antes es
    // gastarle los datos a alguien al pedo.
    installer.allowed = false;
    await mostrar(tester, await available());
    await tester.pump();

    expect(find.text('Habilitar'), findsOneWidget);
    await tester.tap(find.text('Habilitar'));
    await tester.pump();

    expect(installer.settingsOpened, 1);
    expect(installer.installed, isNull, reason: 'no bajó nada todavía');
  });
}
