// ignore: unused_import
import '../../core/error/app_error.dart';
import '../calculations/alcohol.dart';
import '../calculations/duplicate_score.dart';
import '../enums/enums.dart';
import '../models/activity.dart';
import '../models/ai_analysis.dart';
import '../models/ai_calorie_target.dart';
import '../models/alcohol.dart';
import '../models/analysis_stage.dart';
import '../models/body.dart';
import '../models/day_marker.dart';
import '../models/food.dart';
import '../models/goal.dart';
import '../models/meal.dart';
import '../models/meal_suggestion.dart';
import '../models/reminder.dart';
import '../models/restore_outcome.dart';
import '../models/sleep.dart';
import '../models/summaries.dart';
import '../models/user_profile.dart';
import '../models/water.dart';

/// Interfaces de la capa de datos. La presentación depende **solo** de esto;
/// las implementaciones viven en `data/repositories/` (19-project-structure §3).
///
/// Los repositorios son local-first: leen de la base local y escriben local
/// encolando la sincronización (13-state-management.md §5).

/// Borrador de una actividad en edición (S-10).
class ActivityDraft {
  const ActivityDraft({
    required this.activityTypeId,
    required this.startedAt,
    required this.durationMinutes,
    required this.intensity,
    this.id,
    this.customName,
    this.distanceMeters,
    this.steps,
    this.averageHeartRate,
    this.maximumHeartRate,
    this.notes,
    this.overrideCalories,
    this.overrideReason,
    this.usePaceEstimate = false,
    this.isFavorite = false,
  });

  final String? id;
  final String activityTypeId;
  final String? customName;
  final DateTime startedAt;
  final int durationMinutes;
  final Intensity intensity;
  final int? distanceMeters;
  final int? steps;
  final int? averageHeartRate;
  final int? maximumHeartRate;
  final String? notes;
  final int? overrideCalories;
  final String? overrideReason;
  final bool usePaceEstimate;
  final bool isFavorite;
}

/// Resultado de una sincronización de salud (F-09).
class HealthSyncResult {
  const HealthSyncResult({
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.duplicates,
  });

  final int imported;
  final int updated;
  final int skipped;
  final List<DuplicateCandidate> duplicates;
}

/// Par de actividades a resolver por la persona (nunca se resuelve solo, D-07).
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.incoming,
    required this.existing,
    required this.score,
  });

  final Activity incoming;
  final Activity existing;
  final DuplicateScore score;
}

enum DuplicateResolution { keepIncoming, keepExisting, keepBoth, defer }

/// Todas las superficies de datos juntas. Existe para que la presentación
/// pueda inyectar un único objeto sin conocer la implementación concreta.
abstract interface class CeresRepositories
    implements
        ProfileRepository,
        GoalRepository,
        MealRepository,
        ActivityRepository,
        FoodRepository,
        BodyRepository,
        WaterRepository,
        ReminderRepository,
        SleepRepository,
        DayContextRepository,
        AlcoholRepository,
        SummaryRepository,
        HealthRepository,
        AiPhotoRepository,
        BackupRepository,
        ConnectivityRepository {}

abstract interface class ProfileRepository {
  UserProfile? get profileOrNull;
  UserProfile get profile;
  bool get hasSession;

  /// Faltan los datos con los que la app calcula.
  ///
  /// Sin fecha de nacimiento, altura y peso no hay Mifflin-St Jeor: no hay
  /// metabolismo basal, ni gasto diario, ni calorías de ejercicio. Todo lo que
  /// se muestre en Inicio hasta que estén es un valor de referencia con forma de
  /// cuenta, que es justo lo que el producto no hace (RN-03). Mientras sea
  /// `true` el router no deja entrar al shell y manda a completarlos.
  ///
  /// Los tres se eligieron porque son los únicos que **no tienen un valor por
  /// omisión honesto**: el sexo biológico admite "Otro", el nivel de actividad
  /// arranca en moderado y el objetivo en mantener, y ahí un valor por defecto
  /// es una respuesta válida, no un hueco. Estos tres, en cambio, o están o la
  /// fórmula no corre.
  bool get needsOnboarding;

