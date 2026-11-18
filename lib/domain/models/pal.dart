import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../enums/enums.dart';
import 'sleep.dart';

enum PalStatus {
  pending('pending'),
  accepted('accepted'),
  blocked('blocked');

  const PalStatus(this.wire);

  final String wire;

  static PalStatus fromWire(String? w) => PalStatus.values.firstWhere(
    (s) => s.wire == w,
    orElse: () => PalStatus.pending,
  );
}

/// Un vínculo con otra persona, visto desde quien mira.
class Pal {
  const Pal({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.isIncoming,
  });

  final String id;

  /// Id de la otra persona, no el propio.
  final String userId;

  /// Puede venir vacío: el nombre es opcional en el perfil.
  final String displayName;
  final PalStatus status;

  /// `true` cuando la solicitud la mandó la otra persona y falta responderla.
  final bool isIncoming;

  String get label => displayName.trim().isEmpty ? 'Sin nombre' : displayName;
}

/// Una comida tal como la ve un pal: cuándo, qué y cuánto. Sin los ítems.
///
/// [photoPath] solo viaja si quien comparte prendió "Fotos de mis comidas"
/// (`Profile.palSharePhotos`) — si no, siempre es `null`, aunque la comida
/// tenga foto en el teléfono de su dueño.
class PalMeal {
  const PalMeal({
    required this.slot,
    required this.name,
    required this.kcal,
    this.photoPath,
  });

  final MealSlot slot;
  final String name;
  final int kcal;
  final String? photoPath;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slot': slot.wire,
    'name': name,
    'kcal': kcal,
    if (photoPath != null) 'photoPath': photoPath,
  };

  static PalMeal fromJson(Map<String, dynamic> j) => PalMeal(
    slot: MealSlot.values.firstWhere(
      (s) => s.wire == j['slot'],
      orElse: () => MealSlot.snack,
    ),
    name: j['name'] as String? ?? '',
    kcal: (j['kcal'] as num?)?.toInt() ?? 0,
    photoPath: j['photoPath'] as String?,
  );
}

/// Una actividad tal como la ve un pal, cuando el detalle está prendido.
class PalActivity {
  const PalActivity({required this.name, required this.minutes, this.kcal});

  final String name;
  final int minutes;
  final int? kcal;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'minutes': minutes,
    'kcal': kcal,
  };

  static PalActivity fromJson(Map<String, dynamic> j) => PalActivity(
    name: j['name'] as String? ?? 'Actividad',
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    kcal: (j['kcal'] as num?)?.toInt(),
  );
}

/// El día de alguien, con lo único que se publica.
///
/// Cada categoría tiene contenido solo si el dueño la prendió; si no, queda
/// vacía o en `null`. La app lo arma así y la base lo vuelve a limpiar al
/// guardarlo (migración 54), así que un cliente viejo tampoco publica de más.
class PalDay {
  const PalDay({
    required this.userId,
    required this.date,
    required this.meals,
    required this.activityMinutes,
    required this.activityCount,
    this.activities = const <PalActivity>[],
    this.waterGlasses,
    this.sleepMinutes,
    this.sleepQuality,
    this.weightKg,
    this.weightDate,
    this.mealsShared = true,
    this.activityShared = true,
  });

  final String userId;
  final DateTime date;
  final List<PalMeal> meals;
  final int activityMinutes;
  final int activityCount;
  final List<PalActivity> activities;
  final int? waterGlasses;
  final int? sleepMinutes;
  final SleepQuality? sleepQuality;

  /// El último peso registrado hasta este día, y de qué día es.
  final double? weightKg;
  final DateTime? weightDate;

  /// Si esa persona comparte la comida y la actividad. Los pone la base
  /// (migración 54): distinguen "no comió nada" de "no lo comparte".
  final bool mealsShared;
  final bool activityShared;

  bool get isEmpty =>
      meals.isEmpty &&
      activityCount == 0 &&
      activities.isEmpty &&
      waterGlasses == null &&
      sleepMinutes == null &&
      weightKg == null;

  int get totalKcal => meals.fold(0, (acc, m) => acc + m.kcal);

  List<PalMeal> mealsIn(MealSlot slot) =>
      meals.where((m) => m.slot == slot).toList();

  /// Los topes que la tabla `shared_days` hace cumplir (migraciones 20 y 25).
  ///
  /// Están acá y no solo en Postgres porque del lado de la base un número
  /// fuera de rango no es un dato recortado: es un `insert` rechazado, y como
  /// [PalPublisher] se traga los errores a propósito —publicar el día es una
  /// comodidad social, no puede interrumpir el registro de una comida— el
  /// resultado era **que ese día dejaba de actualizarse para siempre** sin que
  /// nadie se enterara.
  ///
  /// Pasaba con cualquiera de los cuatro: tres actividades largas suman más de
  /// 1440 minutos, 41 vasos de agua existen, y `activity_count` corta en 50.
  /// El pal se quedaba viendo la última versión que sí había entrado —de ahí
  /// las "calorías de menos" y las comidas que no aparecían— y el dueño no
  /// tenía forma de saberlo.
  static const int maxActivityMinutes = 1440;
  static const int maxActivityCount = 50;
  static const int maxWaterGlasses = 40;
  static const int maxSleepMinutes = 1440;

