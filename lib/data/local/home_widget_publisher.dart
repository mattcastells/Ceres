import 'package:flutter/services.dart';

import '../../core/utils/dates.dart';
import '../../core/utils/formats.dart';
import '../../domain/models/summaries.dart';
import '../../domain/models/water.dart';

/// Publica el día para el widget de la pantalla de inicio del teléfono.
///
/// El widget vive fuera del proceso de la app —es un `RemoteViews` que dibuja
/// el launcher, y se dibuja también con la app cerrada—, así que no puede
/// preguntarle nada a Dart. Lo que hay es un dato guardado: acá se escribe y en
/// Kotlin se lee.
///
/// **Se manda texto ya formateado, no números.** El widget no reimplementa el
/// formato de miles ni la redacción: "1.234" y "Te quedan" salen de `Fmt` y de
/// las mismas palabras que usa Inicio, así que no pueden desincronizarse. Las
/// dos excepciones son cuentas, no números formateados: los vasos de agua y el
/// porcentaje de cada macro, porque de eso el widget decide **cuánto dibuja**
/// (cuántas gotas, cuánta barra), no cómo se escribe.
class HomeWidgetPublisher {
  const HomeWidgetPublisher();

  static const MethodChannel _channel = MethodChannel(
    'io.ceres.app/widget',
  );