  Future<void> updateProfile(UserProfile profile);
  Future<void> setExerciseCredit({
    required int percentage,
    required bool enabled,
  });
  /// Modo demo sin cuenta: usuario local anónimo (D-15).
  Future<void> startDemoSession({required bool seeded});
  /// Marca el documento local como el de esta cuenta.
  ///
  /// [accountId] es el `auth.users.id`. Va porque es lo que permite distinguir
  /// "la misma persona vuelve a entrar" de "en este teléfono entra otra": el
  /// segundo caso arranca limpio en vez de adoptar —y subir a la cuenta nueva—
  /// los datos del anterior.
  Future<void> signIn(String email, {String? accountId});
  Future<void> signOut();
  Future<void> setThemeMode(ThemeModeSetting mode);
  Future<void> setUnitSystem(UnitSystem units);
  Future<void> setShowNetCalories(bool value);
}

abstract interface class GoalRepository {
  Goal? get currentGoalOrNull;
  Goal goalFor(DateTime date);
  Future<void> saveGoal(Goal goal);
}

abstract interface class MealRepository {
  List<Meal> mealsOn(DateTime date);

  /// Todo el historial, **incluido lo borrado**. Es lo que permite comparar
  /// contra las filas del servidor, que también conservan el borrado lógico:
  /// comparar una lista filtrada contra una que no lo está daría una diferencia
  /// que no existe.
  List<Meal> get allMeals;

  Meal? mealById(String id);
  Future<Meal> saveMeal(Meal meal);
  Future<void> deleteMeal(String id);
  Future<void> restoreMeal(String id);
  Future<Meal> duplicateMeal(String id, DateTime date, MealSlot slot);
  Future<void> toggleMealFavorite(String id);
  List<Meal> favoriteMeals();

  /// Las comidas que se repiten, para volver a cargarlas en dos toques.
  /// Con [slot] se prioriza el del momento sin esconder las de otros.
  List<Meal> frequentMeals({MealSlot? slot, int limit});

  /// Cuántas veces se registró una comida con ese título.
  int mealUseCount(Meal meal);

  /// Borra del bucket las fotos de comidas que se borraron hace rato, y
  /// devuelve cuántas sacó.
  ///
  /// Borrar una comida es un borrado suave: la fila queda como lápida para que
  /// la reconciliación sepa que no volvió a aparecer sola. La **foto**, en
  /// cambio, no tiene por qué quedarse: es lo único del registro que ocupa
  /// megabytes, no la mira nadie nunca más y hasta ahora se quedaba en el
  /// servidor para siempre.
  ///
  /// Espera un día antes de tocar nada, así la ventana de deshacer y cualquier
  /// arrepentimiento del mismo rato encuentran la foto donde estaba.
  Future<int> purgeDeletedPhotos();
}

abstract interface class ActivityRepository {
  List<ActivityType> get types;
  ActivityType? typeById(String id);
  ActivityType? typeBySlug(String slug);
  Future<ActivityType> createCustomType(ActivityType type);

  List<Activity> activitiesOn(DateTime date);

  /// Todo el historial, incluido lo borrado. Ver [MealRepository.allMeals].
  List<Activity> get allActivities;

  Activity? activityById(String id);
  List<Activity> recentActivities({int limit = 5});
  List<Activity> favoriteActivities();

  /// Calcula el gasto estimado de un borrador sin persistirlo (S-10).
  ActivityEstimate estimate(ActivityDraft draft);

  Future<Activity> saveActivity(ActivityDraft draft);
  Future<void> deleteActivity(String id);
  Future<void> restoreActivity(String id);
  Future<Activity> duplicateActivity(String id, DateTime date);
  Future<void> toggleFavorite(String id);
  Future<void> overrideCalories(String id, int calories, String? reason);
  Future<void> restoreCalculatedCalories(String id);

  /// Solapamientos con lo ya registrado, para la advertencia de F-08.
  List<DuplicateCandidate> checkOverlap(ActivityDraft draft);

  List<ExerciseTemplate> get templates;
  Future<void> saveTemplate(ExerciseTemplate template);
  Future<void> deleteTemplate(String id);

  List<ActivityGoal> get activityGoals;
  Future<void> saveActivityGoal(ActivityGoal goal);
  Future<void> deleteActivityGoal(String id);
}

/// Lo que `ExerciseCaloriesEstimate` necesita para explicarse (RN-03).
class ActivityEstimate {
  const ActivityEstimate({
    required this.calories,
    required this.method,
    this.metValue,
    this.weightKg,
    this.durationMinutes,
    this.unavailableReason,
  });

