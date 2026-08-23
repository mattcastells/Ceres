import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/ai_calorie_target.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/goal_planner.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../profile/dietary_screen.dart';
import '../profile/goal_picker_screen.dart';

/// S-05 · Alta guiada. Los datos con los que la app calcula, antes de Inicio.
///
/// **Es obligatoria y no tiene "Ahora no".** Antes de esto, crear la cuenta
/// dejaba a la persona en Inicio con un objetivo de 2.000 kcal que no salía de
/// ningún lado: sin fecha de nacimiento, altura ni peso no hay Mifflin-St Jeor,
/// así que el número grande de la pantalla principal era un valor de referencia
/// con forma de cuenta. El producto entero se apoya en que ningún número sea
/// inventado (RN-03); el primero que ve alguien no puede ser la excepción.
///
/// Los primeros cuatro pasos son los insumos de las fórmulas, en el orden en
/// que se encadenan: sexo y edad y altura y peso → BMR, nivel de actividad →
/// TDEE, objetivo → calorías y macros. Cada paso se guarda al pasar al
/// siguiente, así que cerrar la app a mitad de camino no obliga a empezar de
/// nuevo: al volver se retoma con lo que ya estaba cargado.
///
/// El quinto es el que cierra: muestra el número que salió y **pide
/// confirmarlo**. Antes de esto, elegir "Bajar de peso" en el paso 4 dejaba a
/// la persona en Inicio con un objetivo que nunca había visto —calculado con un
/// ritmo de 0,5 kg por semana que tampoco había elegido—, y el primer contacto
/// con el número más importante de la app era el widget de Inicio. Acá se ve,
/// se elige a qué ritmo, y se puede escribir otro: un objetivo que no se
/// confirmó no es un objetivo, es una suposición con forma de cuenta.
///
/// Quién queda adentro lo decide `CeresRepositories.needsOnboarding`, y lo
/// hace cumplir el `redirect` del router: no alcanza con mandar acá desde el
/// alta, porque a Inicio también se llega desde el splash de un arranque
/// posterior.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  /// Seis: los cuatro insumos de las fórmulas, cómo come, y el número que se
  /// confirma. El de alimentación se puede pasar de largo sin tocar nada —no
  /// es un requisito para calcular—, pero está en el alta y no escondido en
  /// Perfil porque es donde alguien celíaco espera decirlo.
  static const int totalSteps = 6;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;

  late BiologicalSex _sex;
  late DateTime? _birthDate;
  late ActivityLevel _level;
  GoalType? _goalType;
  GoalPace? _pace;

  /// El objetivo se escribe a mano en vez de salir de la fórmula.
  bool _manual = false;

  /// La propuesta de la IA, si se pidió y volvió. Aceptarla es lo que la
  /// convierte en el objetivo: mientras está acá es una opción más en pantalla.
  AiCalorieTarget? _proposal;
  bool _proposalAccepted = false;
  bool _asking = false;
  String? _proposalError;

  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _manualTarget;

  /// El número con el que se sigue si la fórmula no da (no debería pasar: los
  /// pasos 1 y 2 son obligatorios). Está para que nadie quede trabado en el
  /// último paso de una pantalla de la que no se sale.
  late final int _fallbackTarget;

  String? _birthError;
  String? _heightError;
  String? _weightError;

  @override
  void initState() {
    super.initState();
    // Se arranca con lo que ya haya. Quien vuelve porque le falta un dato no
    // tiene por qué volver a escribir los otros tres, y quien entra desde otro
    // teléfono se encuentra lo que trajeron las tablas.
    final profile = ref.read(profileProvider);
    final current = ref.read(currentGoalProvider);
    _sex = profile.biologicalSex;
    _birthDate = profile.birthDate;
    _level = profile.activityLevel;
    _goalType = current?.goalType;
    _fallbackTarget = current?.baseCalorieTarget ?? 2000;
    _height = TextEditingController(
      text: profile.heightCm?.round().toString() ?? '',
    );
    _weight = TextEditingController(
      text: ref.read(currentWeightProvider)?.toString() ?? '',
    );
    _manualTarget = TextEditingController();
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _manualTarget.dispose();
    super.dispose();
  }

  // ── Validación ──────────────────────────────────────────────────────────

  double? get _heightCm {
    final parsed = double.tryParse(_height.text.replaceAll(',', '.'));
    if (parsed == null || parsed < 90 || parsed > 250) return null;
    return parsed;
  }

  double? get _weightKg {
    final parsed = double.tryParse(_weight.text.replaceAll(',', '.'));
    if (parsed == null || parsed < 25 || parsed > 400) return null;
    return parsed;
  }

  /// El ritmo elegido, o el de arranque mientras no se haya tocado.
  GoalPace get _paceOrDefault =>
      _pace ?? GoalPreset.of(_goalType ?? GoalType.maintain).defaultPace;

  /// Lo que sale de los datos cargados hasta ahora.
  ///
  /// Es **el único** lugar del alta donde se llama a las fórmulas. Con dos, el
  /// resumen del paso 3 y el número que se confirma en el 5 podrían decir cosas
  /// distintas, y el que se guarda sería siempre el que no se vio.
  _Plan? get _plan {
    final birthDate = _birthDate;
    final heightCm = _heightCm;
    final weightKg = _weightKg;
    if (birthDate == null || heightCm == null || weightKg == null) return null;

    final bmrValue = bmrMifflinStJeor(
      weightKg: weightKg,
      heightCm: heightCm,
      ageYears: ageFromBirthDate(birthDate),
      sex: _sex,
    );
    final tdeeValue = tdee(bmr: bmrValue, activityLevel: _level);
    final goalType = _goalType;

    return _Plan(
      bmr: bmrValue,
      tdee: tdeeValue,
      sex: _sex,
      planned: goalType == null
          ? null
          : calorieTargetForPace(
              tdee: tdeeValue,
              goalType: goalType,
              fractionOfTdee: _paceOrDefault.fractionFor(goalType),
              sex: _sex,
            ),
    );
  }

  /// De dónde sale el número que se va a guardar. El orden es el de quién
  /// eligió: lo escrito gana sobre lo aceptado, y lo aceptado sobre la fórmula.
  TargetMethod get _method {
    if (_manual) return TargetMethod.manual;
    if (_proposalAccepted && _proposal != null) return TargetMethod.ai;
    return TargetMethod.calculated;
  }

  /// El número que se va a guardar. `null` mientras lo escrito a mano no sea un
  /// objetivo posible: es lo que mantiene apagado el botón del último paso.
  int? get _confirmedTarget {
    if (_manual) {
      final parsed = int.tryParse(_manualTarget.text.trim());
      if (parsed == null) return null;
      if (parsed < CalorieTargetRules.absoluteMin ||
          parsed > CalorieTargetRules.absoluteMax) {
        return null;
      }
      return parsed;
    }
    if (_proposalAccepted && _proposal != null) return _proposal!.targetKcal;
    return _plan?.result?.target ?? _fallbackTarget;
  }

  /// Le pide a la IA que proponga el objetivo con los datos ya cargados.
  ///
  /// La propuesta **no se aplica sola**: aparece al lado del número calculado,
  /// con su explicación y un botón para usarla. Un modelo que cambia el número
  /// más importante de la app sin que nadie lo mire no es una ayuda, es una
  /// decisión tomada por otro.
  Future<void> _askAi() async {
    final weightKg = _weightKg;
    final goalType = _goalType;
    final formulaTarget = _plan?.result?.target;
    if (weightKg == null || goalType == null || formulaTarget == null) return;

    setState(() {
      _asking = true;
      _proposalError = null;
    });

    try {
      final proposal = await ref
          .read(repositoryProvider)
          .proposeCalorieTarget(
            weightKg: weightKg,
            goalType: goalType,
            formulaTarget: formulaTarget,
          );
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _asking = false;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      // El error se muestra **en la pantalla** y no en un cartel que se va: acá
      // no hay a dónde volver, y quien no llegue a leerlo se queda sin saber si
      // conviene reintentar o seguir con el calculado.
      setState(() {
        _proposalError = error.message;
        _asking = false;
      });
    }
  }

  bool get _canContinue => switch (_step) {
    0 => _birthDate != null && ageFromBirthDate(_birthDate!) >= 13,
    1 => _heightCm != null && _weightKg != null,
    2 => true,
    // Alimentación: no elegir nada es una respuesta válida y la más común.
    3 => true,
    4 => _goalType != null,
    _ => _confirmedTarget != null,
  };

  // ── Guardado ────────────────────────────────────────────────────────────

  /// Guarda el paso que se está dejando atrás y avanza.
  ///
  /// Se escribe paso a paso y no todo al final a propósito: cada uno de estos
  /// datos vale por sí solo —la altura sirve aunque nunca se elija un objetivo—
  /// y perderlos porque la app se cerró en el paso siguiente sería obligar a
  /// repetir un formulario que ya se completó.
  Future<void> _next() async {
    if (!_canContinue || _saving) return;
    final repo = ref.read(repositoryProvider);
    setState(() => _saving = true);

    switch (_step) {
      case 0:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(
            biologicalSex: _sex,
            birthDate: _birthDate,
          ),
        );
      case 1:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(heightCm: _heightCm),
        );
        // El peso es un registro con fecha, no un campo del perfil: entra por
        // la misma puerta que el de todos los días, así que el primer punto de
        // la curva de progreso es el de hoy y no un valor suelto.
        await repo.logWeight(weightKg: _weightKg!, date: today());
      case 2:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(activityLevel: _level),
        );
      case 3:
        // Las restricciones ya se fueron guardando a medida que se tocaban los
        // chips, igual que en Perfil: no hay nada pendiente que escribir acá.
        break;
      case 4:
        // El objetivo no se guarda todavía: recién se confirma en el paso 6, y
        // guardarlo acá dejaría escrito un número que la persona no vio.
        break;
      default:
        await _finish(repo);
        return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _step++;
    });
  }

  Future<void> _finish(CeresRepositories repo) async {
    final preset = GoalPreset.of(_goalType!);
    final target = _confirmedTarget!;

    // Escribir un número bajo es una decisión que se puede tomar; tomarla sin
    // saberlo, no. La misma advertencia que en Objetivo y macros y en la hoja
    // de calorías: si el alta fuera el único lugar donde no aparece, sería el
    // más fácil para terminar en 900 kcal sin enterarse.
    final minimum = CalorieTargetRules.minimumFor(_sex);
    if (_manual && target < minimum) {
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
      if (confirmed != true) {
        if (!mounted) return;
        setState(() => _saving = false);
        return;
      }
    }

    await repo.saveGoal(
      GoalPlanner.build(
        preset: preset,
        profile: ref.read(profileProvider),
        weightKg: ref.read(currentWeightProvider),
        current: ref.read(currentGoalProvider),
        pace: _paceOrDefault,
        // Solo se pisa la fórmula si alguien decidió otra cosa: escribir el
        // número, o aceptar el que propuso la IA.
        manualTarget: _method == TargetMethod.calculated ? null : target,
        manualMethod: _method,
      ),
    );
    for (final goal in GoalPlanner.activityGoals(
      preset,
      existing: repo.activityGoals,
    )) {
      await repo.saveActivityGoal(goal);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    context.go(Routes.home);
  }

  void _back() {
    if (_step == 0 || _saving) return;
    setState(() => _step--);
  }

  /// La salida de emergencia.
  ///
  /// Sin esto, quien no quiera dar estos datos queda encerrado en una pantalla
  /// de la que no se sale ni cerrando la app —el router vuelve a traerlo acá en
  /// el próximo arranque—, y la única forma de salir sería desinstalar. Cerrar
  /// sesión no borra nada: los datos que haya siguen en el servidor.
  Future<void> _signOut() async {
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Salir sin completar?',
        body:
            'Volvés a la bienvenida. Tu cuenta y lo que tengas cargado quedan '
            'como están, y podés entrar de nuevo cuando quieras.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Seguir acá',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Salir',
            variant: NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(repositoryProvider).signOut();
    if (!mounted) return;
    context.go(Routes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return NmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s8),
          StepIndicator(current: _step + 1, total: OnboardingScreen.totalSteps),
          const SizedBox(height: NmSpace.s6),
          Text(
            switch (_step) {
              0 => 'Empecemos por vos',
              1 => 'Tu altura y tu peso de hoy',
              2 => '¿Cuánto te movés?',
              3 => '¿Hay algo que no comas?',
              4 => '¿Qué buscás?',
              _ => 'Tus calorías por día',
            },
            style: NmTextStyles.from(NmType.h1, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            switch (_step) {
              0 =>
                'La edad y el sexo entran en la fórmula del metabolismo basal. '
                    'No se comparten con nadie, ni con tus pals.',
              1 =>
                'Con esto y lo anterior ya podemos calcular cuánto gastás. El '
                    'peso lo vas a poder registrar todos los días.',
              2 =>
                'Es el multiplicador que convierte tu metabolismo basal en el '
                    'gasto del día. Elegí lo que hacés en una semana normal.',
              3 =>
                'Si no hay nada, seguí de largo. Esto no cambia tus calorías: '
                    'cambia lo que la IA te puede proponer para comer.',
              4 =>
                'De acá salen tus calorías, tus macros y tu objetivo semanal '
                    'de actividad. Se cambia cuando quieras.',
              _ =>
                'Esto es lo que sale de tus datos. Mirálo, elegí a qué ritmo '
                    'querés ir, y si no te cierra escribí el tuyo.',
            },
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s8),

          switch (_step) {
            0 => _StepIdentity(
              sex: _sex,
              birthDate: _birthDate,
              error: _birthError,
              onSex: (v) => setState(() => _sex = v),
              onBirthDate: (v) => setState(() {
                if (ageFromBirthDate(v) < 13) {
                  _birthError =
                      'Necesitás tener al menos 13 años para usar Ceres.';
                  return;
                }
                _birthError = null;
                _birthDate = v;
              }),
            ),
            1 => _StepBody(
              height: _height,
              weight: _weight,
              heightError: _heightError,
              weightError: _weightError,
              onChanged: () => setState(() {
                _heightError = _height.text.isEmpty || _heightCm != null
                    ? null
                    : 'Poné una altura entre 90 y 250 cm.';
                _weightError = _weight.text.isEmpty || _weightKg != null
                    ? null
                    : 'Poné un peso entre 25 y 400 kg.';
              }),
            ),
            2 => _StepActivity(
              level: _level,
              onChanged: (v) => setState(() => _level = v),
            ),
            // El mismo selector que Perfil → Preferencias y alergias, y se
            // guarda igual: al tocar, no al pasar de paso. Así una alergia
            // cargada acá sobrevive aunque la persona cierre la app antes de
            // terminar el alta.
            3 => DietaryPicker(
              selected: ref.watch(profileProvider).dietaryFlags,
              note: ref.watch(profileProvider).dietaryNote,
              onFlags: (flags) => ref
                  .read(repositoryProvider)
                  .updateProfile(
                    ref.read(profileProvider).copyWith(dietaryFlags: flags),
                  ),
              onNote: (note) => ref
                  .read(repositoryProvider)
                  .updateProfile(
                    ref.read(profileProvider).copyWith(dietaryNote: note),
                  ),
            ),
            4 => _StepGoal(
              selected: _goalType,
              weightKg: _weightKg,
              onChanged: (v) => setState(() {
                _goalType = v;
                // Cada objetivo arranca en su ritmo de referencia, y un número
                // escrito para el objetivo anterior no dice nada del nuevo.
                _pace = GoalPreset.of(v).defaultPace;
                _manual = false;
              }),
            ),
            _ => _StepPlan(
              plan: _plan,
              goalType: _goalType!,
              pace: _paceOrDefault,
              level: _level,
              manual: _manual,
              manualTarget: _manualTarget,
              fallbackTarget: _fallbackTarget,
              shownTarget: _confirmedTarget,
              method: _method,
              proposal: _proposal,
              proposalAccepted: _proposalAccepted,
              asking: _asking,
              proposalError: _proposalError,
              canAskAi:
                  _plan?.result != null &&
                  ref.read(repositoryProvider).canProposeCalorieTarget,
              onPace: (v) => setState(() {
                _pace = v;
                // La propuesta se hizo sobre otro ritmo: dejarla en pantalla
                // sería ofrecer la respuesta a una pregunta que ya cambió.
                _proposal = null;
                _proposalAccepted = false;
                _proposalError = null;
              }),
              onAskAi: _askAi,
              onAcceptProposal: () =>
                  setState(() => _proposalAccepted = true),
              onDiscardProposal: () => setState(() {
                _proposal = null;
                _proposalAccepted = false;
              }),
              onManual: (v) => setState(() {
                _manual = v;
                // Se arranca desde lo que está en pantalla: escribir el
                // objetivo es corregirlo, no inventarlo desde un campo vacío.
                if (v) {
                  _manualTarget.text =
                      (_confirmedTarget ?? _fallbackTarget).toString();
                }
              }),
              onManualChanged: () => setState(() {}),
            ),
          },

          // El resumen del cálculo, en cuanto hay con qué hacerlo.
          //
          // Aparece recién en el paso del nivel de actividad porque antes no
          // hay número que mostrar, y aparece porque pedir cuatro datos sin
          // decir para qué es pedirle a alguien que confíe. Acá se ve que el
          // objetivo sale de lo que se acaba de cargar y no de una tabla. En el
          // último paso no se repite: ahí el resumen es la pantalla entera.
          //
          // En el de alimentación tampoco: ahí no se está decidiendo nada que
          // cambie el número, y ponerlo al lado sugeriría que sí.
          if (_step == 2 || _step == 4) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            _CalculationPreview(plan: _plan, level: _level),
          ],

          const SizedBox(height: NmSpace.s8),
          NmButton(
            label: _step == OnboardingScreen.totalSteps - 1
                ? 'Confirmar y empezar'
                : 'Continuar',
            block: true,
            loading: _saving,
            onPressed: _canContinue ? _next : null,
          ),
          const SizedBox(height: NmSpace.s2),
          Row(
            children: <Widget>[
              if (_step > 0)
                NmButton.ghost(label: 'Atrás', onPressed: _back),
              const Spacer(),
              NmButton.ghost(label: 'Salir', onPressed: _signOut),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepIdentity extends StatelessWidget {
  const _StepIdentity({
    required this.sex,
    required this.birthDate,
    required this.error,
    required this.onSex,
    required this.onBirthDate,
  });

  final BiologicalSex sex;
  final DateTime? birthDate;
  final String? error;
  final ValueChanged<BiologicalSex> onSex;
  final ValueChanged<DateTime> onBirthDate;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final age = birthDate == null ? null : ageFromBirthDate(birthDate!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Sexo biológico',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        NmSegmentedControl<BiologicalSex>(
          options: BiologicalSex.values
              .map((s) => (s, s == BiologicalSex.unspecified ? 'Otro' : s.label))
              .toList(),
          value: sex,
          onChanged: onSex,
        ),
        const SizedBox(height: NmSpace.s2),
        const InfoNote(
          text: 'Se usa solo para la fórmula de metabolismo basal. Con "Otro" '
              'se toma el promedio de las dos.',
        ),
        const SizedBox(height: NmSpace.s6),
        NmDateField(
          label: 'Fecha de nacimiento',
          value: birthDate,
          error: error,
          helper: age == null ? null : '$age años',
          lastDate: DateTime.now(),
          // No es una suposición sobre nadie: es dónde abrir el calendario para
          // que el primer gesto sea elegir y no retroceder treinta años.
          initialDate: DateTime(DateTime.now().year - 30, 1, 1),
          onChanged: onBirthDate,
        ),
      ],
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.height,
    required this.weight,
    required this.heightError,
    required this.weightError,
    required this.onChanged,
  });

  final TextEditingController height;
  final TextEditingController weight;
  final String? heightError;
  final String? weightError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      NmNumberField(
        label: 'Altura',
        controller: height,
        suffix: 'cm',
        error: heightError,
        autofocus: true,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: NmSpace.s6),
      NmNumberField(
        label: 'Peso de hoy',
        controller: weight,
        suffix: 'kg',
        decimals: 1,
        error: weightError,
        helper: 'Queda registrado con la fecha de hoy.',
        onChanged: (_) => onChanged(),
      ),
    ],
  );
}

