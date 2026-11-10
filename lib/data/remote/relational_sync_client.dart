import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/models/day_marker.dart';
import '../local/local_store.dart';

/// Sube y baja los datos del usuario **como filas**, en las tablas del
/// esquema, además del documento JSON del respaldo.
///
/// ## Por qué existe
///
/// Hasta acá todo colgaba de un único documento en Storage. Eso alcanzaba para
/// no perder nada y cambiar de teléfono, pero:
///
/// - Viaja **entero en cada cambio**. Anotar un vaso de agua subía el
///   documento completo, que ya pasó de 38 a 81 kB en un día.
/// - Es todo o nada: si se corrompe, se pierde junto.
/// - El servidor no puede leer nada adentro. Estadísticas, resúmenes o que un
///   pal vea algo real son imposibles contra un blob opaco.
///
/// ## Cómo convive con el respaldo
///
/// Los dos caminos escriben, y **ya se dio vuelta**: mandan las tablas y el
/// documento es la copia con la que trabaja cada dispositivo. Al entrar y al
/// volver a la app se traen las filas y se reconcilian contra lo local
/// (`document_merge.dart`); el respaldo del documento entero al bucket quedó
/// como red de seguridad, no como fuente. El comentario anterior describía el
/// paso previo, cuando esto todavía se estaba verificando.
///
/// ## Lo que hay que saber del esquema
///
/// `activities.activity_type_id` tiene **clave foránea** a `activity_types`,
/// cuyos ids los generó el servidor. El catálogo que viaja en el APK no trae
/// esos ids —solo el `slug`— así que hay que mapear por slug antes de
/// insertar. Y los tipos que crea la persona no existen del lado del servidor:
/// esas actividades se apoyan en el tipo `custom` y conservan el nombre en
/// `custom_name`, que es lo que la app muestra igual.
class RelationalSyncClient {
  RelationalSyncClient(this._db);

  factory RelationalSyncClient.fromInstance() =>
      RelationalSyncClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Corto: es trabajo de fondo y no puede quedar colgado ocupando la red.
  static const Duration timeout = Duration(seconds: 30);

  /// `slug` → id remoto de `activity_types`. Se resuelve una vez por sesión:
  /// el catálogo lo siembra una migración y no cambia entre corridas.
  Map<String, String>? _typeIdBySlug;

  Future<Map<String, String>> _activityTypeIds() async {
    final cached = _typeIdBySlug;
    if (cached != null) return cached;

    final rows = await _db
        .from('activity_types')
        .select('id, slug')
        .timeout(timeout);
    final map = <String, String>{
      for (final row in rows)
        row['slug'] as String: row['id'] as String,
    };
    _typeIdBySlug = map;
    return map;
  }

