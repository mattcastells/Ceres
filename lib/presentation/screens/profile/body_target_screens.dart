import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/adherence.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/calculations/macros.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/goal.dart';
import '../../../domain/repositories/repositories.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../weight/weight_sheet.dart';

const _uuid = Uuid();

/// S-32 · Perfil corporal. Mantiene al día lo que alimenta BMR, TDEE y MET.
class BodyProfileScreen extends ConsumerStatefulWidget {
  const BodyProfileScreen({super.key});

  @override
  ConsumerState<BodyProfileScreen> createState() => _BodyProfileScreenState();
}

class _BodyProfileScreenState extends ConsumerState<BodyProfileScreen> {
  late final TextEditingController _height = TextEditingController(
    text: ref.read(profileProvider).heightCm?.round().toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);
    final weightKg = ref.watch(currentWeightProvider);
    final units = ref.watch(unitSystemProvider);
    final goal = ref.watch(currentGoalProvider);

    final age = profile.birthDate == null
        ? null
        : ageFromBirthDate(profile.birthDate!);

    int? suggested;
    if (profile.birthDate != null && profile.heightCm != null && weightKg != null) {
      final bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: profile.heightCm!,
        ageYears: age!,
        sex: profile.biologicalSex,
      );
      final tdeeValue = tdee(
        bmr: bmrValue,
        activityLevel: profile.activityLevel,
      );
      suggested = calorieTarget(
        tdee: tdeeValue,
        goalType: goal?.goalType ?? GoalType.maintain,
        rateKgPerWeek: goal?.rateKgPerWeek ?? 0,
        sex: profile.biologicalSex,
      ).target;
    }

    return NmScreen(
      title: 'Perfil corporal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Sexo biológico',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          NmSegmentedControl<BiologicalSex>(
            options: BiologicalSex.values
                .map(
                  (s) => (s, s == BiologicalSex.unspecified ? 'Otro' : s.label),
                )
                .toList(),
            value: profile.biologicalSex,
            onChanged: (v) =>
                repo.updateProfile(profile.copyWith(biologicalSex: v)),
          ),
          const SizedBox(height: NmSpace.s2),
          const InfoNote(
            text: 'Se usa solo para la fórmula de metabolismo basal.',
          ),
          const SizedBox(height: NmSpace.s6),
          NmDateField(
            label: 'Fecha de nacimiento',
            value: profile.birthDate,
            helper: age == null ? null : '$age años',
            lastDate: DateTime.now(),
            onChanged: (v) {
              if (ageFromBirthDate(v) < 13) {
                setState(
                  () => _error =
                      'Necesitás tener al menos 13 años para usar Ceres.',
                );
                return;
              }
              setState(() => _error = null);
              repo.updateProfile(profile.copyWith(birthDate: v));
            },
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            InfoNote(text: _error!, tone: NmNoteTone.caution),
          ],
          const SizedBox(height: NmSpace.s6),
          NmNumberField(
            label: 'Altura',
            controller: _height,
            suffix: 'cm',
            onChanged: (raw) {
              final parsed = double.tryParse(raw);
              if (parsed == null || parsed < 90 || parsed > 250) return;
              repo.updateProfile(profile.copyWith(heightCm: parsed));
            },
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'PESO ACTUAL',
                        style: NmTextStyles.from(
                          NmType.overline,
                          color: nm.textMuted,
                        ),
                      ),
                      const SizedBox(height: NmSpace.s1),
                      Text(
                        weightKg == null
                            ? 'Sin registro'
                            : Fmt.weight(weightKg, units),
                        style: NmTextStyles.from(
                          NmType.h3,
                          color: nm.text,
                        ).tnum,
                      ),
                    ],
                  ),
                ),
                NmButton.ghost(
                  label: 'Registrar',
                  onPressed: () => showWeightSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Nivel de actividad'),
          for (final level in ActivityLevel.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: NmRadioRow<ActivityLevel>(
                title: level.label,
                subtitle: level.description,
                value: level,
                groupValue: profile.activityLevel,
                onChanged: (v) =>
                    repo.updateProfile(profile.copyWith(activityLevel: v)),
              ),
            ),
          const SizedBox(height: NmSpace.s6),
          // El IMC no se carga: sale de tu último peso y de tu altura, y se
          // mueve solo cuando alguno de los dos cambia. Sin decirlo, un número
          // en una pantalla de formularios se lee como un campo que no anda.
          if (weightKg != null && profile.heightCm != null)
            NmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ValueRow(
                    label: 'IMC',
                    caption: 'calculado, no se edita',
                    value: Fmt.decimal1(
                      bmi(weightKg: weightKg, heightCm: profile.heightCm!),
                    ),
                    emphasis: true,
                  ),
                  const NmDivider(),
                  const SizedBox(height: NmSpace.s2),
                  FormulaRow(
                    expression: 'peso ÷ altura²',
                    values:
                        '${Fmt.decimal1(weightKg)} kg ÷ '
                        '(${Fmt.decimal2(profile.heightCm! / 100)} m)² = '
                        '${Fmt.decimal1(bmi(weightKg: weightKg, heightCm: profile.heightCm!))}',
                  ),
                  const SizedBox(height: NmSpace.s3),
                  Text(
                    'Se actualiza solo cada vez que registrás un peso nuevo.',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                  const SizedBox(height: NmSpace.s3),
                  const InfoNote(
                    text: 'Es una referencia poblacional y nada más: no '
                        'distingue músculo de grasa ni dice nada sobre tu '
                        'salud. Para composición corporal miran los pliegues '
                        'y la bioimpedancia.',
                  ),
                  const SizedBox(height: NmSpace.s3),
                  NmButton.ghost(
                    label: 'Ver mis medidas corporales',
                    onPressed: () => context.push(Routes.progressMeasurements),
                  ),
                ],
              ),
            ),
          if (suggested != null &&
              goal != null &&
              suggested != goal.baseCalorieTarget) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            InfoNote(
              tone: NmNoteTone.info,
              text: 'Tu objetivo sugerido pasaría de '
                  '${Fmt.integer(goal.baseCalorieTarget)} a '
                  '${Fmt.integer(suggested)} kcal.',
              action: 'Actualizar objetivo',
              onAction: () => context.push('/profile/target'),
            ),
          ],
        ],
      ),
    );
  }
}

