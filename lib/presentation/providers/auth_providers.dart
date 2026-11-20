import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/supabase_config.dart';
import '../../data/local/pal_alert_store.dart';
import '../../data/remote/care_client.dart';
import '../../data/remote/pals_client.dart';
import '../../domain/models/care_grant.dart';
import '../../domain/models/pal.dart';
import '../../domain/repositories/auth_gateway.dart';
import '../../domain/services/cloud_backup_service.dart';
import '../../domain/services/pal_alerts.dart';
import '../../domain/services/pal_publisher.dart';
import '../../domain/services/photo_sync_service.dart';
import '../../domain/services/relational_sync_service.dart';

/// Se sobrescribe en `bootstrap.dart` con la implementación que corresponda:
/// Supabase si la compilación trae credenciales, local si no.
final authGatewayProvider = Provider<AuthGateway>(
  (ref) => throw UnimplementedError('authGatewayProvider sin inicializar'),
);

/// `true` cuando la sesión es real contra el servidor. En `false` la app anda
/// igual, pero los datos no salen del teléfono.
final isCloudEnabledProvider = Provider<bool>(
  (ref) => SupabaseConfig.isConfigured,
);

/// Servicio de respaldo a la nube. Se sobrescribe en `bootstrap.dart` solo
/// cuando hay servidor; sin él, la app no respalda sola y lo dice en Ajustes.
final cloudBackupProvider = Provider<CloudBackupService?>((ref) => null);

/// Estado del respaldo para la UI.
final backupStateProvider = StreamProvider<BackupState>((ref) async* {
  final service = ref.watch(cloudBackupProvider);
  if (service == null) {
    yield BackupUnavailable(
      SupabaseConfig.unavailableReason ?? 'Sin servidor configurado.',
    );
    return;
  }
  // El estado actual primero, igual que `syncStateProvider`: `states` es un
  // broadcast **sin repetición**, así que quien abría la pantalla después de un
  // fallo no veía nada hasta el próximo cambio — justo el caso en el que uno la
  // abre. Y con el stream mudo la pantalla decía "Al día", que es la misma
  // clase de mentira que costó meses de `meals` vacíos.
  yield service.state;
  yield* service.states;
});

/// Persistencia relacional: las mismas cosas del respaldo, como filas en las
/// tablas. Null sin servidor.
final relationalSyncProvider = Provider<RelationalSyncService?>((ref) => null);

/// Cómo viene la escritura en las tablas, para poder mirarla desde Ajustes.
///
/// **Existe porque su ausencia costó meses de datos.** Cuatro restricciones de
/// la base se habían quedado atrás de sus enums y rechazaban cada fila que la
/// app mandaba; el servicio lo registraba como `SyncFailed` y ninguna pantalla
/// lo mostraba, así que la app se veía perfecta mientras la base quedaba vacía.
/// Un fallo que no se ve no existe hasta que es tarde.
final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final service = ref.watch(relationalSyncProvider);
  if (service == null) return;
  // El estado actual primero: `states` es un broadcast y quien abre la pantalla
  // después de un fallo no vería nada hasta el próximo cambio — justo el caso
  // en el que uno la abre.
  yield service.state;
  yield* service.states;
});

/// Sube y sirve las fotos del bucket. Null sin servidor: las fotos quedan
/// solo en este teléfono.
final photoSyncProvider = Provider<PhotoSyncService?>((ref) => null);

/// Vínculos con pals y sus días. Null sin servidor: la función no existe.
final palsClientProvider = Provider<PalsClient?>((ref) => null);

/// Permisos dados a profesionales. Null sin servidor: sin cuenta los datos no
/// salieron del teléfono, así que no hay nada que conceder.
final careClientProvider = Provider<CareClient?>((ref) => null);

/// Los permisos vigentes, recargables tras conceder o revocar.
///
/// `autoDispose` por lo mismo que `palsProvider`: sin eso la lista se consulta
/// una sola vez por sesión de app y revocar desde otro lado no se vería nunca
/// hasta reiniciar.
final careGrantsProvider = FutureProvider.autoDispose<List<CareGrant>>((
  ref,
) async {
  final client = ref.watch(careClientProvider);
  if (client == null) return <CareGrant>[];
  return client.list();
});

/// Las invitaciones de nutricionistas que esperan respuesta (migración 56).
final careInvitesProvider = FutureProvider.autoDispose<List<CareInvite>>((
  ref,
) async {
  final client = ref.watch(careClientProvider);
  if (client == null) return const <CareInvite>[];
  return client.invites();
});

/// Los vínculos, recargables tras aceptar o quitar uno.
///
/// `autoDispose` a propósito: sin eso la lista se consultaba **una sola vez por
/// sesión de app** y quedaba en caché. Quien abría Pals antes de que le
/// llegara una solicitud no la veía aparecer nunca —ni saliendo de la pantalla
/// y volviendo— hasta cerrar y reabrir la app. La solicitud sí estaba en el
/// servidor: lo que no se rehacía era la consulta.
final palsProvider = FutureProvider.autoDispose<List<Pal>>((ref) async {
  final client = ref.watch(palsClientProvider);
  if (client == null) return <Pal>[];
  return client.list();
});

/// Cuántas solicitudes entrantes están sin responder, para avisar desde Perfil.
///
/// Una solicitud que solo se descubre entrando a Pals a ver si hay algo no
/// llega: este es el aviso.
final incomingPalRequestsProvider = Provider.autoDispose<int>(
  (ref) =>
      ref
          .watch(palsProvider)
          .value
          ?.where((p) => p.status == PalStatus.pending && p.isIncoming)
          .length ??
      0,
);

/// Código propio para que alguien te agregue.
///
/// `autoDispose` por lo mismo que `palsProvider`, y con una vuelta de tuerca:
/// un `FutureProvider` global no solo cachea el valor, también **cachea el
/// error**. Abrir Pals una vez sin conexión dejaba el código en "…" el resto de
/// la sesión —el botón "Actualizar" invalida `palsProvider` y no este—, y el
/// código es lo único que alguien necesita para que lo agreguen.
final myPalCodeProvider = FutureProvider.autoDispose<String?>((ref) async {
  final client = ref.watch(palsClientProvider);
  return client?.myCode();
});

/// Qué comparte esta cuenta con sus pals. `autoDispose` para que volver a entrar a la pantalla de privacidad
/// después de guardar traiga el valor real, no uno en caché de la visita
/// anterior.
final myPalSharingPrefsProvider = FutureProvider.autoDispose<PalSharingPrefs>((
  ref,
) async {
  final client = ref.watch(palsClientProvider);
  if (client == null) return const PalSharingPrefs();
  return client.mySharingPrefs();
});

/// Quien publica el día propio para los pals. Se sobrescribe en `bootstrap.dart`
/// con servidor; hace falta acá para volver a publicar en cuanto cambia una
/// preferencia, y no recién con la próxima comida.
final palPublisherProvider = Provider<PalPublisher?>((ref) => null);

final palAlertStoreProvider = Provider<PalAlertStore>((ref) => PalAlertStore());

/// Los avisos de pals de este teléfono.
final palAlertPrefsProvider =
    AsyncNotifierProvider<PalAlertPrefsNotifier, PalAlertPrefs>(
      PalAlertPrefsNotifier.new,
    );

class PalAlertPrefsNotifier extends AsyncNotifier<PalAlertPrefs> {
  @override
  Future<PalAlertPrefs> build() => ref.read(palAlertStoreProvider).load();

  Future<void> set(PalAlertPrefs value) async {
    state = AsyncData(value);
    await ref.read(palAlertStoreProvider).save(value);
  }
}
