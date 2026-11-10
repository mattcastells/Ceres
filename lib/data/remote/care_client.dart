import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/care_grant.dart';

/// Los permisos que esta cuenta le dio a un profesional.
///
/// Del lado de la app solo se **concede y se revoca**. Leer los datos con ese
/// permiso es cosa del backoffice, que entra con la sesión del profesional y
/// contra las mismas políticas: acá no hay nada que sirva para mirar lo ajeno.
class CareClient {
  CareClient(this._db);

  factory CareClient.fromInstance() => CareClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Mismo plazo y mismo motivo que en `PalsClient`: ningún `await` contra la
  /// red sin plazo propio. Con señal mala el socket se abre y no contesta, y
  /// sin esto la pantalla se queda con el botón girando, sin error y sin
  /// salida.
  static const Duration timeout = Duration(seconds: 30);

  String get _me => _db.auth.currentUser?.id ?? '';

  /// Los permisos vigentes, con el nombre de cada profesional.
  ///
  /// El nombre sale de `care_professionals` y no de un join: es una vista de
  /// dos columnas que existe porque abrir `profiles` por policy abre la fila
  /// entera, códigos incluidos. Son dos consultas porque PostgREST solo embebe
  /// atravesando una FK y una vista no la tiene; el costo es una consulta más
  /// sobre una lista del tamaño de "mis profesionales".
  Future<List<CareGrant>> list() async {
    try {
      final rows = await _db
          .from('care_grants')
          .select(
            'id, professional_id, share_meals, share_photos, share_body, '
            'share_wellbeing, expires_at',
          )
          .eq('owner_id', _me)
          .eq('status', 'accepted')
          .isFilter('revoked_at', null)
          .order('created_at')
          .timeout(timeout);
      if (rows.isEmpty) return const <CareGrant>[];

      final names = await _db
          .from('care_professionals')
          .select('id, display_name')
          .inFilter(
            'id',
            rows.map((r) => r['professional_id'] as String).toSet().toList(),
          )
          .timeout(timeout);
      final nameById = <String, String>{
        for (final n in names)
          n['id'] as String: n['display_name'] as String? ?? '',
      };

      return rows
          .map<CareGrant>(
            (row) => CareGrant.fromRow(
              row,
              displayName: nameById[row['professional_id']] ?? '',
            ),
          )
          .toList();
    } on Exception {
      throw _offline;
    }
  }

  /// Concede o actualiza el permiso de un profesional, por su código.
  ///
  /// El mismo llamado sirve para las dos cosas a propósito: cambiar qué ve es
  /// volver a decir qué ve. Un camino aparte para "editar" sería otra ruta que
  /// mantener hacia el mismo lugar.
  Future<void> grant({
    required String code,
    required CareCategories categories,
    DateTime? expiresAt,
  }) async {
    try {
      await _db
          .rpc<String>(
            'grant_care_access',
            params: <String, dynamic>{
              'p_code': code.trim().toUpperCase(),
              'p_share_meals': categories.meals,
              'p_share_photos': categories.photos,
              'p_share_body': categories.body,
              'p_share_wellbeing': categories.wellbeing,
              'p_expires_at': expiresAt?.toUtc().toIso8601String(),
            },
          )
          .timeout(timeout);
    } on PostgrestException catch (error) {
      // La función levanta `ERR_NOT_FOUND` y `ERR_VALIDATION` con un `hint`
      // ya redactado para mostrar. Se respeta ese texto en vez de reescribirlo
      // acá: el servidor sabe por qué falló y el cliente no.
      throw AppError(
        code: error.message.contains('ERR_NOT_FOUND')
            ? ApiErrorCode.notFound
            : ApiErrorCode.validation,
        message: error.hint ?? 'No pudimos dar el acceso. Revisá el código.',
        requestId: error.message,
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Cambia qué ve un permiso que ya existe.
  ///
  /// Va por `update` directo y no por `grant_care_access` porque esa función
  /// toma el **código** del profesional, y el dueño no lo tiene ni puede
  /// leerlo: `care_professionals` expone id y nombre, nada más, para que el
  /// código ajeno no viaje. La policy `care_grants_owner_manages` ya permite
  /// este update, así que no hace falta una función para algo que RLS resuelve.
  Future<void> updateCategories({
    required String grantId,
    required CareCategories categories,
  }) async {
    try {
      await _db
          .from('care_grants')
          .update(<String, dynamic>{
            'share_meals': categories.meals,
            'share_photos': categories.photos,
            'share_body': categories.body,
            'share_wellbeing': categories.wellbeing,
          })
          .eq('id', grantId)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Corta el acceso. La fila queda con `revoked_at`, no se borra: un permiso
  /// sobre datos de salud que desaparece sin rastro no se puede auditar.
  Future<void> revoke(String grantId) async {
    try {
      await _db
          .rpc<void>(
            'revoke_care_access',
            params: <String, dynamic>{'p_grant_id': grantId},
          )
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }


  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No pudimos conectarnos. Revisá tu conexión.',
  );
}
