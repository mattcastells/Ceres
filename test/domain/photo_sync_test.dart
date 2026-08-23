import 'package:ceres/domain/services/photo_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRemotePath', () {
    test('reconoce una ruta del bucket', () {
      expect(
        PhotoSyncService.isRemotePath(
          '11111111-1111-1111-1111-111111111111/aaaa0001.jpg',
        ),
        isTrue,
      );
    });

    test('una ruta de archivo de Android no es del bucket', () {
      expect(
        PhotoSyncService.isRemotePath(
          '/data/user/0/io.ceres.app/cache/CAP123.jpg',
        ),
        isFalse,
      );
    });

    test('una ruta de Windows tampoco', () {
      expect(
        PhotoSyncService.isRemotePath(r'C:\Users\yo\AppData\Temp\foto.jpg'),
        isFalse,
      );
    });

    test('una ruta sin carpeta no es del bucket', () {
      // Importante: la política del bucket compara la primera carpeta con
      // auth.uid(), así que una ruta suelta no estaría protegida por nadie.
      expect(PhotoSyncService.isRemotePath('foto.jpg'), isFalse);
    });

    test('una ruta con carpetas de más tampoco', () {
      expect(PhotoSyncService.isRemotePath('a/b/c.jpg'), isFalse);
    });
  });
}
