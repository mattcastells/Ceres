import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Tipo de actividad del catálogo. Los valores MET viven en la base, no en el
/// código (D-06): este modelo es el espejo local de `activity_types`.
class ActivityType {
  const ActivityType({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.category,
    required this.defaultMet,
    required this.iconName,
    this.lightMet,
    this.moderateMet,
    this.vigorousMet,
    this.supportsDistance = false,
    this.supportsSteps = false,
    this.supportsHeartRate = false,
    this.isSystem = true,
    this.userId,
  });

  final String id;
  final String slug;
  final String displayName;
  final ActivityCategory category;
  final double defaultMet;
  final double? lightMet;
  final double? moderateMet;
  final double? vigorousMet;
  final bool supportsDistance;
  final bool supportsSteps;
  final bool supportsHeartRate;

  /// Nombre del ícono Phosphor.
  final String iconName;
  final bool isSystem;
  final String? userId;

  /// `met = tipo[intensidad + '_met'] ?? tipo.default_met` (§9).
  double metFor(Intensity intensity) => switch (intensity) {
    Intensity.light => lightMet ?? defaultMet,
    Intensity.moderate => moderateMet ?? defaultMet,
    Intensity.vigorous => vigorousMet ?? defaultMet,
  };

  /// Si el tipo no define MET por intensidad, la UI lo aclara (§9).
  bool get hasPerIntensityMet =>
      lightMet != null && moderateMet != null && vigorousMet != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'slug': slug,
    'displayName': displayName,
    'category': category.wire,
    'defaultMet': defaultMet,
    'lightMet': lightMet,
    'moderateMet': moderateMet,
    'vigorousMet': vigorousMet,
    'supportsDistance': supportsDistance,
    'supportsSteps': supportsSteps,
    'supportsHeartRate': supportsHeartRate,
    'iconName': iconName,
    'isSystem': isSystem,
    'userId': userId,
  };

  static ActivityType fromJson(Map<String, dynamic> j) => ActivityType(
    id: j['id'] as String? ?? j['slug'] as String,
    slug: j['slug'] as String,
    displayName: j['displayName'] as String? ?? j['display_name'] as String,
    category: ActivityCategory.fromWire(j['category'] as String),
    // El seed viene en `snake_case` (met-catalog.json) y lo persistido en
    // `camelCase`: se aceptan las dos formas.
    defaultMet: ((j['defaultMet'] ?? j['default_met']) as num).toDouble(),
    lightMet: ((j['lightMet'] ?? j['light_met']) as num?)?.toDouble(),
    moderateMet: ((j['moderateMet'] ?? j['moderate_met']) as num?)?.toDouble(),
    vigorousMet: ((j['vigorousMet'] ?? j['vigorous_met']) as num?)?.toDouble(),
    supportsDistance:
        (j['supportsDistance'] ?? j['supports_distance'] ?? false) as bool,
    supportsSteps: (j['supportsSteps'] ?? j['supports_steps'] ?? false) as bool,
    supportsHeartRate:
        (j['supportsHeartRate'] ?? j['supports_heart_rate'] ?? false) as bool,
    iconName: (j['iconName'] ?? j['icon_name'] ?? 'DotsThreeCircle') as String,
    isSystem: (j['isSystem'] ?? j['is_system'] ?? true) as bool,
    userId: j['userId'] as String?,
  );
}

/// Una sesión de actividad registrada (10-types §Activity).
class Activity {
  const Activity({
    required this.id,
    required this.activityTypeId,
    required this.startedAt,
    required this.localDate,
    required this.durationMinutes,
    required this.intensity,
    required this.estimatedCalories,
    required this.appliedCalories,
    required this.exerciseCreditPercentage,
    required this.estimationMethod,
    required this.sourceType,
    required this.createdAt,
    required this.updatedAt,
    this.activityType,
    this.customName,
    this.endedAt,
    this.distanceMeters,
    this.steps,
    this.averageHeartRate,
    this.maximumHeartRate,
    this.originalCalories,
    this.metValue,
    this.weightKgUsed,
    this.overrideReason,
    this.externalSource,
    this.externalId,
    this.sourceUpdatedAt,
    this.userEdited = false,
    this.notes,
    this.photoPath,
    this.deviceName,
    this.isFavorite = false,
    this.syncStatus = SyncStatus.synced,
    this.deletedAt,
  });

  final String id;
  final String activityTypeId;

  /// Hidratado en lectura.
  final ActivityType? activityType;
  final String? customName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime localDate;
  final int durationMinutes;
  final Intensity intensity;
  final int? distanceMeters;
  final int? steps;
  final int? averageHeartRate;
  final int? maximumHeartRate;

  /// Valor vigente; puede ser el corregido por la persona. Siempre se muestra
  /// con "≈" (RN-03).
  final int estimatedCalories;

  /// Valor calculado antes de un override. Nunca se pierde (RN-04).
  final int? originalCalories;

  /// Lo que efectivamente suma al objetivo del día (RN-02).
  final int appliedCalories;

