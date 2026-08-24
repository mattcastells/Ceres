import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

import '../../core/config/feature_flags.dart';
import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/calculations/alcohol.dart';
import '../../domain/calculations/bmr.dart';
import '../../domain/calculations/duplicate_score.dart';
import '../../domain/calculations/exercise_credit.dart';
import '../../domain/calculations/met_calories.dart';
import '../../domain/calculations/pace_met.dart';
import '../../domain/calculations/tracking_window.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/ai_analysis.dart';
import '../../domain/models/ai_calorie_target.dart';
import '../../domain/models/alcohol.dart';
import '../../domain/models/analysis_stage.dart';
import '../../domain/models/body.dart';
import '../../domain/models/day_marker.dart';
import '../../domain/models/food.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/meal.dart';
import '../../domain/models/meal_suggestion.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/restore_outcome.dart';
import '../../domain/models/sleep.dart';
import '../../domain/models/summaries.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/water.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/document_merge.dart' show collapseGoals;
import '../../domain/services/photo_sync_service.dart';
import '../../domain/services/summary_builder.dart';
import '../local/health_connect_gateway.dart';
import '../local/local_store.dart';
import '../remote/calorie_target_client.dart';
import '../remote/gemini_analysis_client.dart';
import '../remote/meal_suggestions_client.dart';
import '../remote/open_food_facts_client.dart';
import '../remote/photo_storage_client.dart';
import '../remote/usda_food_client.dart';

const _uuid = Uuid();

