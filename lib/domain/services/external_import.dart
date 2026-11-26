import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/utils/dates.dart';
import '../calculations/macros.dart';
import '../enums/enums.dart';
import '../models/food.dart';
import '../models/goal.dart';
import '../models/meal.dart';
import '../repositories/repositories.dart';

/// Traer el historial de alguien que viene de otra app.
///
/// La otra app no exporta nada, pero la persona casi siempre llevó sus datos
/// conversando con una IA (ChatGPT, Gemini, Claude). El camino es ese: Ceres
/// le da un pedido para copiar, la persona se lo pega a **su** IA —la que
/// tiene la conversación y la memoria—, y lo que vuelve es un bloque JSON que
/// se pega acá. Leer ese bloque no necesita otro modelo: es un formato fijo,
/// así que se interpreta en el teléfono, sin cuota y sin mandar el historial
/// a ningún servidor.
///
/// El formato es el mismo que circula como "GymSpot": se aceptan los dos
/// marcadores para que un bloque armado con aquel pedido también entre.
///
/// Lo que Ceres no sabe guardar —récords, rutina, suplementos— se cuenta en la
/// vista previa como "no se importa" en lugar de perderse en silencio.
///
/// Lo que falta se estima en vez de descartarse: la duración de un deporte o
/// de un cardio sale de lo habitual para ese tipo, los macros que faltan se
/// reparten de las calorías, las calorías salen de los macros y la fecha de
/// nacimiento, de la edad. Cada estimación queda dicha en la nota del
/// registro y contada en la vista previa. Lo único que no se inventa es la
/// fecha: un registro sin fecha no tiene día donde caer.

/// El pedido para pegarle a la IA. [hoy] va escrito porque la IA tiene que
/// resolver "ayer" o "hace dos semanas" contra una fecha concreta.
String externalImportPrompt(DateTime hoy) =>
    '''
Necesito pasar TODO mi historial de gimnasio, nutrición y progreso a mi nueva app (Ceres). Hoy es ${isoDate(hoy)}.

Revisá esta conversación ENTERA desde el primer mensaje (y lo que recuerdes de mí, si tenés memoria) y armá un único bloque con todos los datos reales que te pasé. Seguí estas reglas al pie de la letra:

1. SOLO datos que yo te dije o que salieron de lo que hablamos. No inventes, no completes con ejemplos ni promedios. Si un dato no existe, poné null o una lista vacía [].
2. Fechas en formato AAAA-MM-DD. Si yo dije "ayer", "el lunes" o "hace 2 semanas", calculá la fecha a partir del día en que lo dije. Si solo sabés la fecha aproximada, poné tu mejor estimación y "aprox": true.
3. Pesos en kilos (si alguno estaba en libras, multiplicá por 0,4536). Altura en cm.
4. Cada entrenamiento por separado, con TODAS sus series. Si te dije "4x8 con 60 kg", poné 4 series de 8 reps con 60 kg. Si hice drop sets o series con distinto peso, cada serie con su peso.
5. Incluí todos los pesajes, medidas (grasa, cintura, brazo, etc.), récords personales, la rutina que sigo, mi plan de calorías y macros si lo armamos, los días de comida que registramos (totales por día), las comidas que repito seguido con sus macros, suplementos, deportes (fútbol, pádel, running…) y mis objetivos.
6. Ordená todo de lo más viejo a lo más nuevo. No dejes nada afuera, aunque sean muchos datos.
7. Si no entra en una sola respuesta, dividilo en partes: empezá con "PARTE 1 de N", repetí el formato completo en cada parte con datos distintos y esperá a que te escriba "seguí".
8. Respondé ÚNICAMENTE con el bloque, sin explicaciones antes ni después, dentro de un bloque de código, empezando con la línea ===CERES=== y terminando con la línea ===FIN===.

El formato es este JSON (respetá los nombres de los campos tal cual; lo que está entre < > es solo una guía: reemplazalo por mis datos reales y, si de algo no tengo datos, dejá esa lista vacía []):

===CERES===
{
 "v": 1,
 "fuente": "<ChatGPT, Gemini, Claude u otra>",
 "perfil": {
  "nombre": "<tu nombre o null>",
  "sexo": "<m o f>",
  "edad": null,
  "altura_cm": null,
  "objetivo": "<volumen, definicion, mantenimiento o recomposicion>",
  "dias_por_semana": null,
  "meses_entrenando": null,
  "lesiones": ["<ej: hombro derecho>"],
  "notas": null
 },
 "plan": {"kcal": null, "proteina_g": null, "carbos_g": null, "grasas_g": null},
 "pesajes": [{"fecha": "AAAA-MM-DD", "kg": null, "aprox": false}],
 "medidas": [{"fecha": "AAAA-MM-DD", "grasa_pct": null, "masa_muscular_kg": null, "agua_kg": null, "cintura_cm": null, "pecho_cm": null, "brazo_cm": null, "muslo_cm": null}],
 "entrenos": [{"fecha": "AAAA-MM-DD", "titulo": "<ej: Pecho y tríceps>", "ejercicios": [{"nombre": "<ej: Press banca plano>", "series": [{"reps": null, "kg": null}]}], "cardio": [{"nombre": "<ej: Cinta>", "min": null}], "notas": null, "aprox": false}],
 "records": [{"ejercicio": "<ej: Sentadilla>", "kg": null, "reps": null, "fecha": "AAAA-MM-DD"}],
 "rutina": {"nombre": "<ej: Push Pull Legs>", "dias": [{"nombre": "<ej: Día 1 · Empuje>", "ejercicios": [{"nombre": "<ej: Press banca plano>", "series": null, "reps": "<ej: 6-8>"}]}]},
 "dias_nutricion": [{"fecha": "AAAA-MM-DD", "kcal": null, "proteina_g": null, "carbos_g": null, "grasas_g": null}],
 "comidas": [{"nombre": "<ej: Avena con banana>", "porcion": "<ej: 1 bowl>", "kcal": null, "proteina_g": null, "carbos_g": null, "grasas_g": null}],
 "suplementos": [{"nombre": "<ej: Creatina>", "marca": null, "dosis": "<ej: 5 g>"}],
 "deportes": [{"fecha": "AAAA-MM-DD", "deporte": "<ej: Fútbol>", "min": null, "intensidad": "<suave, moderada o alta>"}],
 "objetivos": [{"tipo": "<peso, levantamiento u otro>", "titulo": "<ej: Llegar a 80 kg>", "ejercicio": null, "valor": null, "fecha_limite": null}]
}
===FIN===''';