  /// Escribe todo el contenido del usuario como filas.
  ///
  /// Es un *upsert* completo, no un diff: para el volumen de una persona
  /// —cientos de filas— es más barato y muchísimo más simple de razonar que
  /// llevar un registro de cambios, y no puede quedar desincronizado.
  ///
  /// Devuelve cuántas filas se escribieron por tabla, que es lo que permite
  /// verificar contra el documento sin adivinar.
  Future<Map<String, int>> push({
    required String userId,
    required LocalStore store,
  }) async {
    final escritas = <String, int>{};

    /// Las tablas que fallaron, con el motivo. Se juntan en vez de cortar.
    final fallaron = <String, String>{};

    /// Sube una tabla y **se queda con su fallo**.
    ///
    /// Antes las once tablas compartían un `try`: la primera que fallaba
    /// abortaba el método y las que venían después no se intentaban siquiera.
    /// Fue lo que convirtió una restricción desactualizada en una base sin una
    /// sola comida — `body_measurements` es la cuarta de once, y con ella se
    /// perdieron las siete que le siguen.
    ///
    /// Ahora cada tabla se juega su suerte sola. Al final se lanza igual, con
    /// los nombres de las que fallaron, pero lo que sí entró queda escrito.
    ///
    /// [onConflict] nombra la clave contra la que se resuelve el choque. Sin
    /// él, el upsert resuelve **contra la primary key**, y eso alcanza solo
    /// mientras el id sea la única forma de que dos filas se pisen.
    Future<void> subir(
      String tabla,
      List<Map<String, dynamic>> filas, {
      String? onConflict,
    }) async {
      if (filas.isEmpty) {
        escritas[tabla] = 0;
        return;
      }
      try {
        await _db
            .from(tabla)
            .upsert(filas, onConflict: onConflict)
            .timeout(timeout);
        escritas[tabla] = filas.length;
      } on PostgrestException catch (error) {
        escritas[tabla] = 0;
        fallaron[tabla] = error.message;
      } on TimeoutException {
        escritas[tabla] = 0;
        fallaron[tabla] = 'tardó demasiado';
      } on Exception catch (error) {
        escritas[tabla] = 0;
        fallaron[tabla] = error.toString();
      }
    }

    try {
      // El perfil primero: todo lo demás lo referencia por `user_id`.
      final profile = store.profile;
      if (profile != null) {
        await _db
            .from('profiles')
            .upsert(<String, dynamic>{
              'id': userId,
              'display_name': profile.displayName,
              'biological_sex': profile.biologicalSex.wire,
              'birth_date': profile.birthDate == null
                  ? null
                  : isoDate(profile.birthDate!),
              'height_cm': profile.heightCm,
              'activity_level': profile.activityLevel.wire,
              'timezone': profile.timezone,
              'unit_system': profile.unitSystem.wire,
              'theme_mode': profile.themeMode.wire,
              'locale': profile.locale,
              'exercise_credit_percentage': profile.exerciseCreditPercentage,
              'exercise_credit_enabled': profile.exerciseCreditEnabled,
              'show_net_calories': profile.showNetCalories,
              // Las restricciones alimentarias viajan a las tablas y no solo en
              // el respaldo: al abrir la app en un teléfono nuevo el perfil se
              // arma con esta fila, y una alergia que no llegue ahí no existe
              // del otro lado.
              'dietary_flags': <String>[
                for (final f in profile.dietaryFlags) f.wire,
              ],
              'dietary_note': profile.dietaryNote.trim().isEmpty
                  ? null
                  : profile.dietaryNote.trim(),
            })
            .timeout(timeout);
        escritas['profiles'] = 1;
      }

      await subir('goals', <Map<String, dynamic>>[
        for (final g in store.goals)
          <String, dynamic>{
            'id': g.id,
            'user_id': userId,
            'goal_type': g.goalType.wire,
            'rate_kg_per_week': g.rateKgPerWeek,
            'target_weight_kg': g.targetWeightKg,
            'base_calorie_target': g.baseCalorieTarget,
            'target_method': g.targetMethod.wire,
            'bmr_kcal': g.bmrKcal,
            'tdee_kcal': g.tdeeKcal,
            'protein_g': g.proteinG,
            'carbs_g': g.carbsG,
            'fat_g': g.fatG,
            'macro_method': g.macroMethod,
            'starts_on': isoDate(g.startsOn),
            'ends_on': g.endsOn == null ? null : isoDate(g.endsOn!),
            'updated_at': (g.updatedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
          },
      ]);

      await subir('weight_logs', <Map<String, dynamic>>[
        for (final w in store.weightLogs)
          <String, dynamic>{
            'id': w.id,
            'user_id': userId,
            'weight_kg': w.weightKg,
            'local_date': isoDate(w.localDate),
            'logged_at': w.loggedAt.toUtc().toIso8601String(),
            'source': w.source,
            'notes': w.notes,
            // A diferencia de comidas/actividades (que simplemente dejan de
            // subirse al borrarse), el peso sí escribe `deleted_at`: es lo que
            // permite que un borrado sobreviva a un restore en otro teléfono.
            'deleted_at': w.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      await subir('body_measurements', <Map<String, dynamic>>[
        for (final m in store.measurements)
          <String, dynamic>{
            'id': m.id,
            'user_id': userId,
            'metric': m.metric.wire,
            'value': m.value,
            'unit': m.metric.unit,
            'local_date': isoDate(m.localDate),
            'notes': m.notes,
            // La lápida viaja: sin esto, borrar una medida la sacaba del
            // teléfono y la dejaba viva en la tabla, y la reconciliación
            // siguiente la traía de vuelta. Y `updated_at` es lo que le
            // permite ganar el desempate a la corrección más reciente.
            'updated_at': (m.updatedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      // El agua y el sueño **no se resuelven por id**: ver `_unaPorDia` y el
      // comentario de `onConflict` de arriba. Las dos tablas tienen una segunda
      // clave única `(user_id, local_date)`, y esa es la que manda.
      await subir(
        'water_logs',
        <Map<String, dynamic>>[
          for (final w in _unaPorDia(
            store.waterLogs,
            (w) => w.localDate,
            (w) => w.updatedAt,
          ))
            <String, dynamic>{
              'id': w.id,
              'user_id': userId,
              'local_date': isoDate(w.localDate),
              'glasses': w.glasses,
            },
        ],
        onConflict: 'user_id,local_date',
      );

      await subir(
        'sleep_logs',
        <Map<String, dynamic>>[
          for (final s in _unaPorDia(
            store.sleepLogs,
            (s) => s.localDate,
            (s) => s.loggedAt,
          ))
            <String, dynamic>{
              'id': s.id,
              'user_id': userId,
              'local_date': isoDate(s.localDate),
              'minutes': s.minutes,
              'quality': s.quality.wire,
              'logged_at': s.loggedAt.toUtc().toIso8601String(),
              'notes': s.notes,
              'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
            },
        ],
        onConflict: 'user_id,local_date',
      );

      // ── El contexto del día ─────────────────────────────────────────────
      //
      // `day_markers` es la tabla que **antes se llamaba `rest_days` y no se
      // subía nunca**: existía desde la migración 09, la app guardaba los días
      // de descanso en un `Set` del documento local, y acá no aparecía. Un día
      // marcado en un teléfono no llegaba al siguiente. Ver
      // `docs/contexto-diario.md`.
      //
      // Va con `onConflict` por (usuario, día, tipo) y no por id, por lo mismo
      // que el agua y el sueño: el único de la tabla es ese, así que dos
      // teléfonos que marcaron el mismo día de descanso con ids distintos
      // chocarían contra el índice en vez de pisarse.
      await subir(
        'day_markers',
        <Map<String, dynamic>>[
          for (final m in _unaPorDiaPorTipo(store.dayMarkers))
            <String, dynamic>{
              'id': m.id,
              'user_id': userId,
              'local_date': isoDate(m.localDate),
              'kind': m.kind.wire,
              'severity': m.severity?.level,
              'note': m.note,
              'tags': m.tags,
              'updated_at': m.updatedAt.toUtc().toIso8601String(),
              // La lápida viaja: sin esto, desmarcar un día lo saca del
              // teléfono y lo deja vivo en la tabla, y la reconciliación
              // siguiente lo trae de vuelta.
              'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
            },
        ],
        onConflict: 'user_id,local_date,kind',
      );

      // El alcohol sí se resuelve por id: hay varios consumos por día a
      // propósito, así que no tiene una segunda clave única contra la que
      // chocar.
      await subir('alcohol_logs', <Map<String, dynamic>>[
        for (final a in store.alcoholLogs)
          <String, dynamic>{
            'id': a.id,
            'user_id': userId,
            'local_date': isoDate(a.localDate),
            'drink_type': a.type.wire,
            'quantity': a.quantity,
            'volume_ml': a.volumeMl,
            'abv_pct': a.abvPct,
            'std_drinks': a.standardDrinksTotal,
            'kcal': a.kcal,
            'note': a.note,
            'logged_at': a.loggedAt.toUtc().toIso8601String(),
            'updated_at': a.updatedAt.toUtc().toIso8601String(),
            'deleted_at': a.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      // ── Los recordatorios ───────────────────────────────────────────────
      //
      // Otra tabla que existía desde la migración 22 y no subía nunca. Sin id:
      // el modelo se identifica por (usuario, tipo) y la base pone el uuid, así
      // que el upsert no le reescribe la primary key a la fila en cada subida.
      //
      // Los horarios viajan como minutos desde medianoche, que es como los
      // guarda la columna.
      await subir(
        'reminders',
        <Map<String, dynamic>>[
          for (final r in store.reminders)
            <String, dynamic>{
              'user_id': userId,
              'kind': r.kind.wire,
              'enabled': r.enabled,
              'times': <int>[
                for (final t in r.times) t.hour * 60 + t.minute,
              ],
            },
        ],
        onConflict: 'user_id,kind',
      );

      await subir('activity_goals', <Map<String, dynamic>>[
        for (final g in store.activityGoals)
          <String, dynamic>{
            'id': g.id,
            'user_id': userId,
            'goal_type': g.goalType.wire,
            'target_value': g.targetValue,
            'unit': g.goalType.unit,
            'period': g.period.wire,
            'start_date': isoDate(g.startDate),
            'end_date': g.endDate == null ? null : isoDate(g.endDate!),
            'enabled': g.enabled,
          },
      ]);

      await subir('foods', <Map<String, dynamic>>[
        for (final f in store.userFoods)
          <String, dynamic>{
            'id': f.id,
            'user_id': userId,
            'name': f.name,
            'brand': f.brand,
            'barcode': f.barcode,
            'serving_size': f.servingSize,
            'serving_unit': f.servingUnit,
            'kcal': f.kcal,
            'protein_g': f.proteinG,
            'carbs_g': f.carbsG,
            'fat_g': f.fatG,
            'is_favorite': f.isFavorite,
            'source': 'user',
          },
      ]);

      // Las comidas antes que sus ítems: `meal_items.meal_id` es FK.
      //
      // Las borradas **también suben**, con su lápida. Antes se filtraban con
      // `if (!m.isDeleted)`, así que un borrado se quedaba en el teléfono: la
      // fila seguía viva en la tabla, y como las tablas son la fuente de
      // verdad, la comida volvía entera en un teléfono nuevo o en la web — con
      // la foto ya purgada del bucket, o sea con `photo_path` roto. De paso,
      // `purge_soft_deleted` sobre `meals` era un no-op perpetuo: nunca había
      // una fila con `deleted_at`, así que el servidor se quedaba para siempre
      // con lo que alguien había pedido borrar.
      await subir('meals', <Map<String, dynamic>>[
        for (final m in store.meals)
          <String, dynamic>{
            'id': m.id,
            'user_id': userId,
            'slot': m.slot.wire,
            'eaten_at': m.eatenAt.toUtc().toIso8601String(),
            'local_date': isoDate(m.localDate),
            'name': m.name,
            'total_kcal': m.totalKcal,
            'total_protein_g': m.totalProteinG,
            'total_carbs_g': m.totalCarbsG,
            'total_fat_g': m.totalFatG,
            'source': m.source.wire,
            'photo_path': m.photoPath,
            'notes': m.notes,
            'is_favorite': m.isFavorite,
            // El vínculo con el análisis de IA no viajaba, así que cada vez
            // que la reconciliación traía una comida de vuelta se perdía sin
            // que nada lo dijera.
            'ai_analysis_id': m.aiAnalysisId,
            'updated_at': m.updatedAt.toUtc().toIso8601String(),
            'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      await subir('meal_items', <Map<String, dynamic>>[
        for (final m in store.meals)
          if (!m.isDeleted)
            for (final i in m.items)
              <String, dynamic>{
                'id': i.id,
                'meal_id': m.id,
                'name': i.name,
                'quantity': i.quantity,
                'unit': i.unit,
                'kcal': i.kcal,
                'protein_g': i.proteinG,
                'carbs_g': i.carbsG,
                'fat_g': i.fatG,
                'ai_confidence': i.aiConfidence,
                'was_ai_corrected': i.wasAiCorrected,
                'position': i.position,
                // `food_id` queda en null a propósito: apunta a `foods`, y los
                // ítems que salen del catálogo externo o de la IA no tienen
                // una fila propia ahí. El nombre y los macros son un snapshot,
                // así que la comida se reconstruye igual.
              },
      ]);

      // Y ahora lo que el upsert no puede hacer: **borrar los ítems que ya no
      // están**. Ver `_podarItemsDeComidas`: no es un detalle de higiene, es la
      // diferencia entre editar una comida y clonarla.
      try {
        await _podarItemsDeComidas(store);
      } on PostgrestException catch (error) {
        fallaron['meal_items (limpieza)'] = error.message;
      } on TimeoutException {
        fallaron['meal_items (limpieza)'] = 'tardó demasiado';
      } on Exception catch (error) {
        fallaron['meal_items (limpieza)'] = error.toString();
      }

      // Las actividades al final: necesitan el mapa de tipos.
      final tipos = await _activityTypeIds();
      final custom = tipos['custom'];

      // ── Las plantillas de ejercicio ─────────────────────────────────────
      //
      // Existían desde la migración 09 y se quedaban en el teléfono. Una
      // plantilla que alguien se armó a mano y pierde al cambiar de aparato es
      // de las cosas más molestas de rehacer, que es justo el argumento por el
      // que la tabla se creó.
      //
      // Van acá abajo y no con el resto porque `activity_type_id` es una FK
      // contra el catálogo del servidor, así que necesitan el mismo mapa por
      // slug que las actividades. Una plantilla sobre un tipo que la persona
      // inventó cae en `custom`, igual que su actividad.
      await subir('exercise_templates', <Map<String, dynamic>>[
        for (final t in store.templates)
          if ((tipos[store.typeById(t.activityTypeId)?.slug] ?? custom) != null)
            <String, dynamic>{
              'id': t.id,
              'user_id': userId,
              'name': t.name,
              'activity_type_id':
                  tipos[store.typeById(t.activityTypeId)?.slug] ?? custom,
              'default_duration_minutes': t.defaultDurationMinutes,
              'default_intensity': t.defaultIntensity.wire,
              'default_distance_meters': t.defaultDistanceMeters,
              'default_notes': t.defaultNotes,
              'use_count': t.useCount,
            },
      ]);

      final actividades = <Map<String, dynamic>>[];
      for (final a in store.activities) {
        // Las borradas suben con su lápida, por lo mismo que las comidas: un
        // borrado que no llega al servidor no es un borrado, es un borrado en
        // este teléfono.
        final tipoLocal = store.typeById(a.activityTypeId);
        // Un tipo creado por la persona no existe del lado del servidor: la
        // actividad se apoya en `custom` y el nombre viaja en `custom_name`,
        // que es lo que la app muestra igual.
        final remoteTypeId = tipos[tipoLocal?.slug] ?? custom;
        if (remoteTypeId == null) continue;

        actividades.add(<String, dynamic>{
          'id': a.id,
          'user_id': userId,
          'activity_type_id': remoteTypeId,
          'custom_name': a.customName ?? tipoLocal?.displayName,
          'started_at': a.startedAt.toUtc().toIso8601String(),
          'ended_at': a.endedAt?.toUtc().toIso8601String(),
          'local_date': isoDate(a.localDate),
          'duration_minutes': a.durationMinutes,
          'intensity': a.intensity.wire,
          'distance_meters': a.distanceMeters,
          'steps': a.steps,
          'estimated_calories': a.estimatedCalories,
          'original_calories': a.originalCalories,
          'applied_calories': a.appliedCalories,
          'exercise_credit_percentage': a.exerciseCreditPercentage,
          'estimation_method': a.estimationMethod.wire,
          'met_value': a.metValue,
          'weight_kg_used': a.weightKgUsed,
          'override_reason': a.overrideReason,
          'source_type': a.sourceType.wire,
          'notes': a.notes,
          'is_favorite': a.isFavorite,
          'updated_at': a.updatedAt.toUtc().toIso8601String(),
          'deleted_at': a.deletedAt?.toUtc().toIso8601String(),
        });
      }
      await subir('activities', actividades);

      // Lo que entró, entró. Pero una tabla que no sube es un dato de alguien
      // que no está en la base, así que esto **tiene** que llegar a la pantalla
      // en vez de quedar en un log: el mensaje nombra las tablas.
      if (fallaron.isNotEmpty) {
        final detalle = fallaron.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('; ');
        throw AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos guardar ${fallaron.keys.join(', ')} en la base '
              '($detalle).',
          requestId: fallaron.keys.join(','),
        );
      }

      return escritas;
    } on AppError {
      // Va **primero** y no es decorativo: `AppError implements Exception`, así
      // que sin esta rama el error de arriba —el que nombra las tablas que no
      // subieron y por qué— lo atrapaba el `on Exception` de abajo y salía como
      // "Sin conexión: se guarda cuando vuelva internet".
      //
      // Eso no era un mensaje impreciso, era uno que mentía en las dos mitades:
      // no había problema de conexión, y no se iba a guardar cuando volviera
      // internet porque internet nunca se había ido. Con el respaldo en archivo
      // subiendo bien al lado, la pantalla decía "sin conexión" mientras
      // acababa de subir 176 kB.
      //
      // El resultado es que una tabla podía dejar de sincronizar durante días
      // sin que nada dijera cuál ni por qué, que es exactamente el fallo
      // silencioso que el resto de este archivo se esfuerza en evitar.
      rethrow;
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos guardar en la base (${error.message}).',
        requestId: error.code,
      );
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La base tardó demasiado. Se reintenta con el próximo cambio.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión: se guarda en la base cuando vuelva internet.',
      );
    }
  }

  /// Borra los `meal_items` de la base que ya no están en el teléfono.
  ///
  /// ## El agujero que tapa
  ///
  /// El push es un upsert, y un upsert **agrega y actualiza, nunca borra**. Con
  /// el resto de las tablas eso alcanza porque los borrados viajan como lápida
  /// (`deleted_at`), pero los ítems de una comida no tienen lápida: la comida es
  /// la unidad, y su lista de ítems se reescribe entera en cada guardado.
  ///
  /// El resultado era que cada ítem que dejaba de existir en el teléfono seguía
  /// vivo en la tabla para siempre. Y como el pull reconstruye la comida con
  /// **todas** las filas que tengan su `meal_id`, esos ítems volvían:
  ///
  ///   1. Recalcular una comida con IA le pone ids nuevos a todos sus ítems
  ///      (`recalculate_sheet.dart`), así que el push escribía la generación
  ///      nueva al lado de la vieja: seis filas para una comida de tres ítems.
  ///   2. El pull traía las seis y la comida aparecía duplicada.
  ///   3. Borrar los duplicados en el teléfono no borraba nada del otro lado, y
  ///      el trigger `recalc_meal_totals` le movía `updated_at` a la comida en
  ///      cada escritura de ítems — así que la copia del servidor le ganaba el
  ///      desempate a la local y **la duplicación volvía en cada arranque**.
  ///
  /// Ese bucle es exactamente lo que se reportó: borrar, subir, reabrir y
  /// encontrarla otra vez duplicada. Sacar el ítem del teléfono sin sacarlo de
  /// la tabla no es borrarlo, es esconderlo hasta la próxima reconciliación.
  ///
  /// ## Qué borra y qué no
  ///
  /// Solo filas de comidas que este push **acaba de escribir con sus ítems**:
  /// una comida borrada (que no sube ítems) o una que quedó sin ninguno no entra
  /// en el conjunto, así que sus filas se quedan donde están. De las que sí
  /// entran, se borra lo que no está en el documento local, que es la lista
  /// completa y autoritativa de esa comida.
  ///
  /// Se leen los ids antes de borrar en vez de mandar un `delete ... not in
  /// (...)`: PostgREST codifica el `in` en el **query string**, y con un año de
  /// historial esa URL pasa los 50 kB que aceptan los proxies — el mismo motivo
  /// por el que el pull pide los ítems de a tandas. Leer ids es barato al lado
  /// de lo que este push ya subió, y casi siempre no hay nada que borrar.
  Future<void> _podarItemsDeComidas(LocalStore store) async {
    final vivos = <String>{};
    final comidas = <String>{};
    for (final meal in store.meals) {
      if (meal.isDeleted || meal.items.isEmpty) continue;
      comidas.add(meal.id);
      for (final item in meal.items) {
        vivos.add(item.id);
      }
    }
    if (comidas.isEmpty) return;

    // Sin filtro por comida: la RLS de `meal_items` ya resuelve la pertenencia
    // por la comida padre, así que esto devuelve los del usuario y nada más.
    // El orden por `id` es lo que hace que paginar sea correcto.
    const tamano = 500;
    final sobran = <String>[];
    for (var desde = 0; ; desde += tamano) {
      final pagina = await _db
          .from('meal_items')
          .select('id, meal_id')
          .order('id')
          .range(desde, desde + tamano - 1)
          .timeout(timeout);
      for (final fila in pagina) {
        final id = fila['id'];
        final mealId = fila['meal_id'];
        if (id is! String || mealId is! String) continue;
        if (comidas.contains(mealId) && !vivos.contains(id)) sobran.add(id);
      }
      if (pagina.length < tamano) break;
    }

    if (sobran.isEmpty) return;

    // De a cien: los ids del `in` viajan en la URL, y cien uuids son unos 4 kB.
    const porTanda = 100;
    for (var i = 0; i < sobran.length; i += porTanda) {
      final tanda = sobran.sublist(
        i,
        i + porTanda > sobran.length ? sobran.length : i + porTanda,
      );
      await _db.from('meal_items').delete().inFilter('id', tanda).timeout(
        timeout,
      );
    }
  }

  /// Trae todo lo del usuario **desde las tablas** y lo devuelve con la forma
  /// del documento local.
  ///
  /// Devolver la misma forma que `LocalStore.toDocument()` no es capricho: así
  /// lo consume `restoreDocument`, que ya sabe leer de manera tolerante —un
  /// registro raro se saltea y el resto sobrevive—. Un segundo lector sería un
  /// segundo lugar donde equivocarse.
  ///
  /// Devuelve `null` si la base no tiene nada de este usuario, para que quien
  /// llame pueda distinguir "no hay" de "vino vacío".
  Future<Map<String, dynamic>?> pull({
    required String userId,
    required LocalStore store,
  }) async {
    try {
      final perfil = await _db
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (perfil == null) return null;

      /// Trae una tabla entera, de a páginas.
      ///
      /// PostgREST corta en `max_rows` (1000 por omisión) **sin decir nada**:
      /// no es un error, es un límite, así que una consulta plana devuelve las
      /// primeras mil filas y parece completa. A cuatro comidas por día con
      /// tres ítems cada una, `meal_items` cruza esa marca en unos tres meses
      /// de uso — y desde ahí cada reconciliación reconstruía las comidas con
      /// ítems faltantes contra una base que es la fuente de verdad.
      ///
      /// El orden por `id` es lo que hace que paginar sea correcto: sin un
      /// orden estable, dos páginas pueden repetir y saltear filas.
      Future<List<Map<String, dynamic>>> traer(String tabla) async {
        const tamano = 500;
        final todo = <Map<String, dynamic>>[];
        for (var desde = 0; ; desde += tamano) {
          final pagina = await _db
              .from(tabla)
              .select()
              .eq('user_id', userId)
              .order('id')
              .range(desde, desde + tamano - 1)
              .timeout(timeout);
          todo.addAll(pagina.cast<Map<String, dynamic>>());
          if (pagina.length < tamano) break;
        }
        return todo;
      }

      final goals = await traer('goals');
      final meals = await traer('meals');
      final activities = await traer('activities');
      final weightLogs = await traer('weight_logs');
      final measurements = await traer('body_measurements');
      final waterLogs = await traer('water_logs');
      final sleepLogs = await traer('sleep_logs');
      final dayMarkers = await traer('day_markers');
      final alcoholLogs = await traer('alcohol_logs');
      final activityGoals = await traer('activity_goals');
      final reminders = await traer('reminders');
      final templates = await traer('exercise_templates');
      final foods = await traer('foods');

      // Sin ninguna fila de contenido no hay nada que traer: devolver un
      // documento vacío haría que la app pisara lo local con nada, que es
      // exactamente el modo de falla que ya conocemos.
      final hayContenido = meals.isNotEmpty ||
          activities.isNotEmpty ||
          weightLogs.isNotEmpty ||
          measurements.isNotEmpty ||
          waterLogs.isNotEmpty ||
          sleepLogs.isNotEmpty ||
          dayMarkers.isNotEmpty ||
          alcoholLogs.isNotEmpty ||
          foods.isNotEmpty;
      if (!hayContenido) return null;

      // Los ítems, de a tandas de comidas.
      //
      // Antes se pedían todos de una con un `inFilter` sobre la lista completa
      // de ids. PostgREST codifica eso como `in.(...)` en el **query string**
      // de un GET, así que la URL crece con el historial: un año de uso son
      // ~1.400 uuids, más de 50 kB de URL, bastante por encima de lo que
      // aceptan los proxies. El pull entero fallaba, `refresh` devolvía false
      // en silencio y el teléfono dejaba de reconciliar — justo en las cuentas
      // con más datos, que son las que más lo necesitan.
      //
      // De a **cien**, como la poda del push, y no de a doscientos. Cada id
      // viaja entre comillas codificadas (`%22…%22`): doscientos eran ~8,7 kB
      // de URL, justo arriba de los 8 kB que acepta el Kong de una base
      // Supabase local. Ahí el pull moría con "URI too long", en silencio, y
      // la cuenta entraba al alta como si no tuviera nada. Producción tolera
      // más, pero no hay razón para depender de eso.
      final itemsPorComida = <String, List<Map<String, dynamic>>>{};
      const porTanda = 100;
      final idsDeComidas = meals.map((m) => m['id'] as String).toList();
      for (var i = 0; i < idsDeComidas.length; i += porTanda) {
        final tanda = idsDeComidas.sublist(
          i,
          i + porTanda > idsDeComidas.length ? idsDeComidas.length : i + porTanda,
        );
        // El orden importa y no es cosmético: `itemsDeLaComida` resuelve las
        // posiciones repetidas quedándose con la última fila, y "la última" solo
        // quiere decir algo si vienen de la más vieja a la más nueva.
        //
        // ⚠️ `ascending: true` explícito: `order` de postgrest-dart ordena
        // **descendente por omisión**. Sin esto la generación vieja quedaría
        // última, ganaría el desempate, y la poda del push borraría del servidor
        // justo la corregida — el bug al revés y sin vuelta atrás.
        final items = await _db
            .from('meal_items')
            .select()
            .inFilter('meal_id', tanda)
            .order('updated_at', ascending: true)
            .order('id', ascending: true)
            .timeout(timeout);
        for (final item in items) {
          (itemsPorComida[item['meal_id'] as String] ??=
                  <Map<String, dynamic>>[])
              .add(item);
        }
      }

      // Del id remoto de tipo al id local, pasando por el slug: son dos
      // catálogos distintos que solo comparten esa clave.
      final tipos = await _activityTypeIds();
      final slugPorId = <String, String>{
        for (final e in tipos.entries) e.value: e.key,
      };

      /// Un `timestamptz` de PostgREST, pasado a la hora local del teléfono.
      ///
      /// Vuelven en UTC (`2026-07-31T16:30:00+00:00`) y el documento guarda las
      /// fechas en hora local y sin desfase, que es lo que escribe la app. Sin
      /// convertir acá, `DateTime.parse` dejaba un `DateTime` en UTC y las
      /// pantallas lo formateaban tal cual: **un almuerzo registrado 13:30 se
      /// mostraba 16:30** en cuanto la reconciliación traía esa comida de
      /// vuelta. Y `duplicateMeal` copiaba esa hora corrida a la comida nueva.
      String isoOf(Object? v) {
        if (v == null) return '';
        final parsed = DateTime.tryParse(v.toString());
        return parsed == null ? v.toString() : parsed.toLocal().toIso8601String();
      }

      return <String, dynamic>{
        'schemaVersion': LocalStore.schemaVersion,
        'profile': <String, dynamic>{
          'id': userId,
          'displayName': perfil['display_name'],
          'biologicalSex': perfil['biological_sex'],
          'birthDate': perfil['birth_date'] == null
              ? null
              : '${perfil['birth_date']}T00:00:00.000',
          'heightCm': perfil['height_cm'],
          'activityLevel': perfil['activity_level'],
          'timezone': perfil['timezone'],
          'unitSystem': perfil['unit_system'],
          'themeMode': perfil['theme_mode'],
          'locale': perfil['locale'],
          'exerciseCreditPercentage': perfil['exercise_credit_percentage'],
          'exerciseCreditEnabled': perfil['exercise_credit_enabled'],
          'showNetCalories': perfil['show_net_calories'],
          // Una fila escrita por una versión anterior no trae la columna: se
          // resuelve como lista vacía, no como error.
          'dietaryFlags': <String>[
            for (final f in (perfil['dietary_flags'] as List<dynamic>? ??
                const <dynamic>[]))
              if (f is String) f,
          ],
          'dietaryNote': perfil['dietary_note'] ?? '',
          'isDemo': false,
          'createdAt': isoOf(perfil['created_at']),
          'updatedAt': isoOf(perfil['updated_at']),
        },
        'goals': <Map<String, dynamic>>[
          for (final g in goals)
            <String, dynamic>{
              'id': g['id'],
              'goalType': g['goal_type'],
              'rateKgPerWeek': g['rate_kg_per_week'],
              'targetWeightKg': g['target_weight_kg'],
              'baseCalorieTarget': g['base_calorie_target'],
              'targetMethod': g['target_method'],
              'bmrKcal': g['bmr_kcal'],
              'tdeeKcal': g['tdee_kcal'],
              'proteinG': g['protein_g'],
              'carbsG': g['carbs_g'],
              'fatG': g['fat_g'],
              'macroMethod': g['macro_method'],
              'startsOn': g['starts_on'],
              'endsOn': g['ends_on'],
              'updatedAt': isoOf(g['updated_at']),
            },
        ],
        'meals': <Map<String, dynamic>>[
          for (final m in meals)
            <String, dynamic>{
              'id': m['id'],
              'slot': m['slot'],
              'eatenAt': isoOf(m['eaten_at']),
              'localDate': m['local_date'],
              'name': m['name'],
              'source': m['source'],
              'photoPath': m['photo_path'],
              'notes': m['notes'],
              'isFavorite': m['is_favorite'],
              'aiAnalysisId': m['ai_analysis_id'],
              'syncStatus': 'synced',
              'createdAt': isoOf(m['created_at']),
              'updatedAt': isoOf(m['updated_at']),
              // Sin mapear la lápida, una comida borrada desde otro
              // dispositivo volvía viva en cada reconciliación.
              'deletedAt': m['deleted_at'] == null
                  ? null
                  : isoOf(m['deleted_at']),
              'items': <Map<String, dynamic>>[
                for (final i in itemsDeLaComida(
                  itemsPorComida[m['id']] ?? const <Map<String, dynamic>>[],
                ))
                  <String, dynamic>{
                    'id': i['id'],
                    'name': i['name'],
                    'quantity': i['quantity'],
                    'unit': i['unit'],
                    'kcal': i['kcal'],
                    'proteinG': i['protein_g'],
                    'carbsG': i['carbs_g'],
                    'fatG': i['fat_g'],
                    'aiConfidence': i['ai_confidence'],
                    'wasAiCorrected': i['was_ai_corrected'],
                    'position': i['position'],
                  },
              ],
            },
        ],
        'activities': <Map<String, dynamic>>[
          for (final a in activities)
            if (store.typeBySlug(slugPorId[a['activity_type_id']] ?? '') != null)
              <String, dynamic>{
                'id': a['id'],
                'activityTypeId': store
                    .typeBySlug(slugPorId[a['activity_type_id']] ?? '')!
                    .id,
                'customName': a['custom_name'],
                'startedAt': isoOf(a['started_at']),
                'endedAt': a['ended_at'] == null ? null : isoOf(a['ended_at']),
                'localDate': a['local_date'],
                'durationMinutes': a['duration_minutes'],
                'intensity': a['intensity'],
                'distanceMeters': a['distance_meters'],
                'steps': a['steps'],
                'estimatedCalories': a['estimated_calories'],
                'originalCalories': a['original_calories'],
                'appliedCalories': a['applied_calories'],
                'exerciseCreditPercentage': a['exercise_credit_percentage'],
                'estimationMethod': a['estimation_method'],
                'metValue': a['met_value'],
                'weightKgUsed': a['weight_kg_used'],
                'overrideReason': a['override_reason'],
                'sourceType': a['source_type'],
                'notes': a['notes'],
                'isFavorite': a['is_favorite'],
                'syncStatus': 'synced',
                'createdAt': isoOf(a['created_at']),
                'updatedAt': isoOf(a['updated_at']),
                'deletedAt': a['deleted_at'] == null
                    ? null
                    : isoOf(a['deleted_at']),
              },
        ],
        'weightLogs': <Map<String, dynamic>>[
          for (final w in weightLogs)
            <String, dynamic>{
              'id': w['id'],
              'weightKg': w['weight_kg'],
              'localDate': w['local_date'],
              'loggedAt': isoOf(w['logged_at']),
              'source': w['source'],
              'notes': w['notes'],
              'syncStatus': 'synced',
              'deletedAt': w['deleted_at'] == null
                  ? null
                  : isoOf(w['deleted_at']),
            },
        ],
        'measurements': <Map<String, dynamic>>[
          for (final m in measurements)
            <String, dynamic>{
              'id': m['id'],
              'metric': m['metric'],
              'value': m['value'],
              'localDate': m['local_date'],
              'notes': m['notes'],
              'updatedAt': isoOf(m['updated_at']),
              'deletedAt': m['deleted_at'] == null
                  ? null
                  : isoOf(m['deleted_at']),
            },
        ],
        'waterLogs': <Map<String, dynamic>>[
          for (final w in waterLogs)
            <String, dynamic>{
              'id': w['id'],
              'localDate': w['local_date'],
              'glasses': w['glasses'],
              'updatedAt': isoOf(w['updated_at']),
              'syncStatus': 'synced',
            },
        ],
        'sleepLogs': <Map<String, dynamic>>[
          for (final s in sleepLogs)
            <String, dynamic>{
              'id': s['id'],
              'localDate': s['local_date'],
              'minutes': s['minutes'],
              'quality': s['quality'],
              'loggedAt': isoOf(s['logged_at']),
              'notes': s['notes'],
              'syncStatus': 'synced',
              'deletedAt': s['deleted_at'] == null
                  ? null
                  : isoOf(s['deleted_at']),
            },
        ],
        'dayMarkers': <Map<String, dynamic>>[
          for (final m in dayMarkers)
            <String, dynamic>{
              'id': m['id'],
              'localDate': m['local_date'],
              'kind': m['kind'],
              'severity': m['severity'],
              'note': m['note'],
              'tags': <String>[
                for (final t in (m['tags'] as List<dynamic>? ?? <dynamic>[]))
                  t.toString(),
              ],
              'updatedAt': isoOf(m['updated_at']),
              'syncStatus': 'synced',
              'deletedAt': m['deleted_at'] == null
                  ? null
                  : isoOf(m['deleted_at']),
            },
        ],
        'alcoholLogs': <Map<String, dynamic>>[
          for (final a in alcoholLogs)
            <String, dynamic>{
              'id': a['id'],
              'localDate': a['local_date'],
              'type': a['drink_type'],
              // `numeric` vuelve como String en PostgREST, no como número: sin
              // el `num.tryParse` esto entra al modelo como null y una copa de
              // vino se convierte en cero tragos al reconciliar.
              'quantity': _numero(a['quantity']) ?? 1,
              'volumeMl': (_numero(a['volume_ml']) ?? 0).toInt(),
              'abvPct': _numero(a['abv_pct']) ?? 0,
              'note': a['note'],
              'loggedAt': isoOf(a['logged_at']),
              'updatedAt': isoOf(a['updated_at']),
              'syncStatus': 'synced',
              'deletedAt': a['deleted_at'] == null
                  ? null
                  : isoOf(a['deleted_at']),
            },
        ],
        'reminders': <Map<String, dynamic>>[
          for (final r in reminders)
            <String, dynamic>{
              'kind': r['kind'],
              'enabled': r['enabled'],
              // La columna guarda minutos desde medianoche; el modelo, hora y
              // minuto por separado.
              'times': <Map<String, dynamic>>[
                for (final m in (r['times'] as List<dynamic>? ?? <dynamic>[]))
                  <String, dynamic>{
                    'hour': (m as num).toInt() ~/ 60,
                    'minute': m.toInt() % 60,
                  },
              ],
            },
        ],
        'templates': <Map<String, dynamic>>[
          for (final t in templates)
            <String, dynamic>{
              'id': t['id'],
              'name': t['name'],
              // El id del tipo vuelve traducido a slug: es la misma clave con
              // la que la app resuelve sus tipos locales, y el uuid del
              // servidor no significa nada de este lado.
              'activityTypeId':
                  slugPorId[t['activity_type_id']] ?? 'custom',
              'defaultDurationMinutes': t['default_duration_minutes'],
              'defaultIntensity': t['default_intensity'],
              'defaultDistanceMeters': t['default_distance_meters'],
              'defaultNotes': t['default_notes'],
              'useCount': t['use_count'],
            },
        ],
        'activityGoals': <Map<String, dynamic>>[
          for (final g in activityGoals)
            <String, dynamic>{
              'id': g['id'],
              'goalType': g['goal_type'],
              'targetValue': (g['target_value'] as num).toInt(),
              'period': g['period'],
              'startDate': g['start_date'],
              'endDate': g['end_date'],
              'enabled': g['enabled'],
            },
        ],
        'userFoods': <Map<String, dynamic>>[
          for (final f in foods)
            <String, dynamic>{
              'id': f['id'],
              'name': f['name'],
              'brand': f['brand'],
              'barcode': f['barcode'],
              'source': 'user',
              'servingSize': f['serving_size'],
              'servingUnit': f['serving_unit'],
              'kcal': f['kcal'],
              'proteinG': f['protein_g'],
              'carbsG': f['carbs_g'],
              'fatG': f['fat_g'],
              'isFavorite': f['is_favorite'],
            },
        ],
      };
    } on AppError {
      // Por lo mismo que en `push`: un `AppError` que naciera acá adentro se
      // convertiría en "sin conexión" y perdería lo que sabía.
      rethrow;
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos leer tus datos de la base (${error.message}).',
      );
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La base tardó demasiado en responder.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión: no pudimos traer tus datos de la base.',
      );
    }
  }

  // `counts` se fue junto con el botón de Comparar que lo usaba: nueve
  // consultas contra el servidor cuyo único destino era una pantalla que le
  // pedía a quien usa la app que interpretara dos columnas de números.
}

/// Los ítems de una comida, ordenados y **sin la generación vieja**.
///
/// Dos cosas, y las dos por el mismo motivo.
///
/// **Ordena por posición**, que es lo que la lista del documento significa: las
/// filas volvían en el orden en que las devolviera la base, así que una comida
/// reconstruida podía mostrar el postre antes del plato.
///
/// **Y se queda con una sola fila por posición.** Dos ítems con la misma
/// posición es un estado que la app no puede generar —`MealDraft.toMeal` y
/// `replaceAnalysis` las renumeran 0..n-1 en cada guardado—, así que solo sale
/// de tener dos generaciones de ítems conviviendo en la tabla: lo que dejaba el
/// push cuando todavía no borraba lo que sobraba (ver `_podarItemsDeComidas`).
/// Gana la última, y como las filas vienen ordenadas por `updated_at` esa es la
/// que se tocó más recientemente — la corregida, no la que se corrigió.
///
/// Las dos mitades del arreglo se necesitan: sin podar, esto esconde el
/// duplicado y vuelve a aparecer; sin esto, una cuenta que ya quedó con las dos
/// generaciones adentro se queda así hasta que alguien las borre a mano. Con las
/// dos, el pull elige y el push siguiente borra del servidor la que perdió.
@visibleForTesting
List<Map<String, dynamic>> itemsDeLaComida(List<Map<String, dynamic>> filas) {
  final porPosicion = <int, Map<String, dynamic>>{};
  // Una fila sin posición legible no se puede aparear con nada. Se conserva:
  // descartarla sería perder un ítem por venir mal formada.
  final sinPosicion = <Map<String, dynamic>>[];

  for (final fila in filas) {
    final posicion = fila['position'];
    if (posicion is int) {
      porPosicion[posicion] = fila;
    } else {
      sinPosicion.add(fila);
    }
  }

  final posiciones = porPosicion.keys.toList()..sort();
  return <Map<String, dynamic>>[
    for (final p in posiciones) porPosicion[p]!,
    ...sinPosicion,
  ];
}

/// Un solo registro por día, el más reciente.
///
/// `water_logs` y `sleep_logs` son las dos tablas con una segunda clave única
/// —`(user_id, local_date)`— además de la primary key, y con `onConflict`
/// apuntando a esa clave **mandar dos filas del mismo día rompe el upsert
/// entero**: Postgres contesta "ON CONFLICT DO UPDATE command cannot affect row
/// a second time".
///
/// Y el mismo día con dos filas es un estado que ocurre de verdad, no una
/// hipótesis: la reconciliación (`document_merge.dart`) une las listas **por
/// id**, así que si la fila del servidor y la local tienen ids distintos para
/// el mismo día, las dos sobreviven. Que los ids difieran tampoco es raro:
/// `_dailyId` los deriva de la identidad de la cuenta, que cambia al iniciar
/// sesión, y `repararRegistrosViejos` regeneró a propósito los del agua.
///
/// Se queda con el más reciente porque es el que la persona vio último en la
/// pantalla. Esto no arregla el documento local —de eso se ocupa la reparación
/// del repositorio—, solo evita que un duplicado tire abajo la subida.
Iterable<T> _unaPorDia<T>(
  Iterable<T> items,
  DateTime Function(T) dia,
  DateTime Function(T) marca,
) {
  final porDia = <String, T>{};
  for (final item in items) {
    final clave = isoDate(dia(item));
    final actual = porDia[clave];
    if (actual == null || marca(item).isAfter(marca(actual))) {
      porDia[clave] = item;
    }
  }
  return porDia.values;
}

/// Un `numeric` de PostgREST, que vuelve como String y no como número.
///
/// `quantity`, `abv_pct` y `std_drinks` son `numeric` en la tabla, y postgrest
/// los serializa a texto para no perder precisión. Un cast directo a `num`
/// devuelve null y el modelo se queda con el default, así que una copa de vino
/// entraba como cero tragos en la reconciliación siguiente.
double? _numero(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Lo mismo que [_unaPorDia], pero la clave es **(día, tipo)**.
///
/// `day_markers` tiene ese único y no el del día solo: el mismo día puede ser
/// de descanso y de enfermedad a la vez, que es justamente el caso interesante.
/// Sin partir por tipo, subir un día con las dos marcas mandaría dos filas que
/// el upsert no distingue y rompería el lote entero.
Iterable<DayMarker> _unaPorDiaPorTipo(Iterable<DayMarker> marcas) {
  final porClave = <String, DayMarker>{};
  for (final m in marcas) {
    final clave = '${isoDate(m.localDate)}|${m.kind.wire}';
    final actual = porClave[clave];
    if (actual == null || m.updatedAt.isAfter(actual.updatedAt)) {
      porClave[clave] = m;
    }
  }
  return porClave.values;
}
