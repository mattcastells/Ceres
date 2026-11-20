import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/icons.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/calculations/met_calories.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../system/inputs.dart';
import '../system/surfaces.dart';

/// Chips de tipo de actividad + "Ver todas" (S-10).
class ActivityTypeSelector extends StatelessWidget {
  const ActivityTypeSelector({
    required this.types,
    required this.value,
    required this.onChanged,
    required this.onBrowseAll,
    this.recentTypeIds = const <String>[],
    super.key,
  });

  final List<ActivityType> types;
  final List<String> recentTypeIds;
  final String? value;
  final ValueChanged<String> onChanged;
  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    // Los 4 chips iniciales: las más usadas, más la seleccionada si no está.
    final ordered = <ActivityType>[];
    for (final id in recentTypeIds) {
      final match = types.where((t) => t.id == id);
      if (match.isNotEmpty) ordered.add(match.first);
      if (ordered.length == 4) break;
    }
    for (final t in types) {
      if (ordered.length >= 4) break;
      if (!ordered.any((e) => e.id == t.id)) ordered.add(t);
    }
    if (value != null && !ordered.any((t) => t.id == value)) {
      final selected = types.where((t) => t.id == value);
      if (selected.isNotEmpty) ordered.insert(0, selected.first);
    }

    return Semantics(
      container: true,
      label: 'Tipo de actividad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Tipo',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final type in ordered.take(5))
                NmChip(
                  label: type.displayName,
                  icon: NmIcons.activity(type.iconName),
                  selected: type.id == value,
                  semanticsInRadioGroup: true,
                  onTap: () => onChanged(type.id),
                ),
              InkWell(
                onTap: onBrowseAll,
                borderRadius: BorderRadius.circular(NmRadius.full),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: NmSpace.s4,
                    vertical: NmSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NmRadius.full),
                    border: Border.all(color: nm.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        PhosphorIcons.magnifyingGlass(),
                        size: NmIconSize.md,
                        color: nm.textMuted,
                      ),
                      const SizedBox(width: NmSpace.s2),
                      Text(
                        'Ver todas',
                        style: NmTextStyles.from(
                          NmType.bodySm,
                          color: nm.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Suave · Moderada · Intensa, con el MET de cada una cuando el tipo lo define.
class ActivityIntensitySelector extends StatelessWidget {
  const ActivityIntensitySelector({
    required this.value,
    required this.onChanged,
    this.type,
    super.key,
  });

  final Intensity value;
  final ValueChanged<Intensity> onChanged;
  final ActivityType? type;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final showsPerIntensity = type?.hasPerIntensityMet ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Intensidad',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        Row(
          children: <Widget>[
            for (final intensity in Intensity.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: intensity == Intensity.vigorous ? 0 : NmSpace.s2,
                  ),
                  child: NmChip(
                    label: intensity.label,
                    subtitle: showsPerIntensity && type != null
                        ? 'MET ${Fmt.met(type!.metFor(intensity))}'
                        : null,
                    selected: intensity == value,
                    semanticsInRadioGroup: true,
                    onTap: () => onChanged(intensity),
                  ),
                ),
              ),
          ],
        ),
        if (type != null && !showsPerIntensity) ...<Widget>[
          const SizedBox(height: NmSpace.s2),
          const InfoNote(
            text: 'Este tipo usa el mismo valor para todas las intensidades.',
          ),
        ],
      ],
    );
  }
}

/// Tres formas de entrada, siempre visibles: presets, deslizador de 5 a 240
/// con paso de 5, y campo libre `hh:mm` hasta 24:00 (D-22).
class DurationInput extends StatefulWidget {
  const DurationInput({
    required this.valueMinutes,
    required this.onChanged,
    this.presets = const <int>[15, 30, 45, 60, 90, 120],
    this.error,
    super.key,
  });

  final int valueMinutes;
  final ValueChanged<int> onChanged;
  final List<int> presets;
  final String? error;

  static const int min = MetRanges.minDurationMinutes;
  static const int max = MetRanges.maxDurationMinutes;
  static const double sliderMax = 240;

  @override
  State<DurationInput> createState() => _DurationInputState();
}

class _DurationInputState extends State<DurationInput> {
  late final TextEditingController _controller = TextEditingController(
    text: Fmt.hhmm(widget.valueMinutes),
  );
  bool _editing = false;

