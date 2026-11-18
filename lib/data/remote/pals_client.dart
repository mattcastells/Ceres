import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/models/pal.dart';

/// Resultado de pedir un pal por código. Lo devuelve el RPC.
enum PalRequestResult {
  sent('sent'),
  notFound('not_found'),
  self('self'),
  already('already'),
  rateLimited('rate_limited');

  const PalRequestResult(this.wire);

  final String wire;

  static PalRequestResult fromWire(String? w) => PalRequestResult.values
      .firstWhere((r) => r.wire == w, orElse: () => PalRequestResult.notFound);
}

/// Vínculos con otras personas y sus días compartidos.
class PalsClient {
  PalsClient(this._db);

  factory PalsClient.fromInstance() => PalsClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Ningún `await` contra la red sin plazo propio.
  ///
  /// Los clientes de Supabase no lo traen, y acá la falta se pagaba caro:
  /// `PalPublisher.publish` se queda con `_publishing = true` para siempre, así
  /// que **la cuenta deja de publicar su día** hasta que se reinicie la app; y
  /// la pantalla de Pals se queda en el esqueleto, o con "Enviar solicitud"
  /// girando, sin error y sin salida. Con señal mala —el socket se abre y no
  /// contesta— el `Future` no termina nunca.
  static const Duration timeout = Duration(seconds: 30);

  String get _me => _db.auth.currentUser?.id ?? '';

