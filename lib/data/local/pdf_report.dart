import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/formats.dart';
import '../../domain/calculations/rounding.dart';
import '../../domain/models/summaries.dart';
import '../../domain/services/report_builder.dart';

/// El informe del período, en PDF.
///
/// Se dibuja con los mismos tokens que la app —los colores salen de
/// `NmColors`, la tipografía es la misma Inter que viaja en el APK— porque un
/// informe que no se parece a la app se lee como si lo hubiera hecho otro. El
/// tema es el que la persona tiene puesto: si usa Ceres en claro, su informe
/// sale en claro.
///
/// Lo que **no** hay acá es una sola cifra que la app no pueda mostrar en
/// pantalla. Es la misma verdad del historial, ordenada para leerla de corrido:
/// no hay un modelo escribiendo párrafos ni conclusiones que nadie pueda
/// verificar contra los números de arriba.
class PdfReport {
  const PdfReport({required this.report, required this.dark});

  final NutritionReport report;

  /// Qué tema. Es el de la app, resuelto por quien llama: acá no se adivina.
  final bool dark;

  /// Márgenes de la hoja. A4 es lo que imprime cualquiera en Argentina.
  static const double _margin = 32;

  static double get _contentWidth => PdfPageFormat.a4.width - _margin * 2;

  /// El ancho que le queda a un gráfico adentro de una tarjeta.
  static double get _chartWidth => _contentWidth - 24;