  final int calories;
  final EstimationMethod method;
  final double? metValue;
  final double? weightKg;
  final int? durationMinutes;

  /// "Necesitamos tu peso para estimar" cuando falta un insumo.
  final String? unavailableReason;

  bool get isAvailable => unavailableReason == null;
}

abstract interface class FoodRepository {
  /// Búsqueda local inmediata: alimentos propios y catálogo ya cacheado.
  List<Food> search(String query);

  /// Búsqueda en el catálogo externo (Open Food Facts). Lanza [AppError]
  /// si el proveedor falla o se pasa del timeout; la UI degrada a lo local
  /// con un banner de reintento (F-04).
  Future<List<Food>> searchOnline(String query);

  /// Consulta por código de barras en el catálogo externo.
  Future<Food?> lookupBarcode(String ean);

  List<Food> recent();
  List<Food> favorites();
  List<Food> ownFoods();
  Food? byId(String id);
  Food? byBarcode(String ean);
  Future<Food> createOwnFood(Food food);
  Future<void> toggleFoodFavorite(String id);
  Future<void> deleteOwnFood(String id);
  Future<void> markUsed(String foodId);
}

abstract interface class SleepRepository {
  List<SleepLog> get sleepLogs;

  /// La noche registrada sobre ese día, o `null`.
  SleepLog? sleepOn(DateTime date);

  /// Una noche por día: registrar de nuevo actualiza, igual que el peso (D-16).
  Future<void> logSleep({
    required DateTime date,
    required int minutes,
    required SleepQuality quality,
    String? notes,
  });

  Future<void> deleteSleep(String id);
}

abstract interface class ReminderRepository {
  List<Reminder> get reminders;
  Reminder reminderFor(ReminderKind kind);
  Future<void> saveReminder(Reminder reminder);
}

abstract interface class WaterRepository {
  /// Vasos de hoy o del día pedido. Devuelve 0 si nunca se registró nada.
  int glassesOn(DateTime date);

  List<WaterLog> get waterLogs;

  /// Suma o resta vasos. Nunca baja de 0 ni sube de [WaterLog.maxGlasses].
  Future<void> addGlasses(DateTime date, int delta);

  Future<void> setWaterGoal({required int glasses, required int glassSizeMl});
}

abstract interface class BodyRepository {
  List<WeightLog> get weightLogs;
  WeightLog? weightOn(DateTime date);
  double? get currentWeightKg;
  /// [source] distingue lo que cargó la persona de lo que trajo una
  /// integración. La base contempla `'imported'` desde siempre y la app
  /// mandaba `'manual'` para todo, así que la procedencia de un peso que vino
  /// de Health Connect se perdía — y con ella la posibilidad de deshacer una
  /// importación sin tocar lo cargado a mano.
  Future<WeightLog> logWeight({
    required double weightKg,
    required DateTime date,
    String? notes,
    String source = 'manual',
  });
  Future<void> deleteWeight(String id);
  Future<void> restoreWeight(String id);

  List<BodyMeasurement> measurements(MeasurementMetric metric);

  /// Todas las medidas de todas las métricas, incluido lo borrado.
  /// Ver [MealRepository.allMeals].
  List<BodyMeasurement> get allMeasurements;

  /// Todas las medidas de un día, indexadas por métrica.
  ///
  /// La planilla de una nutricionista se completa entera de una sentada: sin
  /// esto habría que abrir un formulario por cada uno de los veinte valores.
  Map<MeasurementMetric, BodyMeasurement> measurementsOn(DateTime date);

  Future<void> logMeasurement({
    required MeasurementMetric metric,
    required double value,
    required DateTime date,
  });
  Future<void> deleteMeasurement(String id);
}

/// Lo que califica un día sin medirlo: descanso y enfermedad.
///
/// Las dos marcas comparten interfaz porque comparten forma y tabla
/// (`day_markers`). Sumar una tercera —vacaciones, viaje— es agregar un valor
/// al enum, no una superficie nueva. Ver `docs/contexto-diario.md`.
abstract interface class DayContextRepository {
  DayMarker? markerOn(DateTime date, DayMarkerKind kind);

