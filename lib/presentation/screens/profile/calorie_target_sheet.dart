import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/macros.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/goal.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

const _uuid = Uuid();

/// Ajuste rápido de las calorías por día.
///
/// Es el número que más se mira y el que más se quiere mover: antes solo se
/// podía cambiar entrando a Objetivo y macros y prendiendo un switch. Acá se
/// sube y se baja de a 50 kcal, o se escribe el valor. Guardar rige desde hoy;
/// los días ya registrados conservan el objetivo con el que se registraron
/// (F-13).
Future<void> showCalorieTargetSheet(BuildContext context) => showNmSheet<void>(
  context: context,
  builder: (context) => const _CalorieTargetSheet(),
);

/// Paso del +/−: menos que esto no mueve la aguja y más se pasa de largo.
const int _step = 50;

class _CalorieTargetSheet extends ConsumerStatefulWidget {
  const _CalorieTargetSheet();

  @override
  ConsumerState<_CalorieTargetSheet> createState() =>
      _CalorieTargetSheetState();
}

class _CalorieTargetSheetState extends ConsumerState<_CalorieTargetSheet> {
  late final TextEditingController _field;
  late int _value;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = ref.read(currentGoalProvider)?.baseCalorieTarget ?? 2000;
    _field = TextEditingController(text: _value.toString());
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(int value) {
    final clamped = value.clamp(
      CalorieTargetRules.absoluteMin,
      CalorieTargetRules.absoluteMax,
    );
    setState(() {
      _value = clamped;
      _field.text = clamped.toString();
      _error = null;
    });
  }

  /// El objetivo que saldría de la fórmula, si hay con qué calcularlo.
  int? _calculated() {
    final profile = ref.read(profileProvider);
    final weightKg = ref.read(currentWeightProvider);
    final goal = ref.read(currentGoalProvider);
    if (!profile.hasBodyData || weightKg == null || goal == null) return null;

    final bmrValue = bmrMifflinStJeor(
      weightKg: weightKg,
      heightCm: profile.heightCm!,
      ageYears: ageFromBirthDate(profile.birthDate!),
      sex: profile.biologicalSex,
    );
    final tdeeValue = tdee(bmr: bmrValue, activityLevel: profile.activityLevel);
    return calorieTargetForPace(
      tdee: tdeeValue,
      goalType: goal.goalType,
      // El ritmo guardado son kilos por semana; la regla ahora es una fracción
      // del gasto. Se traduce en vez de recalcularse desde un ritmo por
      // defecto: acá no se elige nada, se muestra lo que daría el objetivo que
      // ya está puesto.
      fractionOfTdee: goal.goalType == GoalType.maintain
          ? 0
          : fractionOfTdeeForRate(
              rateKgPerWeek: goal.rateKgPerWeek,
              tdee: tdeeValue,
            ),
      sex: profile.biologicalSex,
    ).target.target;
  }

  Future<void> _save({required bool backToCalculated}) async {
    final goal = ref.read(currentGoalProvider);
    if (goal == null) return;

    final calculated = _calculated();
    final target = backToCalculated ? (calculated ?? _value) : _value;

    if (target < CalorieTargetRules.absoluteMin ||
        target > CalorieTargetRules.absoluteMax) {
      setState(
        () => _error = 'El objetivo va de ${CalorieTargetRules.absoluteMin} a '
            '${CalorieTargetRules.absoluteMax} kcal.',
      );
      return;
    }

    final profile = ref.read(profileProvider);
    final minimum = CalorieTargetRules.minimumFor(profile.biologicalSex);
    if (target < minimum) {
      final confirmed = await showNmDialog<bool>(
        context: context,
        builder: (context) => NmDialog(
          title: 'Es un objetivo muy bajo',
          body: 'Por debajo de $minimum kcal cuesta cubrir los nutrientes '
              'básicos.',
          actions: <Widget>[
            NmButton.ghost(
              label: 'Volver',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NmButton(
              label: 'Guardar igual',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _saving = true);
    final weightKg = ref.read(currentWeightProvider) ?? 70;
    final macros = macroTargets(
      targetKcal: target,
      weightKg: weightKg,
      goalType: goal.goalType,
    );

    await ref
        .read(repositoryProvider)
        .saveGoal(
          Goal(
            // Id nuevo: `saveGoal` cierra el vigente e inserta este. Reusar el
            // id dejaría dos filas distintas con la misma clave.
            id: _uuid.v4(),
            goalType: goal.goalType,
            rateKgPerWeek: goal.rateKgPerWeek,
            targetWeightKg: goal.targetWeightKg,
            baseCalorieTarget: target,
            targetMethod: backToCalculated
                ? TargetMethod.calculated
                : TargetMethod.manual,
            bmrKcal: goal.bmrKcal,
            tdeeKcal: goal.tdeeKcal,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            macroMethod: goal.macroMethod,
            startsOn: today(),
          ),
        );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    NmSnackbar.show(context, 'Objetivo: ${Fmt.kcal(target)} desde hoy');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final goal = ref.watch(currentGoalProvider);
    final calculated = _calculated();

    return NmSheet(
      title: 'Calorías por día',
      subtitle: goal == null
          ? null
          : 'Ahora: ${Fmt.kcal(goal.baseCalorieTarget)} · '
                '${goal.targetMethod.label.toLowerCase()}',
      footer: NmButton(
        label: 'Guardar',
        block: true,
        loading: _saving,
        onPressed: goal == null ? null : () => _save(backToCalculated: false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              NmIconButton(
                icon: PhosphorIcons.minus(),
                tooltip: 'Bajar $_step kcal',
                onPressed: () => _set(_value - _step),
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      Fmt.integer(_value),
                      textAlign: TextAlign.center,
                      style: NmTextStyles.from(
                        NmType.display,
                        color: nm.text,
                      ).tnum,
                    ),
                    Text(
                      'kcal por día',
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              NmIconButton(
                icon: PhosphorIcons.plus(),
                tooltip: 'Subir $_step kcal',
                onPressed: () => _set(_value + _step),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
          NmNumberField(
            label: 'O escribilo',
            controller: _field,
            suffix: 'kcal',
            error: _error,
            onChanged: (raw) {
              final parsed = int.tryParse(raw.trim());
              if (parsed == null) return;
              setState(() {
                _value = parsed;
                _error = null;
              });
            },
          ),
          const SizedBox(height: NmSpace.s4),

          if (calculated != null && calculated != _value)
            NmCard(
              raised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ValueRow(
                    label: 'Con tus datos daría',
                    value: Fmt.kcal(calculated),
                    muted: true,
                  ),
                  const SizedBox(height: NmSpace.s2),
                  NmButton.ghost(
                    label: 'Usar el calculado',
                    onPressed: () => _save(backToCalculated: true),
                  ),
                ],
              ),
            )
          else if (calculated == null)
            InfoNote(
              text: 'Con altura, nacimiento y un peso registrado, se puede '
                  'calcular.',
              action: 'Cargar mis datos',
              onAction: () {
                Navigator.of(context).pop();
                context.push(Routes.profileBody);
              },
            ),

          const SizedBox(height: NmSpace.s4),
          Text(
            'Rige desde hoy; los días anteriores no cambian.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
