import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// F-11 · Registrar peso (`sheet.weight`).
///
/// Un peso por día: registrar de nuevo actualiza el existente y avisa (D-16).
Future<void> showWeightSheet(BuildContext context, {DateTime? date}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _WeightSheet(date: date ?? DateTime.now()),
    );

/// El peso es de un día que ya pasó: un día futuro abierto para planificar
/// comidas cae en hoy. Sin esto el campo de fecha arrancaba en una fecha que su
/// propio selector no deja elegir, y el peso quedaba guardado en el futuro.
DateTime _notFuture(DateTime date) {
  final hoy = today();
  final dia = DateTime(date.year, date.month, date.day);
  return dia.isAfter(hoy) ? hoy : date;
}

class _WeightSheet extends ConsumerStatefulWidget {
  const _WeightSheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<_WeightSheet> {
  late final TextEditingController _weight;
  late final TextEditingController _notes;
  late DateTime _date = _notFuture(widget.date);
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    final existing = repo.weightOn(_date);
    final last = existing?.weightKg ?? repo.currentWeightKg;
    // En las unidades del perfil, igual que la etiqueta al lado del campo. Con
    // libras se mostraba el número en kilos, y lo que se escribía en libras se
    // guardaba como kilos.
    _weight = TextEditingController(
      text: last == null
          ? ''
          : Fmt.weightValue(last, ref.read(unitSystemProvider)),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Lo escrito, pasado a kilos.
  double? get _parsedKg {
    final value = double.tryParse(_weight.text.replaceAll(',', '.').trim());
    if (value == null) return null;
    return Fmt.fromWeightUnits(value, ref.read(unitSystemProvider));
  }

  /// Cambio grande en pocos días: se avisa, no se bloquea (F-11).
  ///
  /// Va por diálogo y no por un cartel dentro del sheet, como estaba antes. El
  /// cartel salía y **"Guardar" no guardaba**: hacía falta tocarlo una segunda
  /// vez, y si en el medio se tocaba el campo —lo primero que hace cualquiera
  /// cuando algo no pasó— el aviso se reseteaba y el botón volvía a no hacer
  /// nada. Era indistinguible de un botón roto, y así se reportó. Un pedido de
  /// confirmación tiene que tener el botón que confirma al lado.
  Future<bool> _confirmBigChange(double value, double previous) async {
    final delta = value - previous;
    final units = ref.read(unitSystemProvider);
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Confirmás ese peso?',
        body:
            'Son ${Fmt.signedWeight(delta, units)} respecto de tu último '
            'registro (${Fmt.weight(previous, units)}). Puede ser un error de '
            'tipeo.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Corregir',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Sí, guardar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _save() async {
    final value = _parsedKg;
    if (value == null || value < 25 || value > 400) {
      final units = ref.read(unitSystemProvider);
      String limit(double kg) => Fmt.integer(Fmt.toWeightUnits(kg, units));
      setState(
        () => _error =
            'Ingresá un peso entre ${limit(25)} y ${limit(400)} '
            '${Fmt.weightUnit(units)}.',
      );
      return;
    }

    final repo = ref.read(repositoryProvider);
    final previous = repo.currentWeightKg;
    final existing = repo.weightOn(_date);

    if (previous != null) {
      final logs = repo.weightLogs;
      if (logs.isNotEmpty) {
        final days = daysBetween(logs.first.localDate, _date).abs();
        if ((value - previous).abs() > 3 && days < 3) {
          final proceed = await _confirmBigChange(value, previous);
          if (!proceed || !mounted) return;
        }
      }
    }

    setState(() => _saving = true);
    await repo.logWeight(
      weightKg: value,
      date: _date,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    NmSnackbar.show(
      context,
      existing == null ? 'Peso registrado' : 'Peso actualizado',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final units = ref.watch(unitSystemProvider);

    return NmSheet(
      title: 'Registrar peso',
      subtitle: friendlyDay(_date),
      footer: NmButton(
        label: 'Guardar',
        block: true,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _weight,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: NmTextStyles.from(NmType.display, color: nm.text).tnum,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s4),
                child: Text(
                  Fmt.weightUnit(units),
                  style: NmTextStyles.from(NmType.h3, color: nm.textMuted),
                ),
              ),
            ],
          ),
          const NmDivider(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            InfoNote(text: _error!, tone: NmNoteTone.caution),
          ],
          const SizedBox(height: NmSpace.s6),
          NmDateField(
            label: 'Fecha',
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() => _date = v),
          ),
          const SizedBox(height: NmSpace.s6),
          NmTextField(
            label: 'Nota (opcional)',
            controller: _notes,
            hint: 'Cómo te sentiste, la balanza que usaste…',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// El registro de medidas corporales vive en `measurement_sheet.dart`: dejó de
// ser un valor suelto y pasó a ser la planilla entera del día.