class _StepActivity extends StatelessWidget {
  const _StepActivity({required this.level, required this.onChanged});

  final ActivityLevel level;
  final ValueChanged<ActivityLevel> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final option in ActivityLevel.values)
        Padding(
          padding: const EdgeInsets.only(bottom: NmSpace.s2),
          child: NmRadioRow<ActivityLevel>(
            title: option.label,
            subtitle: option.description,
            value: option,
            groupValue: level,
            onChanged: onChanged,
          ),
        ),
    ],
  );
}

class _StepGoal extends StatelessWidget {
  const _StepGoal({
    required this.selected,
    required this.weightKg,
    required this.onChanged,
  });

  final GoalType? selected;
  final double? weightKg;
  final ValueChanged<GoalType> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final preset in GoalPreset.all)
        Padding(
          padding: const EdgeInsets.only(bottom: NmSpace.s3),
          child: GoalPresetCard(
            preset: preset,
            selected: preset.goalType == selected,
            weightKg: weightKg,
            onTap: () => onChanged(preset.goalType),
          ),
        ),
    ],
  );
}

/// Lo que sale de los datos cargados, calculado una sola vez.
///
/// Los mismos números que después explica Objetivo y macros, con las mismas
/// funciones: si acá dijera otra cosa que la pantalla de Objetivo, una de las
/// dos estaría mintiendo.
class _Plan {
  const _Plan({
    required this.bmr,
    required this.tdee,
    required this.sex,
    required this.planned,
  });