/// S-33 · Objetivo y macros.
class TargetScreen extends ConsumerStatefulWidget {
  const TargetScreen({super.key});

  @override
  ConsumerState<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends ConsumerState<TargetScreen> {
  GoalType? _goalType;
  GoalPace? _pace;
  bool _manual = false;
  late final TextEditingController _manualValue = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _manualValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final goal = ref.watch(currentGoalProvider);
    final weightKg = ref.watch(currentWeightProvider) ?? 70;
    final repo = ref.watch(repositoryProvider);

    if (goal == null) {
      return const NmScreen(
        title: 'Objetivo',
        child: Center(child: Text('Todavía no hay un objetivo.')),
      );
    }

    final goalType = _goalType ?? goal.goalType;

    int? bmrValue;
    int? tdeeValue;
    var target = goal.baseCalorieTarget;
    var clamped = false;
    // El ritmo guardado son kilos por semana; el que se elige es una fracción
    // del gasto. Sin gasto no hay conversión posible y queda el de referencia.
    var pace = _pace ?? GoalPace.steady;
    var rate = goal.rateKgPerWeek;

    if (profile.birthDate != null && profile.heightCm != null) {
      bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: profile.heightCm!,
        ageYears: ageFromBirthDate(profile.birthDate!),
        sex: profile.biologicalSex,
      );
      tdeeValue = tdee(bmr: bmrValue, activityLevel: profile.activityLevel);
      pace =
          _pace ??
          GoalPace.nearestForRate(
            rateKgPerWeek: goal.rateKgPerWeek,
            goalType: goalType,
            tdee: tdeeValue,
          );
      final planned = calorieTargetForPace(
        tdee: tdeeValue,
        goalType: goalType,
        fractionOfTdee: pace.fractionFor(goalType),
        sex: profile.biologicalSex,
      );
      rate = planned.rateKgPerWeek;
      if (!_manual) {
        target = planned.target.target;
        clamped = planned.target.clamped;
      }
    }
    if (_manual) {
      target = int.tryParse(_manualValue.text) ?? goal.baseCalorieTarget;
    }

    // El campo se lee mientras se escribe, así que pasa por estados que no son
    // un objetivo: vacío, "0", "8". Con cero `macroTargets` **lanza** —su
    // contrato pide un valor positivo— y la pantalla se caía sola al tipearlo;
    // dividir por él para el porcentaje daría infinito. Se previsualiza con el
    // extremo del rango más cercano hasta que lo escrito sirva; guardar valida
    // aparte y no usa este valor.
    final previewTarget = target.clamp(
      CalorieTargetRules.absoluteMin,
      CalorieTargetRules.absoluteMax,
    );

