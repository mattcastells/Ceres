import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/models/summaries.dart';

/// Gráficos con `CustomPainter` y un controlador propio (21-motion §8).
///
/// Cada gráfico se anima **una sola vez por sesión de navegación**: volver a
/// uno ya visto lo muestra en su estado final (§3.5).
abstract final class ChartSession {
  static final Set<String> _seen = <String>{};

  static bool shouldAnimate(String id) => _seen.add(id);
}

/// Envoltura común: alternativa textual accesible + tabla de datos
/// desplegable (15-accessibility.md §8).
///
/// La tabla ("Ver los datos") solo con [showData]: va en las pantallas de
/// "Ampliar", no en el resumen de Progreso, donde eran tres botoncitos
/// iguales que no agregaban nada. La descripción para lectores de pantalla
/// está siempre.
class ChartFrame extends StatefulWidget {
  const ChartFrame({
    required this.semanticsSummary,
    required this.child,
    required this.rows,
    this.height = 180,
    this.showData = false,
    super.key,
  });

  final String semanticsSummary;
  final Widget child;

  /// Filas etiqueta–valor de la tabla accesible.
  final List<(String, String)> rows;
  final double height;
  final bool showData;

  @override
  State<ChartFrame> createState() => _ChartFrameState();
}

class _ChartFrameState extends State<ChartFrame> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          label: widget.semanticsSummary,
          child: ExcludeSemantics(
            child: SizedBox(height: widget.height, child: widget.child),
          ),
        ),
        if (widget.showData) ...<Widget>[
          const SizedBox(height: NmSpace.s2),
          InkWell(
            onTap: () => setState(() => _showTable = !_showTable),
            borderRadius: NmRadius.brSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _showTable
                        ? PhosphorIcons.caretUp()
                        : PhosphorIcons.caretDown(),
                    size: NmIconSize.sm,
                    color: nm.textMuted,
                  ),
                  const SizedBox(width: NmSpace.s2),
                  Text(
                    _showTable ? 'Ocultar los datos' : 'Ver los datos',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showTable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(NmSpace.s3),
              decoration: BoxDecoration(
                color: nm.surfaceRaised,
                borderRadius: NmRadius.brMd,
              ),
              child: Column(
                children: widget.rows
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NmSpace.s1,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                row.$1,
                                style: NmTextStyles.from(
                                  NmType.caption,
                                  color: nm.textMuted,
                                ),
                              ),
                            ),
                            Text(
                              row.$2,
                              style: NmTextStyles.from(
                                NmType.caption,
                                color: nm.text,
                              ).tnum,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ],
    );
  }
}

/// Controlador de entrada compartido por los gráficos.
class _ChartAnimation extends StatefulWidget {
  const _ChartAnimation({required this.id, required this.builder});

  final String id;
  final Widget Function(double t) builder;

  @override
  State<_ChartAnimation> createState() => _ChartAnimationState();
}

class _ChartAnimationState extends State<_ChartAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NmMotion.chart,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animate =
          context.motion.animatesCharts &&
          ChartSession.shouldAnimate(widget.id);
      if (animate) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) =>
        widget.builder(NmMotion.ease.transform(_controller.value)),
  );
}

// ─────────────────────────── Peso ───────────────────────────

/// Puntos diarios + media móvil de 7 días (S-23).
class WeightChart extends StatelessWidget {
  const WeightChart({
    required this.points,
    required this.movingAverage,
    this.id = 'weight',
    this.height = 180,
    this.showData = false,
    super.key,
  });

  final List<ChartPoint> points;
  final List<ChartPoint> movingAverage;
  final String id;
  final double height;
  final bool showData;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    if (points.length < 2) {
      return _ChartPlaceholder(
        height: height,
        message:
            'Necesitamos unos días más de registro para mostrar una '
            'tendencia.',
      );
    }

    final first = points.first.value;
    final last = points.last.value;
    final delta = last - first;