  /// Escribe el estado del día y le pide al sistema que redibuje el widget.
  ///
  /// Nunca lanza. Un widget que no se actualiza es una molestia; un registro de
  /// comida que falla porque el widget no se pudo actualizar sería un error de
  /// prioridades. En una plataforma sin el canal nativo (o en los tests) es un
  /// no-op silencioso.
  Future<void> publish(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
    int? sleepMinutes,
    Set<String> daysWithRecords = const <String>{},
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'publish',
        _payload(
          summary,
          glasses: glasses,
          waterGoal: waterGoal,
          sleepMinutes: sleepMinutes,
          daysWithRecords: daysWithRecords,
        ),
      );
    } on MissingPluginException {
      // Sin lado nativo: no hay widget que actualizar.
    } on PlatformException {
      // Ídem. No hay nada que reintentar ni nada que contarle a nadie.
    }
  }

  /// Los vasos que se sumaron tocando el widget y todavía no están registrados,
  /// por fecha. Los devuelve **y los borra**: quien llama tiene que aplicarlos.
  ///
  /// El widget no puede escribir en la base de la app. Podría —las
  /// preferencias son las mismas— y sería un error grave: los datos viven en un
  /// único documento JSON, así que un proceso de fondo que lo lea y lo reescriba
  /// puede pisar comidas cargadas mientras tanto. No es un riesgo teórico: este
  /// proyecto ya perdió los datos de alguien por una escritura así.
  ///
  /// Entonces el toque solo **anota su intención** de un lado (fecha y delta) y
  /// la app la aplica cuando corre, que es la única que sabe escribir el
  /// documento. El widget muestra lo guardado más lo pendiente, así que el
  /// número que se ve siempre es el que la persona tocó.
  Future<Map<DateTime, int>> drainPendingWater() async {
    try {
      final raw = await _channel.invokeMapMethod<String, int>(
        'drainPendingWater',
      );
      if (raw == null) return const <DateTime, int>{};
      return <DateTime, int>{
        for (final entry in raw.entries)
          if (DateTime.tryParse(entry.key) != null)
            DateTime.parse(entry.key): entry.value,
      };
    } on MissingPluginException {
      return const <DateTime, int>{};
    } on PlatformException {
      return const <DateTime, int>{};
    }
  }

  /// Lo que ve el widget. Público para poder verificarlo sin plataforma nativa
  /// de por medio: es donde vive la decisión de qué se muestra.
  static Map<String, Object> payloadFor(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
    int? sleepMinutes,
    Set<String> daysWithRecords = const <String>{},
  }) => _payload(
    summary,
    glasses: glasses,
    waterGoal: waterGoal,
    sleepMinutes: sleepMinutes,
    daysWithRecords: daysWithRecords,
  );

  /// Días seguidos con al menos un registro, contando desde [from] hacia atrás.
  ///
  /// **Si hoy todavía no tiene nada, la racha no se corta**: se cuenta desde
  /// ayer. Cortarla a las 00:01 sería castigar a alguien por no haber
  /// desayunado todavía, y una racha que se pierde durmiendo deja de ser algo
  /// que se quiera mirar.
  ///
  /// Una racha de un solo día no es una racha: quien llama decide si la muestra.
  static int streakDays(Set<String> daysWithRecords, DateTime from) {
    var day = dateOnly(from);
    if (!daysWithRecords.contains(isoDate(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (daysWithRecords.contains(isoDate(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static Map<String, Object> _payload(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
    int? sleepMinutes,
    Set<String> daysWithRecords = const <String>{},
  }) {
    final balance = summary.balance;
    final remaining = balance.remainingKcal;
    final hasTarget = summary.baseTarget > 0;
    final target = balance.adjustedTarget;
    final streak = streakDays(daysWithRecords, summary.date);

    return <String, Object>{
      'date': isoDate(summary.date),

      // ── Calorías ──────────────────────────────────────────────────────
      // Sin objetivo cargado, "te quedan −1.123" sería un número inventado: el
      // widget dice que falta configurarlo y manda a la app.
      'value': hasTarget ? Fmt.integer(remaining.abs()) : '—',
      // Las mismas palabras que la tarjeta de Inicio y el anillo (D-17): el
      // exceso se cuenta, no se reta.
      'label': hasTarget
          ? (balance.isOverBudget ? 'kcal de más' : 'kcal restantes')
          : 'Sin objetivo configurado',

      // La barra del día. **−1 y no 0 cuando no hay objetivo**: el widget la
      // esconde entera en vez de dibujarla vacía, porque una barra al 0 % es un
      // número inventado con forma de cuenta.
      'caloriesPercent': hasTarget && target > 0
          ? ((summary.consumedKcal / target) * 100).round().clamp(0, 100)
          : -1,

      // El consumido contra el objetivo, para el 4×2, que es el único tamaño
      // donde entra sin quitarle la línea a nadie.
      'intakeLabel': hasTarget
          ? '${Fmt.integer(summary.consumedKcal)} de ${Fmt.integer(target)}'
          : '',

      // ── Agua ──────────────────────────────────────────────────────────
      // Cuentas, no texto: el widget dibuja una gota por vaso, y las gotas se
      // pueden tocar para sumar. El tope viaja para que el widget no pueda
      // ofrecer un vaso que la app después va a recortar — dos topes, uno por
      // lenguaje, es un tope que en algún momento discrepa.
      'waterGlasses': glasses,
      'waterGoal': waterGoal,
      'waterMax': WaterLog.maxGlasses,

      // ── Macros ────────────────────────────────────────────────────────
      // Las tres, en el orden de Inicio: proteínas, carbohidratos, grasas.
      ..._macro('protein', 'P', summary.macros.protein),
      ..._macro('carbs', 'C', summary.macros.carbs),
      ..._macro('fat', 'G', summary.macros.fat),

      // ── Los extras del tamaño grande ──────────────────────────────────
      // Cada uno llega vacío cuando no hay nada que decir, y el widget esconde
      // esa línea. Un "Actividad 0 min" ocupa el mismo lugar que un dato y no
      // es uno: es la ausencia de uno.
      'activityLabel': summary.activityTotals.minutes > 0
          ? 'Actividad ${Fmt.duration(summary.activityTotals.minutes)}'
          : '',
      'sleepLabel': sleepMinutes == null || sleepMinutes <= 0
          ? ''
          : 'Sueño ${Fmt.duration(sleepMinutes)}',
      // Un día suelto no es una racha.
      'streakLabel': streak >= 2 ? 'Racha $streak días' : '',

      // ── Para cuando este dato deje de ser el de hoy ───────────────────
      // Se manda ya escrito y con fecha absoluta, no "ayer": el widget lo va a
      // mostrar en un día que todavía no sabemos cuál es, y "ayer" envejece mal.
      'staleLabel': 'Lo último guardado es del ${longDay(summary.date)}',
    };
  }

  /// Una macro: su etiqueta ya escrita y cuánto de la barra pintar.
  ///
  /// El porcentaje se recorta a 100 para la barra, pero la etiqueta muestra los
  /// gramos de verdad: una barra llena con "180/140 g" al lado dice las dos
  /// cosas —que se pasó y cuánto—, mientras que una barra desbordada no diría
  /// ninguna.
  static Map<String, Object> _macro(
    String key,
    String initial,
    MacroProgress macro,
  ) {
    final current = macro.current.round();
    if (macro.target <= 0) {
      return <String, Object>{
        '${key}Label': '$initial $current g',
        '${key}Percent': 0,
      };
    }
    return <String, Object>{
      '${key}Label': '$initial $current/${macro.target}',
      '${key}Percent': (macro.fraction * 100).round().clamp(0, 100),
    };
  }
}
