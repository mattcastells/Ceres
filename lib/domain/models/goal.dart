import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Objetivo calórico vigente o histórico (10-types §Goal).
///
/// Cambiar el objetivo cierra la fila vigente (`endsOn = ayer`) e inserta una
/// nueva desde hoy: el historial conserva los objetivos viejos (F-13).
class Goal {
  const Goal({
    required this.id,
    required this.goalType,
    required this.rateKgPerWeek,
    required this.baseCalorieTarget,
    required this.targetMethod,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.macroMethod,
    required this.startsOn,
    this.targetWeightKg,
    this.bmrKcal,
    this.tdeeKcal,
    this.endsOn,
    this.updatedAt,
  });

  final String id;
  final GoalType goalType;
  final double rateKgPerWeek;
  final double? targetWeightKg;
  final int baseCalorieTarget;
  final TargetMethod targetMethod;
  final int? bmrKcal;
  final int? tdeeKcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final String macroMethod;
  final DateTime startsOn;

  /// `null` = vigente.
  final DateTime? endsOn;

  /// Lo que desempata en la reconciliación.
  ///
  /// Sin esto, los objetivos se unían por id y ante conflicto ganaba siempre el
  /// local. Con dos dispositivos eso significa que el que tiene abierto un
  /// objetivo viejo le gana al que ya lo cerró, y su push lo **des-cierra** en
  /// el servidor: quedan dos objetivos vigentes para hoy y `goalForDate`
  /// devuelve el primero de la lista, que puede ser el equivocado. Hoy no se
  /// nota porque hay un dispositivo por cuenta; la versión web lo activaría.
  ///
  /// Nulo en los documentos escritos antes de que existiera: la regla del merge
  /// ya cubre ese caso conservando lo local, que es el lado seguro.
  final DateTime? updatedAt;

  bool get isCurrent => endsOn == null;

  Goal copyWith({
    /// Solo lo usa `saveGoal` cuando el objetivo nuevo reemplaza a uno que
    /// empezó hoy: es la misma fila del servidor y tiene que conservar su id.
    /// Cambiar el id de un objetivo ya cerrado partiría el historial en dos.
    String? id,
    GoalType? goalType,
    double? rateKgPerWeek,
    double? targetWeightKg,
    int? baseCalorieTarget,
    TargetMethod? targetMethod,
    int? bmrKcal,
    int? tdeeKcal,
    int? proteinG,
    int? carbsG,
    int? fatG,
    String? macroMethod,
    DateTime? startsOn,
    DateTime? endsOn,
    DateTime? updatedAt,
  }) => Goal(
    id: id ?? this.id,
    goalType: goalType ?? this.goalType,
    rateKgPerWeek: rateKgPerWeek ?? this.rateKgPerWeek,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    baseCalorieTarget: baseCalorieTarget ?? this.baseCalorieTarget,
    targetMethod: targetMethod ?? this.targetMethod,
    bmrKcal: bmrKcal ?? this.bmrKcal,
    tdeeKcal: tdeeKcal ?? this.tdeeKcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    macroMethod: macroMethod ?? this.macroMethod,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
    // Cualquier cambio deja el objetivo más nuevo: es lo que hace que cerrarlo
    // en un dispositivo le gane al que todavía lo tiene abierto.
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'goalType': goalType.wire,
    'rateKgPerWeek': rateKgPerWeek,
    'targetWeightKg': targetWeightKg,
    'baseCalorieTarget': baseCalorieTarget,
    'targetMethod': targetMethod.wire,
    'bmrKcal': bmrKcal,
    'tdeeKcal': tdeeKcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'macroMethod': macroMethod,
    'startsOn': isoDate(startsOn),
    'endsOn': endsOn == null ? null : isoDate(endsOn!),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  static Goal fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String,
    goalType: GoalType.fromWire(j['goalType'] as String),
    rateKgPerWeek: (j['rateKgPerWeek'] as num).toDouble(),
    targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
    baseCalorieTarget: j['baseCalorieTarget'] as int,
    targetMethod: TargetMethod.values.firstWhere(
      (e) => e.wire == j['targetMethod'],
      orElse: () => TargetMethod.calculated,
    ),
    bmrKcal: j['bmrKcal'] as int?,
    tdeeKcal: j['tdeeKcal'] as int?,
    proteinG: j['proteinG'] as int,
    carbsG: j['carbsG'] as int,
    fatG: j['fatG'] as int,
    macroMethod: j['macroMethod'] as String,
    startsOn: DateTime.parse(j['startsOn'] as String),
    endsOn: j['endsOn'] == null
        ? null
        : DateTime.parse(j['endsOn'] as String),
    updatedAt: j['updatedAt'] == null
        ? null
        : DateTime.tryParse(j['updatedAt'] as String),
  );
}