    return ChartFrame(
      height: height,
      showData: showData,
      semanticsSummary:
          'Peso: de ${Fmt.decimal1(first)} a ${Fmt.decimal1(last)} kilos, '
          '${delta >= 0 ? 'una suba' : 'una baja'} de '
          '${Fmt.decimal1(delta.abs())} kilos en el período.',
      rows: <(String, String)>[
        for (final p in points.reversed.take(10))
          (shortDay(p.date), '${Fmt.decimal1(p.value)} kg'),
      ],
      child: _ChartAnimation(
        id: id,
        builder: (t) => CustomPaint(
          size: Size.infinite,
          painter: _LineChartPainter(
            points: points,
            secondary: movingAverage,
            progress: t,
            lineColor: nm.charts.weight,
            // La media móvil sale del tema y no de un color fijo.
            // `NmChartColors.trend` es #E9E9ED, que es el color de **texto del
            // tema oscuro**: sobre el fondo blanco del tema claro da 1,06:1 de
            // contraste, o sea que la línea directamente no se veía. Es lo
            // mismo que ya hace el anillo de calorías con su track.
            trendColor: nm.textMuted,
            gridColor: nm.divider,
            labelColor: nm.textMuted,
            labelStyle: NmTextStyles.from(NmType.micro, color: nm.textMuted),
            unitSuffix: ' kg',
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Calorías ─────────────────────────

/// Barras de consumo con la línea de objetivo (S-23).
class CaloriesChart extends StatelessWidget {
  const CaloriesChart({
    required this.days,
    this.id = 'calories',
    this.height = 180,
    this.showData = false,
    super.key,
  });

  final List<CaloriesDay> days;
  final String id;
  final double height;
  final bool showData;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final withData = days.where((d) => d.consumed > 0).toList();
    if (withData.isEmpty) {
      return _ChartPlaceholder(
        height: height,
        message: 'Todavía no hay comidas registradas en este período.',
      );
    }

    final average =
        withData.fold(0, (acc, d) => acc + d.consumed) / withData.length;

    return ChartFrame(
      height: height,
      showData: showData,
      semanticsSummary:
          'Calorías consumidas por día. Promedio de '
          '${Fmt.integer(average)} kilocalorías, objetivo '
          '${Fmt.integer(days.last.target)}.',
      rows: <(String, String)>[
        for (final d in days.reversed.take(10))
          (
            shortDay(d.date),
            d.consumed == 0 ? 'sin registro' : Fmt.kcal(d.consumed),
          ),
      ],
      child: _ChartAnimation(
        id: id,
        builder: (t) => CustomPaint(
          size: Size.infinite,
          painter: _BarChartPainter(
            values: days.map((d) => d.consumed.toDouble()).toList(),
            dates: days.map((d) => d.date).toList(),
            targetLine: days.isEmpty ? null : days.last.target.toDouble(),
            progress: t,
            barColor: nm.charts.intake,
            // Ídem: #CFD3E5 sobre blanco es 1,35:1 y la línea de objetivo se
            // perdía entera en tema claro.
            targetColor: nm.textMuted,
            gridColor: nm.divider,
            labelStyle: NmTextStyles.from(NmType.micro, color: nm.textMuted),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Actividad ────────────────────────

/// Minutos por día en barras + kcal estimadas en línea (S-24).
class ActivityHistoryChart extends StatelessWidget {
  const ActivityHistoryChart({
    required this.points,
    this.id = 'activity-history',
    this.height = 180,
    this.showData = false,
    super.key,
  });

  final List<ActivityDayPoint> points;
  final String id;
  final double height;
  final bool showData;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    if (points.every((p) => p.minutes == 0)) {
      return _ChartPlaceholder(
        height: height,
        message: 'Sin actividad en este período.',
      );
    }

    final total = points.fold(0, (acc, p) => acc + p.minutes);

    return ChartFrame(
      height: height,
      showData: showData,
      semanticsSummary:
          'Minutos de actividad por día. Total del período: $total minutos.',
      rows: <(String, String)>[
        for (final p in points.reversed.take(10))
          (
            shortDay(p.date),
            '${p.minutes} min · ${Fmt.estimatedKcal(p.calories)}',
          ),
      ],
      child: _ChartAnimation(
        id: id,
        builder: (t) => CustomPaint(
          size: Size.infinite,
          painter: _BarChartPainter(
            values: points.map((p) => p.minutes.toDouble()).toList(),
            dates: points.map((p) => p.date).toList(),
            overlayLine: points.map((p) => p.calories.toDouble()).toList(),
            progress: t,
            barColor: nm.charts.walking,
            overlayColor: nm.charts.running,
            gridColor: nm.divider,
            labelStyle: NmTextStyles.from(NmType.micro, color: nm.textMuted),
            unitSuffix: ' min',
          ),
        ),
      ),
    );
  }
}

/// Distribución del tiempo por categoría en barras apiladas horizontales.
/// **No** se usa torta: legibilidad (S-24).
class ActivityCategoryChart extends StatelessWidget {
  const ActivityCategoryChart({
    required this.slices,
    this.id = 'activity-categories',
    super.key,
  });

  final List<CategorySlice> slices;
  final String id;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final total = slices.fold(0, (acc, s) => acc + s.minutes);
    if (total == 0) {
      return const _ChartPlaceholder(
        height: 80,
        message: 'Sin actividad en este período.',
      );
    }

    Color colorFor(int index) =>
        nm.charts.categories[index % nm.charts.categories.length];

    return _ChartAnimation(
      id: id,
      builder: (t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: slices
                .map(
                  (s) =>
                      '${s.category.label}: ${s.minutes} minutos, '
                      '${(s.minutes / total * 100).round()} por ciento',
                )
                .join('. '),
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NmRadius.full),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: <Widget>[
                      for (var i = 0; i < slices.length; i++)
                        Expanded(
                          flex: math.max(
                            1,
                            (slices[i].minutes * 100 * t).round(),
                          ),
                          child: ColoredBox(color: colorFor(i)),
                        ),
                      if (t < 1)
                        Expanded(
                          flex: math.max(1, (total * 100 * (1 - t)).round()),
                          child: ColoredBox(color: nm.divider),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: NmSpace.s4),
          for (var i = 0; i < slices.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
              child: Row(
                children: <Widget>[
                  Container(
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: colorFor(i),
                      shape: i.isEven ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: i.isEven
                          ? null
                          : BorderRadius.circular(NmRadius.sm),
                    ),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Expanded(
                    child: Text(
                      slices[i].category.label,
                      style: NmTextStyles.from(NmType.caption, color: nm.text),
                    ),
                  ),
                  Text(
                    '${Fmt.duration(slices[i].minutes)} · '
                    '${(slices[i].minutes / total * 100).round()} %',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ).tnum,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({required this.height, required this.message});

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(NmSpace.s4),
      decoration: BoxDecoration(
        borderRadius: NmRadius.brMd,
        border: Border.all(color: nm.divider),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
      ),
    );
  }
}

// ───────────────────── Pintores ─────────────────────

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.secondary,
    required this.progress,
    required this.lineColor,
    required this.trendColor,
    required this.gridColor,
    required this.labelColor,
    required this.labelStyle,
    this.unitSuffix = '',
  });

  final List<ChartPoint> points;
  final List<ChartPoint> secondary;
  final double progress;
  final Color lineColor;
  final Color trendColor;
  final Color gridColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final String unitSuffix;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPadding = 38.0;
    const bottomPadding = 18.0;
    final plot = Rect.fromLTWH(
      leftPadding,
      6,
      size.width - leftPadding - 4,
      size.height - bottomPadding - 6,
    );

    final values = <double>[
      ...points.map((p) => p.value),
      ...secondary.map((p) => p.value),
    ];
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if ((maxValue - minValue).abs() < 0.5) {
      minValue -= 0.5;
      maxValue += 0.5;
    }
    final span = maxValue - minValue;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * i / 2;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);

      final value = maxValue - span * i / 2;
      _text(
        canvas,
        value.toStringAsFixed(1).replaceAll('.', ','),
        Offset(0, y - 6),
        labelStyle,
        maxWidth: leftPadding - 4,
        align: TextAlign.right,
      );
    }

    Offset toOffset(int index, double value, int count) => Offset(
      plot.left + (count == 1 ? 0 : plot.width * index / (count - 1)),
      plot.bottom - ((value - minValue) / span) * plot.height,
    );

    // Trazado progresivo de la media móvil.
    if (secondary.length > 1) {
      final path = Path();
      for (var i = 0; i < secondary.length; i++) {
        final o = toOffset(i, secondary[i].value, secondary.length);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        _trim(path, progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = trendColor.withValues(alpha: 0.85),
      );
    }

    // Los puntos aparecen con fundido y escala 0,6 → 1.
    for (var i = 0; i < points.length; i++) {
      final o = toOffset(i, points[i].value, points.length);
      final appearAt = points.length == 1 ? 0.0 : i / points.length * 0.6;
      final local = ((progress - appearAt) / 0.4).clamp(0.0, 1.0);
      if (local == 0) continue;
      canvas.drawCircle(
        o,
        3.5 * (0.6 + 0.4 * local),
        Paint()..color = lineColor.withValues(alpha: local),
      );
    }

    _text(
      canvas,
      shortDay(points.first.date),
      Offset(plot.left, size.height - 14),
      labelStyle,
      maxWidth: 60,
    );
    _text(
      canvas,
      shortDay(points.last.date),
      Offset(plot.right - 60, size.height - 14),
      labelStyle,
      maxWidth: 60,
      align: TextAlign.right,
    );
  }

  /// Recorta un path al `progress` de su largo — el equivalente de
  /// `stroke-dasharray` animado.
  Path _trim(Path path, double t) {
    if (t >= 1) return path;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (acc, m) => acc + m.length);
    var remaining = total * t;
    final out = Path();
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(metric.length, remaining);
      out.addPath(metric.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    return out;
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.progress != progress || old.points != points;
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.dates,
    required this.progress,
    required this.barColor,
    required this.gridColor,
    required this.labelStyle,
    this.targetLine,
    this.targetColor,
    this.overlayLine,
    this.overlayColor,
    this.unitSuffix = '',
  });

  final List<double> values;
  final List<DateTime> dates;
  final double progress;
  final Color barColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final double? targetLine;
  final Color? targetColor;
  final List<double>? overlayLine;
  final Color? overlayColor;
  final String unitSuffix;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const bottomPadding = 18.0;
    final plot = Rect.fromLTWH(
      2,
      8,
      size.width - 4,
      size.height - bottomPadding - 8,
    );

    final maxValue = math.max(values.reduce(math.max), targetLine ?? 0);
    if (maxValue <= 0) return;

    // Un 8 % de aire arriba: sin esto la línea de objetivo queda pegada al
    // borde superior y se lee como un límite del gráfico, no del día.
    final scaleMax = maxValue * 1.08;

    final slot = plot.width / values.length;
    final barWidth = math.min(slot * 0.62, 22.0);

    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    // scaleY de 0 a 1 con origen abajo, con stagger de izquierda a derecha.
    for (var i = 0; i < values.length; i++) {
      final appearAt = values.length == 1 ? 0.0 : i / values.length * 0.5;
      final local = ((progress - appearAt) / 0.5).clamp(0.0, 1.0);
      final height = plot.height * (values[i] / scaleMax) * local;
      if (height <= 0) continue;
      final left = plot.left + slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, plot.bottom - height, barWidth, height),
          topLeft: const Radius.circular(NmRadius.sm),
          topRight: const Radius.circular(NmRadius.sm),
        ),
        Paint()..color = barColor,
      );
    }

    // La línea de objetivo entra al final con un fundido.
    if (targetLine != null && targetColor != null) {
      final y = plot.bottom - plot.height * (targetLine! / scaleMax);
      final paint = Paint()
        ..color = targetColor!.withValues(
          alpha: (progress - 0.6).clamp(0.0, 0.4) / 0.4,
        )
        ..strokeWidth = 1.5;
      const dash = 6.0;
      for (var x = plot.left; x < plot.right; x += dash * 2) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, plot.right), y),
          paint,
        );
      }
    }

    // Línea superpuesta (kcal sobre los minutos), con 120 ms de retraso.
    final overlay = overlayLine;
    if (overlay != null && overlayColor != null && overlay.length > 1) {
      final overlayMax = overlay.reduce(math.max);
      if (overlayMax > 0) {
        final path = Path();
        for (var i = 0; i < overlay.length; i++) {
          final x = plot.left + slot * i + slot / 2;
          final y = plot.bottom - plot.height * (overlay[i] / overlayMax) * 0.9;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        final delayed = ((progress - 0.23) / 0.77).clamp(0.0, 1.0);
        canvas.drawPath(
          _trim(path, delayed),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = overlayColor!,
        );
      }
    }

    if (dates.isNotEmpty) {
      _text(
        canvas,
        shortDay(dates.first),
        Offset(plot.left, size.height - 14),
        labelStyle,
        maxWidth: 60,
      );
      _text(
        canvas,
        shortDay(dates.last),
        Offset(plot.right - 60, size.height - 14),
        labelStyle,
        maxWidth: 60,
        align: TextAlign.right,
      );
    }
  }

  Path _trim(Path path, double t) {
    if (t >= 1) return path;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (acc, m) => acc + m.length);
    var remaining = total * t;
    final out = Path();
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(metric.length, remaining);
      out.addPath(metric.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    return out;
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.progress != progress || old.values != values;
}

void _text(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style, {
  double maxWidth = 80,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(maxWidth: maxWidth);
  final dx = switch (align) {
    TextAlign.right => offset.dx + maxWidth - painter.width,
    _ => offset.dx,
  };
  painter.paint(canvas, Offset(dx, offset.dy));
}
