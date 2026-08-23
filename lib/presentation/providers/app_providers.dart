import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/restore_outcome.dart';
import '../../domain/models/summaries.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/repositories.dart';

/// Estado global (13-state-management.md §1). La fuente de verdad para la UI
/// es siempre la base local: estos providers la leen y se recalculan cuando
/// una mutación avisa por [appRevisionProvider].

/// Se sobrescribe en `bootstrap.dart` con la implementación concreta.
final repositoryProvider = Provider<CeresRepositories>(
  (ref) => throw UnimplementedError('repositoryProvider sin inicializar'),
);

/// Contador de revisión: toda escritura lo incrementa y con eso se invalidan
/// las lecturas derivadas, sin recargar la app entera (§6, invalidación por
/// clave y no global).
class AppRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final appRevisionProvider = NotifierProvider<AppRevision, int>(
  AppRevision.new,
);

/// Día visible en Inicio.
///
/// Vuelve a hoy al reanudar la app si pasó [_ventanaVigencia] desde la última
/// vez que alguien lo eligió a mano. El comentario decía que esto ya pasaba y
/// no pasaba: `goToToday` tenía un solo llamador —el botón "Hoy" del selector—
/// y el ciclo de vida nunca tocaba esta fecha.
///
/// Se notaba dejando la app abierta de noche y volviendo a la mañana: Inicio
/// seguía en "Ayer" y el "+" arma la URL con **esta** fecha, así que el
/// desayuno caía en el día anterior. El widget del teléfono, mientras tanto,
/// publicaba hoy: dos superficies de la misma app diciendo cosas distintas.
///
/// El plazo existe para no pisar a alguien que está mirando un día pasado a
/// propósito —volver de la cámara son dos `resumed` seguidos—, así que solo se
/// corrige cuando la elección ya quedó vieja.
class SelectedDate extends Notifier<DateTime> {
  /// Cuánto vale una elección manual antes de que reanudar la descarte.
  static const Duration _ventanaVigencia = Duration(hours: 4);

  DateTime? _elegidoAt;

  @override
  DateTime build() => today();

  void set(DateTime date) {
    _elegidoAt = DateTime.now();
    state = dateOnly(date);
  }

  void goToToday() {
    _elegidoAt = null;
    state = today();
  }

  void shift(int days) {
    _elegidoAt = DateTime.now();
    state = state.add(Duration(days: days));
  }

  bool get isToday => isSameDay(state, DateTime.now());

  /// Al volver a primer plano. Devuelve si cambió el día visible.
  ///
  /// No hace nada si ya está en hoy, ni si la elección es reciente.
  bool refreshOnResume() {
    if (isToday) return false;
    final elegido = _elegidoAt;
    if (elegido != null &&
        DateTime.now().difference(elegido) < _ventanaVigencia) {
      return false;
    }
    goToToday();
    return true;
  }
}

final selectedDateProvider = NotifierProvider<SelectedDate, DateTime>(
  SelectedDate.new,
);

/// Rango del tab Progreso.
enum ProgressRange {
  d7('7 d', 7),
  d30('30 d', 30),
  d90('90 d', 90),
  y1('1 año', 365);

  const ProgressRange(this.label, this.days);
  final String label;
  final int days;
}

final progressRangeProvider = StateProvider<ProgressRange>(
  (ref) => ProgressRange.d30,
);

// ── Lecturas derivadas ───────────────────────────────────────────────────

final profileProvider = Provider<UserProfile>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).profile;
});

final hasSessionProvider = Provider<bool>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).hasSession;
});

final currentGoalProvider = Provider<Goal?>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).currentGoalOrNull;
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(profileProvider).themeMode;
  return switch (mode) {
    ThemeModeSetting.light => ThemeMode.light,
    ThemeModeSetting.dark => ThemeMode.dark,
    ThemeModeSetting.system => ThemeMode.system,
  };
});

final unitSystemProvider = Provider<UnitSystem>(
  (ref) => ref.watch(profileProvider).unitSystem,
);

final dailySummaryProvider = Provider.family<DailySummary, DateTime>((
  ref,
  date,
) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).daily(date);
});

final todaySummaryProvider = Provider<DailySummary>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref.watch(dailySummaryProvider(date));
});

final historyProvider = Provider.family<List<HistoryDay>, int>((ref, days) {
  ref.watch(appRevisionProvider);
  final to = today();
  return ref
      .watch(repositoryProvider)
      .history(from: to.subtract(Duration(days: days - 1)), to: to);
});

final progressProvider = Provider<ProgressSummary>((ref) {
  ref.watch(appRevisionProvider);
  final range = ref.watch(progressRangeProvider);
  final to = today();
  return ref
      .watch(repositoryProvider)
      .progress(from: to.subtract(Duration(days: range.days - 1)), to: to);
});

final activityTypesProvider = Provider<List<ActivityType>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).types;
});

final recentActivitiesProvider = Provider<List<Activity>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).recentActivities();
});

final favoriteActivitiesProvider = Provider<List<Activity>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).favoriteActivities();
});

final currentWeightProvider = Provider<double?>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).currentWeightKg;
});

final activityGoalsProvider = Provider<List<ActivityGoal>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).activityGoals;
});

/// Cómo salió leer el documento guardado al arrancar.
///
/// Se mira en Inicio para avisar. Una lectura que falló y un teléfono vacío se
/// veían idénticos, y esa confusión es la que terminaba en datos perdidos sin
/// que nadie se enterara hasta que era tarde.
final restoreOutcomeProvider = Provider<RestoreOutcome>(
  (ref) => ref.watch(repositoryProvider).lastRestore,
);

// `offlineProvider` y `pendingCountProvider` se sacaron: ninguna pantalla los
// leía. Envolvían `isOffline` —que es siempre false desde que se quitó el
// interruptor de desarrollo— y el conteo de pendientes, que tampoco se muestra
// en ningún lado. Un provider sin consumidores es una promesa de que algo se
// está mirando; los datos siguen en el repositorio para cuando haga falta.

final integrationProvider = Provider((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).integration;
});

final pendingReviewsProvider = Provider<List<DuplicateCandidate>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).pendingReviews;
});

final daysWithRecordsProvider = Provider<Set<String>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).daysWithRecords;
});