  static int _clamp(int value, int max) => math.min(math.max(value, 0), max);

  /// El payload de esta fila de `shared_days`, sin `user_id` ni `updated_at`.
  ///
  /// Los pone quien publica. Que no estén acá es lo que permite comparar dos
  /// proyecciones para saber si hay algo nuevo que subir: con la marca de
  /// tiempo adentro, todas serían distintas siempre.
  Map<String, dynamic> toRow() => <String, dynamic>{
    'local_date': isoDate(date),
    'meals': meals.take(maxActivityCount).map((m) => m.toJson()).toList(),
    'activity_minutes': _clamp(activityMinutes, maxActivityMinutes),
    'activity_count': _clamp(activityCount, maxActivityCount),
    'activities': activities
        .take(maxActivityCount)
        .map((a) => a.toJson())
        .toList(),
    'water_glasses': waterGlasses == null
        ? null
        : _clamp(waterGlasses!, maxWaterGlasses),
    'sleep_minutes': sleepMinutes == null
        ? null
        : _clamp(sleepMinutes!, maxSleepMinutes),
    'sleep_quality': sleepQuality?.wire,
    'weight_kg': weightKg,
    'weight_date': weightDate == null ? null : isoDate(weightDate!),
  };

  static PalDay fromRow(Map<String, dynamic> row) => PalDay(
    userId: row['user_id'] as String,
    date: DateTime.parse(row['local_date'] as String),
    meals: (row['meals'] as List<dynamic>? ?? <dynamic>[])
        .map((raw) => PalMeal.fromJson(raw as Map<String, dynamic>))
        .toList(),
    activityMinutes: (row['activity_minutes'] as num?)?.toInt() ?? 0,
    activityCount: (row['activity_count'] as num?)?.toInt() ?? 0,
    activities: (row['activities'] as List<dynamic>? ?? <dynamic>[])
        .map((raw) => PalActivity.fromJson(raw as Map<String, dynamic>))
        .toList(),
    waterGlasses: (row['water_glasses'] as num?)?.toInt(),
    sleepMinutes: (row['sleep_minutes'] as num?)?.toInt(),
    sleepQuality: row['sleep_quality'] == null
        ? null
        : SleepQuality.fromWire(row['sleep_quality'] as String),
    weightKg: (row['weight_kg'] as num?)?.toDouble(),
    weightDate: row['weight_date'] == null
        ? null
        : DateTime.parse(row['weight_date'] as String),
    mealsShared: row['meals_shared'] as bool? ?? true,
    activityShared: row['activity_shared'] as bool? ?? true,
  );
}

/// Qué comparte esta cuenta con sus pals. Una columna `pal_share_*` de
/// `profiles` por interruptor.
///
/// Comida y actividad arrancan prendidas porque es lo que toda cuenta venía
/// compartiendo antes de que se pudieran apagar; el resto arranca apagado.
/// Fotos depende de comida y el detalle de actividad, de actividad: sin la
/// categoría no hay nada que mostrar con más detalle.
class PalSharingPrefs {
  const PalSharingPrefs({
    this.meals = true,
    this.photos = false,
    this.activity = true,
    this.activityDetail = false,
    this.water = false,
    this.sleep = false,
    this.weight = false,
  });

  final bool meals;
  final bool photos;
  final bool activity;
  final bool activityDetail;
  final bool water;
  final bool sleep;
  final bool weight;

  PalSharingPrefs copyWith({
    bool? meals,
    bool? photos,
    bool? activity,
    bool? activityDetail,
    bool? water,
    bool? sleep,
    bool? weight,
  }) => PalSharingPrefs(
    meals: meals ?? this.meals,
    photos: photos ?? this.photos,
    activity: activity ?? this.activity,
    activityDetail: activityDetail ?? this.activityDetail,
    water: water ?? this.water,
    sleep: sleep ?? this.sleep,
    weight: weight ?? this.weight,
  );

  static const List<String> columns = <String>[
    'pal_share_meals',
    'pal_share_photos',
    'pal_share_activity',
    'pal_share_activity_detail',
    'pal_share_water',
    'pal_share_sleep',
    'pal_share_weight',
  ];

  static PalSharingPrefs fromRow(Map<String, dynamic> row) => PalSharingPrefs(
    meals: row['pal_share_meals'] as bool? ?? true,
    photos: row['pal_share_photos'] as bool? ?? false,
    activity: row['pal_share_activity'] as bool? ?? true,
    activityDetail: row['pal_share_activity_detail'] as bool? ?? false,
    water: row['pal_share_water'] as bool? ?? false,
    sleep: row['pal_share_sleep'] as bool? ?? false,
    weight: row['pal_share_weight'] as bool? ?? false,
  );

  Map<String, dynamic> toRow() => <String, dynamic>{
    'pal_share_meals': meals,
    'pal_share_photos': photos,
    'pal_share_activity': activity,
    'pal_share_activity_detail': activityDetail,
    'pal_share_water': water,
    'pal_share_sleep': sleep,
    'pal_share_weight': weight,
  };
}
