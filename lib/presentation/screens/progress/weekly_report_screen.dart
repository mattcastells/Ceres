import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/weekly_report.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/feedback/feedback.dart';
import '../../components/plan/ai_gate.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/plan_providers.dart';

/// El reporte con IA del período elegido en Progreso ("Tu semana", "Tu
/// mes"…): el último guardado de ese período, o el botón para pedirlo.
///
/// Abrir la pantalla **no** genera nada: lee lo guardado. Generar cuesta —es
/// un pedido al modelo con su cuota diaria— y lo decide la persona con el
/// botón. Los números de las tarjetas los calculó el servidor; el texto lo
/// redactó el modelo a partir de ellos, y la pantalla dice cuál es cuál.
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  ConsumerState<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  bool _generating = false;
  AppError? _error;

  /// El recién generado. Se muestra sin esperar a que la lectura de
  /// `care_reports` lo devuelva.
  WeeklyReport? _fresh;

  DateTime _startedAt = DateTime.now();
  Timer? _tick;

  /// Frases para la espera. La función tarda entre 10 y 40 s y no avisa por
  /// dónde va, así que esto no finge pasos: dice lo que hace en orden y,
  /// pasado el minuto, que sigue.
  List<String> get _phases => <String>[
    'Juntando los registros de ${ref.read(progressRangeProvider).noun}…',
    'Calculando promedios y días con registro…',
    'Buscando lo que se repite…',
    'Redactando tu reporte…',
    'Ya casi…',
  ];

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!ensureAiAllowed(context, ref)) return;
    final client = ref.read(careReportClientProvider);
    if (client == null) return;

    setState(() {
      _generating = true;
      _error = null;
      _startedAt = DateTime.now();
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _generating) setState(() {});
    });

    try {
      final report = await client.generateWeekly(
        days: ref.read(progressRangeProvider).days,
      );
      if (!mounted) return;
      _tick?.cancel();
      setState(() {
        _fresh = report;
        _generating = false;
      });
      ref.invalidate(latestWeeklyReportProvider);
    } on AppError catch (error) {
      if (!mounted) return;
      _tick?.cancel();
      setState(() => _generating = false);
      if (handlePlanRequired(context, error)) return;
      setState(() => _error = error);
    } on Object catch (error) {
      if (!mounted) return;
      _tick?.cancel();
      setState(() {
        _generating = false;
        _error = AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos armar el reporte. Probá de nuevo en un rato.',
          requestId: error.toString(),
        );
      });
    }
  }

  String get _phase {
    final seconds = DateTime.now().difference(_startedAt).inSeconds;
    if (seconds >= 60) {
      return 'Está tardando más de lo normal. Podés esperar o volver más '
          'tarde: si se arma, queda guardado.';
    }
    final index = (seconds ~/ 8).clamp(0, _phases.length - 1);
    return _phases[index];
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(progressRangeProvider);
    if (!ref.watch(isCloudEnabledProvider)) {
      return NmScreen(
        title: range.reportTitle,
        child: EmptyState(
          icon: PhosphorIcons.sparkle(),
          title: 'Necesitás una cuenta',
          body:
              'El resumen se arma en el servidor, y sin cuenta tus datos '
              'están solo en este teléfono.',
        ),
      );
    }

    final latest = ref.watch(latestWeeklyReportProvider);
    final report = _fresh ?? latest.valueOrNull;

    return NmScreen(
      // Sin "Regenerar" en la barra: el botón con nombre está al pie del
      // resumen, que es donde se termina de leer. Eran dos para lo mismo.
      title: range.reportTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          if (_error != null) ...<Widget>[
            InfoNote(
              tone: NmNoteTone.caution,
              text: _error!.message,
              action: 'Probar de nuevo',
              onAction: _generate,
            ),
            const SizedBox(height: NmSpace.s4),
          ],
          if (_generating)
            _Generating(
              phase: _phase,
              elapsed: DateTime.now().difference(_startedAt),
            )
          else if (report != null)
            _ReportView(
              report: report,
              onRegenerate: _generate,
              tryLabel: 'Para probar ${range.thisOne}',
            )
          else if (latest.isLoading)
            const SkeletonList(rows: 4, withAvatar: false)
          else if (latest.hasError)
            ErrorState(
              message: latest.error is AppError
                  ? (latest.error! as AppError).message
                  : 'No pudimos traer tu reporte.',
              onRetry: () => ref.invalidate(latestWeeklyReportProvider),
            )
          else
            EmptyState(
              icon: PhosphorIcons.sparkle(),
              title: '${range.reportTitle}, en un reporte',
              body:
                  'Lo que salió bien, lo que se repite y algo para probar, '
                  'con tus registros de ${range.noun}.',
              primaryLabel: 'Generar reporte',
              onPrimary: _generate,
            ),
        ],
      ),
    );
  }
}

class _Generating extends StatelessWidget {
  const _Generating({required this.phase, required this.elapsed});

