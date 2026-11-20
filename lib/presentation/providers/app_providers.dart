import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/palettes.dart';
import '../../core/utils/dates.dart';
import '../../data/local/theme_palette_store.dart';
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

final appRevisionProvider = NotifierProvider<AppRevision, int>(AppRevision.new);

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
    // Por calendario y no sumando 24 h: el día del cambio de hora dura 23 o
    // 25, y `add` dejaba la fecha con una hora colgada —las 23:00 del día
    // anterior— que después no era igual a ningún `dateOnly`.
    state = DateTime(state.year, state.month, state.day + days);
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

/// Un valor que la UI reemplaza entero. Es lo que hacía `StateProvider`, que
/// Riverpod 3 dejó en `legacy`.
class Settable<T> extends Notifier<T> {
  Settable(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

/// El día de hoy, como estado: cambia cuando pasa la medianoche y la app
/// vuelve a primer plano.
///
/// Historial y Progreso calculaban su ventana con `today()` al construirse y
/// la conservaban mientras no cambiara otra cosa: abiertos de noche y vistos a
/// la mañana, terminaban en ayer. Mirando esto se recalculan solos cuando el
/// día cambia, y solo entonces.
class CurrentDay extends Notifier<DateTime> {
  @override
  DateTime build() => today();

  void refresh() {
    final now = today();
    if (now != state) state = now;
  }
}

final currentDayProvider = NotifierProvider<CurrentDay, DateTime>(
  CurrentDay.new,
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

  /// El título del reporte con IA de este período.
  String get reportTitle => switch (this) {
    d7 => 'Tu semana',
    d30 => 'Tu mes',
    d90 => 'Tu trimestre',
    y1 => 'Tu año',
  };

  /// "la semana", "el mes"…, para armar frases.
  String get noun => switch (this) {
    d7 => 'la semana',
    d30 => 'el mes',
    d90 => 'el trimestre',
    y1 => 'el año',
  };

  /// "esta semana", "este mes"…
  String get thisOne => switch (this) {
    d7 => 'esta semana',
    d30 => 'este mes',
    d90 => 'este trimestre',
    y1 => 'este año',
  };
}

final progressRangeProvider =
    NotifierProvider<Settable<ProgressRange>, ProgressRange>(
      () => Settable(ProgressRange.d30),
    );

// ── Lecturas derivadas ───────────────────────────────────────────────────

final profileProvider = Provider<UserProfile>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).profile;
});

final currentGoalProvider = Provider<Goal?>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).currentGoalOrNull;
});

/// El modo que se pide a `MaterialApp`. Sakura y Neo Tokyo fijan el suyo; con
/// Ceres manda lo elegido en Apariencia.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final fixed = ref.watch(themePaletteProvider).fixedBrightness;
  if (fixed != null) {
    return fixed == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }
  final mode = ref.watch(profileProvider).themeMode;
  return switch (mode) {
    ThemeModeSetting.light => ThemeMode.light,
    ThemeModeSetting.dark => ThemeMode.dark,
    ThemeModeSetting.system => ThemeMode.system,
  };
});

/// Dónde se guarda el tema. `bootstrap` lo lee antes de arrancar, para que la
/// app no abra un instante con Ceres y después cambie.
final themePaletteStoreProvider = Provider<ThemePaletteStore>(
  (ref) => ThemePaletteStore(),
);

/// El valor con el que arranca [themePaletteProvider]; lo fija `bootstrap`.
final initialThemePaletteProvider = Provider<AppPalette>(
  (ref) => AppPalette.ceres,
);

class ThemePaletteController extends Notifier<AppPalette> {
  @override
  AppPalette build() => ref.read(initialThemePaletteProvider);

  Future<void> set(AppPalette palette) async {
    state = palette;
    await ref.read(themePaletteStoreProvider).save(palette);
  }
}

final themePaletteProvider =
    NotifierProvider<ThemePaletteController, AppPalette>(
      ThemePaletteController.new,
    );

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
  final to = ref.watch(currentDayProvider);
  return ref
      .watch(repositoryProvider)
      .history(
        from: to.subtract(Duration(days: days - 1)),
        to: to,
      );
});

final progressProvider = Provider<ProgressSummary>((ref) {
  ref.watch(appRevisionProvider);
  final range = ref.watch(progressRangeProvider);
  final to = ref.watch(currentDayProvider);
  return ref
      .watch(repositoryProvider)
      .progress(
        from: to.subtract(Duration(days: range.days - 1)),
        to: to,
      );
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
// leía. Envolvían `isOffline` —que era siempre false desde que se quitó el
// interruptor de desarrollo— y el conteo de pendientes. Después se fueron
// también del repositorio: no había detección de red que los alimentara.

final integrationProvider = Provider((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).integration;
});

final daysWithRecordsProvider = Provider<Set<String>>((ref) {
  ref.watch(appRevisionProvider);
  return ref.watch(repositoryProvider).daysWithRecords;
});
