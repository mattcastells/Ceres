import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';

/// La marca: un anillo que se cierra y tres barras que suben.
///
/// El anillo es el presupuesto del día — el mismo que la app dibuja en Inicio.
/// Geometría exacta de `Ceres Logo.dc.html`: círculo r=36 sobre una caja de
/// 100, trazo 9, apertura de 270° arrancando arriba, y tres barras de 7 de
/// ancho con radio completo.
///
/// Reglas de uso: no rellenar el anillo, no rotarlo, no cambiar la apertura ni
/// agregar un segundo color. Por debajo de 20 px se usa [monochrome].
class BrandMark extends StatelessWidget {
  const BrandMark({
    this.size = 40,
    this.monochrome = false,
    this.color,
    super.key,
  });

  final double size;

  /// Versión de un solo trazo, para tamaños chicos y para el ícono temático.
  final bool monochrome;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      label: 'Ceres',
      child: CustomPaint(
        size: Size.square(size),
        painter: _BrandPainter(
          ringTrack: monochrome
              ? Colors.transparent
              : nm.text.withValues(alpha: 0.10),
          ringColor: color ?? (monochrome ? nm.text : NmAccent.c500),
          barLight: color ?? (monochrome ? nm.text : NmAccent.c300),
          barStrong: color ?? (monochrome ? nm.text : NmAccent.c500),
        ),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({
    required this.ringTrack,
    required this.ringColor,
    required this.barLight,
    required this.barStrong,
  });

  final Color ringTrack;
  final Color ringColor;
  final Color barLight;
  final Color barStrong;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    final center = Offset(50 * k, 50 * k);
    final radius = 36 * k;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * k
      ..color = ringTrack;
    if (ringTrack.a > 0) {
      canvas.drawCircle(center, radius, track);
    }

    // stroke-dasharray 169,6 de 226,2 = 270° exactos, desde arriba.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * k
      ..strokeCap = StrokeCap.round
      ..color = ringColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      arc,
    );

    void bar(double x, double y, double h, Color c) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * k, y * k, 7 * k, h * k),
        Radius.circular(3.5 * k),
      );
      canvas.drawRRect(rect, Paint()..color = c);
    }

    bar(35.5, 52, 14, barLight);
    bar(46.5, 44, 22, barLight);
    bar(57.5, 36, 30, barStrong);
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.ringColor != ringColor ||
      old.barLight != barLight ||
      old.barStrong != barStrong ||
      old.ringTrack != ringTrack;
}

/// Logotipo: marca + palabra. El espacio entre ambas es media altura de la
/// marca; la palabra va en Inter 500 con tracking −0,022em.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.markSize = 40, super.key});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      label: 'Ceres',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandMark(size: markSize),
            SizedBox(width: markSize / 2),
            Text(
              'Ceres',
              style: NmTextStyles.from(NmType.h1, color: nm.text).copyWith(
                fontSize: markSize * 0.75,
                letterSpacing: markSize * 0.75 * -0.022,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