  Future<Uint8List> build() async {
    final palette = _Palette(dark: dark);
    final fonts = await _Fonts.load();

    final doc = pw.Document(
      title: 'Informe de Ceres',
      author: 'Ceres',
      creator: 'Ceres',
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.copyWith(
            marginTop: _margin,
            marginBottom: _margin,
            marginLeft: _margin,
            marginRight: _margin,
          ),
          theme: pw.ThemeData.withFont(
            base: fonts.regular,
            bold: fonts.semiBold,
          ),
          // El fondo se pinta a mano: `PageTheme` no tiene color de página, y
          // sin esto el tema oscuro sería texto claro sobre papel blanco.
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: palette.bg),
          ),
        ),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _runningHeader(palette, fonts),
        footer: (context) => _footer(context, palette, fonts),
        build: (context) => <pw.Widget>[
          _cover(palette, fonts),
          _resumen(palette, fonts),
          _peso(palette, fonts),
          _calorias(palette, fonts),
          _nutrientes(palette, fonts),
          _actividad(palette, fonts),
          _agua(palette, fonts),
          _sueno(palette, fonts),
          ..._medidas(palette, fonts),
          _cierre(palette, fonts),
        ],
      ),
    );

    return doc.save();
  }

  // ── Portada ──────────────────────────────────────────────────────────────

  pw.Widget _cover(_Palette p, _Fonts f) {
    final headline = ReportBuilder.headline(report);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  report.name,
                  style: pw.TextStyle(
                    font: f.medium,
                    fontSize: 26,
                    color: p.text,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '${longDay(report.from)} — ${longDay(report.to)}',
                  style: pw.TextStyle(
                    font: f.regular,
                    fontSize: 11,
                    color: p.textMuted,
                  ),
                ),
              ],
            ),
            // La marca escrita y no el logo en PNG: ese archivo trae su propia
            // tarjeta oscura pintada adentro, así que en el informe claro
            // aparecería como un rectángulo negro en la esquina. Un texto se
            // adapta al tema por definición.
            pw.Text(
              'Ceres',
              style: pw.TextStyle(
                font: f.medium,
                fontSize: 13,
                color: p.textMuted,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        if (headline != null)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: p.surface,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: p.divider, width: 0.5),
            ),
            // La barra de acento va **adentro** y no como borde izquierdo: el
            // paquete no admite un borde de ancho distinto por lado junto con
            // esquinas redondeadas, y el borde de un solo lado en una tarjeta
            // redondeada dispara una aserción al pintar.
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                // Alto fijo y no `stretch`: en un `Row` estirado, un hijo sin
                // altura propia puede crecer sin techo, y la tarjeta pasaba a
                // ser más alta que una página — `MultiPage` entonces abre hojas
                // nuevas para siempre buscando dónde ponerla.
                pw.Container(
                  width: 3,
                  height: 17,
                  decoration: pw.BoxDecoration(
                    color: p.accent,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    headline,
                    style: pw.TextStyle(
                      font: f.medium,
                      fontSize: 13,
                      color: p.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 16),
      ],
    );
  }

  // ── Resumen ──────────────────────────────────────────────────────────────

  pw.Widget _resumen(_Palette p, _Fonts f) {
    final goal = report.goal;

    return _section(
      'El período de un vistazo',
      p.accent,
      p,
      f,
      body: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            children: <pw.Widget>[
              _tile(
                label: 'Días registrados',
                value: '${report.daysWithRecords}',
                caption: 'de ${report.totalDays} · ${report.coveragePct} %',
                color: p.accent,
                p: p,
                f: f,
              ),
              pw.SizedBox(width: 8),
              _tile(
                label: 'Comiste por día',
                value: report.calories.hasData
                    ? Fmt.integer(report.calories.value)
                    : '—',
                caption: report.calories.hasData
                    ? 'kcal en promedio'
                    : 'sin datos',
                color: p.intake,
                p: p,
                f: f,
              ),
              pw.SizedBox(width: 8),
              _tile(
                label: 'Tu objetivo',
                value: goal == null ? '—' : Fmt.integer(goal.baseCalorieTarget),
                caption: goal == null ? 'sin definir' : 'kcal por día',
                color: p.target,
                p: p,
                f: f,
              ),
              pw.SizedBox(width: 8),
              // "Días sin pasarte" y no "días en el objetivo": lo segundo
              // contaba una banda de ±10 % alrededor del número, así que un día
              // de 1.400 con objetivo 2.000 quedaba afuera — y para quien mira
              // su informe ese es exactamente un día en el que no se pasó.
              _tile(
                label: 'Días sin pasarte',
                value: '${report.daysNotOver}',
                caption: 'de ${report.daysWithRecords} registrados',
                color: p.success,
                p: p,
                f: f,
              ),
            ],
          ),
          if (report.startedMidPeriod) ...<pw.Widget>[
            pw.SizedBox(height: 8),
            _note(
              'Se cuentan los días desde que empezaste a registrar '
              '(${longDay(report.countingFrom)}), no desde el principio del '
              'período.',
              p,
              f,
            ),
          ],
          if (!report.hasEnoughData) ...<pw.Widget>[
            pw.SizedBox(height: 8),
            _note(
              'Con ${report.daysWithRecords} '
              '${report.daysWithRecords == 1 ? 'día registrado' : 'días registrados'} '
              'los promedios son orientativos. Se vuelven confiables cuando hay '
              'unas cuantas semanas.',
              p,
              f,
            ),
          ],
          if (report.dietaryLabels.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 8),
            _note('Tenés cargado: ${report.dietaryLabels.join(', ')}.', p, f),
          ],
        ],
      ),
    );
  }

  // ── Peso ─────────────────────────────────────────────────────────────────

  pw.Widget _peso(_Palette p, _Fonts f) {
    final weight = report.weight;
    final progress = report.progress;
    if (weight == null) {
      return _section(
        'Peso',
        p.weight,
        p,
        f,
        body: _empty('No registraste ningún peso en este período.', p, f),
      );
    }

    final trend = progress.trendKgPerWeek;

    return _section(
      'Peso',
      p.weight,
      p,
      f,
      body: _card(
        p,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                _inlineStat('Al empezar', '${_decimal(weight.first)} kg', p, f),
                _inlineStat('Hoy', '${_decimal(weight.last)} kg', p, f),
                _inlineStat(
                  'Diferencia',
                  '${_signedDecimal(weight.delta)} kg',
                  p,
                  f,
                ),
                // Dos decimales: es el mismo número que la frase de arriba, y
                // con uno solo un ritmo de 0,27 se leía "0,3" al lado de un
                // texto que decía 0,27.
                _inlineStat(
                  'Ritmo',
                  trend == null
                      ? 'sin datos'
                      : '${_signedDecimal(trend, digits: 2)} kg/sem',
                  p,
                  f,
                ),
              ],
            ),
            if (progress.weightPoints.length >= 2) ...<pw.Widget>[
              pw.SizedBox(height: 12),
              _legend(
                <(_LegendMark, String)>[
                  (_LegendMark(p.weight), 'Cada registro'),
                  (_LegendMark(p.trend, dashed: true), 'Promedio de 7 días'),
                ],
                p,
                f,
              ),
              pw.SizedBox(height: 6),
              pw.CustomPaint(
                size: PdfPoint(_chartWidth, 130),
                painter: (canvas, size) => _paintWeight(
                  canvas: canvas,
                  size: size,
                  p: p,
                  points: progress.weightPoints,
                  average: progress.weightMovingAverage,
                ),
              ),
              pw.SizedBox(height: 4),
              _axisDates(
                progress.weightPoints.first.date,
                progress.weightPoints.last.date,
                p,
                f,
              ),
            ] else ...<pw.Widget>[
              pw.SizedBox(height: 8),
              _note('Con un solo registro no hay curva que dibujar.', p, f),
            ],
          ],
        ),
      ),
    );
  }

  // ── Calorías ─────────────────────────────────────────────────────────────

  pw.Widget _calorias(_Palette p, _Fonts f) {
    final days = report.progress.calorieDays;
    final extremes = ReportBuilder.calorieExtremes(report);
    final vsTarget = ReportBuilder.averageVsTarget(report);

    return _section(
      'Calorías por día',
      p.intake,
      p,
      f,
      body: _card(
        p,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                _inlineStat(
                  'Promedio',
                  report.calories.hasData
                      ? Fmt.kcal(report.calories.value)
                      : '—',
                  p,
                  f,
                ),
                _inlineStat(
                  'Día más bajo',
                  extremes == null ? '—' : Fmt.kcal(extremes.$1.consumed),
                  p,
                  f,
                ),
                _inlineStat(
                  'Día más alto',
                  extremes == null ? '—' : Fmt.kcal(extremes.$2.consumed),
                  p,
                  f,
                ),
                // Contra el objetivo, en vez de la adherencia: el porcentaje
                // decía qué tan cerca del número estuviste sin decir de qué
                // lado, y de los dos datos este es el que se puede usar.
                _inlineStat(
                  'Contra tu objetivo',
                  vsTarget == null
                      ? '—'
                      : '${Fmt.signed(vsTarget)} kcal/día',
                  p,
                  f,
                ),
              ],
            ),
            if (days.any((d) => d.consumed > 0)) ...<pw.Widget>[
              pw.SizedBox(height: 12),
              // Barras y línea: las dos series se distinguen por **forma**, no
              // por color, así que se leen igual en blanco y negro o con
              // cualquier daltonismo.
              _legend(
                <(_LegendMark, String)>[
                  (_LegendMark(p.intake, bar: true), 'Lo que comiste'),
                  (_LegendMark(p.target, dashed: true), 'Tu objetivo'),
                ],
                p,
                f,
              ),
              pw.SizedBox(height: 6),
              pw.CustomPaint(
                size: PdfPoint(_chartWidth, 130),
                painter: (canvas, size) =>
                    _paintCalories(canvas: canvas, size: size, p: p, days: days),
              ),
              pw.SizedBox(height: 4),
              _axisDates(days.first.date, days.last.date, p, f),
            ],
          ],
        ),
      ),
    );
  }

  // ── Nutrientes ───────────────────────────────────────────────────────────

  /// Cuatro filas y no un gráfico de torta.
  ///
  /// Lo que alguien quiere saber de sus macros es cuánto comió y cuánto le
  /// tocaba, y eso son dos números por fila. Una torta muestra proporciones que
  /// nadie pidió y esconde justo el dato que importa.
  pw.Widget _nutrientes(_Palette p, _Fonts f) => _section(
    'Nutrientes por día',
    p.protein,
    p,
    f,
    body: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _card(
          p,
          pw.Column(
            children: <pw.Widget>[
              _tableHeader(
                <String>['', 'Promedio', 'Objetivo', 'Del objetivo'],
                p,
                f,
              ),
              for (final nutrient in <ReportNutrient>[
                ReportNutrient(
                  label: 'Energía',
                  average: report.calories,
                  targetPerDay: report.goal?.baseCalorieTarget ?? 0,
                  unit: 'kcal',
                ),
                ...report.nutrients,
              ])
                _tableRow(
                  <String>[
                    nutrient.label,
                    nutrient.average.hasData
                        ? '${Fmt.integer(nutrient.average.value)} ${nutrient.unit}'
                        : '—',
                    nutrient.targetPerDay <= 0
                        ? '—'
                        : '${Fmt.integer(nutrient.targetPerDay)} ${nutrient.unit}',
                    nutrient.pctOfTarget == null || !nutrient.average.hasData
                        ? '—'
                        : '${nutrient.pctOfTarget} %',
                  ],
                  p,
                  f,
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        _note(
          'El promedio sale de los ${report.daysWithRecords} días con '
          'registro: un día sin cargar no es un día de cero calorías.',
          p,
          f,
        ),
      ],
    ),
  );

  // ── Actividad ────────────────────────────────────────────────────────────

  pw.Widget _actividad(_Palette p, _Fonts f) {
    final totals = report.progress.activityTotals;
    final byDay = report.progress.activityByDay;
    final byCategory = report.progress.activityByCategory;
    final maxMinutes = byCategory.isEmpty
        ? 0
        : byCategory.map((c) => c.minutes).reduce((a, b) => a > b ? a : b);

    if (totals.sessions == 0) {
      return _section(
        'Actividad',
        p.activity,
        p,
        f,
        body: _empty('No registraste actividad en este período.', p, f),
      );
    }

    return _section(
      'Actividad',
      p.activity,
      p,
      f,
      body: _card(
        p,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                _inlineStat('Sesiones', '${totals.sessions}', p, f),
                _inlineStat(
                  'Por semana',
                  Fmt.duration(report.progress.weeklyAverageMinutes),
                  p,
                  f,
                ),
                _inlineStat('Días activos', '${totals.activeDays}', p, f),
                // "Quemaste por día" y no "Gasto por día": lo segundo no dice
                // de qué gasto habla —¿el del ejercicio, el del día entero?— ni
                // que sea un promedio.
                //
                // Y con cero se muestra una raya: hay sesiones cargadas, así
                // que un "≈ 0 kcal" no significa que no gastó nada, significa
                // que no se pudo estimar —falta el peso con el que se calcula—
                // y son dos cosas distintas.
                _inlineStat(
                  'Quemaste por día',
                  report.exerciseCalories.value < 1
                      ? '—'
                      : Fmt.estimatedKcal(report.exerciseCalories.value),
                  p,
                  f,
                ),
              ],
            ),
            if (byDay.any((d) => d.minutes > 0)) ...<pw.Widget>[
              pw.SizedBox(height: 12),
              pw.CustomPaint(
                size: PdfPoint(_chartWidth, 90),
                painter: (canvas, size) => _paintBars(
                  canvas: canvas,
                  size: size,
                  p: p,
                  color: p.activity,
                  values: <double>[for (final d in byDay) d.minutes.toDouble()],
                ),
              ),
              pw.SizedBox(height: 4),
              _axisLabels(
                shortDay(byDay.first.date),
                'minutos por día',
                shortDay(byDay.last.date),
                p,
                f,
              ),
            ],
            if (byCategory.isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 12),
              // Barras con el nombre al lado: la identidad la lleva la
              // etiqueta, no el color, así que alcanza con un solo tono. Seis
              // colores distintos acá no agregarían nada que el texto no diga
              // y algunos de esos pares no se distinguen entre sí.
              for (final slice in byCategory)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 5),
                  child: _categoryBar(
                    label: slice.category.label,
                    minutes: slice.minutes,
                    maxMinutes: maxMinutes,
                    p: p,
                    f: f,
                  ),
                ),
            ],
            if (totals.mostFrequentTypeName != null)
              _note('Lo que más hiciste: ${totals.mostFrequentTypeName}.', p, f),
          ],
        ),
      ),
    );
  }

  // ── Agua ─────────────────────────────────────────────────────────────────

  pw.Widget _agua(_Palette p, _Fonts f) {
    if (!report.water.hasData) return pw.SizedBox();
    final extremos = ReportBuilder.extremes(report.waterByDay);

    return _section(
      'Agua',
      p.water,
      p,
      f,
      body: _card(
        p,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                _inlineStat(
                  'Promedio',
                  '${_decimal(report.water.value)} vasos',
                  p,
                  f,
                ),
                _inlineStat(
                  'Día más bajo',
                  extremos == null ? '—' : '${extremos.$1.value.round()} vasos',
                  p,
                  f,
                ),
                _inlineStat(
                  'Día más alto',
                  extremos == null ? '—' : '${extremos.$2.value.round()} vasos',
                  p,
                  f,
                ),
                _inlineStat('Días con registro', '${report.water.days}', p, f),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.CustomPaint(
              size: PdfPoint(_chartWidth, 90),
              painter: (canvas, size) => _paintBars(
                canvas: canvas,
                size: size,
                p: p,
                color: p.water,
                values: <double>[for (final d in report.waterByDay) d.value],
                average: report.water.value,
              ),
            ),
            pw.SizedBox(height: 4),
            _axisLabels(
              shortDay(report.waterByDay.first.date),
              'vasos por día · la línea es tu promedio',
              shortDay(report.waterByDay.last.date),
              p,
              f,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sueño ────────────────────────────────────────────────────────────────

  pw.Widget _sueno(_Palette p, _Fonts f) {
    if (!report.sleepMinutes.hasData) return pw.SizedBox();
    final extremos = ReportBuilder.extremes(report.sleepByDay);

    return _section(
      'Sueño',
      p.sleep,
      p,
      f,
      body: _card(
        p,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                _inlineStat(
                  'Promedio',
                  Fmt.duration(roundHalfUp(report.sleepMinutes.value)),
                  p,
                  f,
                ),
                _inlineStat(
                  'Noche más corta',
                  extremos == null
                      ? '—'
                      : Fmt.duration(extremos.$1.value.round()),
                  p,
                  f,
                ),
                _inlineStat(
                  'Noche más larga',
                  extremos == null
                      ? '—'
                      : Fmt.duration(extremos.$2.value.round()),
                  p,
                  f,
                ),
                _inlineStat(
                  'Noches con registro',
                  '${report.sleepMinutes.days}',
                  p,
                  f,
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.CustomPaint(
              size: PdfPoint(_chartWidth, 90),
              painter: (canvas, size) => _paintBars(
                canvas: canvas,
                size: size,
                p: p,
                color: p.sleep,
                values: <double>[for (final d in report.sleepByDay) d.value],
                average: report.sleepMinutes.value,
              ),
            ),
            pw.SizedBox(height: 4),
            _axisLabels(
              shortDay(report.sleepByDay.first.date),
              'horas por noche · la línea es tu promedio',
              shortDay(report.sleepByDay.last.date),
              p,
              f,
            ),
          ],
        ),
      ),
    );
  }

  // ── Medidas ──────────────────────────────────────────────────────────────

  List<pw.Widget> _medidas(_Palette p, _Fonts f) {
    if (report.measurements.isEmpty) return <pw.Widget>[];
    return <pw.Widget>[
      _section(
        'Medidas corporales',
        p.measure,
        p,
        f,
        body: _card(
          p,
          pw.Column(
            children: <pw.Widget>[
              _tableHeader(
                <String>['', 'Al empezar', 'Última', 'Diferencia'],
                p,
                f,
              ),
              for (final m in report.measurements)
                _tableRow(
                  <String>[
                    m.label,
                    '${_decimal(m.first)} ${m.unit}'.trim(),
                    '${_decimal(m.last)} ${m.unit}'.trim(),
                    '${_signedDecimal(m.delta)} ${m.unit}'.trim(),
                  ],
                  p,
                  f,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  pw.Widget _cierre(_Palette p, _Fonts f) => _note(
    'Las calorías del ejercicio y las de las comidas estimadas por IA son '
    'estimaciones, no mediciones. Los pesos, las medidas y los alimentos del '
    'catálogo son lo que cargaste.',
    p,
    f,
  );

  // ── Piezas ───────────────────────────────────────────────────────────────

  /// Una sección entera: su título y su contenido, **sin poder partirse**.
  ///
  /// `Inseparable` es lo que arregla el cascarón vacío que aparecía al pie de
  /// una página: `Column` sabe partirse entre páginas, así que una tarjeta que
  /// no entraba dejaba su marco dibujado arriba y se llevaba todas las filas a
  /// la página siguiente. Ahora la sección que no entra se muda entera.
  pw.Widget _section(
    String title,
    PdfColor color,
    _Palette p,
    _Fonts f, {
    required pw.Widget body,
  }) => pw.Inseparable(
    child: pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            children: <pw.Widget>[
              // Un pastilla del color de la sección antes del título. Es lo
              // único que colorea el encabezado: el texto sigue con la tinta de
              // siempre, porque un título de color se lee como si el color
              // significara algo del dato y acá solo dice de qué sección es.
              pw.Container(
                width: 3,
                height: 9,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  font: f.medium,
                  fontSize: 8,
                  letterSpacing: 1,
                  color: p.textMuted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          body,
        ],
      ),
    ),
  );

  pw.Widget _runningHeader(_Palette p, _Fonts f) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Text(
      '${report.name} · ${numericDate(report.from)} a '
      '${numericDate(report.to)}',
      style: pw.TextStyle(font: f.regular, fontSize: 8, color: p.textMuted),
    ),
  );

  pw.Widget _footer(pw.Context context, _Palette p, _Fonts f) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(
          'Ceres · generado el ${numericDate(report.generatedAt)}',
          style: pw.TextStyle(font: f.regular, fontSize: 8, color: p.textMuted),
        ),
        pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(font: f.regular, fontSize: 8, color: p.textMuted),
        ),
      ],
    ),
  );

  pw.Widget _card(_Palette p, pw.Widget child) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: p.surface,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: p.divider, width: 0.5),
    ),
    child: child,
  );

  pw.Widget _tile({
    required String label,
    required String value,
    required String caption,
    required PdfColor color,
    required _Palette p,
    required _Fonts f,
  }) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: p.surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: p.divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            children: <pw.Widget>[
              pw.Container(
                width: 5,
                height: 5,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    font: f.regular,
                    fontSize: 8,
                    color: p.textMuted,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(font: f.medium, fontSize: 19, color: p.text),
          ),
          pw.Text(
            caption,
            style: pw.TextStyle(
              font: f.regular,
              fontSize: 8,
              color: p.textMuted,
            ),
          ),
        ],
      ),
    ),
  );

  pw.Widget _inlineStat(String label, String value, _Palette p, _Fonts f) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(
              font: f.regular,
              fontSize: 8,
              color: p.textMuted,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(font: f.medium, fontSize: 12, color: p.text),
          ),
        ],
      );

  pw.Widget _tableHeader(List<String> cells, _Palette p, _Fonts f) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          children: <pw.Widget>[
            for (var i = 0; i < cells.length; i++)
              pw.Expanded(
                flex: i == 0 ? 3 : 2,
                child: pw.Text(
                  cells[i],
                  textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
                  style: pw.TextStyle(
                    font: f.regular,
                    fontSize: 8,
                    color: p.textMuted,
                  ),
                ),
              ),
          ],
        ),
      );

  pw.Widget _tableRow(List<String> cells, _Palette p, _Fonts f) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: p.divider, width: 0.5)),
    ),
    child: pw.Row(
      children: <pw.Widget>[
        for (var i = 0; i < cells.length; i++)
          pw.Expanded(
            flex: i == 0 ? 3 : 2,
            child: pw.Text(
              cells[i],
              textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
              style: pw.TextStyle(
                font: i == 0 ? f.regular : f.medium,
                fontSize: 10,
                color: i == 0 ? p.textMuted : p.text,
              ),
            ),
          ),
      ],
    ),
  );

  pw.Widget _categoryBar({
    required String label,
    required int minutes,
    required int maxMinutes,
    required _Palette p,
    required _Fonts f,
  }) {
    final fraction = maxMinutes <= 0 ? 0.0 : minutes / maxMinutes;
    return pw.Row(
      children: <pw.Widget>[
        pw.SizedBox(
          width: 96,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: f.regular,
              fontSize: 9,
              color: p.textMuted,
            ),
          ),
        ),
        // La proporción se reparte con `flex` y no con un ancho fraccional: el
        // paquete de PDF no trae `FractionallySizedBox`, y dos `Expanded` en
        // proporción dan exactamente lo mismo sin conocer el ancho de antemano.
        pw.Expanded(
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                flex: (fraction * 1000).round().clamp(4, 1000),
                child: pw.Container(
                  height: 8,
                  decoration: pw.BoxDecoration(
                    color: p.activity,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),
              ),
              // El resto queda como carril vacío, para que se vea contra qué se
              // compara cada barra. Nunca cero: `Expanded` con flex 0 no ocupa
              // nada y la barra más larga perdería su carril.
              pw.Expanded(
                flex: (1000 - (fraction * 1000).round()).clamp(1, 1000),
                child: pw.SizedBox(height: 8),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 58,
          child: pw.Text(
            Fmt.duration(minutes),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: f.medium, fontSize: 9, color: p.text),
          ),
        ),
      ],
    );
  }

  pw.Widget _legend(
    List<(_LegendMark, String)> entries,
    _Palette p,
    _Fonts f,
  ) => pw.Row(
    children: <pw.Widget>[
      for (final entry in entries) ...<pw.Widget>[
        pw.CustomPaint(
          size: const PdfPoint(14, 8),
          painter: (canvas, size) => entry.$1.paint(canvas, size),
        ),
        pw.SizedBox(width: 5),
        pw.Text(
          entry.$2,
          style: pw.TextStyle(font: f.regular, fontSize: 8, color: p.textMuted),
        ),
        pw.SizedBox(width: 14),
      ],
    ],
  );

  pw.Widget _axisDates(DateTime from, DateTime to, _Palette p, _Fonts f) =>
      _axisLabels(shortDay(from), '', shortDay(to), p, f);

  /// El pie de un gráfico: la fecha de cada punta y, en el medio, qué se está
  /// mirando. Sin eso una barra de 90 pt de alto no dice si son minutos, vasos
  /// o litros.
  pw.Widget _axisLabels(
    String left,
    String middle,
    String right,
    _Palette p,
    _Fonts f,
  ) {
    final style = pw.TextStyle(
      font: f.regular,
      fontSize: 8,
      color: p.textMuted,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(left, style: style),
        if (middle.isNotEmpty) pw.Text(middle, style: style),
        pw.Text(right, style: style),
      ],
    );
  }

  pw.Widget _note(String text, _Palette p, _Fonts f) => pw.Text(
    text,
    style: pw.TextStyle(font: f.regular, fontSize: 8.5, color: p.textMuted),
  );

  pw.Widget _empty(String text, _Palette p, _Fonts f) => _card(
    p,
    pw.Text(
      text,
      style: pw.TextStyle(font: f.regular, fontSize: 10, color: p.textMuted),
    ),
  );

  // ── Gráficos ─────────────────────────────────────────────────────────────

  /// La curva de peso y su promedio de 7 días.
  ///
  /// Dos series, y se distinguen por dos cosas a la vez: color y trazo (la
  /// media va punteada). Con una sola de las dos, quien imprima el informe en
  /// blanco y negro se queda sin saber cuál es cuál.
  void _paintWeight({
    required PdfGraphics canvas,
    required PdfPoint size,
    required _Palette p,
    required List<ChartPoint> points,
    required List<ChartPoint> average,
  }) {
    if (points.length < 2) return;

    final values = <double>[
      ...points.map((e) => e.value),
      ...average.map((e) => e.value),
    ];
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    // Un rango de cero deja todo pegado al borde: se abre medio kilo para
    // arriba y para abajo, que es la resolución con la que se pesa alguien.
    if (max - min < 1) {
      final centro = (max + min) / 2;
      min = centro - 0.5;
      max = centro + 0.5;
    }
    final pad = (max - min) * 0.12;
    min -= pad;
    max += pad;

    _grid(canvas, size, p);

    final firstDate = points.first.date;
    final span = points.last.date.difference(firstDate).inSeconds;

    double x(DateTime date) => span <= 0
        ? 0
        : date.difference(firstDate).inSeconds / span * size.x;
    double y(double value) => (value - min) / (max - min) * size.y;

    void line(List<ChartPoint> serie, PdfColor color, {required bool dashed}) {
      if (serie.length < 2) return;
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(dashed ? 1 : 1.6)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      if (dashed) canvas.setLineDashPattern(<int>[3, 3]);
      canvas.moveTo(x(serie.first.date), y(serie.first.value));
      for (final point in serie.skip(1)) {
        canvas.lineTo(x(point.date), y(point.value));
      }
      canvas.strokePath();
      if (dashed) canvas.setLineDashPattern();
    }

    line(average, p.trend, dashed: true);
    line(points, p.weight, dashed: false);

    // Un punto en cada extremo: son los dos valores que el texto de arriba
    // nombra ("Al empezar" y "Hoy") y así se ve dónde caen en la curva.
    canvas.setFillColor(p.weight);
    for (final point in <ChartPoint>[points.first, points.last]) {
      canvas
        ..drawEllipse(x(point.date), y(point.value), 2.4, 2.4)
        ..fillPath();
    }
  }

  /// Las calorías de cada día contra el objetivo.
  ///
  /// Barras para lo comido y una línea punteada para el objetivo: dos formas
  /// distintas, no dos colores parecidos. Un día sin registro no dibuja barra —
  /// no es un día de cero calorías, es un día que no está.
  void _paintCalories({
    required PdfGraphics canvas,
    required PdfPoint size,
    required _Palette p,
    required List<CaloriesDay> days,
  }) {
    if (days.isEmpty) return;

    final maxValue = <int>[
      ...days.map((d) => d.consumed),
      ...days.map((d) => d.target),
    ].reduce((a, b) => a > b ? a : b);
    if (maxValue <= 0) return;
    final top = maxValue * 1.12;

    _grid(canvas, size, p);

    double y(num value) => value / top * size.y;

    // Un espacio de 2 pt entre barras, y nunca más finas que 1,5 pt: con un
    // año de días, el ancho por día es menos de 1,5 pt y las barras se
    // superponen hasta volverse una mancha.
    final slot = size.x / days.length;
    final width = (slot - 2).clamp(1.0, 14.0);

    canvas.setFillColor(p.intake);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      if (day.consumed <= 0) continue;
      final height = y(day.consumed);
      final left = i * slot + (slot - width) / 2;
      if (height <= 2 || width <= 3) {
        canvas.drawRect(left, 0, width, height < 0.8 ? 0.8 : height);
      } else {
        canvas.drawRRect(left, 0, width, height, 2, 2);
      }
    }
    canvas.fillPath();

    // El objetivo puede cambiar dentro del período: se dibuja día a día y no
    // como una recta, porque una recta diría que siempre fue el mismo.
    canvas
      ..setStrokeColor(p.target)
      ..setLineWidth(1)
      ..setLineDashPattern(<int>[3, 3])
      ..moveTo(0, y(days.first.target));
    for (var i = 1; i < days.length; i++) {
      canvas.lineTo(i * slot + slot / 2, y(days[i].target));
    }
    canvas
      ..lineTo(size.x, y(days.last.target))
      ..strokePath()
      ..setLineDashPattern();
  }

  /// Barras de una sola serie, con su promedio marcado.
  ///
  /// Lo usan agua, sueño y actividad: los tres son "cuánto hubo cada día" y no
  /// hay nada contra qué compararlos salvo el propio promedio, así que la línea
  /// punteada es eso y lo dice el pie del gráfico.
  void _paintBars({
    required PdfGraphics canvas,
    required PdfPoint size,
    required _Palette p,
    required PdfColor color,
    required List<double> values,
    double? average,
  }) {
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    if (maxValue <= 0) return;
    final top = maxValue * 1.15;

    _grid(canvas, size, p, lines: 2);

    double y(double value) => value / top * size.y;

    final slot = size.x / values.length;
    final width = (slot - 2).clamp(1.0, 14.0);

    canvas.setFillColor(color);
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final height = y(values[i]);
      final left = i * slot + (slot - width) / 2;
      if (height <= 2 || width <= 3) {
        canvas.drawRect(left, 0, width, height < 0.8 ? 0.8 : height);
      } else {
        canvas.drawRRect(left, 0, width, height, 2, 2);
      }
    }
    canvas.fillPath();

    if (average != null && average > 0) {
      canvas
        ..setStrokeColor(p.textMuted)
        ..setLineWidth(1)
        ..setLineDashPattern(<int>[3, 3])
        ..moveTo(0, y(average))
        ..lineTo(size.x, y(average))
        ..strokePath()
        ..setLineDashPattern();
    }
  }

  /// Líneas de fondo, muy tenues. La grilla ubica; no compite.
  void _grid(PdfGraphics canvas, PdfPoint size, _Palette p, {int lines = 3}) {
    canvas
      ..setStrokeColor(p.divider)
      ..setLineWidth(0.4);
    for (var i = 0; i <= lines; i++) {
      final y = size.y / lines * i;
      canvas
        ..moveTo(0, y)
        ..lineTo(size.x, y);
    }
    canvas.strokePath();
  }

  static String _decimal(double value, {int digits = 1}) =>
      value.toStringAsFixed(digits).replaceAll('.', ',');

  static String _signedDecimal(double value, {int digits = 1}) => value == 0
      ? _decimal(0, digits: digits)
      : (value > 0
            ? '+${_decimal(value, digits: digits)}'
            : _decimal(value, digits: digits));
}

