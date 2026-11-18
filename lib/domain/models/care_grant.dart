import '../enums/enums.dart';

/// Un permiso vigente sobre los datos propios, dado a un profesional.
///
/// Es lo que ve el dueño en su pantalla: a quién le dio acceso, a qué, y hasta
/// cuándo. Del otro lado —el backoffice— la misma fila se lee al revés, como
/// "a quién puedo seguir".
///
/// No hay un `status` acá. La app solo lista lo vigente: un permiso revocado
/// no es una cosa que la persona tenga que administrar, es una que ya no
/// existe. El historial queda en la base para poder auditarlo, no para
/// mostrarlo.
class CareGrant {
  const CareGrant({
    required this.id,
    required this.professionalId,
    required this.displayName,
    required this.shareMeals,
    required this.sharePhotos,
    required this.shareBody,
    required this.shareWellbeing,
    this.expiresAt,
  });

  final String id;
  final String professionalId;

  /// Vacío si la vista no lo devuelve. La pantalla sabe mostrar un permiso sin
  /// nombre, y quedarse sin la lista entera por un nombre que falta sería peor.
  final String displayName;

  final bool shareMeals;
  final bool sharePhotos;
  final bool shareBody;
  final bool shareWellbeing;

  /// Sin fecha, el permiso dura hasta que se revoque.
  final DateTime? expiresAt;

  static CareGrant fromRow(
    Map<String, dynamic> row, {
    required String displayName,
  }) => CareGrant(
    id: row['id'] as String,
    professionalId: row['professional_id'] as String,
    displayName: displayName,
    shareMeals: row['share_meals'] as bool? ?? false,
    sharePhotos: row['share_photos'] as bool? ?? false,
    shareBody: row['share_body'] as bool? ?? false,
    shareWellbeing: row['share_wellbeing'] as bool? ?? false,
    expiresAt: row['expires_at'] == null
        ? null
        : DateTime.tryParse(row['expires_at'] as String)?.toLocal(),
  );
}

/// Una invitación de una nutricionista a sumarse (migración 56): la manda
/// desde su panel con tu mail, y vos la aceptás o la rechazás. Hasta que la
/// aceptás no ve nada.
class CareInvite {
  const CareInvite({
    required this.id,
    required this.professionalName,
    this.orgName,
    this.intake,
  });

  final String id;

  /// Vacío si el perfil no tiene nombre: la pantalla dice "Una nutricionista".
  final String professionalName;

  /// El consultorio, si es parte de uno.
  final String? orgName;

  /// Los datos que cargó la nutricionista en la primera consulta (migración
  /// 60), o `null` si la invitación salió sin datos.
  final CareInviteIntake? intake;

  static CareInvite? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is! String || id.isEmpty) return null;
    final org = row['org_name'];
    final intake = row['intake'];
    return CareInvite(
      id: id,
      professionalName: (row['professional_name'] as String?)?.trim() ?? '',
      orgName: org is String && org.trim().isNotEmpty ? org.trim() : null,
      intake: intake is Map<String, dynamic>
          ? CareInviteIntake.fromJson(intake)
          : null,
    );
  }
}

/// Lo que la nutricionista cargó para proponerlo en el onboarding: los mismos
/// datos que esa pantalla pide. **No se aplica solo**: la app lo usa como
/// punto de partida y la persona lo revisa y lo confirma paso por paso.
///
/// La anamnesis clínica no viaja nunca hasta acá: queda en el panel.
///
/// Cada campo es opcional y un valor que la app no reconoce se descarta en vez
/// de reemplazarse por un default: proponer "Moderado" porque llegó una
/// palabra rara sería inventar un dato con la firma de la profesional.
class CareInviteIntake {
  const CareInviteIntake({
    this.sex,
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.goalType,
    this.calorieTarget,
    this.dietaryFlags = const <DietaryFlag>[],
  });

  final BiologicalSex? sex;
  final DateTime? birthDate;
  final double? heightCm;
  final double? weightKg;
  final ActivityLevel? activityLevel;
  final GoalType? goalType;
  final int? calorieTarget;
  final List<DietaryFlag> dietaryFlags;

  /// Sin ningún dato útil: se trata como una invitación común.
  bool get isEmpty =>
      sex == null &&
      birthDate == null &&
      heightCm == null &&
      weightKg == null &&
      activityLevel == null &&
      goalType == null &&
      calorieTarget == null &&
      dietaryFlags.isEmpty;

  static T? _enum<T extends Enum>(
    List<T> values,
    String Function(T) wire,
    Object? raw,
  ) {
    if (raw is! String) return null;
    for (final v in values) {
      if (wire(v) == raw) return v;
    }
    return null;
  }

  static double? _num(Object? raw) => raw is num ? raw.toDouble() : null;

  factory CareInviteIntake.fromJson(Map<String, dynamic> j) {
    final birth = j['birth_date'];
    final kcal = j['calorie_target'];
    final flags = j['dietary_flags'];
    return CareInviteIntake(
      sex: _enum(BiologicalSex.values, (e) => e.wire, j['sex']),
      birthDate: birth is String ? DateTime.tryParse(birth) : null,
      heightCm: _num(j['height_cm']),
      weightKg: _num(j['weight_kg']),
      activityLevel: _enum(
        ActivityLevel.values,
        (e) => e.wire,
        j['activity_level'],
      ),
      goalType: _enum(GoalType.values, (e) => e.wire, j['goal_type']),
      calorieTarget: kcal is num ? kcal.round() : null,
      dietaryFlags: flags is List
          ? DietaryFlag.fromWires(flags)
          : const <DietaryFlag>[],
    );
  }
}