  final String phase;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    // La barra llega al 90 % en un minuto y ahí se queda: no promete un final
    // que no se conoce, pero muestra que el tiempo corre.
    final progress = (elapsed.inMilliseconds / 60000).clamp(0.0, 1.0) * 0.9;
    return Semantics(
      liveRegion: true,
      label: phase,
      child: NmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const NmSpinner(size: 20),
                const SizedBox(width: NmSpace.s3),
                Expanded(
                  child: Text(
                    phase,
                    style: NmTextStyles.from(NmType.body, color: nm.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s4),
            ClipRRect(
              borderRadius: NmRadius.brMd,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: nm.accent,
                backgroundColor: nm.divider,
              ),
            ),
            const SizedBox(height: NmSpace.s2),
            Text(
              'Puede tardar hasta un minuto.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.report,
    required this.onRegenerate,
    required this.tryLabel,
  });

  final WeeklyReport report;
  final VoidCallback onRegenerate;
  final String tryLabel;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final tiles = weeklyMetricTiles(report.metrics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${shortDay(report.periodFrom)} – ${shortDay(report.periodTo)}',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s1),
        Text(report.title, style: NmTextStyles.from(NmType.h2, color: nm.text)),
        const SizedBox(height: NmSpace.s6),

        if (tiles.isNotEmpty) ...<Widget>[
          Text(
            'CALCULADO CON TUS REGISTROS',
            style: NmTextStyles.from(NmType.overline, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          for (var i = 0; i < tiles.length; i += 2) ...<Widget>[
            StatCardRow(
              children: <Widget>[
                for (final t in tiles.skip(i).take(2))
                  StatCard(label: t.label, value: t.value, caption: t.caption),
              ],
            ),
            const SizedBox(height: NmSpace.s3),
          ],
          const SizedBox(height: NmSpace.s4),
        ],

        Row(
          children: <Widget>[
            Icon(
              PhosphorIcons.sparkle(),
              size: NmIconSize.sm,
              color: nm.textMuted,
            ),
            const SizedBox(width: NmSpace.s2),
            Expanded(
              child: Text(
                'Redactado con IA a partir de tus registros',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: NmSpace.s3),
        NmCard(
          child: Text(
            report.summary,
            style: NmTextStyles.from(NmType.body, color: nm.text),
          ),
        ),
        _Bullets(
          title: 'Lo que salió bien',
          items: report.achievements,
          icon: PhosphorIcons.checkCircle(),
        ),
        _Bullets(
          title: 'Lo que se repite',
          items: report.patterns,
          icon: PhosphorIcons.chartLine(),
        ),
        _Bullets(
          title: tryLabel,
          items: report.suggestions,
          icon: PhosphorIcons.lightbulb(),
          emphasis: true,
        ),
        if (report.closing.isNotEmpty) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          Text(
            report.closing,
            style: NmTextStyles.from(NmType.body, color: nm.textMuted),
          ),
        ],
        const SizedBox(height: NmSpace.s8),
        NmButton.secondary(
          label: 'Regenerar',
          block: true,
          icon: PhosphorIcons.arrowsClockwise(),
          onPressed: onRegenerate,
        ),
        const SizedBox(height: NmSpace.s2),
        Text(
          'Generado el ${longDay(report.createdAt).toLowerCase()} a las '
          '${timeOfDay(report.createdAt)}. No es un diagnóstico: para '
          'decisiones sobre tu salud, hablalo con tu nutricionista.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({
    required this.title,
    required this.items,
    required this.icon,
    this.emphasis = false,
  });

  final String title;
  final List<String> items;
  final IconData icon;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final nm = context.nm;
    final iconColor = emphasis
        ? (nm.isDark ? nm.accentText : nm.accent)
        : nm.textMuted;
    return Padding(
      padding: const EdgeInsets.only(top: NmSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NmSectionHeader(title: title),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: NmIconSize.sm, color: iconColor),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Expanded(
                    child: Text(
                      item,
                      style: NmTextStyles.from(NmType.body, color: nm.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Una tarjeta de número del resumen.
typedef WeeklyMetricTile = ({String label, String value, String? caption});

/// Las tarjetas que se pueden armar con lo que vino: días con registro,
/// calorías promedio contra el objetivo, proteína y cambio de peso.
///
/// Un dato que falta **no se muestra**, en vez de mostrarse en cero: una
/// semana sin pesajes no tuvo "0 kg de cambio". Y nada se pinta de rojo por
/// pasarse del objetivo: el número es un dato, no una nota.
List<WeeklyMetricTile> weeklyMetricTiles(WeeklyMetrics m) => <WeeklyMetricTile>[
  if (m.daysLogged != null)
    (
      label: 'Días con registro',
      value: m.periodDays == null
          ? '${m.daysLogged}'
          : '${m.daysLogged} de ${m.periodDays}',
      caption: null,
    ),
  if (m.kcalAverage != null)
    (
      label: 'Promedio diario',
      value: Fmt.kcal(m.kcalAverage!),
      caption: m.kcalTarget == null
          ? 'en los días con registro'
          : 'objetivo ${Fmt.kcal(m.kcalTarget!)}',
    ),
  if (m.proteinAverageG != null)
    (
      label: 'Proteína promedio',
      value: Fmt.grams(m.proteinAverageG!),
      caption: m.proteinTargetG == null
          ? null
          : 'objetivo ${Fmt.grams(m.proteinTargetG!)}',
    ),
  if (m.weightChangeKg != null)
    (
      label: 'Cambio de peso',
      value: '${Fmt.signedDecimal1(m.weightChangeKg!)} kg',
      caption: 'entre el primer y el último pesaje',
    ),
];
