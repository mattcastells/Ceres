// Que ningún valor que la app puede mandar sea rechazado por la base.
//
// Este test existe por un día entero de datos que no llegaron. Dos
// restricciones habían quedado atrás de sus enums:
//
//   goals_type   check (goal_type in ('lose', 'maintain', 'gain'))
//   meals_source check (source in ('manual','ai_photo','barcode','duplicate'))
//
// Mientras tanto Dart ya tenía `gainMuscle('gain_muscle')` —uno de los cuatro
// objetivos que ofrece la app— y `aiText('ai_text')` —lo que graba estimar una
// comida escribiéndola—. Cada fila con esos valores era rechazada por Postgres,
// y como `RelationalSyncClient.push` sube cada tabla en un solo `upsert`, **una
// fila mala tiraba el lote entero**; como además todas las tablas comparten un
// `try`, la excepción se llevaba puestas las nueve tablas siguientes. El error
// terminaba en un `SyncFailed` que ninguna pantalla mostraba, así que la base
// quedó sin una sola comida durante meses sin que nada fallara a la vista.
//
// El problema no es que a dos restricciones les faltara un valor: es que
// agregar un valor a un enum de Dart y no tocar el SQL no rompía nada visible.
// Esto lo rompe acá, en un test que corre en cada push.
//
// **Cómo se agrega una columna nueva con valores fijos**: sumarla a
// `_escribeLaApp` si la sube el cliente, o a `_noLasEscribeLaApp` si no. El
// test falla si aparece una restricción que no está en ninguna de las dos, así
// que la decisión no se puede saltear por olvido.

import 'dart:io';

import 'package:ceres/domain/calculations/alcohol.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/day_marker.dart';
import 'package:ceres/domain/models/sleep.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las restricciones de valores fijos sobre columnas que **sube el cliente**
/// (`RelationalSyncClient.push`), con el enum de Dart que las alimenta.
///
/// Si un valor del enum no está en la lista del `check`, la fila se rechaza.
final Map<String, List<String>> _escribeLaApp = <String, List<String>>{
  // profiles
  'profiles_biological_sex': BiologicalSex.values.map((e) => e.wire).toList(),
  'profiles_activity_level': ActivityLevel.values.map((e) => e.wire).toList(),
  'profiles_unit_system': UnitSystem.values.map((e) => e.wire).toList(),
  'profiles_theme_mode': ThemeModeSetting.values.map((e) => e.wire).toList(),

  // goals
  'goals_type': GoalType.values.map((e) => e.wire).toList(),
  'goals_method': TargetMethod.values.map((e) => e.wire).toList(),

  // meals
  'meals_slot': MealSlot.values.map((e) => e.wire).toList(),
  'meals_source': MealSource.values.map((e) => e.wire).toList(),
  'meals_sync_status': SyncStatus.values.map((e) => e.wire).toList(),

  // activities
  'activities_intensity': Intensity.values.map((e) => e.wire).toList(),
  'activities_source_type':
      ActivitySourceType.values.map((e) => e.wire).toList(),
  'activities_method': EstimationMethod.values.map((e) => e.wire).toList(),
  'activities_sync_status': SyncStatus.values.map((e) => e.wire).toList(),

  // el resto del contenido del usuario
  'body_measurements_metric':
      MeasurementMetric.values.map((e) => e.wire).toList(),
  // El cliente no manda la unidad suelta: manda `m.metric.unit`, así que la
  // restricción tiene que aceptar todas las unidades que exista alguna métrica.
  'body_measurements_unit':
      MeasurementMetric.values.map((e) => e.unit).toSet().toList(),
  'sleep_logs_quality_valid': SleepQuality.values.map((e) => e.wire).toList(),
  'activity_goals_type': ActivityGoalType.values.map((e) => e.wire).toList(),
  'activity_goals_period': GoalPeriod.values.map((e) => e.wire).toList(),
  'weight_logs_sync_status': SyncStatus.values.map((e) => e.wire).toList(),

  // El contexto del día. Las dos las sube el cliente: la marca sale de
  // `DayMarkerKind` y la bebida de `DrinkType`, así que agregar un valor a
  // cualquiera de los dos enums sin tocar la migración 40 tiene que romper acá
  // y no en silencio contra la base.
  'day_markers_kind': DayMarkerKind.values.map((e) => e.wire).toList(),
  'alcohol_logs_type': DrinkType.values.map((e) => e.wire).toList(),

  // Las plantillas pasaron a subirse con la migración 44: existían desde la 09
  // y se quedaban en el teléfono. Por eso esta restricción se movió de la lista
  // de abajo a esta.
  'exercise_templates_intensity':
      Intensity.values.map((e) => e.wire).toList(),
};