  /// Pone o saca la marca. Volver a marcar un día ya marcado **actualiza** la
  /// que hay en vez de agregar otra: el único es por (día, tipo).
  Future<void> setMarker({
    required DateTime date,
    required DayMarkerKind kind,
    required bool on,
    SickSeverity? severity,
    String? note,
    List<String> tags,
  });
}

abstract interface class AlcoholRepository {
  List<AlcoholLog> alcoholOn(DateTime date);

  Future<AlcoholLog> logAlcohol({
    required DateTime date,
    required DrinkType type,
    required double quantity,
    required int volumeMl,
    required double abvPct,
    String? note,
  });

  Future<void> deleteAlcohol(String id);
}

abstract interface class SummaryRepository {
  DailySummary daily(DateTime date);
  List<HistoryDay> history({required DateTime from, required DateTime to});
  ProgressSummary progress({required DateTime from, required DateTime to});
  bool isRestDay(DateTime date);
  bool isSickDay(DateTime date);
  Future<void> setRestDay(DateTime date, bool isRest);

  /// Días con al menos un registro, para la densidad del selector de fecha.
  Set<String> get daysWithRecords;

  /// El primer día del que hay algo cargado. `null` si no hay nada.
  ///
  /// Es "desde cuándo usás la app", y sirve para no dividir por días que
  /// todavía no existían: alguien que empezó hace dos semanas registró 16 de
  /// 16 días, no 16 de 30, y decirle lo segundo es contarle como huecos los
  /// días en que no tenía la app.
  DateTime? get trackingSince;
}

abstract interface class HealthRepository {
  HealthIntegration get integration;

  /// Solo se muestra en Android (D-21).
  bool get isPlatformSupported;
  Future<void> connect();
  Future<void> disconnect();
  Future<HealthSyncResult> sync();
  Future<void> deleteImported();
  Future<void> resolveDuplicate(
    DuplicateCandidate candidate,
    DuplicateResolution resolution,
  );
  List<DuplicateCandidate> get pendingReviews;
}

abstract interface class AiPhotoRepository {
  /// Cuota diaria de análisis (D-18).
  int get quotaLimit;
  int get quotaUsed;
  /// [onStage] avisa en qué paso real va el circuito, para que la pantalla de
  /// espera muestre lo que está pasando y no una animación decorativa.
  ///
  /// [onUploaded] entrega la ruta del bucket **apenas la foto sube**, antes de
  /// que el modelo conteste. Existe porque analizar sube la foto con un id al
  /// azar, y si después el análisis falla o alguien cancela, esa copia queda en
  /// el bucket sin que ninguna comida la nombre: invisible, imborrable y
  /// pagando espacio para siempre. Con la ruta en la mano, la pantalla la puede
  /// borrar al salir.
  /// [description] es la aclaración opcional que escribió la persona sobre la
  /// foto. Una imagen no dice de qué es el relleno de una empanada ni si el
  /// pollo está frito o hervido: eso lo sabe quien comió, y cuando lo cuenta la
  /// estimación deja de ser una adivinanza. Vacía o nula, el análisis es el de
  /// siempre.
  Future<AiAnalysis> analyze({
    required String photoPath,
    String? description,
    void Function(AnalysisStage stage)? onStage,
    void Function(String remotePath)? onUploaded,
  });

  /// Estima una comida a partir de una descripción escrita. Comparte la cuota
  /// diaria con el análisis por foto: las dos gastan lo mismo del proveedor.
  Future<AiAnalysis> analyzeText({required String description});

  /// Vuelve a estimar una comida **que ya existe**, con lo que tiene cargado
  /// más una corrección escrita.
  ///
  /// Es lo que faltaba para poder corregir sin empezar de nuevo: cambiar un
  /// peso mal estimado obligaba a sacar la foto otra vez y rehacer la comida
  /// entera. [items] es lo que hay hoy, [instruction] lo que la persona quiere
  /// cambiar ("le falta el pan", "la milanesa pesaba 200 g"), y [photoPath] la
  /// foto de la comida —la que ya tenía o una nueva—. Sin foto se estima solo
  /// con la lista y la corrección.
  ///
  /// Devuelve la comida **completa** ya corregida: lo que la corrección no
  /// toca vuelve igual. Comparte la misma cuota diaria.
  Future<AiAnalysis> recalculate({
    required List<MealItem> items,
    required String instruction,
    String? photoPath,
    void Function(AnalysisStage stage)? onStage,
    void Function(String remotePath)? onUploaded,
  });

