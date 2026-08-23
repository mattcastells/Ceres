import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import 'measurement_draft.dart';

/// S-26 · Registrar medidas corporales.
///
/// Una nutricionista no entrega una medida: entrega una planilla con
/// perímetros, pliegues y lo que dijo la balanza, todo del mismo día. Por eso
/// el formulario carga la sesión entera y no un valor por vez, y viene con los
/// valores que ya haya de esa fecha para poder corregirlos.
///
/// El peso y la talla quedan afuera a propósito: el peso tiene su propio
/// registro diario y la altura vive en el perfil corporal, donde alimenta el
/// cálculo del metabolismo basal.
Future<void> showMeasurementSheet(
  BuildContext context, {
  DateTime? date,
  MeasurementGroup? group,
}) => showNmSheet<void>(
  context: context,
  builder: (context) => _MeasurementSheet(
    date: date ?? DateTime.now(),
    group: group ?? MeasurementGroup.perimeters,
  ),
);

class _MeasurementSheet extends ConsumerStatefulWidget {
  const _MeasurementSheet({required this.date, required this.group});

  final DateTime date;
  final MeasurementGroup group;

  @override
  ConsumerState<_MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends ConsumerState<_MeasurementSheet> {
  late MeasurementGroup _group = widget.group;
  late DateTime _date = widget.date;

  final MeasurementDraft _draft = MeasurementDraft();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft.loadFrom(ref.read(repositoryProvider), _date);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await _draft.commit(ref.read(repositoryProvider), _date);
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _saving = false;
        // Se salta al primer grupo con problemas para que el error se vea.
        final first = _draft.errors.keys.firstOrNull;
        if (first != null) _group = first.group;
      });
      return;
    }

    setState(() => _saving = false);
    Navigator.of(context).pop();
    NmSnackbar.show(
      context,
      saved == 1 ? 'Medida registrada' : '$saved medidas registradas',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final metrics = MeasurementMetric.inGroup(_group);
    final (foldSum, foldCount) = _draft.foldSum;

    return NmSheet(
      title: 'Registrar medidas',
      subtitle: friendlyDay(_date),
      footer: NmButton(
        label: 'Guardar',
        block: true,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NmSegmentedControl<MeasurementGroup>(
            options: const <(MeasurementGroup, String)>[
              (MeasurementGroup.perimeters, 'Perímetros'),
              (MeasurementGroup.skinfolds, 'Pliegues'),
              (MeasurementGroup.composition, 'Balanza'),
            ],
            value: _group,
            onChanged: (v) => setState(() => _group = v),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            _group.help,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s5),

          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s4),
              child: NmNumberField(
                label: metric.label,
                controller: _draft.controller(metric),
                decimals: 1,
                suffix: metric.unitLabel.isEmpty
                    ? 'índice'
                    : metric.unitLabel,
                error: _draft.errors[metric],
                onChanged: (_) => setState(() => _draft.errors.remove(metric)),
              ),
            ),

          if (_group == MeasurementGroup.skinfolds && foldCount >= 2) ...<Widget>[
            NmCard(
              raised: true,
              child: ValueRow(
                label: 'Sumatoria',
                caption: '$foldCount pliegues',
                value: '${Fmt.decimal1(foldSum)} mm',
                emphasis: true,
              ),
            ),
            const SizedBox(height: NmSpace.s3),
            Text(
              'Ceres no convierte los pliegues a porcentaje de grasa: cada '
              'ecuación pide un juego de pliegues distinto y da un número '
              'distinto. La suma sirve para compararte con vos mismo.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          NmDateField(
            label: 'Fecha',
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() {
              _date = v;
              _draft.loadFrom(ref.read(repositoryProvider), _date);
            }),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            'El peso se registra aparte, y la altura está en Perfil corporal.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