/// Restricciones de valores fijos que la app **no** escribe: las llena el
/// servidor, una migración, o son de tablas que el cliente no sube.
///
/// Están listadas para que el test pueda exigir que toda restricción nueva pase
/// por una de las dos listas. Si mañana el cliente empieza a subir una de
/// estas, hay que moverla arriba — y este comentario es el aviso.
const Set<String> _noLasEscribeLaApp = <String>{
  'activities_deletion_reason',
  'activity_goals_unit',
  'activity_types_category',
  'ai_analyses_source',
  'ai_analyses_status',
  'audit_log_action',
  'audit_log_actor',
  // El estado del acceso profesional lo pone el servidor: la app llama a
  // `grant_care_access` / `revoke_care_access` y nunca manda el literal.
  'care_grants_status',
  'foods_source', // el cliente manda 'user' fijo, no el enum
  'goals_macro_method',
  'pals_status',
  'weight_logs_source',
};

/// `constraint <nombre> check (<columna> in ('a', 'b', …))`, en una o varias
/// líneas. Los rangos (`between`, `>`) no matchean y quedan afuera, que es lo
/// correcto: acá solo se comparan listas de valores fijos.
final RegExp _constraintConIn = RegExp(
  r"constraint\s+(\w+)\s+check\s*\(\s*\w+\s+in\s*\(([^)]*)\)",
  multiLine: true,
);

/// `drop table [if exists] public.X` — la tabla que una migración se lleva.
///
/// Hace falta porque este archivo lee **el texto de las migraciones**, no la
/// base: una tabla borrada en la 43 sigue teniendo su `create table` escrito en
/// la 11, así que sus restricciones se siguen encontrando. Sin esto, cada
/// limpieza obligaba a dejar los nombres de tablas muertas en una de las dos
/// listas de arriba para que el test no fallara — que es exactamente el residuo
/// que la limpieza venía a sacar.
final RegExp _dropTable = RegExp(
  r'drop\s+table\s+(?:if\s+exists\s+)?public\.(\w+)',
  multiLine: true,
);

/// `alter table public.X rename to Y`. El nombre viejo deja de existir, y con
/// él sus restricciones: `rest_days_uniq` no se puede clasificar después de que
/// la migración 40 renombrara la tabla a `day_markers`.
final RegExp _renameTable = RegExp(
  r'alter\s+table\s+public\.(\w+)\s+rename\s+to\s+(\w+)',
  multiLine: true,
);