/// Una muestra de la leyenda: una barra, una línea o una línea punteada.
class _LegendMark {
  const _LegendMark(this.color, {this.dashed = false, this.bar = false});

  final PdfColor color;
  final bool dashed;
  final bool bar;

  void paint(PdfGraphics canvas, PdfPoint size) {
    if (bar) {
      canvas
        ..setFillColor(color)
        ..drawRRect(0, 1, 8, size.y - 2, 2, 2)
        ..fillPath();
      return;
    }
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(1.6)
      ..setLineCap(PdfLineCap.round);
    if (dashed) canvas.setLineDashPattern(<int>[3, 3]);
    canvas
      ..moveTo(0, size.y / 2)
      ..lineTo(size.x, size.y / 2)
      ..strokePath();
    if (dashed) canvas.setLineDashPattern();
  }
}

/// Los colores del informe, tomados de los tokens de la app.
///
/// No hay una paleta propia del PDF: si el sistema de diseño cambia, el informe
/// cambia con él. Es lo que hace que se vea como Ceres y no como el reporte
/// genérico de una librería.
///
/// Cada sección tiene su tono, y eso no es decoración: es lo que permite
/// reconocer de un vistazo en qué parte del informe está uno cuando lo hojea.
/// Como cada gráfico tiene **una sola serie**, el color identifica la sección y
/// nunca compite dentro del mismo gráfico — los dos que sí tienen dos series
/// (peso y calorías) las separan además por trazo.
class _Palette {
  _Palette({required this.dark})
    : _roles = dark ? NmColors.dark : NmColors.light;

