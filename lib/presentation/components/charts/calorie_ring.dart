import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';

/// El anillo de calorías de Inicio (S-06). ★
///
/// Al montar, el arco crece de 0 al valor en `motion.chart` y el número hace
/// count-up; al cambiar el valor transiciona en `motion.slow`, nunca salta
/// (21-motion §3.1). Si se pasó del objetivo, el arco completa la vuelta y el
/// excedente se dibuja encima en `accent-700` — sin rebote ni vibración,
/// porque nada de castigo cinético (RN-14 / D-17).
class CalorieRing extends StatefulWidget {
  const CalorieRing({
    required this.consumed,
    required this.adjustedTarget,
    required this.remaining,
    this.size = 176,
    super.key,
  });

  final int consumed;
  final int adjustedTarget;
  final int remaining;
  final double size;

  @override
  State<CalorieRing> createState() => _CalorieRingState();
}

class _CalorieRingState extends State<CalorieRing> {
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mounted = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final motion = context.motion;

    final fraction = widget.adjustedTarget <= 0
        ? 0.0
        : widget.consumed / widget.adjustedTarget;
    final target = motion.animatesCharts ? (_mounted ? fraction : 0.0) : fraction;
    final duration = _mounted
        ? motion.move(NmMotion.slow)
        : motion.move(NmMotion.chart);

    final overBudget = widget.remaining < 0;
    final label = overBudget
        ? 'Te pasaste por ${Fmt.integer(widget.remaining.abs())} calorías '
              'de ${Fmt.integer(widget.adjustedTarget)}'
        : 'Te quedan ${Fmt.integer(widget.remaining)} calorías '
              'de ${Fmt.integer(widget.adjustedTarget)}';

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.size,
          width: widget.size,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: duration,
            curve: NmMotion.ease,
            builder: (context, value, _) => CustomPaint(
              painter: _RingPainter(
                fraction: value,
                track: nm.track,
                arc: nm.accent,
                excess: nm.overBudget,
              ),
              child: Center(
                child: _RingCenter(
                  remaining: widget.remaining,
                  adjustedTarget: widget.adjustedTarget,
                  animate: motion.animatesCounters,
                  duration: duration,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingCenter extends StatelessWidget {
  const _RingCenter({
    required this.remaining,
    required this.adjustedTarget,
    required this.animate,
    required this.duration,
  });

  final int remaining;
  final int adjustedTarget;
  final bool animate;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final overBudget = remaining < 0;
    final value = remaining.abs();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          overBudget ? 'Te pasaste por' : 'Te quedan',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        CountUpText(
          value: value,
          animate: animate,
          duration: duration,
          style: NmTextStyles.from(
            NmType.display,
            color: overBudget ? nm.overBudget : nm.text,
          ).tnum,
        ),
        Text(
          'de ${Fmt.integer(adjustedTarget)} kcal',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted).tnum,
        ),
      ],
    );
  }
}

/// Contador que hace count-up con redondeo por frame: nunca muestra decimales
/// intermedios (21-motion §3.2).
class CountUpText extends StatelessWidget {
  const CountUpText({
    required this.value,
    required this.style,
    this.animate = true,
    this.duration = NmMotion.slow,
    this.prefix = '',
    this.suffix = '',
    super.key,
  });

  final int value;
  final TextStyle style;
  final bool animate;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    if (!animate) {
      return Text('$prefix${Fmt.integer(value)}$suffix', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: NmMotion.ease,
      builder: (context, v, _) => Text(
        '$prefix${Fmt.integer(v.round())}$suffix',
        style: style,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.arc,
    required this.excess,
  });

  final double fraction;
  final Color track;
  final Color arc;
  final Color excess;

  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = track,
    );

    final base = fraction.clamp(0.0, 1.0);
    if (base > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * base,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = arc,
      );
    }

    // El excedente se dibuja encima, con el mismo largo proporcional.
    if (fraction > 1) {
      final over = (fraction - 1).clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * over,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = excess,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.arc != arc || old.track != track;
}