  /// El nombre que ven los pals.
  ///
  /// Vive en `profiles`, que es la única tabla de servidor que la app escribe
  /// fuera del respaldo. Si no se setea nunca, el trigger de alta deja la parte
  /// del correo anterior a la arroba, y eso es lo que terminan viendo los
  /// demás.
  Future<void> setDisplayName(String name) async {
    try {
      await _db
          .from('profiles')
          .update(<String, dynamic>{'display_name': name})
          .eq('id', _me)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Código propio, el que se le pasa a alguien para que te agregue.
  Future<String?> myCode() async {
    try {
      final row = await _db
          .from('profiles')
          .select('pal_code')
          .eq('id', _me)
          .maybeSingle()
          .timeout(timeout);
      return row?['pal_code'] as String?;
    } on Exception {
      return null;
    }
  }

  Future<PalRequestResult> request(String code) async {
    try {
      final result = await _db
          .rpc<String>('request_pal', params: <String, dynamic>{'p_code': code})
          .timeout(timeout);
      return PalRequestResult.fromWire(result);
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos mandar la solicitud.',
        requestId: error.message,
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Todos los vínculos, en las dos direcciones.
  ///
  /// El nombre sale de `pal_profiles` y no de un join con `profiles`. Es una
  /// vista de dos columnas —id y nombre— que existe justamente porque la
  /// policy que abría `profiles` a los pals abría **la fila entera**: fecha de
  /// nacimiento, altura, sexo y el código de pal, y encima con la solicitud
  /// todavía sin aceptar (migración 28).
  ///
  /// Son dos consultas y no un join embebido porque PostgREST solo embebe
  /// atravesando una FK, y una vista no la tiene. El costo es una consulta
  /// más sobre una lista de ids que tiene el tamaño de la agenda de alguien.
  Future<List<Pal>> list() async {
    try {
      final rows = await _db
          .from('pals')
          .select('id, status, requester_id, addressee_id')
          .order('created_at')
          .timeout(timeout);
      if (rows.isEmpty) return const <Pal>[];

      String otherOf(Map<String, dynamic> row) =>
          (row['addressee_id'] == _me
                  ? row['requester_id']
                  : row['addressee_id'])
              as String;

      final names = await _db
          .from('pal_profiles')
          .select('id, display_name')
          .inFilter('id', rows.map(otherOf).toSet().toList())
          .timeout(timeout);
      final nameById = <String, String>{
        for (final n in names)
          n['id'] as String: n['display_name'] as String? ?? '',
      };

      return rows.map<Pal>((row) {
        final other = otherOf(row);
        return Pal(
          id: row['id'] as String,
          userId: other,
          // Vacío si la vista no lo devuelve: la pantalla ya sabe mostrar un
          // vínculo sin nombre, y quedarse sin la lista entera por un nombre
          // que falta sería peor.
          displayName: nameById[other] ?? '',
          status: PalStatus.fromWire(row['status'] as String?),
          isIncoming: row['addressee_id'] == _me,
        );
      }).toList();
    } on Exception {
      throw _offline;
    }
  }

  Future<void> accept(String palId) => _setStatus(palId, PalStatus.accepted);

  Future<void> remove(String palId) async {
    try {
      await _db.from('pals').delete().eq('id', palId).timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  Future<void> _setStatus(String palId, PalStatus status) async {
    try {
      await _db
          .from('pals')
          .update(<String, dynamic>{
            'status': status.wire,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', palId)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// El día de un pal. `null` si todavía no publicó nada ese día.
  Future<PalDay?> dayOf(String userId, DateTime date) async {
    try {
      final row = await _db
          .from('shared_days')
          .select()
          .eq('user_id', userId)
          .eq('local_date', isoDate(date))
          .maybeSingle()
          .timeout(timeout);
      return row == null ? null : PalDay.fromRow(row);
    } on Exception {
      throw _offline;
    }
  }

  /// El día de todos los pals en una fecha. RLS solo deja ver los de pals
  /// aceptados (y el propio, que se descarta acá).
  Future<List<PalDay>> palDaysOn(DateTime date) async {
    try {
      final rows = await _db
          .from('shared_days')
          .select()
          .eq('local_date', isoDate(date))
          .neq('user_id', _me)
          .timeout(timeout);
      return <PalDay>[for (final row in rows) PalDay.fromRow(row)];
    } on Exception {
      throw _offline;
    }
  }

  /// Escucha en vivo lo que publican los pals (Realtime, migración 54).
  ///
  /// Realtime aplica RLS con la sesión de quien escucha: llegan solo los días
  /// de sus pals, igual que en una consulta. Devuelve con qué cortar.
  ///
  /// [onSubscribed] corre cada vez que el canal queda escuchando, también al
  /// reconectar: `supabase_flutter` corta Realtime cuando la app pasa a
  /// segundo plano y lo que pasó mientras tanto no llega por el canal.
  Future<void> Function() listenPalDays(
    void Function(PalDay day) onDay, {
    void Function()? onSubscribed,
  }) {
    final me = _me;
    final channel = _db.channel('pal-days-$me')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'shared_days',
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty || row['user_id'] == me) return;
          try {
            onDay(PalDay.fromRow(row));
          } on Object {
            // Una fila que no se entiende no puede tirar la escucha entera.
          }
        },
      )
      ..subscribe((status, error) {
        if (kDebugMode) debugPrint('pal-days realtime: $status ${error ?? ''}');
        if (status == RealtimeSubscribeStatus.subscribed) onSubscribed?.call();
      });
    return () async {
      await _db.removeChannel(channel);
    };
  }

  /// Publica varios días propios de una. Sobrescribe la fila de cada fecha.
  ///
  /// En **un** pedido y no uno por día: la ventana que puede mirar un pal son
  /// ocho fechas, y corregir el día de anteayer no puede costar ocho viajes.
  /// La clave primaria es `(user_id, local_date)`, así que el upsert resuelve
  /// por día sin necesidad de decirle sobre qué.
  Future<void> publishDays(List<PalDay> days) async {
    if (days.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _db
          .from('shared_days')
          .upsert(<Map<String, dynamic>>[
            for (final day in days)
              <String, dynamic>{
                'user_id': _me,
                ...day.toRow(),
                'updated_at': now,
              },
          ])
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Qué comparte esta cuenta con sus pals.
  Future<PalSharingPrefs> mySharingPrefs() async {
    try {
      final row = await _db
          .from('profiles')
          .select(PalSharingPrefs.columns.join(', '))
          .eq('id', _me)
          .maybeSingle()
          .timeout(timeout);
      return row == null
          ? const PalSharingPrefs()
          : PalSharingPrefs.fromRow(row);
    } on Exception {
      throw _offline;
    }
  }

  Future<void> setSharingPrefs(PalSharingPrefs prefs) async {
    try {
      await _db
          .from('profiles')
          .update(prefs.toRow())
          .eq('id', _me)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: se reintenta cuando vuelva internet.',
  );
}