  final bool dark;
  final NmColorRoles _roles;

  PdfColor get bg => _of(_roles.bg);
  PdfColor get surface => _of(_roles.surface);
  PdfColor get text => _of(_roles.text);
  PdfColor get textMuted => _of(_roles.textMuted);
  PdfColor get divider => _of(_roles.divider);
  PdfColor get accent => _of(_roles.accent);
  PdfColor get success => _of(_roles.success);

  /// La paleta de datos del sistema (`NmChartColors`), la misma que usan los
  /// gráficos de Progreso y el panel profesional.
  PdfColor get intake => _of(NmChartColors.intake);
  PdfColor get weight => _of(NmChartColors.weight);
  PdfColor get activity => _of(NmChartColors.cycling);
  PdfColor get water => _of(NmChartColors.running);
  PdfColor get sleep => _of(NmChartColors.sports);
  PdfColor get protein => _of(NmChartColors.walking);
  PdfColor get measure => _of(NmChartColors.strength);

  /// La línea del objetivo. El token es un gris muy claro pensado contra el
  /// fondo oscuro, y sobre papel blanco la línea punteada casi no se ve; en
  /// claro se baja a un gris medio, que sigue siendo recesivo pero se lee.
  PdfColor get target =>
      dark ? _of(NmChartColors.target) : _of(NmNeutral.c600);

  /// La media móvil, con el mismo problema y la misma solución. Es lo que hace
  /// el panel profesional en su media query de tema claro.
  PdfColor get trend => dark ? _of(NmChartColors.trend) : _of(NmNeutral.c900);

  static PdfColor _of(Color color) => PdfColor.fromInt(color.toARGB32());
}

/// Inter, la misma familia que la app, embebida en el archivo.
///
/// Sin esto el PDF sale en Helvetica y con los acentos rotos: las fuentes
/// estándar del formato son Latin-1 y no tienen ni la ñ ni las comillas
/// tipográficas que usa todo el texto de Ceres.
class _Fonts {
  const _Fonts({
    required this.regular,
    required this.medium,
    required this.semiBold,
  });

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;

  static Future<_Fonts> load() async => _Fonts(
    regular: pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    ),
    medium: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Medium.ttf')),
    semiBold: pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    ),
  );
}
