import 'package:ceres/domain/models/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('lee una versión simple', () {
      final version = AppVersion.tryParse('1.2.3')!;
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.isPreRelease, isFalse);
    });

    test('tolera la v inicial de los tags de git', () {
      expect(AppVersion.tryParse('v1.2.3'), AppVersion.tryParse('1.2.3'));
      expect(AppVersion.tryParse('V1.2.3'), AppVersion.tryParse('1.2.3'));
    });

    test('descarta el +build, que no cuenta para la precedencia', () {
      expect(AppVersion.tryParse('1.0.0+7'), AppVersion.tryParse('1.0.0'));
    });

    test('lee los identificadores de pre-release', () {
      final version = AppVersion.tryParse('1.0.0-beta.2')!;
      expect(version.preRelease, <String>['beta', '2']);
      expect(version.toString(), '1.0.0-beta.2');
    });

    test('rechaza lo que no es una versión', () {
      for (final raw in <String>[
        '',
        '1.2',
        '1.2.3.4',
        'uno.dos.tres',
        '1.2.x',
        '1..3',
        '1.2.-3',
        '1.2.3-',
        '1.2.3-alpha..1',
        'latest',
      ]) {
        expect(AppVersion.tryParse(raw), isNull, reason: 'debía rechazar "$raw"');
      }
    });

    test('no acepta el signo que int.tryParse dejaría pasar', () {
      // `int.tryParse('+5')` devuelve 5: sin validar dígitos, '1.2.+5' pasaría.
      expect(AppVersion.tryParse('1.2.+5'), isNull);
    });
  });

  group('AppVersion · precedencia', () {
    AppVersion v(String raw) => AppVersion.tryParse(raw)!;

    test('compara mayor, menor y parche como números, no como texto', () {
      expect(v('1.0.10') > v('1.0.9'), isTrue);
      expect(v('1.10.0') > v('1.9.0'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
    });

    test('una pre-release es anterior a su versión final', () {
      expect(v('1.0.0-beta') < v('1.0.0'), isTrue);
      expect(v('1.0.0') > v('1.0.0-rc.1'), isTrue);
    });

    test('entre pre-releases, lo numérico pesa menos que lo alfanumérico', () {
      expect(v('1.0.0-alpha.1') < v('1.0.0-alpha.beta'), isTrue);
      expect(v('1.0.0-alpha.2') > v('1.0.0-alpha.1'), isTrue);
      expect(v('1.0.0-alpha') < v('1.0.0-alpha.1'), isTrue);
    });

    test('la cadena del ejemplo de semver queda ordenada', () {
      final versions = <AppVersion>[
        v('1.0.0-alpha'),
        v('1.0.0-alpha.1'),
        v('1.0.0-alpha.beta'),
        v('1.0.0-beta'),
        v('1.0.0-beta.2'),
        v('1.0.0-beta.11'),
        v('1.0.0-rc.1'),
        v('1.0.0'),
      ];
      for (var i = 1; i < versions.length; i++) {
        expect(
          versions[i - 1] < versions[i],
          isTrue,
          reason: '${versions[i - 1]} debía ser anterior a ${versions[i]}',
        );
      }
    });

    test('dos versiones iguales no se ofrecen como actualización', () {
      expect(v('1.2.3') > v('1.2.3'), isFalse);
      expect(v('1.2.3') == v('1.2.3+9'), isTrue);
    });
  });

  group('AppRelease', () {
    AppRelease release(int bytes) => AppRelease(
      version: const AppVersion(1, 0, 0),
      tag: 'v1.0.0',
      notes: '',
      apkUrl: Uri.parse('https://example.test/app.apk'),
      apkSizeBytes: bytes,
      publishedAt: DateTime(2026, 7, 28),
    );

    test('el tamaño se muestra en la unidad que se entiende de un vistazo', () {
      expect(release(26 * 1024 * 1024).apkSizeLabel, '26.0 MB');
      expect(release(512 * 1024).apkSizeLabel, '512 kB');
    });
  });
}