  @override
  void didUpdateWidget(DurationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.valueMinutes != widget.valueMinutes) {
      _controller.text = Fmt.hhmm(widget.valueMinutes);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final value = widget.valueMinutes;
    final sliderValue = value.clamp(5, DurationInput.sliderMax.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Duración',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ),
            Text(
              Fmt.duration(value),
              style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
            ),
          ],
        ),
        const SizedBox(height: NmSpace.s2),
        Wrap(
          spacing: NmSpace.s2,
          runSpacing: NmSpace.s2,
          children: <Widget>[
            for (final preset in widget.presets)
              NmChip(
                label: '$preset min',
                selected: value == preset,
                onTap: () => widget.onChanged(preset),
              ),
          ],
        ),
        const SizedBox(height: NmSpace.s2),
        Semantics(
          slider: true,
          value: '$value minutos',
          child: Slider(
            value: sliderValue.toDouble(),
            min: 5,
            max: DurationInput.sliderMax,
            divisions: (DurationInput.sliderMax - 5) ~/ 5,
            label: Fmt.duration(sliderValue),
            onChanged: (v) => widget.onChanged(v.round()),
          ),
        ),
        Row(
          children: <Widget>[
            SizedBox(
              width: 108,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.datetime,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                style: NmTextStyles.from(NmType.body, color: nm.text).tnum,
                onTap: () => _editing = true,
                onEditingComplete: () {
                  _editing = false;
                  FocusScope.of(context).unfocus();
                },
                onChanged: (raw) {
                  final minutes = Fmt.parseHhmm(raw);
                  if (minutes != null &&
                      minutes >= DurationInput.min &&
                      minutes <= DurationInput.max) {
                    widget.onChanged(minutes);
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'hh:mm',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: NmSpace.s3),
            Expanded(
              child: Text(
                'Hasta 24:00. El deslizador llega a 4 h.',
                style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
              ),
            ),
          ],
        ),
        if (value > MetRanges.longSessionThresholdMinutes) ...<Widget>[
          const SizedBox(height: NmSpace.s2),
          const InfoNote(text: '¿Cuatro horas o más? Confirmá la duración.'),
        ],
        if (widget.error != null) ...<Widget>[
          const SizedBox(height: NmSpace.s2),
          Text(
            widget.error!,
            style: NmTextStyles.from(NmType.caption, color: nm.danger),
          ),
        ],
      ],
    );
  }
}

/// Distancia en la unidad del perfil; se almacena en metros.
class DistanceInput extends StatelessWidget {
  const DistanceInput({
    required this.controller,
    required this.units,
    required this.onChanged,
    this.error,
    super.key,
  });

  final TextEditingController controller;
  final UnitSystem units;
  final ValueChanged<int?> onChanged;
  final String? error;

  static const int maxMeters = 500000;

  @override
  Widget build(BuildContext context) => NmNumberField(
    label: 'Distancia',
    controller: controller,
    decimals: 2,
    suffix: Fmt.distanceUnit(units),
    error: error,
    onChanged: (raw) {
      final normalized = raw.replaceAll(',', '.');
      final parsed = double.tryParse(normalized);
      if (parsed == null) {
        onChanged(null);
        return;
      }
      final meters = units == UnitSystem.metric
          ? (parsed * 1000).round()
          : (parsed * 1609.344).round();
      onChanged(meters);
    },
  );
}

/// Radios 0/50/75/100 + personalizado con slider, con el copy fijo de S-28.
///
/// Con el ajuste apagado se ve marcado "No sumar", que es lo que significa.
/// Había además un interruptor "Desactivar completamente el ajuste por
/// ejercicio" que hacía lo mismo que ese radio; elegir cualquier opción ahora
/// lo deja prendido con ese porcentaje ([onChanged]).
class ExerciseCreditSelector extends StatelessWidget {
  const ExerciseCreditSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.previewEstimatedCalories,
    super.key,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final int? previewEstimatedCalories;

  static const List<int> presets = <int>[0, 50, 75, 100];

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final storedCustom = !presets.contains(value);
    final isCustom = enabled && storedCustom;
    final preview = previewEstimatedCalories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const InfoNote(
          text: 'Las calorías de ejercicio suelen sobreestimarse. Elegí cuánto '
              'sumar a tu objetivo.',
        ),
        const SizedBox(height: NmSpace.s4),
        for (final preset in presets)
          Padding(
            padding: const EdgeInsets.only(bottom: NmSpace.s2),
            child: NmRadioRow<int>(
              title: switch (preset) {
                0 => 'No sumar (recomendado)',
                100 => 'Sumar el 100 %',
                _ => 'Sumar el $preset %',
              },
              subtitle: preset == 0
                  ? 'Tu objetivo no cambia por el ejercicio'
                  : null,
              value: preset,
              groupValue: enabled ? value : 0,
              onChanged: onChanged,
            ),
          ),
        NmRadioRow<bool>(
          title: 'Porcentaje personalizado',
          value: true,
          groupValue: isCustom,
          onChanged: (_) => onChanged(storedCustom ? value : 25),
        ),
        if (isCustom)
          Padding(
            padding: const EdgeInsets.only(top: NmSpace.s2),
            child: Semantics(
              slider: true,
              value: preview == null
                  ? '$value por ciento'
                  : '$value por ciento, sumaría '
                        '${(preview * value / 100).round()} calorías hoy',
              child: Slider(
                value: value.toDouble(),
                max: 100,
                divisions: 20,
                label: '$value %',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
        const SizedBox(height: NmSpace.s4),
        if (preview != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NmSpace.s4),
            decoration: BoxDecoration(
              color: nm.surfaceRaised,
              borderRadius: NmRadius.brMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Con los datos de hoy',
                  style: NmTextStyles.from(
                    NmType.overline,
                    color: nm.textMuted,
                  ),
                ),
                const SizedBox(height: NmSpace.s2),
                Text(
                  enabled && value > 0
                      ? 'Con ${Fmt.integer(preview)} kcal de actividad, hoy '
                            'sumarías +${(preview * value / 100).round()} kcal'
                      : 'El ejercicio no suma a tu objetivo',
                  style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
