import '../../core/utils/formats.dart';
import '../calculations/calorie_target.dart';
import '../calculations/macros.dart';
import '../enums/enums.dart';
import 'goal.dart';

/// Lo que la nutricionista le escribe a la persona desde el panel.
///
/// Dos clases, con vidas distintas:
///
/// - [CareFeedbackKind.feedback]: una devolución sobre un día, una comida o la
///   semana. Se lee y queda en la lista.
/// - [CareFeedbackKind.indication]: una indicación que **sigue vigente**
///   ("sumá proteína en el desayuno") mientras ella no la saque. Por eso se
///   muestra en Inicio aunque ya se haya leído.
///
/// La app solo recibe lo publicado y no borrado: un borrador es de quien lo
/// escribe, y eso lo decide RLS, no un filtro de acá.
enum CareFeedbackKind {
  feedback('feedback'),
  indication('indication');

  const CareFeedbackKind(this.wire);

  final String wire;

  /// Un tipo que esta versión no conoce se lee como devolución: es la clase
  /// que se lee y se archiva sola, así que un texto nuevo no queda clavado en
  /// Inicio para siempre.
  static CareFeedbackKind fromWire(Object? raw) =>
      raw == 'indication' ? indication : feedback;
}

class CareFeedback {
  const CareFeedback({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.body,
    required this.publishedAt,
    this.localDate,
    this.readAt,
    this.target,
    this.appliedAt,
  });

  final String id;
  final String authorId;

  /// Vacío si la vista de nombres no lo devolvió. La pantalla sabe mostrar
  /// una devolución sin firma: perderla entera por el nombre sería peor.
  final String authorName;

  final CareFeedbackKind kind;
  final String body;
  final DateTime publishedAt;

  /// El día del que habla, si habla de uno. Sin fecha es sobre el seguimiento
  /// en general.
  final DateTime? localDate;
  final DateTime? readAt;

  /// Los números de un objetivo recomendado (migración 53). Solo una
  /// indicación puede traerlos.
  final CareTarget? target;

  /// Cuándo la persona aplicó [target]. Lo pone `mark_care_target_applied`.
  final DateTime? appliedAt;

  bool get isUnread => readAt == null;
  bool get isIndication => kind == CareFeedbackKind.indication;
  bool get isTarget => target != null;
  bool get isApplied => appliedAt != null;

  /// El texto sin la primera línea de números que arma el panel: los números
  /// ya se muestran aparte.
  String get note => target == null ? body : CareTarget.noteOf(body);

  CareFeedback markedRead(DateTime at) => CareFeedback(
    id: id,
    authorId: authorId,
    authorName: authorName,
    kind: kind,
    body: body,
    publishedAt: publishedAt,
    localDate: localDate,
    readAt: readAt ?? at,
    target: target,
    appliedAt: appliedAt,
  );

  /// Como queda después de aplicarla: aplicar implica haberla leído, igual
  /// que en `mark_care_target_applied`.
  CareFeedback markedApplied(DateTime at) => CareFeedback(
    id: id,
    authorId: authorId,
    authorName: authorName,
    kind: kind,
    body: body,
    publishedAt: publishedAt,
    localDate: localDate,
    readAt: readAt ?? at,
    target: target,
    appliedAt: appliedAt ?? at,
  );

  /// Lee una fila de `care_feedback`, o devuelve `null` si no cierra.
  ///
  /// Una fila rota se descarta y no tumba la lista: la forma la decide el
  /// servidor y acá se la trata como entrada. Un `as String` sobre un campo
  /// que no vino lanza un `TypeError`, que no es una `Exception` y se escapa
  /// de los `catch` de quien llama.
  static CareFeedback? fromRow(
    Map<String, dynamic> row, {
    String authorName = '',
  }) {
    final id = row['id'];
    final authorId = row['author_id'];
    final body = row['body'];
    final published = _parseInstant(row['published_at']);
    if (id is! String || id.isEmpty) return null;
    if (body is! String || body.trim().isEmpty) return null;
    if (published == null) return null;

    final rawDate = row['local_date'];
    final localDate = rawDate is String ? DateTime.tryParse(rawDate) : null;
    final kind = CareFeedbackKind.fromWire(row['kind']);
    final target = kind == CareFeedbackKind.indication
        ? CareTarget.fromRow(row)
        : null;

    return CareFeedback(
      id: id,
      authorId: authorId is String ? authorId : '',
      authorName: authorName,
      kind: kind,
      body: body.trim(),
      publishedAt: published,
      localDate: localDate == null
          ? null
          : DateTime(localDate.year, localDate.month, localDate.day),
      readAt: _parseInstant(row['read_at']),
      target: target,
      appliedAt: target == null ? null : _parseInstant(row['applied_at']),
    );
  }