  /// Porcentaje congelado al momento de guardar (D-05).
  final int exerciseCreditPercentage;
  final EstimationMethod estimationMethod;
  final double? metValue;
  final double? weightKgUsed;
  final String? overrideReason;
  final ActivitySourceType sourceType;
  final String? externalSource;
  final String? externalId;
  final DateTime? sourceUpdatedAt;
  final bool userEdited;
  final String? notes;
  final String? photoPath;
  final String? deviceName;
  final bool isFavorite;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  String get displayName =>
      customName ?? activityType?.displayName ?? 'Actividad';

  bool get isDeleted => deletedAt != null;

  bool get wasOverridden => estimationMethod == EstimationMethod.userOverride;

  DataOrigin get origin => switch (sourceType) {
    ActivitySourceType.imported => DataOrigin.imported,
    _ => DataOrigin.manual,
  };

  Activity copyWith({
    String? activityTypeId,
    ActivityType? activityType,
    String? customName,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? localDate,
    int? durationMinutes,
    Intensity? intensity,
    int? distanceMeters,
    int? steps,
    int? averageHeartRate,
    int? maximumHeartRate,
    int? estimatedCalories,
    int? originalCalories,
    int? appliedCalories,
    int? exerciseCreditPercentage,
    EstimationMethod? estimationMethod,
    double? metValue,
    double? weightKgUsed,
    String? overrideReason,
    ActivitySourceType? sourceType,
    bool? userEdited,
    String? notes,
    String? photoPath,
    bool? isFavorite,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool clearOverride = false,
  }) => Activity(
    id: id,
    activityTypeId: activityTypeId ?? this.activityTypeId,
    activityType: activityType ?? this.activityType,
    customName: customName ?? this.customName,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    localDate: localDate ?? this.localDate,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    intensity: intensity ?? this.intensity,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    steps: steps ?? this.steps,
    averageHeartRate: averageHeartRate ?? this.averageHeartRate,
    maximumHeartRate: maximumHeartRate ?? this.maximumHeartRate,
    estimatedCalories: estimatedCalories ?? this.estimatedCalories,
    originalCalories: clearOverride
        ? null
        : (originalCalories ?? this.originalCalories),
    appliedCalories: appliedCalories ?? this.appliedCalories,
    exerciseCreditPercentage:
        exerciseCreditPercentage ?? this.exerciseCreditPercentage,
    estimationMethod: estimationMethod ?? this.estimationMethod,
    metValue: metValue ?? this.metValue,
    weightKgUsed: weightKgUsed ?? this.weightKgUsed,
    overrideReason: clearOverride
        ? null
        : (overrideReason ?? this.overrideReason),
    sourceType: sourceType ?? this.sourceType,
    externalSource: externalSource,
    externalId: externalId,
    sourceUpdatedAt: sourceUpdatedAt,
    userEdited: userEdited ?? this.userEdited,
    notes: notes ?? this.notes,
    photoPath: photoPath ?? this.photoPath,
    deviceName: deviceName,
    isFavorite: isFavorite ?? this.isFavorite,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'activityTypeId': activityTypeId,
    'customName': customName,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'localDate': isoDate(localDate),
    'durationMinutes': durationMinutes,
    'intensity': intensity.wire,
    'distanceMeters': distanceMeters,
    'steps': steps,
    'averageHeartRate': averageHeartRate,
    'maximumHeartRate': maximumHeartRate,
    'estimatedCalories': estimatedCalories,
    'originalCalories': originalCalories,
    'appliedCalories': appliedCalories,
    'exerciseCreditPercentage': exerciseCreditPercentage,
    'estimationMethod': estimationMethod.wire,
    'metValue': metValue,
    'weightKgUsed': weightKgUsed,
    'overrideReason': overrideReason,
    'sourceType': sourceType.wire,
    'externalSource': externalSource,
    'externalId': externalId,
    'sourceUpdatedAt': sourceUpdatedAt?.toIso8601String(),
    'userEdited': userEdited,
    'notes': notes,
    'photoPath': photoPath,
    'deviceName': deviceName,
    'isFavorite': isFavorite,
    'syncStatus': syncStatus.wire,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static Activity fromJson(Map<String, dynamic> j) => Activity(
    id: j['id'] as String,
    activityTypeId: j['activityTypeId'] as String,
    customName: j['customName'] as String?,
    startedAt: DateTime.parse(j['startedAt'] as String),
    endedAt: j['endedAt'] == null
        ? null
        : DateTime.parse(j['endedAt'] as String),
    localDate: DateTime.parse(j['localDate'] as String),
    durationMinutes: j['durationMinutes'] as int,
    intensity: Intensity.fromWire(j['intensity'] as String),
    distanceMeters: j['distanceMeters'] as int?,
    steps: j['steps'] as int?,
    averageHeartRate: j['averageHeartRate'] as int?,
    maximumHeartRate: j['maximumHeartRate'] as int?,
    estimatedCalories: j['estimatedCalories'] as int,
    originalCalories: j['originalCalories'] as int?,
    appliedCalories: j['appliedCalories'] as int,
    exerciseCreditPercentage: j['exerciseCreditPercentage'] as int,
    estimationMethod: EstimationMethod.fromWire(
      j['estimationMethod'] as String,
    ),
    metValue: (j['metValue'] as num?)?.toDouble(),
    weightKgUsed: (j['weightKgUsed'] as num?)?.toDouble(),
    overrideReason: j['overrideReason'] as String?,
    sourceType: ActivitySourceType.values.firstWhere(
      (e) => e.wire == j['sourceType'],
      orElse: () => ActivitySourceType.manual,
    ),
    externalSource: j['externalSource'] as String?,
    externalId: j['externalId'] as String?,
    sourceUpdatedAt: j['sourceUpdatedAt'] == null
        ? null
        : DateTime.parse(j['sourceUpdatedAt'] as String),
    userEdited: j['userEdited'] as bool? ?? false,
    notes: j['notes'] as String?,
    photoPath: j['photoPath'] as String?,
    deviceName: j['deviceName'] as String?,
    isFavorite: j['isFavorite'] as bool? ?? false,
    syncStatus: SyncStatus.values.firstWhere(
      (e) => e.wire == j['syncStatus'],
      orElse: () => SyncStatus.synced,
    ),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    deletedAt: j['deletedAt'] == null
        ? null
        : DateTime.parse(j['deletedAt'] as String),
  );
}

/// Plantilla de ejercicio reutilizable (S-34).
class ExerciseTemplate {
  const ExerciseTemplate({
    required this.id,
    required this.name,
    required this.activityTypeId,
    required this.defaultDurationMinutes,
    required this.defaultIntensity,
    this.defaultDistanceMeters,
    this.defaultNotes,
    this.useCount = 0,
  });