  /// Tres comidas que entran en las calorías que quedan del día.
  ///
  /// Al revés que las otras dos: acá el modelo **propone** en vez de reconocer.
  /// Lo que no cambia es la regla — ninguna opción puede pasarse del
  /// presupuesto, y eso se comprueba sumando de este lado además del servidor.
  /// Comparte la misma cuota diaria que las estimaciones.
  ///
  /// Devuelve la lista vacía solo si ninguna opción cerró; los fallos de verdad
  /// llegan como [AppError].
  Future<List<MealSuggestion>> suggestMeals({
    required int remainingKcal,
    MealSlot? slot,
    int? remainingProteinG,
  });

  /// Si hay a quién preguntarle. Sin servidor no hay Edge Function, y ofrecer
  /// un botón que siempre falla es peor que no ofrecerlo.
  bool get canProposeCalorieTarget;

  /// Le pide a la IA un objetivo calórico para el perfil cargado, con su
  /// explicación (S-05).
  ///
  /// Es una **propuesta**, no un resultado: se muestra al lado del número de la
  /// fórmula y no reemplaza nada hasta que la persona la acepta. Lo que
  /// devuelve ya viene acotado por el servidor contra el gasto que él mismo
  /// recalcula — nunca por debajo del mínimo de RN-12 ni fuera de la banda que
  /// permite ese gasto—, así que acá no hace falta volver a topearlo.
  ///
  /// Comparte la cuota diaria con las estimaciones y las sugerencias.
  Future<AiCalorieTarget> proposeCalorieTarget({
    required double weightKg,
    required GoalType goalType,
    required int formulaTarget,
  });
}

/// Qué trajo un archivo de respaldo, para poder contarlo antes y después.
class BackupSummary {
  const BackupSummary({
    required this.meals,
    required this.activities,
    required this.weights,
    required this.measurements,
  });

  final int meals;
  final int activities;
  final int weights;
  final int measurements;

  String get description =>
      '$meals ${meals == 1 ? 'comida' : 'comidas'}, '
      '$activities ${activities == 1 ? 'actividad' : 'actividades'}, '
      '$weights ${weights == 1 ? 'peso' : 'pesos'} y '
      '$measurements ${measurements == 1 ? 'medida' : 'medidas'}';
}

/// Respaldo manual mientras no exista la nube (Supabase).
///
/// Es la única red de seguridad hoy: sin esto, perder el teléfono es perder
/// todo el historial.
abstract interface class BackupRepository {
  /// Hay algo que perder: comidas, actividades, peso, medidas, agua o sueño.
  ///
  /// El perfil y el objetivo por defecto no cuentan — los crea el propio
  /// inicio de sesión, así que un teléfono recién instalado los tiene igual.
  bool get hasUserData;

  /// Cómo salió la última lectura del documento guardado en el teléfono.
  RestoreOutcome get lastRestore;

  /// El documento que no se pudo leer, apartado antes de escribir encima.
  String? get quarantinedDocument;

  /// Documento JSON con todo lo del usuario.
  String exportJson();

  /// Lee un respaldo **sin aplicarlo**, para poder mostrar qué contiene antes
  /// de reemplazar lo que hay.
  BackupSummary inspectBackup(String json);

  /// Reemplaza el contenido local por el del respaldo.
  Future<BackupSummary> importJson(String json);

  /// Aplica un documento ya armado. Lo usa la lectura desde las tablas, que
  /// devuelve la misma forma que el documento del respaldo.
  Future<void> importDocument(Map<String, dynamic> document);
}

abstract interface class ConnectivityRepository {
  /// ⚠️ Hoy siempre `false`: no hay detección real de conectividad. Es el
  /// punto donde enchufarla — ver la nota en `LocalRepository`.
  bool get isOffline;
  int get pendingCount;
  // `setOffline` se sacó junto con el interruptor de simulación: nadie podía
  // llamarlo y dejaba la puerta abierta a que alguien "simulara" sin conexión
  // en producción, con las escrituras quedando en pendiente sin explicación.

  /// Vacía la cola: todo lo pendiente pasa a sincronizado.
  Future<void> flushQueue();
}