  static DateTime? _parseInstant(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}

/// El objetivo recomendado: calorías y, si vienen, macros (migración 53).
///
/// La profesional no escribe en `goals` —el objetivo es del paciente—: publica
/// una indicación con estos números y la persona la aplica desde la app.
class CareTarget {
  const CareTarget({
    required this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  final int kcal;

  /// En `null`, la app reparte ese macro como siempre.
  final int? proteinG;
  final int? carbsG;
  final int? fatG;

  /// La primera línea que escribe el panel (`PREFIJO` en
  /// `backoffice/lib/objetivo.ts`).
  static const String bodyPrefix = 'Objetivo recomendado:';

  bool get hasAllMacros => proteinG != null && carbsG != null && fatG != null;

  /// Lee los números de una fila, o `null` si no hay un objetivo que se pueda
  /// guardar. Los topes son los de `goals`: un número fuera de rango lo
  /// rechazaría la base al subirlo, así que no se ofrece aplicarlo.
  static CareTarget? fromRow(Map<String, dynamic> row) {
    final kcal = _int(row['target_kcal']);
    if (kcal == null ||
        kcal < CalorieTargetRules.absoluteMin ||
        kcal > CalorieTargetRules.absoluteMax) {
      return null;
    }
    return CareTarget(
      kcal: kcal,
      proteinG: _inRange(_int(row['target_protein_g']), 500),
      carbsG: _inRange(_int(row['target_carbs_g']), 1000),
      fatG: _inRange(_int(row['target_fat_g']), 400),
    );
  }

  /// "1.800 kcal · P 120 g · C 180 g · G 60 g". Sin los macros que no vienen.
  String get compact => <String>[
    Fmt.kcal(kcal),
    if (proteinG != null) 'P ${Fmt.grams(proteinG!)}',
    if (carbsG != null) 'C ${Fmt.grams(carbsG!)}',
    if (fatG != null) 'G ${Fmt.grams(fatG!)}',
  ].join(' · ');

  /// Si aplicarlo cambiaría algo. Un macro que no vino no cuenta: la app lo
  /// recalcula, así que no hay un número de la profesional con qué comparar.
  bool differsFrom(Goal? goal) {
    if (goal == null) return true;
    return kcal != goal.baseCalorieTarget ||
        (proteinG != null && proteinG != goal.proteinG) ||
        (carbsG != null && carbsG != goal.carbsG) ||
        (fatG != null && fatG != goal.fatG);
  }

  /// El objetivo que se guarda al aplicarlo: el vigente con estos números.
  ///
  /// Conserva el tipo, el ritmo y el peso meta —la profesional fija cuánto
  /// comer, no hacia dónde va la persona—. Los macros que no vienen se
  /// reparten con la regla de siempre para las calorías nuevas. El método es
  /// `manual`: la base no acepta otro valor sin una migración, y de dónde
  /// salió el número ya lo dice la indicación.
  Goal toGoal({
    required Goal? current,
    required double weightKg,
    required String id,
    required DateTime startsOn,
  }) {
    final goalType = current?.goalType ?? GoalType.maintain;
    final split = macroTargets(
      targetKcal: kcal,
      weightKg: weightKg > 0 ? weightKg : 70,
      goalType: goalType,
    );
    return Goal(
      id: id,
      goalType: goalType,
      rateKgPerWeek: current?.rateKgPerWeek ?? 0,
      targetWeightKg: current?.targetWeightKg,
      baseCalorieTarget: kcal,
      targetMethod: TargetMethod.manual,
      bmrKcal: current?.bmrKcal,
      tdeeKcal: current?.tdeeKcal,
      proteinG: proteinG ?? split.proteinG,
      carbsG: carbsG ?? split.carbsG,
      fatG: fatG ?? split.fatG,
      macroMethod: hasAllMacros ? 'custom' : 'default',
      startsOn: startsOn,
    );
  }

  /// La nota de la profesional, sin la línea de números que arma el panel
  /// (`notaDe` en `backoffice/lib/objetivo.ts`). Si el texto no empieza con
  /// esa línea, se devuelve entero.
  static String noteOf(String body) {
    if (!body.startsWith(bodyPrefix)) return body.trim();
    final cut = body.indexOf('\n');
    return cut == -1 ? '' : body.substring(cut).trim();
  }

  static int? _int(Object? raw) => switch (raw) {
    final int v => v,
    final num v when v == v.roundToDouble() => v.toInt(),
    _ => null,
  };

  static int? _inRange(int? v, int max) =>
      v == null || v < 0 || v > max ? null : v;
}

/// Lo que va a la tarjeta de Inicio, sacado de la lista entera.
///
/// Es una regla de producto y por eso vive acá y no en el widget: la última
/// devolución **sin leer** y todas las indicaciones vigentes. Una devolución
/// ya leída no vuelve a Inicio —para eso está la lista—; una indicación sí,
/// porque sigue valiendo hasta que la profesional la saque.
class CareInbox {
  CareInbox(List<CareFeedback> all)
    : items = List<CareFeedback>.unmodifiable(
        <CareFeedback>[...all]
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );

  /// Todo, de lo más nuevo a lo más viejo.
  final List<CareFeedback> items;

  /// Las indicaciones de texto. El objetivo recomendado es una indicación,
  /// pero tiene su propio lugar: ver [target].
  List<CareFeedback> get indications =>
      items.where((f) => f.isIndication && !f.isTarget).toList();

  /// El objetivo recomendado vigente: la indicación publicada más reciente
  /// con números. Si quedara más de uno —el panel borra el anterior después
  /// de guardar el nuevo, y eso podría fallar—, manda el más nuevo.
  CareFeedback? get target {
    for (final f in items) {
      if (f.isTarget) return f;
    }
    return null;
  }

  List<CareFeedback> get unread => items.where((f) => f.isUnread).toList();

  /// La devolución sin leer más reciente. Las indicaciones no cuentan acá:
  /// ya tienen su propio lugar en la tarjeta.
  CareFeedback? get latestUnreadFeedback {
    for (final f in items) {
      if (!f.isIndication && f.isUnread) return f;
    }
    return null;
  }

  int get unreadCount => unread.length;

  /// Si la tarjeta de Inicio tiene algo que decir.
  bool get hasSomethingForHome =>
      latestUnreadFeedback != null || indications.isNotEmpty || target != null;
}