  final String id;
  final String name;
  final String activityTypeId;
  final int defaultDurationMinutes;
  final Intensity defaultIntensity;
  final int? defaultDistanceMeters;
  final String? defaultNotes;
  final int useCount;

  ExerciseTemplate copyWith({int? useCount}) => ExerciseTemplate(
    id: id,
    name: name,
    activityTypeId: activityTypeId,
    defaultDurationMinutes: defaultDurationMinutes,
    defaultIntensity: defaultIntensity,
    defaultDistanceMeters: defaultDistanceMeters,
    defaultNotes: defaultNotes,
    useCount: useCount ?? this.useCount,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'activityTypeId': activityTypeId,
    'defaultDurationMinutes': defaultDurationMinutes,
    'defaultIntensity': defaultIntensity.wire,
    'defaultDistanceMeters': defaultDistanceMeters,
    'defaultNotes': defaultNotes,
    'useCount': useCount,
  };

  static ExerciseTemplate fromJson(Map<String, dynamic> j) => ExerciseTemplate(
    id: j['id'] as String,
    name: j['name'] as String,
    activityTypeId: j['activityTypeId'] as String,
    defaultDurationMinutes: j['defaultDurationMinutes'] as int,
    defaultIntensity: Intensity.fromWire(j['defaultIntensity'] as String),
    defaultDistanceMeters: j['defaultDistanceMeters'] as int?,
    defaultNotes: j['defaultNotes'] as String?,
    useCount: j['useCount'] as int? ?? 0,
  );
}

/// Objetivo de actividad. Opcional y nunca reduce el objetivo calórico (RN-09).
class ActivityGoal {
  const ActivityGoal({
    required this.id,
    required this.goalType,
    required this.targetValue,
    required this.period,
    required this.startDate,
    this.endDate,
    this.enabled = true,
  });

  final String id;
  final ActivityGoalType goalType;
  final int targetValue;
  final GoalPeriod period;
  final DateTime startDate;
  final DateTime? endDate;
  final bool enabled;

  ActivityGoal copyWith({
    ActivityGoalType? goalType,
    int? targetValue,
    GoalPeriod? period,
    bool? enabled,
  }) => ActivityGoal(
    id: id,
    goalType: goalType ?? this.goalType,
    targetValue: targetValue ?? this.targetValue,
    period: period ?? this.period,
    startDate: startDate,
    endDate: endDate,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'goalType': goalType.wire,
    'targetValue': targetValue,
    'period': period.wire,
    'startDate': isoDate(startDate),
    'endDate': endDate == null ? null : isoDate(endDate!),
    'enabled': enabled,
  };

  static ActivityGoal fromJson(Map<String, dynamic> j) => ActivityGoal(
    id: j['id'] as String,
    goalType: ActivityGoalType.values.firstWhere(
      (e) => e.wire == j['goalType'],
      orElse: () => ActivityGoalType.activeMinutes,
    ),
    targetValue: j['targetValue'] as int,
    period: GoalPeriod.values.firstWhere(
      (e) => e.wire == j['period'],
      orElse: () => GoalPeriod.week,
    ),
    startDate: DateTime.parse(j['startDate'] as String),
    endDate: j['endDate'] == null
        ? null
        : DateTime.parse(j['endDate'] as String),
    enabled: j['enabled'] as bool? ?? true,
  );
}
