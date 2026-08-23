import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../data/local/pdf_report.dart';
import '../../../domain/calculations/tracking_window.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/summaries.dart';
import '../../../domain/services/report_builder.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Configuración → Tu informe.
///
/// Genera un PDF con el promedio, el resumen y el análisis del período: lo que
/// comiste, lo que te moviste, cómo se movió tu peso y qué nutrientes cubriste.
/// Se arma con lo que ya está en el teléfono —no sale a la red, no pasa por
/// ningún modelo— y sale con el mismo tema que tenés puesto en la app.
///
/// Una sola decisión antes de generar: el período. Todo lo demás lo decide el
/// informe, porque preguntarle a alguien qué secciones quiere en su propio
/// resumen es hacerle armar el resumen.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ProgressRange _range = ProgressRange.d30;
  bool _busy = false;

  Future<void> _generar() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final to = today();
      final from = to.subtract(Duration(days: _range.days - 1));

      final report = ReportBuilder.build(
        profile: repo.profile,
        goal: repo.currentGoalOrNull,
        progress: repo.progress(from: from, to: to),
        days: <DailySummary>[
          for (var i = 0; i < _range.days; i++)
            repo.daily(from.add(Duration(days: i))),
        ],
        glassesOn: repo.glassesOn,
        sleepMinutesOn: (date) => repo.sleepOn(date)?.minutes,
        measurementsOf: repo.measurements,
        // Desde cuándo usa la app: es lo que evita decirle "16 de 30 días" a
        // alguien que la instaló hace dos semanas.
        trackingSince: repo.trackingSince,
        generatedAt: DateTime.now(),
      );

      // El tema del informe es el de la app, con `system` resuelto contra el
      // teléfono: alguien que usa Ceres en claro no espera abrir un PDF
      // negro.
      final mode = repo.profile.themeMode;
      final dark = switch (mode) {
        ThemeModeSetting.dark => true,
        ThemeModeSetting.light => false,
        ThemeModeSetting.system =>
          MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      };

      final bytes = await PdfReport(report: report, dark: dark).build();

      final directory = await getTemporaryDirectory();
      final name = 'ceres-informe-${isoDate(to)}.pdf';
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
          fileNameOverrides: <String>[name],
          subject: 'Mi informe de Ceres',
        ),
      );
    } on Object {
      // Cualquier fallo termina acá y se dice. Un botón que gira para siempre
      // es peor que un error: no se distingue de estar por terminar.
      if (!mounted) return;
      NmSnackbar.show(context, 'No pudimos generar el informe. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final to = today();
    final from = to.subtract(Duration(days: _range.days - 1));

    // El denominador de acá tiene que ser el mismo que el del PDF.
    //
    // Antes esta pantalla decía "4 de 90" con `_range.days` mientras el informe
    // que generaba abajo contaba desde `countingFrom` y salía con otro número:
    // dos pantallas del mismo flujo, contradiciéndose sobre el mismo período.
    // Ver `docs/contexto-diario.md`.
    final ventana = TrackingWindow(
      from: from,
      to: to,
      trackingSince: ref.read(repositoryProvider).trackingSince,
    );
    final conRegistro = ref
        .watch(daysWithRecordsProvider)
        .where((iso) {
          final date = DateTime.tryParse(iso);
          return date != null && ventana.contains(date);
        })
        .length;

    return NmScreen(
      title: 'Tu informe',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Un PDF con tus promedios, tus gráficos y cómo venís. Se arma con '
            'lo que ya está en el teléfono y queda en tus archivos.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),

          const NmSectionHeader(title: 'Período'),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final range in ProgressRange.values)
                NmChip(
                  label: range.label,
                  selected: range == _range,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _range = range),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),

          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Desde',
                  value: longDay(from),
                ),
                ValueRow(label: 'Hasta', value: longDay(to)),
                // El denominador a la vista antes de generar: un informe de 90
                // días con 4 registrados no es un informe de 90 días, y es
                // mejor saberlo acá que después de abrir el archivo.
                ValueRow(
                  label: 'Días con registro',
                  value: '$conRegistro de ${ventana.effectiveDays}',
                  muted: true,
                ),
                // Solo cuando la ventana se recortó: si no, "13 de 13" parece
                // un período elegido a mano y no el que se pidió.
                if (ventana.startedMidPeriod)
                  ValueRow(
                    label: 'Contado desde',
                    value: longDay(ventana.effectiveFrom),
                    muted: true,
                  ),
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Generar el PDF',
            block: true,
            icon: PhosphorIcons.filePdf(),
            loading: _busy,
            onPressed: conRegistro == 0 ? null : _generar,
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            conRegistro == 0
                ? 'No hay nada registrado en este período: elegí uno más largo.'
                : 'Las calorías del ejercicio y las comidas estimadas por IA '
                      'son estimaciones, y el informe lo aclara.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
