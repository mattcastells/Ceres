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

  /// Se suma a la nutricionista dueña de ese código.
  ///
  /// Desde la migración 55 no hay categorías: la profesional ve todo. La
  /// función conserva sus parámetros de categorías por la app publicada, pero
  /// los ignora.
  Future<void> grant({required String code}) async {
    try {
      await _db
          .rpc<String>(
            'grant_care_access',
            params: <String, dynamic>{'p_code': code.trim().toUpperCase()},
          )
          .timeout(timeout);
    } on PostgrestException catch (error) {
      // La función levanta `ERR_NOT_FOUND` y `ERR_VALIDATION` con un `hint`
      // ya redactado para mostrar.
      throw AppError(
        code: error.message.contains('ERR_NOT_FOUND')
            ? ApiErrorCode.notFound
            : ApiErrorCode.validation,
        message: error.hint ?? 'No pudimos sumarte. Revisá el código.',
        requestId: error.message,
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Darse de baja. La fila queda con `revoked_at`, no se borra: un acceso a
  /// datos de salud que desaparece sin rastro no se puede auditar.
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

  /// Las invitaciones pendientes a tu mail (migración 56). Si la consulta
  /// falla se devuelve vacío: la pantalla sigue andando con el código.
  Future<List<CareInvite>> invites() async {
    try {
      final rows = await _db
          .rpc<List<dynamic>>('my_care_invites')
          .timeout(timeout);
      return rows
          .whereType<Map<String, dynamic>>()
          .map(CareInvite.fromRow)
          .whereType<CareInvite>()
          .toList();
    } on Exception {
      return const <CareInvite>[];
    }
  }

  /// Aceptar una invitación: desde acá la nutricionista ve lo que registrás.
  /// Si ya tenés otra, la base lo rechaza con un `hint` que lo dice.
  Future<void> acceptInvite(String id) async {
    try {
      await _db
          .rpc<String>(
            'accept_care_invite',
            params: <String, dynamic>{'p_id': id},
          )
          .timeout(timeout);
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.validation,
        message: error.hint ?? 'No pudimos aceptar la invitación.',
        requestId: error.message,
      );
    } on Exception {
      throw _offline;
    }
  }

  Future<void> declineInvite(String id) async {
    try {
      await _db
          .rpc<void>(
            'decline_care_invite',
            params: <String, dynamic>{'p_id': id},
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
