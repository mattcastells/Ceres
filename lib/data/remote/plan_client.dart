import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/plan.dart';

/// El plan de la cuenta y la compra simulada de la demo.
///
/// Las dos cosas son funciones de la base y no tablas: el plan **efectivo**
/// depende de cosas que la app no puede ver —si la profesional de alguien
/// tiene Pro—, y el plan no lo escribe ningún cliente. La compra simulada es
/// la única excepción, y solo para las cuentas de demostración.
class PlanClient {
  PlanClient(this._db);

  factory PlanClient.fromInstance() => PlanClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Mismo plazo que el resto de las consultas: ningún `await` contra la red
  /// sin uno propio.
  static const Duration timeout = Duration(seconds: 20);

  Future<AppPlan> effectivePlan() async {
    try {
      final raw = await _db.rpc<dynamic>('effective_plan').timeout(timeout);
      return AppPlan.fromWire(raw);
    } on Exception {
      throw _offline;
    }
  }

  /// "Compra" el plan en la demo y devuelve el plan efectivo que quedó.
  ///
  /// No hay cobro: es la pieza que haría un sistema de pagos, simulada. A una
  /// cuenta real el servidor le contesta `ERR_FORBIDDEN`, y acá se lo traduce
  /// a algo que se entienda en vez de mostrar el código.
  Future<AppPlan> demoSwitch(AppPlan plan) async {
    try {
      final raw = await _db
          .rpc<dynamic>(
            'demo_switch_plan',
            params: <String, dynamic>{'p_plan': plan.wire},
          )
          .timeout(timeout);
      return AppPlan.fromWire(raw);
    } on PostgrestException catch (error) {
      throw translate(error.message, hint: error.hint);
    } on Exception {
      throw _offline;
    }
  }

  /// Público para poder probarlo sin servidor.
  static AppError translate(String message, {String? hint}) {
    if (message.contains('ERR_FORBIDDEN')) {
      return const AppError(
        code: ApiErrorCode.forbidden,
        message:
            'Las cuentas reales no cambian de plan desde la app. En esta '
            'demostración la compra se simula solo con las cuentas de prueba.',
      );
    }
    return AppError(
      code: ApiErrorCode.validation,
      message: hint ?? 'No pudimos cambiar el plan. Probá de nuevo.',
      requestId: message,
    );
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No pudimos conectarnos. Revisá tu conexión.',
  );
}