/// El texto pegado no tiene un bloque que se pueda leer.
class ExternalImportFormatException implements Exception {
  const ExternalImportFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ── Lo que trae el bloque, ya leído ────────────────────────────────────────

class ImportedProfile {
  const ImportedProfile({
    this.name,
    this.sex,
    this.heightCm,
    this.birthDate,
    this.objective,
  });

  final String? name;
  final BiologicalSex? sex;
  final double? heightCm;

  /// Estimada a partir de la edad: el formato no trae la fecha.
  final DateTime? birthDate;

  /// `volumen`, `definicion`, `mantenimiento` o `recomposicion`.
  final String? objective;
}

class ImportedPlan {
  const ImportedPlan({
    required this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  final int kcal;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;

  bool get hasMacros => proteinG != null && carbsG != null && fatG != null;
}

class ImportedWeight {
  const ImportedWeight(this.date, this.kg);

  final DateTime date;
  final double kg;
}

class ImportedMeasurement {
  const ImportedMeasurement(this.date, this.metric, this.value);

  final DateTime date;
  final MeasurementMetric metric;
  final double value;
}

/// Una sesión de algo que se mueve: un entreno de pesas, el cardio que vino
/// con él o un deporte. Las tres terminan siendo una actividad de Ceres.
class ImportedActivity {
  const ImportedActivity({
    required this.date,
    required this.slug,
    required this.minutes,
    required this.intensity,
    this.customName,
    this.notes,
  });

  final DateTime date;

  /// Slug de `activity_types`.
  final String slug;
  final int minutes;
  final Intensity intensity;
  final String? customName;
  final String? notes;
}

class ImportedNutritionDay {
  const ImportedNutritionDay({
    required this.date,
    required this.kcal,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.estimated = false,
  });

  final DateTime date;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Las calorías o alguno de los macros no venían y se estimaron.
  final bool estimated;
}

class ImportedFood {
  const ImportedFood({
    required this.name,
    required this.servingSize,
    required this.servingUnit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final String name;
  final double servingSize;
  final String servingUnit;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

/// Todo lo que se pudo leer del bloque (o de los bloques, si vino en partes).
class ExternalImport {
  const ExternalImport({
    this.source,
    this.profile = const ImportedProfile(),
    this.plan,
    this.targetWeightKg,
    this.weights = const <ImportedWeight>[],
    this.measurements = const <ImportedMeasurement>[],
    this.workouts = const <ImportedActivity>[],
    this.sports = const <ImportedActivity>[],
    this.nutritionDays = const <ImportedNutritionDay>[],
    this.foods = const <ImportedFood>[],
    this.records = 0,
    this.routineDays = 0,
    this.supplements = 0,
    this.otherGoals = 0,
    this.discarded = 0,
    this.estimated = 0,
  });

  /// La IA de la que viene, si lo dijo.
  final String? source;
  final ImportedProfile profile;
  final ImportedPlan? plan;
  final double? targetWeightKg;
  final List<ImportedWeight> weights;
  final List<ImportedMeasurement> measurements;

  /// Entrenos de gimnasio y el cardio que vino con ellos.
  final List<ImportedActivity> workouts;
  final List<ImportedActivity> sports;
  final List<ImportedNutritionDay> nutritionDays;
  final List<ImportedFood> foods;

  // Lo que Ceres no guarda: se cuenta para decirlo, no se lee más.
  final int records;
  final int routineDays;
  final int supplements;
  final int otherGoals;

  /// Entradas que no se pudieron ubicar: sin fecha, con fecha futura o con un
  /// valor fuera de rango.
  final int discarded;

  /// Datos que no venían y se estimaron (duraciones, macros, calorías, fecha
  /// de nacimiento, peso objetivo).
  final int estimated;

  bool get isEmpty =>
      weights.isEmpty &&
      measurements.isEmpty &&
      workouts.isEmpty &&
      sports.isEmpty &&
      nutritionDays.isEmpty &&
      foods.isEmpty &&
      plan == null &&
      profile.heightCm == null &&
      profile.sex == null &&
      profile.birthDate == null &&
      profile.name == null;

  /// Lee el texto que devolvió la IA.
  ///
  /// Tolera lo que las IA suelen hacer: bloque de código alrededor, varias
  /// partes pegadas una debajo de la otra, comillas tipográficas, comas de
  /// más al final de una lista y números escritos con coma decimal.
  static ExternalImport parse(String text, {DateTime? now}) {
    final documents = _documents(text);
    if (documents.isEmpty) {
      throw const ExternalImportFormatException(
        'No encontramos el bloque. Tiene que empezar con ===CERES=== y '
        'terminar con ===FIN===.',
      );
    }
    return _Reader(today: dateOnly(now ?? DateTime.now())).read(documents);
  }

  static final RegExp _block = RegExp(
    r'===\s*[A-Za-zÁÉÍÓÚáéíóú]+\s*===([\s\S]*?)===\s*FIN\s*===',
  );

  static List<Map<String, dynamic>> _documents(String text) {
    final normalized = text
        .replaceAll(RegExp('[“”]'), '"')
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll(' ', ' ');
    final bodies = <String>[
      for (final match in _block.allMatches(normalized)) match.group(1)!,
    ];
    // Sin marcadores: puede que se haya copiado solo el JSON.
    if (bodies.isEmpty) bodies.add(normalized);

    final documents = <Map<String, dynamic>>[];
    for (final body in bodies) {
      final start = body.indexOf('{');
      final end = body.lastIndexOf('}');
      if (start < 0 || end <= start) continue;
      final json = body
          .substring(start, end + 1)
          // Coma de más antes de cerrar: JSON no la acepta y las IA la ponen.
          .replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) documents.add(decoded);
      } on FormatException {
        // Una parte rota no tira abajo a las demás: se avisa si no queda
        // ninguna.
      }
    }
    return documents;
  }
}

class _Reader {
  _Reader({required this.today});

  final DateTime today;
  int _discarded = 0;
  int _estimated = 0;

  ExternalImport read(List<Map<String, dynamic>> documents) {
    String? source;
    String? name;
    BiologicalSex? sex;
    double? height;
    DateTime? birthDate;
    String? objective;
    ImportedPlan? plan;
    double? targetWeight;
    final weights = <DateTime, ImportedWeight>{};
    final measurements = <String, ImportedMeasurement>{};
    final workouts = <ImportedActivity>[];
    final sports = <ImportedActivity>[];
    final nutrition = <DateTime, ImportedNutritionDay>{};
    final foods = <String, ImportedFood>{};
    var records = 0;
    var routineDays = 0;
    var supplements = 0;
    var otherGoals = 0;

    for (final doc in documents) {
      source ??= _text(doc['fuente']);

      final perfil = _map(doc['perfil']);
      name ??= _text(perfil['nombre']);
      sex ??= switch (_text(perfil['sexo'])?.toLowerCase()) {
        'm' || 'masculino' || 'hombre' => BiologicalSex.male,
        'f' || 'femenino' || 'mujer' => BiologicalSex.female,
        _ => null,
      };
      height ??= _inRange(_number(perfil['altura_cm']), 100, 250);
      // Con la edad sola el cumpleaños puede caer cualquier día del año: se
      // toma la mitad, que es lo que menos se equivoca en promedio.
      if (birthDate == null) {
        final age = _inRange(_number(perfil['edad']), 10, 100)?.round();
        if (age != null) {
          birthDate = dateOnly(
            DateTime(
              today.year - age,
              today.month,
              today.day,
            ).subtract(const Duration(days: 182)),
          );
          _estimated++;
        }
      }
      objective ??= _plain(_text(perfil['objetivo']));

      final planMap = _map(doc['plan']);
      if (plan == null) {
        final protein = _inRange(_number(planMap['proteina_g']), 0, 600);
        final carbs = _inRange(_number(planMap['carbos_g']), 0, 1000);
        final fat = _inRange(_number(planMap['grasas_g']), 0, 400);
        var kcal = _inRange(_number(planMap['kcal']), 800, 6000);
        // Sin calorías pero con los tres macros: la cuenta es exacta.
        if (kcal == null && protein != null && carbs != null && fat != null) {
          kcal = _inRange(protein * 4 + carbs * 4 + fat * 9, 800, 6000);
          if (kcal != null) _estimated++;
        }
        // Los macros que falten los completa el importador con la regla de
        // la app (`macroTargets`), que conoce el peso de la persona.
        if (kcal != null) {
          plan = ImportedPlan(
            kcal: kcal.round(),
            proteinG: protein?.round(),
            carbsG: carbs?.round(),
            fatG: fat?.round(),
          );
        }
      }

      for (final e in _list(doc['pesajes'])) {
        final date = _date(e['fecha']);
        final kg = _inRange(_number(e['kg']), 25, 400);
        if (date == null || kg == null) {
          _skip(e);
          continue;
        }
        weights[date] = ImportedWeight(date, kg);
      }

      for (final e in _list(doc['medidas'])) {
        final date = _date(e['fecha']);
        if (date == null) {
          _skip(e);
          continue;
        }
        for (final (field, metric) in _metricFields) {
          final value = _number(e[field]);
          if (value == null) continue;
          if (value < metric.min || value > metric.max) {
            _discarded++;
            continue;
          }
          measurements['${isoDate(date)}|${metric.wire}'] = ImportedMeasurement(
            date,
            metric,
            value,
          );
        }
      }

      for (final e in _list(doc['entrenos'])) {
        final date = _date(e['fecha']);
        if (date == null) {
          _skip(e);
          continue;
        }
        workouts.addAll(_workout(date, e));
      }

      for (final e in _list(doc['deportes'])) {
        final date = _date(e['fecha']);
        final sport = _text(e['deporte']);
        if (date == null || sport == null) {
          _skip(e);
          continue;
        }
        final slug = _slugFor(sport);
        final (minutes, note) = _minutes(e['min'], slug);
        sports.add(
          ImportedActivity(
            date: date,
            slug: slug,
            minutes: minutes,
            intensity: _intensity(e['intensidad']),
            customName: _needsName(slug) ? _cap(sport) : null,
            notes: note,
          ),
        );
      }

      for (final e in _list(doc['dias_nutricion'])) {
        final date = _date(e['fecha']);
        final totals = _energy(
          kcal: _inRange(_number(e['kcal']), 1, 15000),
          proteinG: _inRange(_number(e['proteina_g']), 0, 1000),
          carbsG: _inRange(_number(e['carbos_g']), 0, 2000),
          fatG: _inRange(_number(e['grasas_g']), 0, 1000),
          maxKcal: 15000,
        );
        if (date == null || totals == null) {
          _skip(e);
          continue;
        }
        nutrition[date] = ImportedNutritionDay(
          date: date,
          kcal: totals.kcal,
          proteinG: totals.proteinG,
          carbsG: totals.carbsG,
          fatG: totals.fatG,
          estimated: totals.estimated,
        );
      }

      for (final e in _list(doc['comidas'])) {
        final food = _food(e);
        if (food == null) {
          _skip(e);
          continue;
        }
        foods[food.name.toLowerCase()] = food;
      }

      records += _list(doc['records']).where(_hasData).length;
      supplements += _list(doc['suplementos']).where(_hasData).length;
      routineDays += _list(_map(doc['rutina'])['dias']).where(_hasData).length;

      for (final e in _list(doc['objetivos'])) {
        if (!_hasData(e)) continue;
        final tipo = _plain(_text(e['tipo']));
        var value = _inRange(_number(e['valor']), 25, 400);
        // "Llegar a 80 kg" sin `valor`: el número está en el título.
        if (tipo == 'peso' && value == null) {
          final inTitle = RegExp(
            r'(\d+(?:[.,]\d+)?)\s*kg',
          ).firstMatch(_text(e['titulo']) ?? '');
          value = _inRange(_number(inTitle?.group(1)), 25, 400);
          if (value != null) _estimated++;
        }
        if (tipo == 'peso' && value != null && targetWeight == null) {
          targetWeight = value;
        } else {
          otherGoals++;
        }
      }
    }

    int byDate(DateTime a, DateTime b) => a.compareTo(b);

    return ExternalImport(
      source: source,
      profile: ImportedProfile(
        name: name,
        sex: sex,
        heightCm: height,
        birthDate: birthDate,
        objective: objective,
      ),
      plan: plan,
      targetWeightKg: targetWeight,
      weights: weights.values.toList()..sort((a, b) => byDate(a.date, b.date)),
      measurements: measurements.values.toList()
        ..sort((a, b) => byDate(a.date, b.date)),
      workouts: workouts..sort((a, b) => byDate(a.date, b.date)),
      sports: sports..sort((a, b) => byDate(a.date, b.date)),
      nutritionDays: nutrition.values.toList()
        ..sort((a, b) => byDate(a.date, b.date)),
      foods: foods.values.toList(),
      records: records,
      routineDays: routineDays,
      supplements: supplements,
      otherGoals: otherGoals,
      discarded: _discarded,
      estimated: _estimated,
    );
  }

  static const List<(String, MeasurementMetric)> _metricFields =
      <(String, MeasurementMetric)>[
        ('grasa_pct', MeasurementMetric.bodyFatPct),
        ('masa_muscular_kg', MeasurementMetric.muscleKg),
        ('cintura_cm', MeasurementMetric.waist),
        ('pecho_cm', MeasurementMetric.chest),
        ('brazo_cm', MeasurementMetric.arm),
        ('muslo_cm', MeasurementMetric.thigh),
      ];

  /// Un entreno de gimnasio es una actividad de fuerza; el cardio que vino
  /// con él va aparte, con su propio tipo, porque gasta distinto.
  ///
  /// El formato no trae cuánto duró el entreno, y Ceres necesita minutos para
  /// estimar el gasto. Se estiman a partir de las series —unos tres minutos
  /// por serie contando el descanso— y la nota lo dice.
  List<ImportedActivity> _workout(DateTime date, Map<String, dynamic> e) {
    final title = _text(e['titulo']);
    final lines = <String>[];
    var sets = 0;
    for (final exercise in _list(e['ejercicios'])) {
      final name = _text(exercise['nombre']);
      if (name == null) continue;
      final series = <(int?, double?)>[
        for (final s in _list(exercise['series']))
          (_number(s['reps'])?.round(), _number(s['kg'])),
      ].where((s) => s.$1 != null || s.$2 != null).toList();
      sets += series.length;
      lines.add(series.isEmpty ? name : '$name: ${_describeSeries(series)}');
    }

    final out = <ImportedActivity>[];
    if (lines.isNotEmpty || title != null) {
      final minutes = sets == 0
          ? _usualMinutes('strength_training')
          : (sets * 3).clamp(20, 150);
      _estimated++;
      final notes = <String>[
        ...lines,
        ?_text(e['notas']),
        sets == 0
            ? 'Duración estimada: el entreno vino sin series.'
            : 'Duración estimada a partir de $sets series.',
      ].join('\n');
      out.add(
        ImportedActivity(
          date: date,
          slug: 'strength_training',
          minutes: minutes,
          intensity: Intensity.moderate,
          customName: title,
          notes: notes.length > 1000 ? '${notes.substring(0, 999)}…' : notes,
        ),
      );
    }

    for (final c in _list(e['cardio'])) {
      final name = _text(c['nombre']);
      if (name == null) continue;
      final slug = _slugFor(name);
      final (minutes, note) = _minutes(c['min'], slug);
      out.add(
        ImportedActivity(
          date: date,
          slug: slug,
          minutes: minutes,
          intensity: Intensity.moderate,
          customName: _needsName(slug) ? _cap(name) : null,
          notes: note,
        ),
      );
    }
    if (out.isEmpty) _discarded++;
    return out;
  }

  /// "4×8 · 60 kg, 1×6 · 70 kg": las series iguales seguidas se juntan.
  static String _describeSeries(List<(int?, double?)> series) {
    final groups = <((int?, double?), int)>[];
    for (final s in series) {
      if (groups.isNotEmpty && groups.last.$1 == s) {
        groups.last = (s, groups.last.$2 + 1);
      } else {
        groups.add((s, 1));
      }
    }
    return groups
        .map((g) {
          final (reps, kg) = g.$1;
          final count = '${g.$2}×${reps ?? '?'}';
          return kg == null ? count : '$count · ${_kg(kg)} kg';
        })
        .join(', ');
  }

  static String _kg(double kg) => kg == kg.roundToDouble()
      ? kg.round().toString()
      : kg.toStringAsFixed(1).replaceAll('.', ',');

  ImportedFood? _food(Map<String, dynamic> e) {
    final name = _text(e['nombre']);
    final totals = _energy(
      kcal: _inRange(_number(e['kcal']), 0, 2000),
      proteinG: _inRange(_number(e['proteina_g']), 0, 500),
      carbsG: _inRange(_number(e['carbos_g']), 0, 500),
      fatG: _inRange(_number(e['grasas_g']), 0, 500),
      maxKcal: 2000,
    );
    if (name == null || totals == null) return null;
    // "1 bowl", "200 g", "2 unidades": el número es la porción y el resto, la
    // unidad. Sin número, la porción entera es una unidad de lo que diga.
    final portion = _text(e['porcion']);
    final match = portion == null
        ? null
        : RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(.*)$').firstMatch(portion);
    final size = match == null
        ? 1.0
        : double.parse(match.group(1)!.replaceAll(',', '.'));
    final unit = match == null
        ? (portion ?? 'porción')
        : (match.group(2)!.trim().isEmpty ? 'porción' : match.group(2)!.trim());
    return ImportedFood(
      name: name.length > 120 ? name.substring(0, 120) : name,
      servingSize: size <= 0 || size > 10000 ? 1 : size,
      servingUnit: unit,
      kcal: totals.kcal,
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
    );
  }

  /// Minutos de una actividad, o lo habitual para su tipo si no vinieron.
  (int, String?) _minutes(Object? value, String slug) {
    final given = _inRange(_number(value), 1, 1440)?.round();
    if (given != null) return (given, null);
    _estimated++;
    final usual = _usualMinutes(slug);
    return (usual, 'Duración estimada ($usual min): no venía en el bloque.');
  }

  /// Lo que dura una sesión típica de cada tipo. Es la mejor apuesta cuando
  /// la persona no lo dijo: un partido de fútbol o de pádel ronda la hora, una
  /// salida a correr la media hora.
  static int _usualMinutes(String slug) => switch (slug) {
    'sports' => 60,
    'strength_training' => 60,
    'yoga' => 60,
    'pilates' => 50,
    'hiking' => 120,
    'cycling' => 45,
    'dancing' => 45,
    'functional_training' => 45,
    'rowing' || 'stairs' => 20,
    'running' || 'walking' || 'swimming' || 'elliptical' => 30,
    _ => 45,
  };

  /// Completa calorías y macros con lo que haya.
  ///
  /// - Con los tres macros y sin calorías: 4/4/9 kcal por gramo.
  /// - Con calorías y algún macro faltante: lo que queda de las calorías se
  ///   reparte entre los que faltan según un plato típico (20 % proteína,
  ///   50 % carbohidratos, 30 % grasas).
  /// - Sin calorías y con macros incompletos no hay de dónde sacarlas: null.
  _Energy? _energy({
    required double? kcal,
    required double? proteinG,
    required double? carbsG,
    required double? fatG,
    required double maxKcal,
  }) {
    var total = kcal;
    var estimated = false;
    if (total == null) {
      if (proteinG == null || carbsG == null || fatG == null) return null;
      total = proteinG * 4 + carbsG * 4 + fatG * 9;
      if (total <= 0 || total > maxKcal) return null;
      estimated = true;
    }

    final known = (proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9;
    final missingShare =
        (proteinG == null ? 0.2 : 0) +
        (carbsG == null ? 0.5 : 0) +
        (fatG == null ? 0.3 : 0);
    final left = (total - known).clamp(0, double.infinity);
    double fill(double? grams, double share, int kcalPerGram) {
      if (grams != null) return grams;
      estimated = true;
      return _round1(left * share / missingShare / kcalPerGram);
    }

    final energy = _Energy(
      kcal: total.round(),
      proteinG: fill(proteinG, 0.2, 4),
      carbsG: fill(carbsG, 0.5, 4),
      fatG: fill(fatG, 0.3, 9),
      estimated: estimated,
    );
    if (estimated) _estimated++;
    return energy;
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  /// El tipo de Ceres para lo que la persona nombró. Lo que no se reconoce va
  /// como actividad propia con su nombre: mejor eso que adivinar un MET.
  static String _slugFor(String name) {
    final n = _plain(name) ?? '';
    bool has(List<String> words) => words.any(n.contains);
    if (has(<String>[
      'futbol',
      'padel',
      'tenis',
      'basquet',
      'basket',
      'voley',
      'rugby',
      'hockey',
      'handball',
      'squash',
      'paddle',
    ])) {
      return 'sports';
    }
    if (has(<String>['running', 'correr', 'trote', 'trotar', 'carrera'])) {
      return 'running';
    }
    if (has(<String>['bici', 'ciclismo', 'spinning', 'cycling'])) {
      return 'cycling';
    }
    if (has(<String>['nata', 'nadar', 'pileta', 'swim'])) return 'swimming';
    if (has(<String>['eliptic'])) return 'elliptical';
    if (has(<String>['remo', 'rowing'])) return 'rowing';
    if (has(<String>['escalera', 'stair', 'escaladora'])) return 'stairs';
    if (has(<String>['trekking', 'senderismo', 'hiking'])) return 'hiking';
    if (has(<String>['caminata', 'caminar', 'cinta', 'walking'])) {
      return 'walking';
    }
    if (has(<String>['yoga'])) return 'yoga';
    if (has(<String>['pilates'])) return 'pilates';
    if (has(<String>['baile', 'danza', 'zumba'])) return 'dancing';
    if (has(<String>['crossfit', 'funcional', 'hiit'])) {
      return 'functional_training';
    }
    if (has(<String>['pesas', 'gimnasio', 'musculacion', 'gym'])) {
      return 'strength_training';
    }
    return 'custom';
  }

  /// Con "Deporte" a secas no se sabe si fue fútbol o pádel: el nombre viaja.
  static bool _needsName(String slug) => slug == 'sports' || slug == 'custom';

  static Intensity _intensity(Object? value) => switch (_plain(_text(value))) {
    'suave' || 'baja' || 'leve' => Intensity.light,
    'alta' || 'intensa' || 'fuerte' => Intensity.vigorous,
    _ => Intensity.moderate,
  };

  DateTime? _date(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (match == null) return null;
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    // Una fecha imposible (31 de febrero) se corre de mes: se descarta.
    if (date.month != int.parse(match.group(2)!)) return null;
    if (date.isAfter(today) || date.year < 1950) return null;
    return date;
  }

  /// Una entrada de ejemplo que quedó tal cual (`AAAA-MM-DD`, todo null) no
  /// es un dato descartado: es la plantilla vacía, y no se cuenta.
  void _skip(Map<String, dynamic> entry) {
    if (_hasData(entry)) _discarded++;
  }

  static bool _hasData(Map<String, dynamic> entry) => entry.entries.any(
    (e) =>
        e.key != 'aprox' &&
        e.key != 'fecha' &&
        switch (e.value) {
          null => false,
          final String s => _text(s) != null,
          final List<dynamic> l => l.isNotEmpty,
          final Map<String, dynamic> m => _hasData(m),
          _ => true,
        },
  );

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const <Map<String, dynamic>>[];

  /// El texto, o null si está vacío o si es la guía `<...>` de la plantilla.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final t = value.trim();
    if (t.isEmpty || t == 'null' || (t.startsWith('<') && t.endsWith('>'))) {
      return null;
    }
    return t;
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(
      s.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.'),
    ),
    _ => null,
  };

  static double? _inRange(double? value, double min, double max) =>
      value == null || value.isNaN || value < min || value > max ? null : value;

  /// Minúsculas y sin tildes, para comparar lo que escribió una persona.
  static String? _plain(String? text) {
    if (text == null) return null;
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buffer.write(i < 0 ? ch : to[i]);
    }
    return buffer.toString().trim();
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Energy {
  const _Energy({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.estimated,
  });

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final bool estimated;
}

// ── Aplicarlo ─────────────────────────────────────────────────────────────

/// Qué se puede elegir antes de importar.
class ExternalImportOptions {
  const ExternalImportOptions({this.usePlan = false});

  /// Reemplazar el objetivo de calorías y macros por el de la otra app.
  ///
  /// Apagado de entrada: el objetivo vigente puede haberlo puesto la
  /// nutricionista, y pisarlo sin que la persona lo pida sería un susto.
  final bool usePlan;
}

/// Cuánto entra y cuánto ya estaba, por categoría.
class ExternalImportReport {
  const ExternalImportReport({
    required this.weights,
    required this.measurements,
    required this.workouts,
    required this.sports,
    required this.nutritionDays,
    required this.foods,
    required this.alreadyThere,
    required this.profileFields,
    required this.planApplied,
  });

  final int weights;
  final int measurements;
  final int workouts;
  final int sports;
  final int nutritionDays;
  final int foods;

  /// Lo que no entra porque Ceres ya lo tenía: un peso ese día, un alimento
  /// con el mismo nombre, un día que ya tiene comidas cargadas.
  final int alreadyThere;

  /// Datos del perfil que estaban vacíos y se completan.
  final List<String> profileFields;
  final bool planApplied;

  int get total =>
      weights +
      measurements +
      workouts +
      sports +
      nutritionDays +
      foods +
      profileFields.length +
      (planApplied ? 1 : 0);
}

/// Pasa un [ExternalImport] a los registros de Ceres.
///
/// Nunca reemplaza nada: lo que ya está cargado gana. Importar dos veces el
/// mismo bloque no duplica, porque la segunda vez todo "ya estaba".
class ExternalImporter {
  ExternalImporter(this.repo);

  final CeresRepositories repo;
  static const _uuid = Uuid();

  /// Lo que haría [apply], sin escribir nada.
  Future<ExternalImportReport> preview(
    ExternalImport data, {
    ExternalImportOptions options = const ExternalImportOptions(),
  }) => _run(data, options, write: false);

  /// Escribe todo con un solo guardado al final.
  Future<ExternalImportReport> apply(
    ExternalImport data, {
    ExternalImportOptions options = const ExternalImportOptions(),
  }) => repo.inBatch(() => _run(data, options, write: true));

  Future<ExternalImportReport> _run(
    ExternalImport data,
    ExternalImportOptions options, {
    required bool write,
  }) async {
    var already = 0;

    // ── Perfil: solo lo que falta ────────────────────────────────────────
    final profile = repo.profile;
    final fields = <String>[];
    var updated = profile;
    if ((profile.displayName ?? '').trim().isEmpty &&
        data.profile.name != null) {
      updated = updated.copyWith(displayName: data.profile.name);
      fields.add('nombre');
    }
    if (profile.heightCm == null && data.profile.heightCm != null) {
      updated = updated.copyWith(heightCm: data.profile.heightCm);
      fields.add('altura');
    }
    if (profile.biologicalSex == BiologicalSex.unspecified &&
        data.profile.sex != null) {
      updated = updated.copyWith(biologicalSex: data.profile.sex);
      fields.add('sexo');
    }
    if (profile.birthDate == null && data.profile.birthDate != null) {
      updated = updated.copyWith(birthDate: data.profile.birthDate);
      fields.add('fecha de nacimiento (por la edad)');
    }
    if (write && fields.isNotEmpty && repo.hasSession) {
      await repo.updateProfile(updated);
    }

    // ── Pesos y medidas ──────────────────────────────────────────────────
    var weights = 0;
    for (final w in data.weights) {
      if (repo.weightOn(w.date) != null) {
        already++;
        continue;
      }
      weights++;
      if (write) {
        await repo.logWeight(
          weightKg: w.kg,
          date: w.date,
          notes: _importNote(data),
        );
      }
    }

    var measurements = 0;
    for (final m in data.measurements) {
      if (repo.measurementsOn(m.date).containsKey(m.metric)) {
        already++;
        continue;
      }
      measurements++;
      if (write) {
        await repo.logMeasurement(
          metric: m.metric,
          value: m.value,
          date: m.date,
        );
      }
    }

    // ── Actividades ──────────────────────────────────────────────────────
    final seen = <String>{};
    Future<int> activities(List<ImportedActivity> list) async {
      var added = 0;
      for (final a in list) {
        final type = repo.typeBySlug(a.slug) ?? repo.typeBySlug('custom');
        if (type == null) continue;
        final key =
            '${isoDate(a.date)}|${type.id}|${a.customName}|${a.minutes}';
        final exists = repo
            .activitiesOn(a.date)
            .any(
              (x) =>
                  x.activityTypeId == type.id &&
                  x.durationMinutes == a.minutes &&
                  x.customName == a.customName,
            );
        if (exists || !seen.add(key)) {
          already++;
          continue;
        }
        added++;
        if (write) {
          await repo.saveActivity(
            ActivityDraft(
              activityTypeId: type.id,
              // Sin hora en el formato: el mediodía no cae en el día de al
              // lado con ningún huso.
              startedAt: a.date.add(const Duration(hours: 12)),
              durationMinutes: a.minutes,
              intensity: a.intensity,
              customName: a.customName,
              notes: a.notes,
            ),
          );
        }
      }
      return added;
    }

    final workouts = await activities(data.workouts);
    final sports = await activities(data.sports);

    // ── Días de comida ───────────────────────────────────────────────────
    //
    // La otra app solo da el total del día. Va como una comida con un ítem,
    // para que el historial y los promedios de Progreso lo cuenten; un día
    // que ya tiene comidas en Ceres se deja como está, porque sumarle el
    // total de afuera lo contaría dos veces.
    var nutritionDays = 0;
    for (final d in data.nutritionDays) {
      if (repo.mealsOn(d.date).isNotEmpty) {
        already++;
        continue;
      }
      nutritionDays++;
      if (write) {
        final now = DateTime.now();
        await repo.saveMeal(
          Meal(
            id: _uuid.v4(),
            slot: MealSlot.dinner,
            eatenAt: d.date.add(const Duration(hours: 21)),
            localDate: d.date,
            name: 'Total del día',
            notes: d.estimated
                ? '${_importNote(data)}: la otra app guardaba solo el total, '
                      'y lo que faltaba se estimó.'
                : '${_importNote(data)}: la otra app guardaba solo el total.',
            source: MealSource.manual,
            createdAt: now,
            updatedAt: now,
            items: <MealItem>[
              MealItem(
                id: _uuid.v4(),
                name: 'Total del día',
                quantity: 1,
                unit: 'día',
                kcal: d.kcal,
                proteinG: d.proteinG,
                carbsG: d.carbsG,
                fatG: d.fatG,
                position: 0,
              ),
            ],
          ),
        );
      }
    }

    // ── Comidas que repite: alimentos propios ────────────────────────────
    final ownNames = repo.ownFoods().map((f) => f.name.toLowerCase()).toSet();
    var foods = 0;
    for (final f in data.foods) {
      if (!ownNames.add(f.name.toLowerCase())) {
        already++;
        continue;
      }
      foods++;
      if (write) {
        await repo.createOwnFood(
          Food(
            id: _uuid.v4(),
            userId: profile.id,
            name: f.name,
            source: FoodSource.user,
            servingSize: f.servingSize,
            servingUnit: f.servingUnit,
            kcal: f.kcal,
            proteinG: f.proteinG,
            carbsG: f.carbsG,
            fatG: f.fatG,
            portions: <FoodPortion>[
              FoodPortion(
                label: '${_num(f.servingSize)} ${f.servingUnit}',
                grams: f.servingSize,
              ),
            ],
          ),
        );
      }
    }

    // ── Plan ─────────────────────────────────────────────────────────────
    final plan = data.plan;
    final planApplied = options.usePlan && plan != null;
    if (write && planApplied) {
      final current = repo.goalFor(today());
      final macros = plan.hasMacros
          ? MacroTargets(
              proteinG: plan.proteinG!,
              carbsG: plan.carbsG!,
              fatG: plan.fatG!,
            )
          : macroTargets(
              targetKcal: plan.kcal,
              weightKg: repo.currentWeightKg ?? 70,
              goalType: current.goalType,
            );
      await repo.saveGoal(
        Goal(
          id: _uuid.v4(),
          goalType: current.goalType,
          rateKgPerWeek: current.rateKgPerWeek,
          targetWeightKg: data.targetWeightKg ?? current.targetWeightKg,
          baseCalorieTarget: plan.kcal,
          targetMethod: TargetMethod.manual,
          bmrKcal: current.bmrKcal,
          tdeeKcal: current.tdeeKcal,
          proteinG: macros.proteinG,
          carbsG: macros.carbsG,
          fatG: macros.fatG,
          macroMethod: plan.hasMacros ? 'custom' : current.macroMethod,
          startsOn: today(),
        ),
      );
    }

    return ExternalImportReport(
      weights: weights,
      measurements: measurements,
      workouts: workouts,
      sports: sports,
      nutritionDays: nutritionDays,
      foods: foods,
      alreadyThere: already,
      profileFields: fields,
      planApplied: planApplied,
    );
  }

  static String _importNote(ExternalImport data) => data.source == null
      ? 'Importado de otra app'
      : 'Importado de otra app (${data.source})';

  static String _num(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');
}
