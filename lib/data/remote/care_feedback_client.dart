import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/care_feedback.dart';

/// Lo que la nutricionista le publicó a esta cuenta: devoluciones e
/// indicaciones.
///
/// La app solo **lee y marca como leído**. Escribir es cosa del panel, con la
/// sesión de la profesional. Y qué se ve lo decide RLS: el paciente recibe
/// solo lo publicado y no borrado, así que un borrador no puede llegar acá
/// aunque el filtro de abajo se equivocara.
class CareFeedbackClient {
  CareFeedbackClient(this._db);

  factory CareFeedbackClient.fromInstance() =>
      CareFeedbackClient(Supabase.instance.client);

  final SupabaseClient _db;

  static const Duration timeout = Duration(seconds: 30);

  /// Más que esto no se muestra en una lista que se lee de arriba abajo, y sin
  /// tope una profesional muy activa haría crecer la consulta sin límite.
  static const int maxItems = 100;

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<List<CareFeedback>> list() async {
    try {
      // Los filtros repiten lo que ya garantiza la policy a propósito: así la
      // consulta usa el índice `(patient_id, published_at desc)` en vez de
      // dejar que RLS filtre fila por fila.
      final rows = await _db
          .from('care_feedback')
          .select(
            'id, author_id, kind, local_date, body, published_at, read_at, '
            // El objetivo recomendado (migración 53). Va en la misma consulta:
            // el vigente es la indicación más reciente que los trae, y la
            // lista ya viene ordenada así.
            'target_kcal, target_protein_g, target_carbs_g, target_fat_g, '
            'applied_at, '
            // La comida sobre la que es el comentario (migración 56).
            'meal_id',
          )
          .eq('patient_id', _me)
          .not('published_at', 'is', null)
          .isFilter('deleted_at', null)
          .order('published_at', ascending: false)
          .limit(maxItems)
          .timeout(timeout);
      if (rows.isEmpty) return const <CareFeedback>[];

      // El nombre sale de `care_professionals`, la vista de dos columnas que
      // ya usa la pantalla de accesos. Si una profesional dejó de tener
      // acceso, la vista no la devuelve y la devolución queda sin firma: lo
      // que escribió sigue valiendo.
      final nameById = await professionalNames(_db, <String>{
        for (final r in rows)
          if (r['author_id'] case final String id) id,
      });

      return parseRows(rows, namesById: nameById);
    } on Exception {
      throw _offline;
    }
  }

  /// Público para probarlo sin servidor: descarta las filas que no cierran en
  /// vez de tirar la lista entera.
  static List<CareFeedback> parseRows(
    List<dynamic> rows, {
    Map<String, String> namesById = const <String, String>{},
  }) => <CareFeedback>[
    for (final row in rows)
      if (row is Map)
        if (CareFeedback.fromRow(
              Map<String, dynamic>.from(row),
              authorName: namesById[row['author_id']] ?? '',
            )
            case final CareFeedback f)
          f,
  ];

  /// Marca como leída. Va por función y no por un `update`: una policy que
  /// dejara al paciente tocar `read_at` lo dejaría reescribir el texto de su
  /// nutricionista, porque RLS no limita columnas.
  Future<void> markRead(String id) async {
    try {
      await _db
          .rpc<void>(
            'mark_care_feedback_read',
            params: <String, dynamic>{'p_id': id},
          )
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Avisa que la persona aplicó el objetivo recomendado: pone `applied_at`
  /// (y `read_at`) para que la profesional lo vea en el panel. Va por función
  /// por lo mismo que [markRead].
  Future<void> markTargetApplied(String id) async {
    try {
      await _db
          .rpc<void>(
            'mark_care_target_applied',
            params: <String, dynamic>{'p_id': id},
          )
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No pudimos traer lo de tu nutricionista. Revisá tu conexión.',
  );
}

/// `id → display_name` de las profesionales, desde `care_professionals`. La
/// usan las devoluciones y los artículos. Si falla devuelve lo que tenga: sin
/// nombres la lista se muestra igual, sin firma.
Future<Map<String, String>> professionalNames(
  SupabaseClient db,
  Set<String> ids,
) async {
  final nameById = <String, String>{};
  if (ids.isEmpty) return nameById;
  try {
    final names = await db
        .from('care_professionals')
        .select('id, display_name')
        .inFilter('id', ids.toList())
        .timeout(CareFeedbackClient.timeout);
    for (final n in names) {
      if (n['id'] case final String id) {
        nameById[id] = n['display_name'] as String? ?? '';
      }
    }
  } on Exception {
    // Sin nombres la lista se muestra igual.
  }
  return nameById;
}
