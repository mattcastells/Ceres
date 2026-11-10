import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_error.dart';
import '../../data/remote/care_feedback_client.dart';
import '../../data/remote/care_report_client.dart';
import '../../data/remote/plan_client.dart';
import '../../domain/models/care_feedback.dart';
import '../../domain/models/plan.dart';
import '../../domain/models/weekly_report.dart';

// ── Plan ─────────────────────────────────────────────────────────────────

/// Null sin servidor: sin cuenta no hay plan que consultar y la app es la de
/// siempre, con todo incluido.
final planClientProvider = Provider<PlanClient?>((ref) => null);

/// El plan efectivo, para decidir en el momento si se ofrece la IA o los
/// anuncios.
///
/// Es un estado sincrónico a propósito, y no un `FutureProvider`: los botones
/// lo leen al tocarse y no pueden esperar una consulta para decidir qué hacer.
/// Arranca en [AppPlan.fallback] y se corrige apenas contesta el servidor.
///
/// Se refresca al iniciar sesión (lo engancha `bootstrap` a los cambios de
/// sesión), al volver a la app, al tirar para actualizar en Inicio y después
/// de dar o cortar un acceso, que es lo que convierte una cuenta gratis en
/// "IA incluida por tu nutricionista".
class PlanController extends Notifier<AppPlan> {
  /// Si alguna vez contestó el servidor en esta sesión. Mientras no, un error
  /// deja [AppPlan.fallback]; después, un error deja lo último que se supo:
  /// una red que se cae no puede cambiarle el plan a nadie.
  bool _known = false;

  Future<void>? _inFlight;

  @override
  AppPlan build() {
    final client = ref.watch(planClientProvider);
    if (client != null) {
      // Primera consulta sin bloquear el arranque. `Future.microtask` porque
      // dentro de `build` todavía no se puede escribir el estado.
      Future<void>.microtask(refresh);
    }
    return AppPlan.fallback;
  }

  /// Vuelve a preguntar. Llamadas superpuestas comparten la misma consulta.
  Future<void> refresh() =>
      _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  Future<void> _fetch() async {
    final client = ref.read(planClientProvider);
    if (client == null) return;
    try {
      state = await client.effectivePlan();
      _known = true;
    } on AppError {
      if (!_known) state = AppPlan.fallback;
    }
  }

  /// Sin sesión no hay plan: se vuelve al valor por defecto, para que la
  /// cuenta siguiente no herede el de la anterior.
  void reset() {
    _known = false;
    state = AppPlan.fallback;
  }

  /// La compra simulada de la demo. El plan cambia en el acto en toda la app:
  /// todo lo que mira este provider se redibuja.
  ///
  /// Lanza [AppError] si no se pudo (`forbidden` para una cuenta real).
  Future<AppPlan> switchDemo(AppPlan target) async {
    final client = ref.read(planClientProvider);
    if (client == null) return state;
    final next = await client.demoSwitch(target);
    _known = true;
    state = next;
    return next;
  }

  /// Para los tests y para las pantallas de muestra.
  void debugSet(AppPlan plan) => state = plan;
}

final planProvider = NotifierProvider<PlanController, AppPlan>(
  PlanController.new,
);

// ── De tu nutricionista ──────────────────────────────────────────────────

/// Null sin servidor: no hay nutricionista que escriba.
final careFeedbackClientProvider = Provider<CareFeedbackClient?>((ref) => null);

/// Todo lo publicado para esta cuenta, de lo más nuevo a lo más viejo.
///
/// `autoDispose` por lo mismo que `careGrantsProvider`: sin eso la lista se
/// consulta una vez por sesión de app y una devolución nueva no aparecería
/// hasta reiniciar. Inicio lo mantiene vivo mientras está montado; volver a la
/// app y tirar para actualizar lo invalidan.
final careFeedbackProvider = FutureProvider.autoDispose<CareInbox>((ref) async {
  final client = ref.watch(careFeedbackClientProvider);
  if (client == null) return CareInbox(const <CareFeedback>[]);
  return CareInbox(await client.list());
});

// ── Resumen semanal ──────────────────────────────────────────────────────

/// Null sin servidor: el resumen lo arma una Edge Function.
final careReportClientProvider = Provider<CareReportClient?>((ref) => null);

/// El último resumen guardado. Leerlo no gasta nada; generarlo sí, y eso lo
/// hace solo el botón de la pantalla.
final latestWeeklyReportProvider = FutureProvider.autoDispose<WeeklyReport?>((
  ref,
) async {
  final client = ref.watch(careReportClientProvider);
  if (client == null) return null;
  return client.latestWeekly();
});

/// Lo que se refresca al volver a la app o al tirar para actualizar: el plan
/// y lo que escribió la nutricionista. Un solo lugar para que los tres
/// disparadores no se separen con el tiempo.
void refreshServerState(WidgetRef ref) {
  unawaited(ref.read(planProvider.notifier).refresh());
  ref.invalidate(careFeedbackProvider);
}