  final int bmr;
  final int tdee;
  final BiologicalSex sex;

  /// `null` hasta que haya un objetivo elegido: sin él no hay ajuste que
  /// aplicar y el gasto diario es lo único que se puede decir.
  final ({CalorieTargetResult target, double rateKgPerWeek})? planned;

  CalorieTargetResult? get result => planned?.target;

  /// Los kilos por semana que salen del ritmo elegido **para este gasto**.
  double get rateKgPerWeek => planned?.rateKgPerWeek ?? 0;
}

/// El resumen del cálculo mientras se cargan los datos.
class _CalculationPreview extends StatelessWidget {
  const _CalculationPreview({required this.plan, required this.level});

  final _Plan? plan;
  final ActivityLevel level;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    if (plan == null) return const SizedBox.shrink();

    return NmCard(
      child: Column(
        children: <Widget>[
          ValueRow(
            label: 'Metabolismo basal',
            caption: 'Mifflin-St Jeor',
            value: Fmt.kcal(plan.bmr),
          ),
          ValueRow(
            label: '× nivel de actividad',
            caption: level.label,
            value: Fmt.decimal2(level.factor),
          ),
          ValueRow(label: 'Gasto diario', value: Fmt.kcal(plan.tdee)),
          if (plan.result != null) ...<Widget>[
            const NmDivider(),
            ValueRow(
              label: 'Tu objetivo',
              value: Fmt.kcal(plan.result!.target),
              emphasis: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// El último paso: el número, a qué ritmo, y la opción de escribir otro.
///
/// El orden no es casual. Primero el número, porque es lo que se vino a saber.
/// Después el ritmo, con **el objetivo de cada opción al lado**: así la
/// elección no se hace sobre un adjetivo sino sobre las calorías que deja cada
/// una, que es la única diferencia real entre ellas. Último el campo para
/// escribirlo, porque es la salida para quien ya tiene un plan de un
/// profesional y no vino a que se lo calculemos.
class _StepPlan extends StatelessWidget {
  const _StepPlan({
    required this.plan,
    required this.goalType,
    required this.pace,
    required this.level,
    required this.manual,
    required this.manualTarget,
    required this.fallbackTarget,
    required this.shownTarget,
    required this.method,
    required this.proposal,
    required this.proposalAccepted,
    required this.asking,
    required this.proposalError,
    required this.canAskAi,
    required this.onPace,
    required this.onAskAi,
    required this.onAcceptProposal,
    required this.onDiscardProposal,
    required this.onManual,
    required this.onManualChanged,
  });

  final _Plan? plan;
  final GoalType goalType;
  final GoalPace pace;
  final ActivityLevel level;
  final bool manual;
  final TextEditingController manualTarget;
  final int fallbackTarget;

  /// El número que se va a guardar, o `null` si lo escrito todavía no sirve.
  final int? shownTarget;
  final TargetMethod method;
  final AiCalorieTarget? proposal;
  final bool proposalAccepted;
  final bool asking;
  final String? proposalError;
  final bool canAskAi;
  final ValueChanged<GoalPace> onPace;
  final VoidCallback onAskAi;
  final VoidCallback onAcceptProposal;
  final VoidCallback onDiscardProposal;
  final ValueChanged<bool> onManual;
  final VoidCallback onManualChanged;

  /// Lo que daría [option] con **este** gasto: el objetivo y los kilos por
  /// semana que implica.
  ({CalorieTargetResult target, double rateKgPerWeek})? _outcomeFor(
    GoalPace option,
  ) {
    final plan = this.plan;
    if (plan == null) return null;
    return calorieTargetForPace(
      tdee: plan.tdee,
      goalType: goalType,
      fractionOfTdee: option.fractionFor(goalType),
      sex: plan.sex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final result = plan?.result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NmCard(
          raised: true,
          child: Column(
            children: <Widget>[
              Text(
                shownTarget == null ? '—' : Fmt.integer(shownTarget!),
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.display, color: nm.text).tnum,
              ),
              Text(
                'kcal por día · ${method.label.toLowerCase()}',
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ),

        // Cuando el piso de RN-12 actúa hay que decirlo acá y no solo en
        // Objetivo y macros: si el número que se confirma en el alta salió de
        // un tope y no de la resta, callarlo es presentar como cálculo algo
        // que no lo es.
        if (result != null &&
            result.clamped &&
            method == TargetMethod.calculated) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          InfoNote(tone: NmNoteTone.caution, text: result.clampNotice),
        ],

        if (goalType != GoalType.maintain) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'A qué ritmo'),
          if (plan != null) ...<Widget>[
            Text(
              'Cada opción es una parte de tu gasto diario, que hoy es de '
              '${Fmt.kcal(plan!.tdee)}. Los kilos por semana salen de ahí.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s3),
          ],
          // Cada opción es una fracción de **su** gasto, no una cantidad fija
          // de kilos: los kilos por semana salen de ahí y se muestran como la
          // consecuencia que son.
          for (final option in GoalPace.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: NmRadioRow<GoalPace>(
                title: option.label,
                subtitle: _outcomeFor(option) == null
                    ? option.detailFor(goalType)
                    : '${option.shareLabelFor(goalType)} · ≈ '
                          '${Fmt.decimal2(_outcomeFor(option)!.rateKgPerWeek)}'
                          ' kg/semana',
                value: option,
                groupValue: pace,
                onChanged: onPace,
                trailing: _outcomeFor(option) == null
                    ? null
                    : Text(
                        Fmt.kcal(_outcomeFor(option)!.target.target),
                        style: NmTextStyles.from(
                          NmType.bodySm,
                          color: nm.textMuted,
                        ).tnum,
                      ),
              ),
            ),
          const SizedBox(height: NmSpace.s1),
          Text(
            pace.detailFor(goalType),
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],

        // La opción de que lo calcule la IA.
        //
        // Va después del ritmo y antes del campo a mano, que es el orden de
        // cuánto se aparta cada una de la fórmula. Y no se pide sola al entrar
        // al paso: gastar una consulta de la cuota de alguien que iba a
        // aceptar el número calculado es cobrarle por algo que no pidió.
        if (canAskAi) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          if (proposal == null)
            NmButton.ghost(
              label: asking ? 'Pensándolo…' : 'Que lo calcule la IA',
              block: true,
              loading: asking,
              onPressed: asking ? null : onAskAi,
            )
          else
            NmCard(
              raised: proposalAccepted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ValueRow(
                    label: 'La IA propone',
                    caption: proposalAccepted ? 'en uso' : null,
                    value: Fmt.kcal(proposal!.targetKcal),
                    emphasis: true,
                  ),
                  const SizedBox(height: NmSpace.s2),
                  Text(
                    proposal!.rationale,
                    style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                  ),
                  if (proposal!.clamped) ...<Widget>[
                    const SizedBox(height: NmSpace.s2),
                    InfoNote(
                      tone: NmNoteTone.caution,
                      text: 'La subimos al mínimo saludable de '
                          '${CalorieTargetRules.minimumFor(plan!.sex)} kcal.',
                    ),
                  ],
                  const SizedBox(height: NmSpace.s3),
                  if (proposalAccepted)
                    NmButton.ghost(
                      label: 'Volver al calculado',
                      onPressed: onDiscardProposal,
                    )
                  else
                    NmButton.ghost(
                      label: 'Usar este número',
                      onPressed: onAcceptProposal,
                    ),
                ],
              ),
            ),
          if (proposalError != null) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            InfoNote(
              tone: NmNoteTone.caution,
              text: proposalError!,
              action: 'Probar de nuevo',
              onAction: onAskAi,
            ),
          ],
        ],

        const SizedBox(height: NmSpace.s4),
        NmSwitchRow(
          title: 'Prefiero escribir el número',
          subtitle: 'Si seguís un plan de un profesional, este es el lugar.',
          value: manual,
          onChanged: onManual,
        ),
        if (manual) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          NmNumberField(
            label: 'Calorías por día',
            controller: manualTarget,
            suffix: 'kcal',
            helper: 'Entre ${CalorieTargetRules.absoluteMin} y '
                '${CalorieTargetRules.absoluteMax} kcal.',
            onChanged: (_) => onManualChanged(),
          ),
        ],

        if (plan != null) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'De dónde sale'),
          _CalculationPreview(plan: plan, level: level),
        ],

        const SizedBox(height: NmSpace.s4),
        const InfoNote(
          text: 'Es un punto de partida, no una indicación médica. Lo cambiás '
              'cuando quieras desde Perfil, y los días ya registrados '
              'conservan el objetivo con el que fueron cargados.',
        ),
      ],
    );
  }
}