/// Implementación local-first de todos los repositorios sobre [LocalStore].
///
/// Cada mutación: escribe en la base local, deja `sync_status` según el estado
/// de conexión y avisa por [onChanged] para que la UI se actualice de
/// inmediato (escritura optimista, D-08).
class LocalRepository
    implements
        CeresRepositories,
        ProfileRepository,
        GoalRepository,
        MealRepository,
        ActivityRepository,
        FoodRepository,
        BodyRepository,
        WaterRepository,
        ReminderRepository,
        SleepRepository,
        SummaryRepository,
        HealthRepository,
        AiPhotoRepository,
        BackupRepository,
        ConnectivityRepository {
  LocalRepository(
    this.store, {
    required this.onChanged,
    OpenFoodFactsClient? foodCatalog,
    this.photos,
    this.aiAnalysis,
    this.suggestions,
    this.calorieTargets,
    this.usdaFoods,
    this.health,
  }) : _foodCatalog = foodCatalog ?? OpenFoodFactsClient();

  final LocalStore store;
  final void Function() onChanged;
  final OpenFoodFactsClient _foodCatalog;

  /// Sube al bucket las fotos que quedan en el teléfono. Null sin servidor.
  final PhotoSyncService? photos;

  /// Análisis de foto por la Edge Function. Null sin servidor.
  final GeminiAnalysisClient? aiAnalysis;

  /// Sugerencias de comida para lo que queda del día. Null sin servidor: la
  /// función es la que habla con el modelo.
  final MealSuggestionsClient? suggestions;

  /// La propuesta de objetivo calórico del alta guiada. Null sin servidor: es
  /// la función la que habla con el modelo, y la que acota lo que devuelve.
  final CalorieTargetClient? calorieTargets;

  /// Health Connect, el almacén de salud del teléfono: de ahí salen el peso, la
  /// grasa corporal y el sueño que miden la balanza y el reloj. Null en los
  /// tests y en cualquier plataforma que no sea Android.
  final HealthConnectGateway? health;

  /// Alimentos genéricos de USDA por la Edge Function. Null sin servidor: la
  /// búsqueda sigue andando con Open Food Facts y con la tabla argentina.
  final UsdaFoodClient? usdaFoods;

  Future<void> _commit() async {
    await store.persist();
    onChanged();
  }

  // ── Perfil ─────────────────────────────────────────────────────────────

  @override
  UserProfile? get profileOrNull => store.profile;

  @override
  UserProfile get profile =>
      store.profile ?? UserProfile.empty('anonymous');

  @override
  bool get hasSession => store.profile != null;

  @override
  bool get needsOnboarding {
    final current = store.profile;
    // Sin sesión no hay nada que completar: de eso se ocupa la bienvenida.
    if (current == null) return false;
    return current.birthDate == null ||
        current.heightCm == null ||
        store.currentWeightKg == null;
  }

  @override
  Future<void> updateProfile(UserProfile updated) async {
    store.profile = updated;
    await _commit();
  }

  @override
  Future<void> setThemeMode(ThemeModeSetting mode) =>
      updateProfile(profile.copyWith(themeMode: mode));

  @override
  Future<void> setUnitSystem(UnitSystem units) =>
      updateProfile(profile.copyWith(unitSystem: units));

  @override
  Future<void> setShowNetCalories(bool value) =>
      updateProfile(profile.copyWith(showNetCalories: value));

  /// Cambiar el crédito recalcula **solo** el día en curso y los futuros; los
  /// días cerrados conservan su porcentaje congelado (D-05, F-13).
  @override
  Future<void> setExerciseCredit({
    required int percentage,
    required bool enabled,
  }) async {
    store.profile = profile.copyWith(
      exerciseCreditPercentage: percentage,
      exerciseCreditEnabled: enabled,
    );
    final from = today();
    store.activities = store.activities.map((a) {
      if (a.localDate.isBefore(from)) return a;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: a.estimatedCalories,
        creditPercentage: percentage,
        creditEnabled: enabled,
      );
      return a.copyWith(
        appliedCalories: applied,
        exerciseCreditPercentage: percentage,
      );
    }).toList();
    await _commit();
  }

  /// Deja el perfil en condiciones de usar la app sin pasar por ningún
  /// asistente: sin datos corporales todavía, pero con un objetivo con el que
  /// arrancar.
  ///
  /// El objetivo inicial es **manual**, no calculado. Sin sexo, altura, edad y
  /// peso no hay Mifflin-St Jeor, y presentar un número inventado como si
  /// fuera el resultado de una fórmula es exactamente lo que el producto no
  /// hace (RN-03). Se marca `targetMethod: manual` para que la pantalla de
  /// objetivo lo muestre como lo que es: un punto de partida a ajustar.
  Future<void> _ensureUsableProfile(UserProfile profile) async {
    store.profile = profile;
    if (store.goals.isEmpty) {
      store.goals = <Goal>[
        Goal(
          id: _uuid.v4(),
          goalType: GoalType.maintain,
          rateKgPerWeek: 0,
          baseCalorieTarget: defaultCalorieTarget,
          targetMethod: TargetMethod.manual,
          proteinG: 120,
          carbsG: 220,
          fatG: 65,
          macroMethod: 'default',
          startsOn: today(),
        ),
      ];
    }
    await _commit();
  }

  /// Punto de partida hasta que se carguen los datos corporales. Es un valor
  /// de referencia, no una estimación: la app lo dice en pantalla.
  static const int defaultCalorieTarget = 2000;

  @override
  Future<void> startDemoSession({required bool seeded}) async {
    if (seeded) {
      store.seed();
      await _commit();
      return;
    }
    store.reset(
      newProfile: UserProfile.empty(_uuid.v4()).copyWith(isDemo: true),
    );
    await _ensureUsableProfile(store.profile!);
  }

  /// Id estable para las colecciones que admiten **una fila por día**.
  ///
  /// Peso, agua, sueño y medidas tienen del lado de la base un índice único
  /// sobre `(user_id, local_date)` —más la métrica, en el caso de las medidas—.
  /// Con ids al azar, dos dispositivos que registran el mismo día crean dos
  /// filas distintas para la misma clave: la segunda choca contra ese índice y
  /// el push de esa tabla falla. Y no se auto-repara, porque la reconciliación
  /// une por id y conserva las dos: vuelve a fallar en cada intento.
  ///
  /// Derivando el id de la clave natural, los dos dispositivos generan **el
  /// mismo**, así que el upsert los hace converger en vez de chocar. Es lo que
  /// hace falta para la versión web, donde la misma cuenta va a estar abierta
  /// en dos lados de verdad.
  ///
  /// Las filas que ya existen con id al azar no se tocan: esto solo aplica al
  /// crear una nueva, y el id que ya está siempre se reutiliza.
  /// Id estable por día: volver a registrar el mismo día actualiza en vez de
  /// duplicar (D-16).
  ///
  /// El sufijo de identidad **no puede ser un literal compartido**. Era
  /// `store.accountId ?? 'local'`, y todo lo cargado antes de iniciar sesión
  /// caía en `'local'`: dos personas distintas generaban el **mismo UUID** para
  /// el mismo día. Al sincronizar, el upsert chocaba contra la fila de otro y
  /// RLS lo rechazaba —"new row violates row-level security policy"—, así que
  /// esa tabla dejaba de subir para siempre sin decir por qué.
  ///
  /// El perfil ya tiene un id propio, distinto en cada instalación, así que
  /// sirve de identidad mientras no haya cuenta. `'local'` queda solo para el
  /// caso imposible de no tener ni perfil.
  ///
  /// El prefijo `nutrimat:` es el nombre viejo de la app y **se queda así**:
  /// es la semilla de los ids que ya están guardados en el servidor. Con otra
  /// semilla, el mismo día daría otro id y el upsert crearía una segunda fila
  /// en vez de actualizar la que existe. No es un texto que alguien lea.
  String _dailyId(String coleccion, DateTime date, [String extra = '']) =>
      _uuid.v5(
        Namespace.url.value,
        'nutrimat:$coleccion'
        ':${store.accountId ?? store.profile?.id ?? 'local'}'
        ':${isoDate(date)}:$extra',
      );

  /// Repara lo que quedó mal guardado antes de los arreglos de la 1.14.2.
  ///
  /// Prevenir no alcanzaba: las filas rotas ya estaban en el teléfono, y una
  /// tabla que el servidor rechaza no sube **ninguna** de sus filas, así que
  /// una sola fila vieja dejaba fuera a todas las nuevas. Esto es la otra
  /// mitad del arreglo.
  ///
  /// Dos cosas, las dos idempotentes —correrlo mil veces deja lo mismo que una,
  /// así que no necesita bandera de "ya se hizo":
  ///
  /// 1. **Objetivos con las fechas al revés** (`ends_on < starts_on`). Se
  ///    descartan: no gobernaron ni un día, así que no son historial. Es la
  ///    misma decisión que toma `saveGoal`.
  /// 2. **Ids derivados del literal `'local'`**, en agua y en sueño, que
  ///    colisionaban entre cuentas. Se regeneran con la identidad de esta
  ///    instalación. Solo se tocan los que **no** coinciden con el id esperado,
  ///    así que lo que ya estaba bien se queda como está.
  ///
  /// El sueño entró acá después que el agua, y por un choque distinto:
  ///
  ///     duplicate key value violates unique constraint "sleep_logs_pkey"
  ///
  /// No es la clave del día, es la **primary key**. Desde que el upsert resuelve
  /// contra `(user_id, local_date)`, un id que ya existe en la fila de **otra
  /// persona** dejó de dar un error de RLS y pasa a dar uno de clave primaria:
  /// el `ON CONFLICT` del día no encuentra esa fila —no es de esta cuenta—, así
  /// que Postgres intenta insertar y el índice de la primary key, que no sabe de
  /// RLS, la rechaza. Con eso, la tabla entera deja de subir.
  ///
  /// Que dos personas compartan un id es exactamente lo que dejó la versión del
  /// literal `'local'` (ver `_dailyId`): el mismo uuid para el mismo día en dos
  /// teléfonos distintos, y la primera cuenta que sincronizó se quedó con él.
  ///
  /// Derivar el id de esta identidad y de este día lo cierra por los dos lados:
  /// no puede ser de otra persona —el sufijo es la cuenta— ni de otro día —la
  /// fecha va adentro—. Y no deja huérfanos, que era el motivo para no tocar los
  /// ids: como el upsert resuelve por día, la fila que ya está en el servidor se
  /// actualiza y su id converge, en vez de aparecer una segunda al lado.
  ///
  /// El peso y las medidas siguen sin re-identificarse: su upsert resuelve por
  /// id, así que cambiárselo dejaría la fila vieja viva del otro lado. Las
  /// medidas tienen su propia reparación —`_collapseMeasurements` adopta el id
  /// que el servidor ya conoce—, que es la misma idea al revés.
  ///
  /// 3. **Dos registros para el mismo día**, en agua y en sueño. Es el estado
  ///    que dejaba el error `duplicate key value violates unique constraint
  ///    "water_logs_one_per_day"`: la reconciliación une las listas **por id**,
  ///    así que cuando la fila del servidor y la local tenían ids distintos
  ///    para el mismo día, las dos quedaban en el documento. No es solo un
  ///    problema al subir —`glassesOn` y `sleepOn` devuelven la primera que
  ///    encuentran, o sea que la app podía estar mostrando la vieja—. Se
  ///    conserva la de marca de tiempo más reciente, que es la última que la
  ///    persona vio en pantalla.
  Future<void> repararRegistrosViejos() async {
    // 4. **Dos objetivos cubriendo los mismos días.** Mismo patrón que el agua
    //    y el sueño —la reconciliación une por id y no mira las fechas—, pero
    //    con dos diferencias que lo hacen peor: acá el que se queja es el
    //    servidor, con `goals_no_overlap`, y rechaza el lote entero, así que
    //    los objetivos **dejan de sincronizar para siempre**; y el mensaje no
    //    dice cuál es la fila que molesta. Pasó al reinstalar la app antes de
    //    la 1.22.1: el alta forzada recalculaba el objetivo por fórmula sin
    //    cerrar el que la persona tenía escrito a mano, y quedaban los dos
    //    abiertos desde el mismo día.
    //
    //    Se repara acá y no solo en la reconciliación porque la reconciliación
    //    necesita que la descarga funcione, y un teléfono ya roto tiene que
    //    poder arreglarse sin depender de la red. `collapseGoals` decide, y su
    //    regla es la del producto: lo que escribió la persona le gana a lo que
    //    calculó una fórmula.
    final objetivos = <Goal>[
      for (final json in collapseGoals(<Map<String, dynamic>>[
        for (final g in store.goals)
          if (g.endsOn == null || !g.endsOn!.isBefore(g.startsOn)) g.toJson(),
      ]))
        Goal.fromJson(json),
    ];

    // El renombrado va antes de juntar los duplicados: si no, se elegiría una
    // de las dos filas y después se le cambiaría el id igual.
    final aguaRenombrada = <WaterLog>[
      for (final w in store.waterLogs)
        if (w.id == _dailyId('water', w.localDate))
          w
        else
          WaterLog(
            id: _dailyId('water', w.localDate),
            localDate: w.localDate,
            glasses: w.glasses,
            updatedAt: w.updatedAt,
            syncStatus: SyncStatus.pending,
          ),
    ];

    // La lápida viaja en la copia: sin ella, regenerar el id de una noche
    // borrada la revive. El upsert resuelve por día, así que el `deleted_at`
    // llega igual a la fila que el servidor ya tiene para ese día.
    final suenoRenombrado = <SleepLog>[
      for (final s in store.sleepLogs)
        if (s.id == _dailyId('sleep', s.localDate))
          s
        else
          SleepLog(
            id: _dailyId('sleep', s.localDate),
            localDate: s.localDate,
            minutes: s.minutes,
            quality: s.quality,
            loggedAt: s.loggedAt,
            notes: s.notes,
            syncStatus: SyncStatus.pending,
            deletedAt: s.deletedAt,
          ),
    ];

    final agua = _unaPorDia<WaterLog>(
      aguaRenombrada,
      (w) => w.localDate,
      (w) => w.updatedAt,
    );
    final sueno = _unaPorDia<SleepLog>(
      suenoRenombrado,
      (s) => s.localDate,
      (s) => s.loggedAt,
    );

    // Los dos `indexed` van al final a propósito: comparan por posición, y solo
    // son válidos si antes se descartó que los largos difieran. `||` corta.
    final cambio =
        objetivos.length != store.goals.length ||
        agua.length != store.waterLogs.length ||
        sueno.length != store.sleepLogs.length ||
        agua.indexed.any((e) => e.$2.id != store.waterLogs[e.$1].id) ||
        sueno.indexed.any((e) => e.$2.id != store.sleepLogs[e.$1].id);
    if (!cambio) return;

    store.goals = objetivos;
    store.waterLogs = agua;
    store.sleepLogs = sueno;
    await _commit();
  }

  /// Un registro por día, el más reciente, conservando el orden de aparición.
  ///
  /// Devuelve una lista nueva siempre; quien llama compara los largos para
  /// saber si hubo algo que juntar.
  List<T> _unaPorDia<T>(
    List<T> items,
    DateTime Function(T) dia,
    DateTime Function(T) marca,
  ) {
    final indicePorDia = <String, int>{};
    final salida = <T>[];
    for (final item in items) {
      final clave = isoDate(dia(item));
      final i = indicePorDia[clave];
      if (i == null) {
        indicePorDia[clave] = salida.length;
        salida.add(item);
      } else if (marca(item).isAfter(marca(salida[i]))) {
        salida[i] = item;
      }
    }
    return salida;
  }

  @override
  Future<void> signIn(String email, {String? accountId}) async {
    final base = store.profile ?? UserProfile.empty(_uuid.v4());

    // Entrar a una cuenta no es seguir la sesión de prueba con otro nombre.
    //
    // Antes el documento del modo demo se adoptaba tal cual: lo que hubiera
    // ahí quedaba adentro de la cuenta y, con la reconciliación, subía a las
    // tablas. Alcanzaba con tocar "Probar sin cuenta" una vez —por curiosidad o
    // sin querer— para que el historial de una persona que no existe pasara a
    // ser el historial de una que sí. Se arranca limpio y lo que había en el
    // servidor lo trae `openAfterPull`, que es de donde tiene que venir.
    //
    // Lo mismo vale para **otra persona**, y ese caso faltaba. Si la sesión
    // vence sin pasar por "cerrar sesión" —contraseña cambiada en otro lado,
    // refresh token invalidado—, la app vuelve a la bienvenida con el documento
    // intacto. Quien entrara después en ese teléfono se quedaba con las
    // comidas, los pesos y las medidas de la persona anterior, y el push las
    // escribía en **su** cuenta. El alta ya estaba protegida; iniciar sesión,
    // no.
    final otraCuenta =
        accountId != null &&
        store.accountId != null &&
        store.accountId != accountId;

    if (base.isDemo || otraCuenta) {
      store.reset(newProfile: UserProfile.empty(_uuid.v4()));
    }

    store.accountId = accountId;
    await _ensureUsableProfile(
      (store.profile ?? base).copyWith(email: email, isDemo: false),
    );
  }

  @override
  Future<void> signOut() async {
    store.reset(newProfile: UserProfile.empty(_uuid.v4()));
    store.profile = null;
    // La cuarentena se va con la sesión.
    //
    // Es un documento entero apartado porque no se pudo leer, y vive en su
    // propia clave de preferencias: `reset` no la tocaba, así que sobrevivía al
    // cierre de sesión y **la siguiente persona que entrara en ese teléfono
    // podía verla y exportarla** desde la pantalla de recuperación. Quien
    // quiera recuperarla tiene que hacerlo antes de cerrar la sesión, que es
    // cuando la pantalla se la ofrece.
    await store.clearQuarantine();
    await _commit();
  }

  // ── Objetivo ───────────────────────────────────────────────────────────

  @override
  Goal? get currentGoalOrNull => store.currentGoal;

  @override
  Goal goalFor(DateTime date) =>
      store.goalForDate(date) ??
      store.currentGoal ??
      Goal(
        id: 'fallback',
        goalType: GoalType.maintain,
        rateKgPerWeek: 0,
        baseCalorieTarget: 2000,
        targetMethod: TargetMethod.calculated,
        proteinG: 110,
        carbsG: 220,
        fatG: 60,
        macroMethod: 'default',
        startsOn: today(),
      );

  /// Guardar cierra la fila vigente (`endsOn = ayer`) e inserta la nueva desde
  /// hoy: el historial no se reescribe (F-13, AC-16).
  ///
  /// Un objetivo que empezó hoy y se reemplaza hoy **se descarta**, no se
  /// cierra.
  ///
  /// Cerrarlo lo dejaba con `ends_on = ayer` contra `starts_on = hoy`, y el
  /// servidor lo rechazaba con `goals_dates: ends_on >= starts_on`. Como cada
  /// tabla sube en un solo lote, eso tiraba los objetivos enteros de la cuenta
  /// —no solo esa fila— y la persona se quedaba sin objetivo del lado del
  /// servidor sin que nada lo dijera.
  ///
  /// Descartarlo y no cerrarlo el mismo día es lo correcto por dos motivos: no
  /// gobernó ni un día, así que no es historial que preservar; y cerrarlo con
  /// `ends_on = hoy` lo dejaría **vigente**, con dos objetivos activos a la vez.
  ///
  /// Pero descartarlo **no alcanza**: el que se descarta ya está subido, y la
  /// subida manda solo lo que hay en el teléfono, así que nada lo borra de allá.
  /// Con un id nuevo quedaban dos objetivos abiertos el mismo día en el
  /// servidor, y desde ese momento `goals_no_overlap` rechazaba **todas** las
  /// subidas de objetivos —para siempre, y con un error que no dice qué lo
  /// causó ("conflicting key value violates exclusion constraint")—. Alcanzaba
  /// con cambiar el objetivo dos veces en un día, que es exactamente lo que
  /// hace quien completa el alta y después ajusta su número.
  ///
  /// Por eso el que reemplaza **se queda con el id del que reemplaza**: es la
  /// misma fila del servidor y el upsert la actualiza en vez de duplicarla. No
  /// hace falta borrar nada ni una columna de bajas.
  @override
  Future<void> saveGoal(Goal goal) async {
    final yesterday = today().subtract(const Duration(days: 1));

    String? idQueSeReemplaza;
    for (final g in store.goals) {
      if (g.isCurrent && yesterday.isBefore(g.startsOn)) {
        idQueSeReemplaza = g.id;
        break;
      }
    }

    store.goals = <Goal>[
      for (final g in store.goals)
        if (!g.isCurrent)
          g
        else if (!yesterday.isBefore(g.startsOn))
          g.copyWith(endsOn: yesterday),
      if (idQueSeReemplaza == null) goal else goal.copyWith(id: idQueSeReemplaza),
    ];
    await _commit();
  }

  // ── Comidas ────────────────────────────────────────────────────────────

  @override
  List<Meal> mealsOn(DateTime date) =>
      SummaryBuilder.mealsOn(store.meals, date);

  @override
  List<Meal> get allMeals => List<Meal>.unmodifiable(store.meals);

  @override
  Meal? mealById(String id) {
    for (final m in store.meals) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<Meal> saveMeal(Meal meal) async {
    // La foto se sube antes de guardar para que en `photo_path` quede la ruta
    // del bucket y no una del teléfono, que en otro dispositivo no existiría.
    // Si la subida falla queda la local y se reintenta al volver a guardar.
    final photoPath = await photos?.ensureUploaded(
      bucket: PhotoBucket.meal,
      recordId: meal.id,
      localPath: meal.photoPath,
    );

    final withStatus = meal.copyWith(
      syncStatus: store.writeStatus,
      photoPath: photoPath ?? meal.photoPath,
    );
    final index = store.meals.indexWhere((m) => m.id == meal.id);
    if (index >= 0) {
      store.meals[index] = withStatus;
    } else {
      store.meals.add(withStatus);
    }
    for (final item in meal.items) {
      final foodId = item.foodId;
      if (foodId != null) await _touchRecent(foodId);
    }
    await _commit();
    return withStatus;
  }

  /// Cuánto se espera antes de borrar del bucket la foto de una comida
  /// borrada. Un día es holgado contra la ventana de deshacer de 8 s: cubre
  /// también al que se arrepiente esa misma tarde.
  static const Duration photoPurgeGrace = Duration(hours: 24);

  @override
  Future<int> purgeDeletedPhotos() async {
    final service = photos;
    if (service == null) return 0;

    final limit = DateTime.now().subtract(photoPurgeGrace);
    final next = <Meal>[];
    var borradas = 0;

    for (final meal in store.meals) {
      final deletedAt = meal.deletedAt;
      final path = meal.photoPath;
      if (deletedAt == null ||
          path == null ||
          !PhotoSyncService.isRemotePath(path) ||
          deletedAt.isAfter(limit)) {
        next.add(meal);
        continue;
      }

      try {
        await service.delete(bucket: PhotoBucket.meal, path: path);
      } on AppError {
        // Sin conexión o con el servidor caído: se deja como está y se
        // reintenta la próxima vez. Nunca se limpia la ruta sin haber borrado,
        // porque ahí la foto quedaría en el bucket sin nada que la nombre.
        next.add(meal);
        continue;
      }

      // Recién ahora se saca la ruta. La lápida sigue siendo una lápida; lo que
      // deja de estar es el megabyte.
      next.add(meal.copyWith(clearPhotoPath: true));
      borradas++;
    }

    if (borradas > 0) {
      store.meals = next;
      await _commit();
    }
    return borradas;
  }

  /// Borrado suave con ventana de deshacer de 8 s (RN-16).
  @override
  Future<void> deleteMeal(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(deletedAt: DateTime.now()) : m)
        .toList();
    await _commit();
  }

  @override
  Future<void> restoreMeal(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(clearDeletedAt: true) : m)
        .toList();
    await _commit();
  }

  @override
  Future<Meal> duplicateMeal(String id, DateTime date, MealSlot slot) async {
    final source = mealById(id);
    if (source == null) throw StateError('La comida ya no existe');
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      source.eatenAt.hour,
      source.eatenAt.minute,
    );
    final copy = Meal(
      id: _uuid.v4(),
      slot: slot,
      eatenAt: at,
      localDate: dateOnly(date),
      name: source.name,
      items: source.items
          .map((i) => i.copyWith())
          .map(
            (i) => MealItem(
              id: _uuid.v4(),
              foodId: i.foodId,
              name: i.name,
              quantity: i.quantity,
              unit: i.unit,
              kcal: i.kcal,
              proteinG: i.proteinG,
              carbsG: i.carbsG,
              fatG: i.fatG,
              position: i.position,
            ),
          )
          .toList(),
      source: MealSource.duplicate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: store.writeStatus,
    );
    store.meals.add(copy);
    await _commit();
    return copy;
  }

  @override
  Future<void> toggleMealFavorite(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(isFavorite: !m.isFavorite) : m)
        .toList();
    await _commit();
  }

  @override
  List<Meal> favoriteMeals() =>
      store.meals.where((m) => m.isFavorite && !m.isDeleted).toList();

  /// Lo que se repite: primero lo marcado con la estrella, después lo más
  /// registrado en el último tiempo.
  ///
  /// El desayuno es el mismo casi todos los días, y volver a armarlo ítem por
  /// ítem es la fricción más grande de una app de registro. Se agrupa por
  /// título normalizado y de cada grupo se devuelve la versión **más
  /// reciente**, que es la que ya tiene las cantidades como las come hoy.
  ///
  /// El slot no filtra pero sí ordena: un café con leche puede ser desayuno o
  /// merienda, así que esconderlo por estar en otro slot sería adivinar mal.
  @override
  List<Meal> frequentMeals({MealSlot? slot, int limit = 8}) {
    final candidates = store.meals
        .where((m) => !m.isDeleted && m.items.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return const <Meal>[];

    String key(Meal m) => m.title.trim().toLowerCase();

    final newest = <String, Meal>{};
    final uses = <String, int>{};
    for (final meal in candidates) {
      final k = key(meal);
      uses[k] = (uses[k] ?? 0) + 1;
      final current = newest[k];
      if (current == null || meal.eatenAt.isAfter(current.eatenAt)) {
        newest[k] = meal;
      }
    }

    final result = newest.values.toList()
      ..sort((a, b) {
        // Estrella primero: es una elección explícita y gana a cualquier conteo.
        final fav = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
        if (fav != 0) return fav;
        if (slot != null) {
          final s = (b.slot == slot ? 1 : 0) - (a.slot == slot ? 1 : 0);
          if (s != 0) return s;
        }
        final byUse = (uses[key(b)] ?? 0).compareTo(uses[key(a)] ?? 0);
        if (byUse != 0) return byUse;
        return b.eatenAt.compareTo(a.eatenAt);
      });

    // Una comida cargada una sola vez y sin estrella no es "frecuente": sin
    // este filtro la lista se llenaría de cosas que nunca se van a repetir.
    final worth = result
        .where((m) => m.isFavorite || (uses[key(m)] ?? 0) > 1)
        .toList();

    return worth.take(limit).toList();
  }

  /// Cuántas veces se registró una comida con ese título.
  @override
  int mealUseCount(Meal meal) {
    final k = meal.title.trim().toLowerCase();
    return store.meals
        .where((m) => !m.isDeleted && m.title.trim().toLowerCase() == k)
        .length;
  }

  // ── Actividad ──────────────────────────────────────────────────────────

  @override
  List<ActivityType> get types => store.allTypes;

  @override
  ActivityType? typeById(String id) => store.typeById(id);

  @override
  ActivityType? typeBySlug(String slug) => store.typeBySlug(slug);

  @override
  Future<ActivityType> createCustomType(ActivityType type) async {
    store.customTypes.add(type);
    await _commit();
    return type;
  }

  @override
  List<Activity> activitiesOn(DateTime date) =>
      SummaryBuilder.activitiesOn(store.activities, date);

  @override
  List<Activity> get allActivities =>
      List<Activity>.unmodifiable(store.activities);

  @override
  Activity? activityById(String id) {
    for (final a in store.activities) {
      if (a.id == id) return a.copyWith(activityType: typeById(a.activityTypeId));
    }
    return null;
  }

  @override
  List<Activity> recentActivities({int limit = 5}) {
    final seen = <String>{};
    final sorted = <Activity>[...store.activities.where((a) => !a.isDeleted)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final out = <Activity>[];
    for (final a in sorted) {
      if (seen.add(a.activityTypeId)) out.add(a);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  List<Activity> favoriteActivities() =>
      store.activities.where((a) => a.isFavorite && !a.isDeleted).toList();

  @override
  ActivityEstimate estimate(ActivityDraft draft) {
    final override = draft.overrideCalories;
    final weightKg = store.currentWeightKg;
    final type = typeById(draft.activityTypeId);

    if (override != null) {
      return ActivityEstimate(
        calories: override,
        method: EstimationMethod.userOverride,
        durationMinutes: draft.durationMinutes,
      );
    }
    if (weightKg == null) {
      return const ActivityEstimate(
        calories: 0,
        method: EstimationMethod.met,
        unavailableReason: 'Necesitamos tu peso para estimar',
      );
    }
    if (type == null) {
      return const ActivityEstimate(
        calories: 0,
        method: EstimationMethod.met,
        unavailableReason: 'Elegí un tipo de actividad',
      );
    }

    var met = type.metFor(draft.intensity);
    var method = EstimationMethod.met;

    if (draft.usePaceEstimate &&
        draft.distanceMeters != null &&
        draft.distanceMeters! > 0) {
      final paceMet = estimateMetFromPace(
        distanceMeters: draft.distanceMeters!,
        durationMinutes: draft.durationMinutes,
        typeSlug: type.slug,
      );
      if (paceMet != null) {
        met = paceMet;
        method = EstimationMethod.pace;
      }
    }

    return ActivityEstimate(
      calories: calculateCaloriesFromMet(
        met: met,
        weightKg: weightKg,
        durationMinutes: draft.durationMinutes,
      ),
      method: method,
      metValue: met,
      weightKg: weightKg,
      durationMinutes: draft.durationMinutes,
    );
  }

  @override
  Future<Activity> saveActivity(ActivityDraft draft) async {
    final estimated = estimate(draft);
    final credit = profile.effectiveCreditPercentage;
    final enabled = profile.exerciseCreditEnabled;
    final existing = draft.id == null ? null : activityById(draft.id!);

    final calories = estimated.calories;
    final applied = calculateAppliedExerciseCalories(
      estimatedCalories: calories,
      creditPercentage: credit,
      creditEnabled: enabled,
    );

    final activity = Activity(
      id: draft.id ?? _uuid.v4(),
      activityTypeId: draft.activityTypeId,
      activityType: typeById(draft.activityTypeId),
      customName: draft.customName,
      startedAt: draft.startedAt,
      endedAt: draft.startedAt.add(Duration(minutes: draft.durationMinutes)),
      localDate: dateOnly(draft.startedAt),
      durationMinutes: draft.durationMinutes,
      intensity: draft.intensity,
      distanceMeters: draft.distanceMeters,
      steps: draft.steps,
      averageHeartRate: draft.averageHeartRate,
      maximumHeartRate: draft.maximumHeartRate,
      estimatedCalories: calories,
      // El valor calculado nunca se pierde ante un override (RN-04).
      originalCalories: draft.overrideCalories == null
          ? existing?.originalCalories
          : (existing?.originalCalories ??
                estimate(
                  ActivityDraft(
                    activityTypeId: draft.activityTypeId,
                    startedAt: draft.startedAt,
                    durationMinutes: draft.durationMinutes,
                    intensity: draft.intensity,
                    distanceMeters: draft.distanceMeters,
                    usePaceEstimate: draft.usePaceEstimate,
                  ),
                ).calories),
      appliedCalories: applied,
      exerciseCreditPercentage: credit,
      estimationMethod: estimated.method,
      metValue: estimated.metValue,
      weightKgUsed: estimated.weightKg,
      overrideReason: draft.overrideReason,
      sourceType: existing?.sourceType ?? ActivitySourceType.manual,
      userEdited: existing != null || draft.overrideCalories != null,
      notes: draft.notes,
      isFavorite: draft.isFavorite,
      syncStatus: store.writeStatus,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final index = store.activities.indexWhere((a) => a.id == activity.id);
    if (index >= 0) {
      store.activities[index] = activity;
    } else {
      store.activities.add(activity);
    }
    await _commit();
    return activity;
  }

  @override
  Future<void> deleteActivity(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(deletedAt: DateTime.now()) : a)
        .toList();
    await _commit();
  }

  @override
  Future<void> restoreActivity(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(clearDeletedAt: true) : a)
        .toList();
    await _commit();
  }

  @override
  Future<Activity> duplicateActivity(String id, DateTime date) async {
    final source = activityById(id);
    if (source == null) throw StateError('La actividad ya no existe');
    final startedAt = DateTime(
      date.year,
      date.month,
      date.day,
      source.startedAt.hour,
      source.startedAt.minute,
    );
    return saveActivity(
      ActivityDraft(
        activityTypeId: source.activityTypeId,
        customName: source.customName,
        startedAt: startedAt,
        durationMinutes: source.durationMinutes,
        intensity: source.intensity,
        distanceMeters: source.distanceMeters,
        steps: source.steps,
        notes: source.notes,
      ),
    );
  }

  @override
  Future<void> toggleFavorite(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(isFavorite: !a.isFavorite) : a)
        .toList();
    await _commit();
  }

  /// RN-04: se conserva `original_calories`, se marca `user_override`.
  @override
  Future<void> overrideCalories(String id, int calories, String? reason) async {
    store.activities = store.activities.map((a) {
      if (a.id != id) return a;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: calories,
        creditPercentage: a.exerciseCreditPercentage,
        creditEnabled: profile.exerciseCreditEnabled,
      );
      return a.copyWith(
        originalCalories: a.originalCalories ?? a.estimatedCalories,
        estimatedCalories: calories,
        appliedCalories: applied,
        estimationMethod: EstimationMethod.userOverride,
        overrideReason: reason,
        userEdited: true,
      );
    }).toList();
    await _commit();
  }

  @override
  Future<void> restoreCalculatedCalories(String id) async {
    store.activities = store.activities.map((a) {
      if (a.id != id) return a;
      final original = a.originalCalories ?? a.estimatedCalories;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: original,
        creditPercentage: a.exerciseCreditPercentage,
        creditEnabled: profile.exerciseCreditEnabled,
      );
      return a.copyWith(
        estimatedCalories: original,
        appliedCalories: applied,
        estimationMethod: a.metValue == null
            ? EstimationMethod.met
            : EstimationMethod.met,
        clearOverride: true,
      );
    }).toList();
    await _commit();
  }

  @override
  List<DuplicateCandidate> checkOverlap(ActivityDraft draft) {
    final incoming = DuplicateInput(
      activityTypeId: draft.activityTypeId,
      startedAt: draft.startedAt,
      durationMinutes: draft.durationMinutes,
      estimatedCalories: estimate(draft).calories,
      distanceMeters: draft.distanceMeters,
    );

    final out = <DuplicateCandidate>[];
    for (final a in store.activities) {
      if (a.isDeleted || a.id == draft.id) continue;
      final score = duplicateScore(
        incoming,
        DuplicateInput(
          activityTypeId: a.activityTypeId,
          startedAt: a.startedAt,
          durationMinutes: a.durationMinutes,
          estimatedCalories: a.estimatedCalories,
          distanceMeters: a.distanceMeters,
        ),
      );
      if (score.score >= DuplicateThresholds.suspicious) {
        out.add(
          DuplicateCandidate(
            incoming: _draftToActivity(draft, incoming.estimatedCalories),
            existing: a,
            score: score,
          ),
        );
      }
    }
    return out;
  }

  Activity _draftToActivity(ActivityDraft draft, int calories) => Activity(
    id: draft.id ?? 'draft',
    activityTypeId: draft.activityTypeId,
    activityType: typeById(draft.activityTypeId),
    customName: draft.customName,
    startedAt: draft.startedAt,
    endedAt: draft.startedAt.add(Duration(minutes: draft.durationMinutes)),
    localDate: dateOnly(draft.startedAt),
    durationMinutes: draft.durationMinutes,
    intensity: draft.intensity,
    distanceMeters: draft.distanceMeters,
    steps: draft.steps,
    estimatedCalories: calories,
    appliedCalories: 0,
    exerciseCreditPercentage: profile.effectiveCreditPercentage,
    estimationMethod: EstimationMethod.met,
    sourceType: ActivitySourceType.manual,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  @override
  List<ExerciseTemplate> get templates => store.templates;

  @override
  Future<void> saveTemplate(ExerciseTemplate template) async {
    final index = store.templates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      store.templates[index] = template;
    } else {
      store.templates.add(template);
    }
    await _commit();
  }

  @override
  Future<void> deleteTemplate(String id) async {
    store.templates.removeWhere((t) => t.id == id);
    await _commit();
  }

  @override
  List<ActivityGoal> get activityGoals => store.activityGoals;

  @override
  Future<void> saveActivityGoal(ActivityGoal goal) async {
    final index = store.activityGoals.indexWhere((g) => g.id == goal.id);
    if (index >= 0) {
      store.activityGoals[index] = goal;
    } else {
      store.activityGoals.add(goal);
    }
    await _commit();
  }

  @override
  Future<void> deleteActivityGoal(String id) async {
    store.activityGoals.removeWhere((g) => g.id == id);
    await _commit();
  }

  // ── Alimentos ──────────────────────────────────────────────────────────

  @override
  List<Food> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recent();
    final matches = store.allFoods.where((f) {
      final haystack = '${f.name} ${f.brand ?? ''}'.toLowerCase();
      return haystack.contains(q);
    }).toList();
    // "Tuyos" primero, después marcas, después genéricos (F-04 paso 4).
    matches.sort((a, b) {
      int rank(Food f) => switch (f.source) {
        FoodSource.user => 0,
        FoodSource.off => 1,
        _ => 2,
      };
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return matches;
  }

  /// Consulta los catálogos externos y cachea lo que traen, para que la
  /// próxima búsqueda —y el modo sin conexión— lo encuentren local.
  ///
  /// Dos fuentes que no se pisan:
  ///
  /// - **Open Food Facts**: productos envasados, por código de barras. Un
  ///   yogur de una marca.
  /// - **USDA** (por Edge Function): alimentos genéricos y crudos. "Pechuga de
  ///   pollo", "arroz cocido". Es lo que OFF no tiene y es la mitad de lo que
  ///   come cualquiera.
  ///
  /// Los alimentos argentinos no salen de acá: la tabla de ARGENFOODS viaja
  /// dentro del APK y ya la resolvió [search] sin tocar la red.
  ///
  /// Si una fuente falla, la otra igual contesta. Que se caiga USDA no puede
  /// dejar sin buscar a alguien que quería un producto de góndola.
  ///
  /// Pero si fallan **las dos**, lanza. Antes cada fuente tenía su
  /// `catchError` que devolvía la lista vacía, así que estar sin conexión era
  /// indistinguible de que el alimento no existiera: la pantalla decía "No
  /// encontramos ese alimento" y su botón "Reintentar" —que existe justamente
  /// para el otro caso— era inalcanzable.
  @override
  Future<List<Food>> searchOnline(String query) async {
    if (!FeatureFlags.onlineFoodCatalog || store.offline) {
      return const <Food>[];
    }
    if (query.trim().length < 2) return const <Food>[];

    var fallaron = 0;
    var fuentes = 0;
    AppError? ultimoError;

    Future<List<Food>> intentar(Future<List<Food>> consulta) {
      fuentes++;
      return consulta.catchError((Object error) {
        fallaron++;
        if (error is AppError) ultimoError = error;
        return const <Food>[];
      });
    }

    final responses = await Future.wait<List<Food>>(<Future<List<Food>>>[
      intentar(_foodCatalog.search(query)),
      if (usdaFoods != null)
        intentar(usdaFoods!.search(query))
      else
        Future<List<Food>>.value(const <Food>[]),
    ]);

    if (fuentes > 0 && fallaron == fuentes) {
      throw ultimoError ??
          const AppError(
            code: ApiErrorCode.offline,
            message: 'No pudimos consultar el catálogo. Revisá tu conexión.',
          );
    }

    // Sin ids repetidos: el mismo alimento puede venir de las dos.
    final byId = <String, Food>{};
    for (final food in responses.expand((r) => r)) {
      byId.putIfAbsent(food.id, () => food);
    }
    final results = byId.values.toList();
    if (results.isEmpty) return results;

    store.cacheFoods(results);
    await store.persist();
    return results;
  }

  @override
  Future<Food?> lookupBarcode(String ean) async {
    final local = byBarcode(ean);
    if (local != null) return local;
    if (!FeatureFlags.onlineFoodCatalog || store.offline) {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión no podemos buscar el código en el catálogo.',
      );
    }

    final found = await _foodCatalog.byBarcode(ean);
    if (found == null) return null;

    store.cacheFoods(<Food>[found]);
    await _commit();
    return found;
  }

  @override
  List<Food> recent() {
    final out = <Food>[];
    for (final id in store.recentFoodIds) {
      final food = byId(id);
      if (food != null) out.add(food);
    }
    return out;
  }

  @override
  List<Food> favorites() => store.allFoods.where((f) => f.isFavorite).toList();

  @override
  List<Food> ownFoods() => store.userFoods;

  @override
  Food? byId(String id) {
    for (final f in store.allFoods) {
      if (f.id == id) return f;
    }
    return null;
  }

  @override
  Food? byBarcode(String ean) {
    for (final f in store.allFoods) {
      if (f.barcode == ean) return f;
    }
    return null;
  }

  @override
  Future<Food> createOwnFood(Food food) async {
    store.userFoods.add(food);
    await _commit();
    return food;
  }

  @override
  Future<void> toggleFoodFavorite(String id) async {
    // Las tres listas, no dos: lo que viene de Open Food Facts queda en
    // `cachedFoods`, y saltearla hacía que marcar un producto del catálogo
    // externo no tuviera ningún efecto.
    //
    // El valor nuevo se calcula una sola vez y se aplica a todas: si un id
    // estuviera en más de una lista, invertir cada una por separado lo dejaría
    // marcado en unas y desmarcado en otras.
    final current = byId(id)?.isFavorite ?? false;
    final next = !current;

    List<Food> apply(List<Food> foods) => foods
        .map((f) => f.id == id ? f.copyWith(isFavorite: next) : f)
        .toList();

    store.userFoods = apply(store.userFoods);
    store.catalogFoods = apply(store.catalogFoods);
    store.cachedFoods = apply(store.cachedFoods);
    await _commit();
  }

  @override
  Future<void> deleteOwnFood(String id) async {
    store.userFoods.removeWhere((f) => f.id == id);
    await _commit();
  }

  @override
  Future<void> markUsed(String foodId) => _touchRecent(foodId);

  Future<void> _touchRecent(String foodId) async {
    store.recentFoodIds
      ..remove(foodId)
      ..insert(0, foodId);
    if (store.recentFoodIds.length > 20) {
      store.recentFoodIds = store.recentFoodIds.sublist(0, 20);
    }
  }

  // ── Cuerpo ─────────────────────────────────────────────────────────────

  @override
  List<WeightLog> get weightLogs =>
      <WeightLog>[...store.weightLogs.where((w) => !w.isDeleted)]
        ..sort((a, b) => b.localDate.compareTo(a.localDate));

  @override
  WeightLog? weightOn(DateTime date) {
    for (final w in store.weightLogs) {
      if (!w.isDeleted && isSameDay(w.localDate, date)) return w;
    }
    return null;
  }

  @override
  double? get currentWeightKg => store.currentWeightKg;

  /// Un peso por día: registrar de nuevo actualiza el existente (D-16).
  @override
  Future<WeightLog> logWeight({
    required double weightKg,
    required DateTime date,
    String? notes,
    String source = 'manual',
  }) async {
    final existing = weightOn(date);
    final log = WeightLog(
      id: existing?.id ?? _dailyId('weight', date),
      weightKg: weightKg,
      localDate: dateOnly(date),
      loggedAt: DateTime.now(),
      source: source,
      notes: notes,
      syncStatus: store.writeStatus,
    );
    store.weightLogs = <WeightLog>[
      ...store.weightLogs.where((w) => !isSameDay(w.localDate, date)),
      log,
    ];
    await _commit();
    return log;
  }

  @override
  Future<void> deleteWeight(String id) async {
    store.weightLogs = store.weightLogs
        .map((w) => w.id == id ? w.copyWith(deletedAt: DateTime.now()) : w)
        .toList();
    await _commit();
  }

  @override
  Future<void> restoreWeight(String id) async {
    store.weightLogs = store.weightLogs
        .map((w) => w.id == id ? w.copyWith(clearDeletedAt: true) : w)
        .toList();
    await _commit();
  }

  // ── Sueño ──────────────────────────────────────────────────────────────

  @override
  List<SleepLog> get sleepLogs =>
      <SleepLog>[...store.sleepLogs.where((s) => !s.isDeleted)]
        ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  SleepLog? sleepOn(DateTime date) {
    final day = dateOnly(date);
    for (final log in store.sleepLogs) {
      if (!log.isDeleted && isSameDay(log.localDate, day)) return log;
    }
    return null;
  }


  @override
  Future<void> logSleep({
    required DateTime date,
    required int minutes,
    required SleepQuality quality,
    String? notes,
  }) async {
    final day = dateOnly(date);
    final index = store.sleepLogs.indexWhere(
      (s) => isSameDay(s.localDate, day),
    );
    final entry = SleepLog(
      id: index >= 0 ? store.sleepLogs[index].id : _dailyId('sleep', day),
      localDate: day,
      minutes: SleepLog.clampMinutes(minutes),
      quality: quality,
      loggedAt: DateTime.now(),
      notes: notes,
      syncStatus: store.writeStatus,
      // Cargar de nuevo una noche borrada la revive en su misma fila.
    );
    if (index >= 0) {
      store.sleepLogs[index] = entry;
    } else {
      store.sleepLogs.add(entry);
    }
    await _commit();
  }

  /// Borrado suave, por lo mismo que el resto: con `removeWhere` la noche se
  /// iba del teléfono y seguía viva en la tabla, así que la reconciliación la
  /// devolvía en menos de treinta segundos.
  @override
  Future<void> deleteSleep(String id) async {
    store.sleepLogs = store.sleepLogs
        .map((s) => s.id == id ? s.copyWith(deletedAt: DateTime.now()) : s)
        .toList();
    await _commit();
  }

  // ── Recordatorios ──────────────────────────────────────────────────────

  @override
  List<Reminder> get reminders => store.reminders;

  @override
  Reminder reminderFor(ReminderKind kind) => store.reminders.firstWhere(
    (r) => r.kind == kind,
    orElse: () => Reminder.byDefault(kind),
  );

  @override
  Future<void> saveReminder(Reminder reminder) async {
    store.reminders = <Reminder>[
      for (final r in store.reminders)
        if (r.kind == reminder.kind) reminder else r,
    ];
    await _commit();
  }

  // ── Agua ───────────────────────────────────────────────────────────────

  @override
  List<WaterLog> get waterLogs =>
      <WaterLog>[...store.waterLogs]
        ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  int glassesOn(DateTime date) {
    final day = dateOnly(date);
    for (final log in store.waterLogs) {
      if (isSameDay(log.localDate, day)) return log.glasses;
    }
    return 0;
  }

  @override
  Future<void> addGlasses(DateTime date, int delta) async {
    final day = dateOnly(date);
    final index = store.waterLogs.indexWhere(
      (w) => isSameDay(w.localDate, day),
    );

    if (index >= 0) {
      final current = store.waterLogs[index];
      final next = (current.glasses + delta).clamp(0, WaterLog.maxGlasses);
      store.waterLogs[index] = current.copyWith(
        glasses: next,
        updatedAt: DateTime.now(),
      );
    } else {
      // Restar cuando no hay registro no crea uno en cero: no aporta nada y
      // ensucia el historial con días vacíos.
      if (delta <= 0) return;
      store.waterLogs.add(
        WaterLog(
          id: _dailyId('water', day),
          localDate: day,
          glasses: delta.clamp(0, WaterLog.maxGlasses),
          updatedAt: DateTime.now(),
        ),
      );
    }
    await _commit();
  }

  @override
  Future<void> setWaterGoal({
    required int glasses,
    required int glassSizeMl,
  }) => updateProfile(
    profile.copyWith(
      waterGoalGlasses: glasses.clamp(1, WaterLog.maxGlasses),
      glassSizeMl: glassSizeMl.clamp(50, 1000),
    ),
  );

  @override
  List<BodyMeasurement> measurements(MeasurementMetric metric) =>
      store.measurements
          .where((m) => m.metric == metric && !m.isDeleted)
          .toList()
        ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  List<BodyMeasurement> get allMeasurements => List<BodyMeasurement>.unmodifiable(
    store.measurements.where((m) => !m.isDeleted),
  );

  @override
  Map<MeasurementMetric, BodyMeasurement> measurementsOn(DateTime date) =>
      <MeasurementMetric, BodyMeasurement>{
        for (final m in store.measurements)
          if (!m.isDeleted && isSameDay(m.localDate, date)) m.metric: m,
      };

  /// La medida de esa métrica y ese día, borrada o no.
  ///
  /// Se mira también entre las borradas a propósito: volver a cargar una medida
  /// que se había borrado tiene que **revivir la misma fila** y no crear otra,
  /// porque del lado del servidor las dos ocuparían la misma clave única.
  BodyMeasurement? _measurementSlot(MeasurementMetric metric, DateTime date) {
    for (final m in store.measurements) {
      if (m.metric == metric && isSameDay(m.localDate, date)) return m;
    }
    return null;
  }

  /// Una medida por métrica y por día: volver a cargarla **actualiza la misma
  /// fila**, con su id.
  ///
  /// Antes generaba un id nuevo cada vez. Del lado de la base hay un índice
  /// único sobre `(user_id, metric, local_date)`, así que la fila vieja seguía
  /// viva en la tabla y la nueva chocaba contra ella: el `upsert` de medidas
  /// —que sube todas juntas en una sola sentencia— fallaba entero, y como nada
  /// borraba la fila vieja, **volvía a fallar en cada push siguiente**. Encima
  /// la reconciliación traía la fila vieja de vuelta y la pantalla mostraba el
  /// número que la persona acababa de corregir.
  @override
  Future<void> logMeasurement({
    required MeasurementMetric metric,
    required double value,
    required DateTime date,
  }) async {
    final slot = _measurementSlot(metric, date);
    final entry = BodyMeasurement(
      id: slot?.id ?? _dailyId('measurement', date, metric.wire),
      metric: metric,
      value: value,
      localDate: dateOnly(date),
      notes: slot?.notes,
      updatedAt: DateTime.now(),
    );
    store.measurements = <BodyMeasurement>[
      ...store.measurements.where((m) => m.id != entry.id),
      entry,
    ];
    await _commit();
  }

  /// Borrado suave: la lápida es lo que hace que el borrado llegue al servidor.
  ///
  /// Con `removeWhere` la fila desaparecía del teléfono y seguía viva en la
  /// tabla, así que la reconciliación siguiente —como mucho 30 segundos
  /// después— la traía de vuelta.
  @override
  Future<void> deleteMeasurement(String id) async {
    final now = DateTime.now();
    store.measurements = store.measurements
        .map(
          (m) => m.id == id
              ? m.copyWith(deletedAt: now, updatedAt: now)
              : m,
        )
        .toList();
    await _commit();
  }

  // ── Agregados ──────────────────────────────────────────────────────────

  @override
  DailySummary daily(DateTime date) => SummaryBuilder.daily(
    date: date,
    goal: goalFor(date),
    allMeals: store.meals,
    allActivities: store.activities,
    weightLogs: store.weightLogs,
    creditPercentage: profile.exerciseCreditPercentage,
    creditEnabled: profile.exerciseCreditEnabled,
    isRestDay: isRestDay(date),
    sickMarker: store.markerOn(date, DayMarkerKind.sick),
    alcoholLogs: store.alcoholLogs,
  );

  @override
  List<HistoryDay> history({required DateTime from, required DateTime to}) =>
      SummaryBuilder.history(
        from: from,
        to: to,
        allMeals: store.meals,
        allActivities: store.activities,
        goalFor: goalFor,
        isRestDay: isRestDay,
        creditEnabled: profile.exerciseCreditEnabled,
        isSickDay: isSickDay,
        alcoholLogs: store.alcoholLogs,
      );

  @override
  ProgressSummary progress({required DateTime from, required DateTime to}) =>
      SummaryBuilder.progress(
        from: from,
        to: to,
        allMeals: store.meals,
        allActivities: store.activities,
        weightLogs: store.weightLogs,
        activityGoals: store.activityGoals,
        goalFor: goalFor,
        isRestDay: isRestDay,
        creditEnabled: profile.exerciseCreditEnabled,
        // Sin esto, los denominadores del período salen del calendario y
        // cuentan como huecos los días anteriores a que la persona existiera
        // en la app. Ver `TrackingWindow`.
        trackingSince: trackingSince,
        markers: store.dayMarkers,
        alcoholLogs: store.alcoholLogs,
      );

  @override
  bool isRestDay(DateTime date) => store.isRestDay(date);

  @override
  bool isSickDay(DateTime date) => store.isSickDay(date);

  @override
  Future<void> setRestDay(DateTime date, bool isRest) => setMarker(
    date: date,
    kind: DayMarkerKind.rest,
    on: isRest,
  );

  // ── Contexto del día ───────────────────────────────────────────────────

  @override
  DayMarker? markerOn(DateTime date, DayMarkerKind kind) =>
      store.markerOn(date, kind);

  @override
  Future<void> setMarker({
    required DateTime date,
    required DayMarkerKind kind,
    required bool on,
    SickSeverity? severity,
    String? note,
    List<String> tags = const <String>[],
  }) async {
    final existente = store.markerOn(date, kind);

    if (!on) {
      if (existente == null) return;
      // Lápida y no borrado de la lista: sin esto, desmarcar acá lo saca de
      // este teléfono y lo deja vivo en la tabla, así que la reconciliación
      // siguiente lo resucita. Es el mismo error que ya se arregló en el sueño
      // (migración 29).
      _replaceMarker(existente.copyWith(deletedAt: DateTime.now()));
      await _commit();
      return;
    }

    // Puede haber una marca **borrada** de ese mismo día: se revive en vez de
    // insertar otra, porque el único de la tabla es por (día, tipo) y dos filas
    // vivas para el mismo par no entran.
    final enterrada = _buriedMarker(date, kind);
    final base = existente ?? enterrada;

    if (base != null) {
      _replaceMarker(
        base.copyWith(
          severity: kind == DayMarkerKind.sick ? severity : null,
          clearSeverity: kind != DayMarkerKind.sick || severity == null,
          note: note,
          clearNote: note == null,
          tags: tags,
          clearDeletedAt: true,
        ),
      );
    } else {
      store.dayMarkers.add(
        DayMarker(
          id: _uuid.v4(),
          localDate: dateOnly(date),
          kind: kind,
          severity: kind == DayMarkerKind.sick ? severity : null,
          note: note,
          tags: tags,
          updatedAt: DateTime.now(),
          syncStatus: store.writeStatus,
        ),
      );
    }
    await _commit();
  }

  DayMarker? _buriedMarker(DateTime date, DayMarkerKind kind) {
    final key = isoDate(date);
    for (final m in store.dayMarkers) {
      if (m.isDeleted && m.kind == kind && isoDate(m.localDate) == key) {
        return m;
      }
    }
    return null;
  }

  void _replaceMarker(DayMarker updated) {
    final i = store.dayMarkers.indexWhere((m) => m.id == updated.id);
    if (i >= 0) {
      store.dayMarkers[i] = updated;
    } else {
      store.dayMarkers.add(updated);
    }
  }

  // ── Alcohol ────────────────────────────────────────────────────────────

  @override
  List<AlcoholLog> alcoholOn(DateTime date) => store.alcoholOn(date);

  @override
  Future<AlcoholLog> logAlcohol({
    required DateTime date,
    required DrinkType type,
    required double quantity,
    required int volumeMl,
    required double abvPct,
    String? note,
  }) async {
    final log = AlcoholLog(
      id: _uuid.v4(),
      localDate: dateOnly(date),
      type: type,
      quantity: quantity.clamp(0.1, AlcoholLog.maxQuantity),
      volumeMl: volumeMl,
      abvPct: abvPct,
      note: note,
      loggedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: store.writeStatus,
    );
    store.alcoholLogs.add(log);
    await _commit();
    return log;
  }

  @override
  Future<void> deleteAlcohol(String id) async {
    final i = store.alcoholLogs.indexWhere((a) => a.id == id);
    if (i < 0) return;
    store.alcoholLogs[i] =
        store.alcoholLogs[i].copyWith(deletedAt: DateTime.now());
    await _commit();
  }

  @override
  Set<String> get daysWithRecords => <String>{
    ...store.meals.where((m) => !m.isDeleted).map((m) => isoDate(m.localDate)),
    ...store.activities
        .where((a) => !a.isDeleted)
        .map((a) => isoDate(a.localDate)),
  };

  /// El primer día del que hay algo cargado.
  ///
  /// Entran comidas, actividades y pesos: el peso porque el alta guiada lo
  /// registra antes que cualquier otra cosa, así que para casi todo el mundo es
  /// el primero de los tres. Se ignoran agua y sueño a propósito — se pueden
  /// cargar hacia atrás y no marcan cuándo empezó nadie.
  /// La fórmula es una sola y vive en `tracking_window.dart`, porque también la
  /// tienen que contestar igual el panel web (`backoffice/lib/tracking.ts`) y el
  /// servidor (`public.tracking_since`). Si el PDF que genera el teléfono y la
  /// pantalla que mira la nutricionista contaran distinto, estarían discutiendo
  /// sobre dos números que se llaman igual.
  @override
  DateTime? get trackingSince => earliestTrackedDay(<DateTime>[
    for (final m in store.meals)
      if (!m.isDeleted) m.localDate,
    for (final a in store.activities)
      if (!a.isDeleted) a.localDate,
    for (final w in store.weightLogs)
      if (!w.isDeleted) w.localDate,
  ]);

  // ── Salud ──────────────────────────────────────────────────────────────

  @override
  HealthIntegration get integration => store.integration;

  /// La pantalla de integraciones solo existe en Android (D-21).
  @override
  bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> connect() async {
    final gateway = health;
    if (gateway == null) {
      store.integration = store.integration.copyWith(
        status: IntegrationStatus.error,
        lastError: 'Esta compilación no tiene el puente de Health Connect.',
      );
      await _commit();
      return;
    }

    // Tres estados, tres arreglos distintos: sin soporte no hay nada que hacer,
    // "actualizá Health Connect" sí tiene salida, y recién con permiso se
    // conecta. Meterlos en un solo "falló" mandaría a la persona a buscar el
    // problema donde no está.
    final availability = await gateway.availability();
    if (availability != HealthConnectAvailability.available) {
      store.integration = store.integration.copyWith(
        status: IntegrationStatus.error,
        lastError: availability == HealthConnectAvailability.updateRequired
            ? 'Actualizá Health Connect desde Play Store y volvé a intentar.'
            : 'Este teléfono no tiene Health Connect. Necesita Android 9 o más '
                  'nuevo.',
      );
      await _commit();
      return;
    }

    final granted = await gateway.requestPermissions();
    if (!granted) {
      store.integration = store.integration.copyWith(
        status: IntegrationStatus.error,
        lastError: 'Sin los tres permisos no podemos importar. Se dan desde '
            'Health Connect.',
      );
      await _commit();
      return;
    }

    store.integration = store.integration.copyWith(
      status: IntegrationStatus.connected,
      connectedAt: DateTime.now(),
      permissions: const <String>['Weight', 'BodyFat', 'SleepSession'],
      clearError: true,
    );
    await _commit();
  }

  @override
  Future<void> disconnect() async {
    // No se revoca el permiso desde acá: eso lo hace la persona en Health
    // Connect. Una app que dijera "desconectado" con el permiso todavía dado
    // estaría mintiendo sobre lo que puede leer; lo que se corta es la
    // importación, que es lo que sí depende de nosotros.
    store.integration = store.integration.copyWith(
      status: IntegrationStatus.notConnected,
      permissions: const <String>[],
    );
    await _commit();
  }

  /// Trae de Health Connect el peso, la grasa corporal y el sueño de los
  /// últimos 30 días.
  ///
  /// **No puede duplicar nada**, y eso no es suerte: las tres cosas son una por
  /// día o por noche en Ceres, y volver a registrarlas actualiza el registro
  /// que ya estaba (D-16). Sincronizar diez veces deja lo mismo que una.
  ///
  /// Tampoco toca las calorías: lo que mide el reloj es la estimación de otro
  /// modelo, y presentarla como propia rompería RN-03. Las sesiones de ejercicio
  /// —lo único que sí podría duplicar— no entran todavía: necesitan la revisión
  /// de duplicados de por medio, que ya existe, y merecen su propio paso.
  @override
  Future<HealthSyncResult> sync() async {
    final gateway = health;
    if (gateway == null || !await gateway.hasPermissions()) {
      store.integration = store.integration.copyWith(
        status: IntegrationStatus.error,
        lastError: 'Faltan los permisos de Health Connect.',
      );
      await _commit();
      return const HealthSyncResult(
        imported: 0,
        updated: 0,
        skipped: 0,
        duplicates: <DuplicateCandidate>[],
      );
    }

    final HealthConnectSnapshot snapshot;
    try {
      snapshot = await gateway.read();
    } on AppError catch (error) {
      store.integration = store.integration.copyWith(
        status: IntegrationStatus.error,
        lastError: error.message,
      );
      await _commit();
      rethrow;
    }

    var imported = 0;
    var updated = 0;

    // Se cuenta aparte lo que entra por primera vez de lo que corrige un
    // registro que ya estaba: son dos cosas distintas y la pantalla las dice
    // por separado.
    for (final entry in snapshot.weightKg.entries) {
      final existing = weightOn(entry.key) != null;
      await logWeight(
        weightKg: entry.value,
        date: entry.key,
        source: 'imported',
      );
      if (existing) {
        updated++;
      } else {
        imported++;
      }
    }

    for (final entry in snapshot.bodyFatPct.entries) {
      final existing = measurementsOn(
        entry.key,
      ).containsKey(MeasurementMetric.bodyFatPct);
      await logMeasurement(
        metric: MeasurementMetric.bodyFatPct,
        value: entry.value,
        date: entry.key,
      );
      if (existing) {
        updated++;
      } else {
        imported++;
      }
    }

    for (final entry in snapshot.sleepMinutes.entries) {
      final existing = sleepOn(entry.key);
      await logSleep(
        date: entry.key,
        minutes: entry.value,
        // La calidad no la mide Health Connect de una forma que se pueda
        // traducir sin inventar, así que se conserva la que haya puesto la
        // persona y si no hay ninguna queda en "normal". Lo importado es la
        // duración, que es lo que el reloj sí sabe.
        quality: existing?.quality ?? SleepQuality.ok,
        notes: existing?.notes,
      );
      if (existing != null) {
        updated++;
      } else {
        imported++;
      }
    }

    store.integration = store.integration.copyWith(
      status: IntegrationStatus.connected,
      lastSyncAt: DateTime.now(),
      importedCount: store.integration.importedCount + imported,
      clearError: true,
    );
    await _commit();

    return HealthSyncResult(
      imported: imported,
      updated: updated,
      skipped: 0,
      // Ninguna de las tres cosas que se importan puede duplicar, así que no
      // hay nada que mandar a revisar.
      duplicates: const <DuplicateCandidate>[],
    );
  }

  @override
  Future<void> deleteImported() async {
    final removed = store.activities
        .where((a) => a.sourceType == ActivitySourceType.imported)
        .length;
    store.activities.removeWhere(
      (a) => a.sourceType == ActivitySourceType.imported,
    );
    store.integration = store.integration.copyWith(
      importedCount:
          (store.integration.importedCount - removed).clamp(0, 1 << 31),
    );
    await _commit();
  }

  /// La descartada pasa a `deleted_at` con motivo `duplicate_merge`; sin
  /// acción del usuario queda `needs_review` (S-14).
  @override
  Future<void> resolveDuplicate(
    DuplicateCandidate candidate,
    DuplicateResolution resolution,
  ) async {
    switch (resolution) {
      case DuplicateResolution.keepIncoming:
        await deleteActivity(candidate.existing.id);
        _markReviewed(candidate.incoming.id);
      case DuplicateResolution.keepExisting:
        await deleteActivity(candidate.incoming.id);
      case DuplicateResolution.keepBoth:
        _markReviewed(candidate.incoming.id);
      case DuplicateResolution.defer:
        break;
    }
    await _commit();
  }

  void _markReviewed(String id) {
    store.activities = store.activities
        .map(
          (a) => a.id == id && a.syncStatus == SyncStatus.needsReview
              ? a.copyWith(syncStatus: SyncStatus.synced)
              : a,
        )
        .toList();
  }

  @override
  List<DuplicateCandidate> get pendingReviews {
    final out = <DuplicateCandidate>[];
    final needsReview = store.activities.where(
      (a) => !a.isDeleted && a.syncStatus == SyncStatus.needsReview,
    );
    for (final incoming in needsReview) {
      for (final existing in store.activities) {
        if (existing.id == incoming.id ||
            existing.isDeleted ||
            existing.sourceType == ActivitySourceType.imported) {
          continue;
        }
        final score = duplicateScore(
          DuplicateInput(
            activityTypeId: incoming.activityTypeId,
            startedAt: incoming.startedAt,
            durationMinutes: incoming.durationMinutes,
            estimatedCalories: incoming.estimatedCalories,
            distanceMeters: incoming.distanceMeters,
          ),
          DuplicateInput(
            activityTypeId: existing.activityTypeId,
            startedAt: existing.startedAt,
            durationMinutes: existing.durationMinutes,
            estimatedCalories: existing.estimatedCalories,
            distanceMeters: existing.distanceMeters,
          ),
        );
        if (score.score >= DuplicateThresholds.suspicious) {
          out.add(
            DuplicateCandidate(
              incoming: incoming,
              existing: existing,
              score: score,
            ),
          );
        }
      }
    }
    return out;
  }

  // ── Análisis de foto ───────────────────────────────────────────────────

  /// Cuota de 20 análisis por día (D-18).
  @override
  int get quotaLimit => 20;

  int _quotaUsed = 0;

  @override
  int get quotaUsed => _quotaUsed;

  @override
  Future<AiAnalysis> analyzeText({required String description}) async {
    final client = aiAnalysis;
    if (client == null) {
      throw const AppError(
        code: ApiErrorCode.providerUnavailable,
        message: 'Esta compilación no tiene servidor: la estimación con IA '
            'necesita cuenta.',
      );
    }
    final analysis = await client.analyzeText(description: description);
    _quotaUsed++;
    return analysis;
  }

  @override
  Future<List<MealSuggestion>> suggestMeals({
    required int remainingKcal,
    MealSlot? slot,
    int? remainingProteinG,
  }) async {
    final client = suggestions;
    if (client == null) {
      throw const AppError(
        code: ApiErrorCode.providerUnavailable,
        message: 'Esta compilación no tiene servidor: las sugerencias '
            'necesitan cuenta.',
      );
    }

    // El mismo piso que aplica el servidor, comprobado acá para no gastar un
    // viaje ni una unidad de cuota en que nos digan que no.
    if (remainingKcal < MealSuggestionsClient.minBudgetKcal) {
      throw const AppError(
        code: ApiErrorCode.budgetTooLow,
        message: 'Con menos de 150 kcal no hay un plato que sugerir sin '
            'inventarlo. Para completar el día alcanza una fruta o un yogur.',
      );
    }

    final options = await client.suggest(
      remainingKcal: remainingKcal,
      slot: slot,
      remainingProteinG: remainingProteinG,
      // Las restricciones salen del perfil y las manda el cliente: la Edge
      // Function no las lee de `profiles` a propósito, para que la app funcione
      // igual con un perfil que todavía no se sincronizó. Son de esta persona,
      // así que no hay nada que defender de un cliente que mienta: mentirse a
      // sí mismo sobre su propia alergia no es un ataque.
      restrictions: <String>[
        for (final flag in profile.dietaryFlags) flag.wire,
      ],
      restrictionsNote: profile.dietaryNote,
    );
    _quotaUsed++;
    return options;
  }

  @override
  bool get canProposeCalorieTarget => calorieTargets != null;

  @override
  Future<AiCalorieTarget> proposeCalorieTarget({
    required double weightKg,
    required GoalType goalType,
    required int formulaTarget,
  }) async {
    final client = calorieTargets;
    if (client == null) {
      throw const AppError(
        code: ApiErrorCode.providerUnavailable,
        message: 'Esta compilación no tiene servidor: calcularlo con IA '
            'necesita cuenta.',
      );
    }

    // Los mismos datos con los que la app calcula, y ninguno más. El servidor
    // rehace la cuenta con ellos: acá no se manda un gasto ya masticado
    // justamente para que el techo de la validación no salga del teléfono.
    final current = profile;
    if (!current.hasBodyData) {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Faltan tu altura y tu fecha de nacimiento para calcularlo.',
      );
    }

    final proposal = await client.propose(
      sex: current.biologicalSex,
      ageYears: ageFromBirthDate(current.birthDate!),
      heightCm: current.heightCm!,
      weightKg: weightKg,
      activityLevel: current.activityLevel,
      goalType: goalType,
      formulaTarget: formulaTarget,
    );
    _quotaUsed++;
    return proposal;
  }

  @override
  Future<AiAnalysis> analyze({
    required String photoPath,
    String? description,
    void Function(AnalysisStage stage)? onStage,
    void Function(String remotePath)? onUploaded,
  }) async {
    final client = aiAnalysis;
    if (client != null) {
      onStage?.call(AnalysisStage.preparing);
      // La foto tiene que estar en el bucket antes: la función la descarga de
      // ahí. Si la subida falló, esto devuelve la ruta local y la función
      // responde "no encontramos esa foto", que es correcto y se muestra tal
      // cual.
      onStage?.call(AnalysisStage.uploading);
      final remotePath =
          await photos?.ensureUploaded(
            bucket: PhotoBucket.meal,
            recordId: _uuid.v4(),
            localPath: photoPath,
            rethrowOnFailure: true,
          ) ??
          photoPath;

      // Se avisa apenas subió, no al final: si el modelo falla o alguien
      // cancela, quien llama necesita esta ruta para borrar la copia.
      if (remotePath != photoPath) onUploaded?.call(remotePath);

      onStage?.call(AnalysisStage.analyzing);
      final analysis = await client.analyze(
        photoPath: remotePath,
        description: description,
      );
      _quotaUsed++;

      // La ruta del bucket viaja de vuelta con el análisis, y de ahí la toma la
      // pantalla de revisión para que la comida se guarde apuntando a **esta**
      // copia.
      //
      // Sin esto se subía dos veces: acá con un id al azar, y otra vez en
      // `saveMeal` con el id de la comida, porque lo que llegaba ahí seguía
      // siendo la ruta del archivo del teléfono. Cada foto analizada ocupaba el
      // doble en el bucket y la primera copia no la referenciaba nadie: no se
      // mostraba, no se borraba y no había forma de encontrarla.
      return analysis.copyWith(photoPath: remotePath);
    }

    // Sin servidor: resultado fijo. Solo se llega acá con `NM_AI_PHOTO`
    // encendido a mano en una compilación sin Supabase.
    _quotaUsed++;
    final now = DateTime.now();
    return AiAnalysis(
      id: _uuid.v4(),
      photoPath: photoPath,
      status: AiAnalysisStatus.completed,
      model: 'gemini-2.5-flash',
      promptVersion: 'v1',
      latencyMs: 1200,
      createdAt: now,
      items: const <AiAnalysisItem>[
        AiAnalysisItem(
          name: 'Milanesa de carne',
          quantity: 1,
          unit: 'unidad',
          kcal: 289,
          proteinG: 23,
          carbsG: 14,
          fatG: 15,
          confidence: 0.82,
        ),
        AiAnalysisItem(
          name: 'Puré de papas',
          quantity: 200,
          unit: 'g',
          kcal: 174,
          proteinG: 3.6,
          carbsG: 29,
          fatG: 5,
          confidence: 0.64,
        ),
        AiAnalysisItem(
          name: 'Ensalada de tomate',
          quantity: 120,
          unit: 'g',
          kcal: 38,
          proteinG: 1.4,
          carbsG: 5.6,
          fatG: 0.5,
          confidence: 0.41,
        ),
      ],
    );
  }

  @override
  Future<AiAnalysis> recalculate({
    required List<MealItem> items,
    required String instruction,
    String? photoPath,
    void Function(AnalysisStage stage)? onStage,
    void Function(String remotePath)? onUploaded,
  }) async {
    final client = aiAnalysis;
    if (client == null) {
      throw const AppError(
        code: ApiErrorCode.providerUnavailable,
        message: 'Esta compilación no tiene servidor: recalcular con IA '
            'necesita cuenta.',
      );
    }

    // La foto que ya está en el bucket no se vuelve a subir: `ensureUploaded`
    // la reconoce y la devuelve igual. Solo sube la que la persona acaba de
    // sacar, y ahí sí avisa la ruta nueva — si el recálculo falla después,
    // quien llama necesita esa ruta para borrar la copia que quedó suelta.
    String? remotePath;
    if (photoPath != null && photoPath.isNotEmpty) {
      onStage?.call(AnalysisStage.preparing);
      onStage?.call(AnalysisStage.uploading);
      remotePath =
          await photos?.ensureUploaded(
            bucket: PhotoBucket.meal,
            recordId: _uuid.v4(),
            localPath: photoPath,
            rethrowOnFailure: true,
          ) ??
          photoPath;
      if (remotePath != photoPath) onUploaded?.call(remotePath);
    }

    onStage?.call(AnalysisStage.analyzing);
    final analysis = await client.recalculate(
      items: items,
      instruction: instruction,
      photoPath: remotePath,
    );
    _quotaUsed++;
    return analysis;
  }

  // ── Respaldo ───────────────────────────────────────────────────────────

  // Vive en el store: es la condición que decide si se puede pisar el
  // respaldo remoto, y tener dos definiciones de "vacío" es pedir que se
  // separen justo en el caso que importa.
  @override
  bool get hasUserData => store.hasUserData;

  /// Cómo salió la última lectura del documento guardado. La UI avisa cuando
  /// no salió limpia, en vez de mostrar la app vacía como si nunca hubiera
  /// habido nada.
  @override
  RestoreOutcome get lastRestore => store.lastRestore;

  @override
  String? get quarantinedDocument => store.quarantinedDocument;

  @override
  String exportJson() {
    final document = store.toDocument();
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': 'Ceres',
      'exportedAt': DateTime.now().toIso8601String(),
      ...document,
    });
  }

  @override
  BackupSummary inspectBackup(String json) {
    final document = _parseBackup(json);
    int count(String key) => (document[key] as List<dynamic>?)?.length ?? 0;
    return BackupSummary(
      meals: count('meals'),
      activities: count('activities'),
      weights: count('weightLogs'),
      measurements: count('measurements'),
    );
  }

  @override
  Future<BackupSummary> importJson(String json) async {
    final document = _parseBackup(json);
    final summary = inspectBackup(json);
    store.restoreDocument(document);
    await _commit();
    return summary;
  }

  /// Aplica un documento ya armado, sin pasar por JSON.
  ///
  /// Lo usa la lectura desde las tablas: la sincronización relacional devuelve
  /// exactamente la misma forma que el documento local, así que se aprovecha
  /// la lectura tolerante de `restoreDocument` —un registro raro se saltea y
  /// el resto sobrevive— en vez de escribir un segundo lector.
  @override
  Future<void> importDocument(Map<String, dynamic> document) async {
    store.restoreDocument(document);
    await _commit();
  }

  Map<String, dynamic> _parseBackup(String json) {
    Map<String, dynamic> document;
    try {
      document = jsonDecode(json) as Map<String, dynamic>;
    } on Object {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese archivo no es un respaldo de Ceres.',
      );
    }

    // Un archivo de otra app puede ser JSON válido: se exige el perfil, que
    // es lo mínimo que todo respaldo nuestro tiene.
    if (!document.containsKey('profile')) {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese archivo no es un respaldo de Ceres.',
      );
    }

    final version = document['schemaVersion'] as int? ?? 1;
    if (version > LocalStore.schemaVersion) {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese respaldo viene de una versión más nueva de la app. '
            'Actualizá Ceres antes de importarlo.',
      );
    }
    return document;
  }

  // ── Conectividad ───────────────────────────────────────────────────────

  /// ⚠️ Hoy devuelve **siempre `false`**.
  ///
  /// Lo único que ponía `offline` en true era el interruptor de "simular modo
  /// sin conexión", que se sacó de Configuración por ser una herramienta de
  /// desarrollo peligrosa en manos de quien usa la app. No hay detección real
  /// de conectividad: cuando la haya, este getter es el lugar donde enchufarla
  /// y todo lo que ya lo consulta —el banner, el estado `pending` de cada
  /// escritura, el corte del catálogo online— empieza a funcionar solo.
  ///
  /// Se deja explícito para que nadie lea un `if (isOffline)` y crea que hay
  /// algo detectando la red.
  @override
  bool get isOffline => store.offline;

  @override
  int get pendingCount => store.pendingCount;

  @override
  Future<void> flushQueue() async {
    store.meals = store.meals
        .map(
          (m) => m.syncStatus == SyncStatus.pending
              ? m.copyWith(syncStatus: SyncStatus.synced)
              : m,
        )
        .toList();
    store.activities = store.activities
        .map(
          (a) => a.syncStatus == SyncStatus.pending
              ? a.copyWith(syncStatus: SyncStatus.synced)
              : a,
        )
        .toList();
    store.weightLogs = store.weightLogs
        .map(
          (w) => w.syncStatus == SyncStatus.pending
              ? w.copyWith(syncStatus: SyncStatus.synced)
              : w,
        )
        .toList();
    await _commit();
  }
}