    final macros = macroTargets(
      targetKcal: previewTarget,
      weightKg: weightKg,
      goalType: goalType,
    );
    final method = _manual ? TargetMethod.manual : TargetMethod.calculated;
    // El método también cuenta: pasar de manual a calculado con el mismo número
    // es un cambio real, y sin esto el botón quedaba deshabilitado.
    final dirty =
        target != goal.baseCalorieTarget ||
        goalType != goal.goalType ||
        rate != goal.rateKgPerWeek ||
        method != goal.targetMethod;
    final effectiveRate = goalType == GoalType.maintain ? 0.0 : rate;

    return NmScreen(
      title: 'Objetivo y macros',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Objetivo vigente',
                  value: Fmt.kcal(goal.baseCalorieTarget),
                  emphasis: true,
                ),
                ValueRow(
                  label: 'Rige desde',
                  value: _formatDate(goal.startsOn),
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          if (bmrValue != null) ...<Widget>[
            const NmSectionHeader(title: 'Cómo se calcula'),
            NmCard(
              child: Column(
                children: <Widget>[
                  ValueRow(
                    label: 'Metabolismo basal',
                    caption: 'Mifflin-St Jeor',
                    value: Fmt.kcal(bmrValue),
                  ),
                  ValueRow(
                    label: '× factor de actividad',
                    caption: profile.activityLevel.label,
                    value: Fmt.decimal2(profile.activityLevel.factor),
                  ),
                  ValueRow(label: 'Gasto diario', value: Fmt.kcal(tdeeValue!)),
                  if (goalType != GoalType.maintain)
                    ValueRow(
                      label: goalType == GoalType.lose
                          ? '− déficit'
                          : '+ superávit',
                      caption: '${pace.shareLabelFor(goalType)} · '
                          '≈ ${Fmt.decimal2(effectiveRate)} kg/semana',
                      value: Fmt.kcal(
                        CalorieTargetRules.dailyAdjustment(
                          effectiveRate,
                        ).round(),
                      ),
                    ),
                  const NmDivider(),
                  ValueRow(
                    label: 'Objetivo',
                    value: Fmt.kcal(target),
                    emphasis: true,
                  ),
                ],
              ),
            ),
            if (clamped) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              InfoNote(
                tone: NmNoteTone.caution,
                text: 'Ajustamos tu objetivo al mínimo saludable de '
                    '${CalorieTargetRules.minimumFor(profile.biologicalSex)} '
                    'kcal.',
              ),
            ],
            const SizedBox(height: NmSpace.s6),
          ],
          NmSectionHeader(
            title: 'Tipo de objetivo',
            action: 'Ver los cuatro',
            onAction: () => context.push(Routes.profileGoal),
          ),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final type in GoalType.values)
                NmChip(
                  label: type.label,
                  selected: type == goalType,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() {
                    _goalType = type;
                    // Cada objetivo arranca en su ritmo de referencia;
                    // conservar el del objetivo anterior daba combinaciones
                    // raras, como ganar músculo al ritmo más exigente.
                    _pace = GoalPreset.of(type).defaultPace;
                  }),
                ),
            ],
          ),
          if (goalType != GoalType.maintain) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            const NmSectionHeader(title: 'Ritmo'),
            // El ritmo es una fracción de **tu** gasto, no una cantidad fija
            // de kilos: los kilos por semana son la consecuencia y se muestran
            // como tal.
            for (final option in GoalPace.values)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s2),
                child: NmRadioRow<GoalPace>(
                  title: option.label,
                  subtitle: tdeeValue == null
                      ? option.detailFor(goalType)
                      : '${option.shareLabelFor(goalType)} · ≈ '
                            '${Fmt.decimal2(_rateOf(option, goalType, tdeeValue))}'
                            ' kg/semana',
                  value: option,
                  groupValue: pace,
                  onChanged: (v) => setState(() => _pace = v),
                  trailing: tdeeValue == null
                      ? null
                      : Text(
                          Fmt.kcal(
                            _targetOf(
                              option,
                              goalType,
                              tdeeValue,
                              profile.biologicalSex,
                            ),
                          ),
                          style: NmTextStyles.from(
                            NmType.bodySm,
                            color: context.nm.textMuted,
                          ).tnum,
                        ),
                ),
              ),
            const SizedBox(height: NmSpace.s2),
            const InfoNote(text: 'El tope es 1 kg por semana.'),
          ],
          const SizedBox(height: NmSpace.s6),
          NmSwitchRow(
            title: 'Ingresar el objetivo a mano',
            value: _manual,
            onChanged: (v) => setState(() {
              _manual = v;
              if (v) _manualValue.text = target.toString();
            }),
          ),
          if (_manual) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            NmNumberField(
              label: 'Objetivo calórico',
              controller: _manualValue,
              suffix: 'kcal',
              helper: 'Entre 800 y 6000 kcal.',
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Macros sugeridos'),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Proteínas',
                  caption: '${(macros.proteinG * 4 * 100 / previewTarget).round()} %',
                  value: Fmt.grams(macros.proteinG),
                ),
                ValueRow(
                  label: 'Carbohidratos',
                  caption: '${(macros.carbsG * 4 * 100 / previewTarget).round()} %',
                  value: Fmt.grams(macros.carbsG),
                ),
                ValueRow(
                  label: 'Grasas',
                  caption: '${(macros.fatG * 9 * 100 / previewTarget).round()} %',
                  value: Fmt.grams(macros.fatG),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          const InfoNote(
            text: 'Al guardar, el objetivo nuevo rige desde hoy. Los días '
                'anteriores conservan el objetivo con el que fueron '
                'registrados.',
          ),
          // Sin datos corporales no hay fórmula posible: el objetivo solo puede
          // ser manual, y conviene decir dónde se cargan en vez de dejar el
          // botón apagado sin explicación.
          if (!profile.hasBodyData) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(
              text: 'Sin altura, nacimiento y sexo no se puede calcular. '
                  'Cargalos y el objetivo sale de tus datos.',
              action: 'Cargar mis datos',
              onAction: () => context.push(Routes.profileBody),
            ),
          ],
          const SizedBox(height: NmSpace.s4),
          NmButton(
            label: 'Guardar objetivo',
            block: true,
            loading: _saving,
            onPressed: !dirty
                ? null
                : () async {
                    // Y si está fuera de rango se dice. Antes era un `return`
                    // mudo: se tocaba "Guardar objetivo" y no pasaba nada, sin
                    // una sola pista de por qué.
                    if (target < CalorieTargetRules.absoluteMin ||
                        target > CalorieTargetRules.absoluteMax) {
                      NmSnackbar.show(
                        context,
                        'El objetivo va de ${CalorieTargetRules.absoluteMin} a '
                        '${CalorieTargetRules.absoluteMax} kcal.',
                      );
                      return;
                    }
                    final minimum = CalorieTargetRules.minimumFor(
                      profile.biologicalSex,
                    );
                    if (target < minimum) {
                      final confirmed = await showNmDialog<bool>(
                        context: context,
                        builder: (context) => NmDialog(
                          title: 'Es un objetivo muy bajo',
                          body: 'Por debajo de $minimum kcal cuesta cubrir los '
                              'nutrientes básicos.',
                          actions: <Widget>[
                            NmButton.ghost(
                              label: 'Volver',
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
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
                    await repo.saveGoal(
                      Goal(
                        id: _uuid.v4(),
                        goalType: goalType,
                        rateKgPerWeek: effectiveRate,
                        targetWeightKg: goal.targetWeightKg,
                        baseCalorieTarget: target,
                        targetMethod: _manual
                            ? TargetMethod.manual
                            : TargetMethod.calculated,
                        bmrKcal: bmrValue,
                        tdeeKcal: tdeeValue,
                        proteinG: macros.proteinG,
                        carbsG: macros.carbsG,
                        fatG: macros.fatG,
                        macroMethod: 'default',
                        startsOn: DateTime.now(),
                      ),
                    );
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    NmSnackbar.show(
                      context,
                      'Objetivo actualizado desde hoy',
                    );
                  },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  /// Los kilos por semana que le tocan a [pace] con este gasto.
  double _rateOf(GoalPace pace, GoalType goalType, int tdeeValue) =>
      calorieTargetForPace(
        tdee: tdeeValue,
        goalType: goalType,
        fractionOfTdee: pace.fractionFor(goalType),
        sex: ref.read(profileProvider).biologicalSex,
      ).rateKgPerWeek;

  /// El objetivo que dejaría [pace]. Va al lado de cada opción: es la única
  /// diferencia real entre ellas.
  int _targetOf(
    GoalPace pace,
    GoalType goalType,
    int tdeeValue,
    BiologicalSex sex,
  ) => calorieTargetForPace(
    tdee: tdeeValue,
    goalType: goalType,
    fractionOfTdee: pace.fractionFor(goalType),
    sex: sex,
  ).target.target;
}

/// S-34 · Mis alimentos, actividades, plantillas y favoritos.
///
/// Siempre abre en la primera solapa. El parámetro `initialTab` existía para
/// dos rutas —`/profile/templates` y `/profile/favorites`— que ninguna pantalla
/// navegaba, así que se fue con ellas.
class MyItemsScreen extends ConsumerStatefulWidget {
  const MyItemsScreen({super.key});

  @override
  ConsumerState<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends ConsumerState<MyItemsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final weightKg = ref.watch(currentWeightProvider);

    return NmScreen(
      title: 'Mis cosas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmSegmentedControl<int>(
            options: const <(int, String)>[
              (0, 'Alimentos'),
              (1, 'Plantillas'),
              (2, 'Favoritos'),
            ],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: NmSpace.s6),
          if (_tab == 0)
            _EmptyOrList(
              items: <_MyItem>[
                for (final food in repo.ownFoods())
                  _MyItem(
                    title: food.displayName,
                    onTap: () => context.push(Routes.food(food.id)),
                  ),
              ],
              emptyTitle: 'Sin alimentos propios',
              emptyBody: 'Los alimentos que crees aparecen acá.',
              icon: PhosphorIcons.bowlFood(),
            )
          else if (_tab == 1)
            repo.templates.isEmpty
                ? _EmptyOrList(
                    items: const <_MyItem>[],
                    emptyTitle: 'Sin plantillas',
                    emptyBody:
                        'Guardá una actividad como plantilla para repetirla '
                        'en dos toques.',
                    icon: PhosphorIcons.barbell(),
                  )
                : Column(
                    children: <Widget>[
                      for (final template in repo.templates)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NmSpace.s3),
                          child: ExerciseTemplateCard(
                            template: template,
                            typeName:
                                repo
                                    .typeById(template.activityTypeId)
                                    ?.displayName ??
                                'Actividad',
                            estimatedCalories: weightKg == null
                                ? null
                                : repo
                                      .estimate(
                                        ActivityDraft(
                                          activityTypeId:
                                              template.activityTypeId,
                                          startedAt: DateTime.now(),
                                          durationMinutes:
                                              template.defaultDurationMinutes,
                                          intensity: template.defaultIntensity,
                                          distanceMeters:
                                              template.defaultDistanceMeters,
                                        ),
                                      )
                                      .calories,
                            // Una plantilla se mira para usarla: abre el
                            // formulario ya cargado con lo que guardó.
                            onUse: () => context.push(
                              '${Routes.activityNew}?templateId=${template.id}',
                            ),
                            onDelete: () => repo.deleteTemplate(template.id),
                          ),
                        ),
                    ],
                  )
          else
            _EmptyOrList(
              items: <_MyItem>[
                for (final food in repo.favorites())
                  _MyItem(
                    title: food.name,
                    subtitle: 'Alimento',
                    onTap: () => context.push(Routes.food(food.id)),
                  ),
                for (final activity in repo.favoriteActivities())
                  _MyItem(
                    title: activity.displayName,
                    subtitle: 'Actividad',
                    onTap: () => context.push(Routes.activity(activity.id)),
                  ),
              ],
              emptyTitle: 'Sin favoritos',
              emptyBody: 'Marcá con la estrella lo que uses seguido.',
              icon: PhosphorIcons.star(),
            ),
        ],
      ),
    );
  }
}

/// Una fila de "Mis cosas" con adónde lleva.
///
/// La lista mostraba texto y nada más: se veía qué había guardado pero no se
/// podía abrir nada, así que el alimento propio o el favorito eran un nombre
/// suelto. Cada fila lleva ahora a su ficha.
class _MyItem {
  const _MyItem({required this.title, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}

class _EmptyOrList extends StatelessWidget {
  const _EmptyOrList({
    required this.items,
    required this.emptyTitle,
    required this.emptyBody,
    required this.icon,
  });

  final List<_MyItem> items;
  final String emptyTitle;
  final String emptyBody;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    // El vacío es el `EmptyState` del sistema y no una columna a mano: la de
    // acá no estiraba al ancho disponible, así que el título y el cuerpo
    // quedaban centrados entre sí pero corridos respecto de la pantalla.
    if (items.isEmpty) {
      return EmptyState(icon: icon, title: emptyTitle, body: emptyBody);
    }
    return NmCard(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
      child: Column(
        children: <Widget>[
          for (final item in items)
            NmListRow(
              title: item.title,
              subtitle: item.subtitle,
              dense: true,
              onTap: item.onTap,
              trailing: Icon(
                PhosphorIcons.caretRight(),
                size: NmIconSize.md,
                color: nm.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