Map<String, Set<String>> _leerRestricciones() {
  final dir = Directory('supabase/migrations');
  final encontradas = <String, Set<String>>{};

  /// Las tablas que ya no existen al final de todas las migraciones.
  final desaparecidas = <String>{};

  // **Ordenadas por nombre**, que en este esquema es el orden en que se
  // aplican. `listSync()` devuelve lo que le da el sistema de archivos: NTFS
  // lo entrega alfabético y en Windows esto pasaba siempre, pero ext4 usa un
  // hash del directorio y el orden es arbitrario. Como el hash depende de los
  // nombres, **cada migración nueva vuelve a sortear**, y ahí el test se
  // volvía verde o rojo sin que nadie tocara una restricción: bastaba con
  // agregar un archivo. Cinco de estas restricciones las redefine una
  // migración posterior agregando valores —`goals_type` suma `gain_muscle`,
  // `goals_method` suma `ai`, `meals_source` suma `ai_text`—, así que leer la
  // vieja al final deja al test creyendo que la base rechaza algo que acepta.
  final archivos = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in archivos) {
    if (!file.path.endsWith('.sql')) continue;

    // Los comentarios `--` se sacan **antes** de juntar las líneas. Al revés,
    // un comentario adentro de una lista de valores se pega al valor que le
    // sigue —"-- perímetros, en cm 'arm_flexed'"— y ese valor deja de matchear:
    // el test reportaría que falta algo que sí está. Pasó en el primer intento.
    final sql = file
        .readAsStringSync()
        .split('\n')
        .map((linea) {
          final comentario = linea.indexOf('--');
          return comentario < 0 ? linea : linea.substring(0, comentario);
        })
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final match in _constraintConIn.allMatches(sql)) {
      final nombre = match.group(1)!;
      final valores = match
          .group(2)!
          .split(',')
          .map((v) => v.trim().replaceAll("'", ''))
          .where((v) => v.isNotEmpty)
          .toSet();
      // Una migración posterior puede reemplazar una restricción: gana la
      // última, que es como las aplica Postgres.
      encontradas[nombre] = valores;
    }

    // El orden importa: una tabla se puede crear, borrar y volver a crear, y
    // los archivos se recorren en el orden en que se aplican.
    for (final match in _dropTable.allMatches(sql)) {
      desaparecidas.add(match.group(1)!);
    }
    for (final match in _renameTable.allMatches(sql)) {
      desaparecidas.add(match.group(1)!);
      desaparecidas.remove(match.group(2)!);
    }
    for (final match in RegExp(
      r'create\s+table\s+(?:if\s+not\s+exists\s+)?public\.(\w+)',
    ).allMatches(sql)) {
      desaparecidas.remove(match.group(1)!);
    }
  }

  // Las restricciones de una tabla que ya no está no se clasifican: no hay
  // nada que pueda rechazar una fila. Se identifican por prefijo, que es la
  // convención de nombres de todo el esquema (`meals_slot`, `pals_status`).
  encontradas.removeWhere(
    (nombre, _) => desaparecidas.any((t) => nombre.startsWith('${t}_')),
  );

  return encontradas;
}

void main() {
  late Map<String, Set<String>> restricciones;

  setUpAll(() {
    restricciones = _leerRestricciones();
    expect(
      restricciones,
      isNotEmpty,
      reason: 'no se leyó ninguna migración: ¿cambió supabase/migrations/?',
    );
  });

  group('la base acepta todo lo que la app manda', () {
    for (final entry in _escribeLaApp.entries) {
      test(entry.key, () {
        final aceptados = restricciones[entry.key];
        expect(
          aceptados,
          isNotNull,
          reason:
              'la restricción `${entry.key}` ya no está en las migraciones. Si '
              'se renombró, actualizar este test; si se borró, sacarla de la '
              'lista.',
        );

        final rechazados =
            entry.value.where((v) => !aceptados!.contains(v)).toList();
        expect(
          rechazados,
          isEmpty,
          reason:
              'Postgres va a rechazar ${rechazados.join(', ')} en '
              '`${entry.key}`. Y no rechaza solo esa fila: el `upsert` sube la '
              'tabla entera en un lote, así que se pierde toda, y con ella las '
              'tablas que van después en `RelationalSyncClient.push`. Hace '
              'falta una migración que agregue el valor a la restricción.',
        );
      });
    }
  });

  test('toda restricción de valores fijos está clasificada', () {
    // La red que atrapa lo que el resto del test no puede ver: una tabla nueva
    // con una columna de valores fijos que nadie registró acá.
    final sinClasificar = restricciones.keys
        .where(
          (c) =>
              !_escribeLaApp.containsKey(c) && !_noLasEscribeLaApp.contains(c),
        )
        .toList()
      ..sort();

    expect(
      sinClasificar,
      isEmpty,
      reason:
          'Restricciones nuevas sin clasificar: ${sinClasificar.join(', ')}.\n'
          'Si el cliente sube esa columna, agregala a `_escribeLaApp` con su '
          'enum. Si no, a `_noLasEscribeLaApp`. La decisión es a mano a '
          'propósito: es la que no se tomó las dos veces que esto falló.',
    );
  });
}
