import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/weekly_report.dart';

/// El resumen semanal con IA: leer el último guardado y pedir uno nuevo.
///
/// Se guardan en `care_reports` para no regenerarlos —y pagarlos— cada vez
/// que alguien abre la pantalla. Abrirla lee; solo el botón genera.
class CareReportClient {
  CareReportClient(this._db);

  factory CareReportClient.fromInstance() =>
      CareReportClient(Supabase.instance.client);

  final SupabaseClient _db;

  static const String functionName = 'care-report';
  static const String weeklyKind = 'patient_weekly';

  static const Duration readTimeout = Duration(seconds: 30);

  /// La función tarda entre 10 y 40 s: lee la semana, calcula y redacta. Este
  /// techo tiene que quedar **por encima** del suyo, por lo mismo que en
  /// `GeminiAnalysisClient.timeout`: al revés, el teléfono corta primero, la
  /// cuota queda gastada y el informe que el servidor sí guardó no se ve
  /// hasta la próxima vez que se abra la pantalla.
  static const Duration generateTimeout = Duration(seconds: 90);

  String get _me => _db.auth.currentUser?.id ?? '';

  /// El último reporte guardado de un período de [days] días, o `null` si
  /// nunca se pidió uno de ese largo.
  ///
  /// Todos se guardan con el mismo `kind`; el largo sale de las fechas. Se
  /// traen los últimos y se elige acá: son pocos y no hace falta una columna.
  Future<WeeklyReport?> latestWeekly({int days = 7}) async {
    try {
      final rows = await _db
          .from('care_reports')
          .select(
            'id, kind, patient_id, period_from, period_to, content, created_at',
          )
          .eq('kind', weeklyKind)
          .eq('patient_id', _me)
          .order('created_at', ascending: false)
          .limit(30)
          .timeout(readTimeout);
      for (final row in rows) {
        final report = WeeklyReport.fromRow(row);
        if (report != null &&
            report.periodTo.difference(report.periodFrom).inDays + 1 == days) {
          return report;
        }
      }
      return null;
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos traer tu resumen. Revisá tu conexión.',
      );
    }
  }

  Future<WeeklyReport> generateWeekly({int days = 7}) async {
    final FunctionResponse response;
    try {
      response = await _db.functions
          .invoke(
            functionName,
            body: <String, dynamic>{'kind': weeklyKind, 'days': days},
          )
          .timeout(generateTimeout);
    } on FunctionException catch (error) {
      throw translate(error.details);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message:
            'El resumen tardó demasiado. Si se llegó a armar, va a aparecer '
            'la próxima vez que abras esta pantalla.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos pedir el resumen: revisá tu conexión.',
      );
    }
    return parseGenerated(response.data);
  }

  /// Lee `{ report: {...} }`. Público para probarlo sin servidor.
  static WeeklyReport parseGenerated(Object? data) {
    final report = data is Map ? WeeklyReport.fromRow(data['report']) : null;
    if (report == null) {
      throw const AppError(
        code: ApiErrorCode.aiInvalidResponse,
        message:
            'El resumen vino con algo que no pudimos leer. Probá de nuevo.',
      );
    }
    return report;
  }

  /// `{error: {code, message}}` → [AppError], con el mensaje del servidor:
  /// es el que sabe si fue la cuota, el plan o que no hay registros, y cada
  /// uno manda a hacer algo distinto.
  static AppError translate(Object? details) {
    String? code;
    String? message;
    if (details is Map && details['error'] is Map) {
      final inner = details['error'] as Map;
      code = inner['code'] as String?;
      message = inner['message'] as String?;
    }
    final apiCode = ApiErrorCode.values.firstWhere(
      (c) => c.wire == code,
      orElse: () => ApiErrorCode.upstreamFailed,
    );
    return AppError(
      code: apiCode,
      message: message ?? 'No pudimos armar el resumen. Probá de nuevo.',
    );
  }
}
