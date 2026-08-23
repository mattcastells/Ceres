import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/user_profile.dart';
import '../../components/brand/brand_mark.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/update_providers.dart';
import 'calorie_target_sheet.dart';

/// S-27 · Perfil.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final profile = ref.watch(profileProvider);
    final goal = ref.watch(currentGoalProvider);
    final palRequests = ref.watch(incomingPalRequestsProvider);
    final weightKg = ref.watch(currentWeightProvider);
    final activityGoals = ref.watch(activityGoalsProvider);
    final repo = ref.watch(repositoryProvider);

    final preset = goal == null ? null : GoalPreset.of(goal.goalType);
    final minutes = activityGoals
        .where((g) => g.goalType == ActivityGoalType.activeMinutes)
        .firstOrNull;
    final strength = activityGoals
        .where((g) => g.goalType == ActivityGoalType.strengthSessions)
        .firstOrNull;

    return NmScreen(
      title: 'Perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            onTap: () => showDisplayNameSheet(context),
            child: Row(
              children: <Widget>[
                Container(
                  height: 52,
                  width: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nm.accentFill,
                    borderRadius: BorderRadius.circular(NmRadius.full),
                  ),
                  child: Text(
                    (profile.displayName?.trim().isNotEmpty ?? false)
                        ? profile.displayName!.trim().characters.first
                              .toUpperCase()
                        : 'N',
                    style: NmTextStyles.from(
                      NmType.h3,
                      color: nm.accentOnFill,
                    ),
                  ),
                ),
                const SizedBox(width: NmSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        (profile.displayName?.trim().isNotEmpty ?? false)
                            ? profile.displayName!.trim()
                            : 'Poné tu nombre',
                        style: NmTextStyles.from(NmType.h4, color: nm.text),
                      ),
                      Text(
                        profile.isDemo
                            ? 'Modo demo · sin respaldo'
                            : profile.email ?? '',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.isDemo)
                  NmButton.ghost(
                    label: 'Crear cuenta',
                    onPressed: () => context.push(Routes.signUp),
                  )
                else
                  Icon(
                    PhosphorIcons.pencilSimple(),
                    size: NmIconSize.md,
                    color: nm.textMuted,
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),

          // Todo lo que define el día, junto y editable: qué se busca, cuántas
          // calorías, cuánta proteína y cuánto movimiento.
          if (goal != null && preset != null) ...<Widget>[
            const NmSectionHeader(title: 'Tu objetivo'),
            NmCard(
              child: Column(
                children: <Widget>[
                  ValueRow(
                    label: goal.goalType.label,
                    value: goal.goalType == GoalType.maintain
                        ? '—'
                        : '${Fmt.decimal2(goal.rateKgPerWeek)} kg/semana',
                    emphasis: true,
                    onEdit: () => context.push(Routes.profileGoal),
                    editTooltip: 'Cambiar de objetivo',
                  ),
                  const NmDivider(),
                  ValueRow(
                    label: 'Calorías por día',
                    caption: goal.targetMethod.label.toLowerCase(),
                    value: Fmt.kcal(goal.baseCalorieTarget),
                    onEdit: () => showCalorieTargetSheet(context),
                    editTooltip: 'Cambiar las calorías por día',
                  ),
                  ValueRow(
                    label: 'Proteína por día',
                    caption: weightKg == null
                        ? '${Fmt.decimal1(preset.proteinGPerKg)} g/kg'
                        : '${Fmt.decimal1(preset.proteinGPerKg)} g/kg de tu '
                              'peso',
                    value: Fmt.grams(goal.proteinG),
                    muted: true,
                  ),
                  if (minutes != null)
                    ValueRow(
                      label: 'Actividad por semana',
                      value: '${minutes.targetValue} min',
                      muted: true,
                    ),
                  if (strength != null)
                    ValueRow(
                      label: 'Fuerza por semana',
                      value:
                          '${strength.targetValue} '
                          '${strength.targetValue == 1 ? 'sesión' : 'sesiones'}',
                      muted: true,
                    ),
                  ValueRow(
                    label: 'El ejercicio suma',
                    value: profile.effectiveCreditPercentage == 0
                        ? 'No suma'
                        : '${profile.effectiveCreditPercentage} %',
                    muted: true,
                    onEdit: () => context.push(Routes.exerciseCredit),
                    editTooltip: 'Cambiar cuánto suma el ejercicio',
                  ),
                ],
              ),
            ),
            const SizedBox(height: NmSpace.s6),
          ],

          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                NmListRow(
                  title: 'Objetivo',
                  subtitle: 'Bajar, mantener, subir o ganar músculo',
                  leading: Icon(PhosphorIcons.flag()),
                  onTap: () => context.push(Routes.profileGoal),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Perfil corporal',
                  subtitle: 'Sexo, nacimiento, altura, nivel de actividad',
                  leading: Icon(PhosphorIcons.user()),
                  onTap: () => context.push(Routes.profileBody),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Preferencias y alergias',
                  subtitle: profile.hasDietaryLimits
                      ? _dietarySummary(profile)
                      : 'Lo que la IA no te va a sugerir',
                  leading: Icon(PhosphorIcons.plant()),
                  onTap: () => context.push(Routes.profileDietary),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Objetivo y macros',
                  subtitle: 'Cómo se calcula tu objetivo diario',
                  leading: Icon(PhosphorIcons.target()),
                  onTap: () => context.push(Routes.profileTarget),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Medidas corporales',
                  subtitle: 'Perímetros, pliegues y bioimpedancia',
                  leading: Icon(PhosphorIcons.ruler()),
                  onTap: () => context.push(Routes.progressMeasurements),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Mis alimentos y plantillas',
                  subtitle: 'Alimentos propios, actividades, favoritos',
                  leading: Icon(PhosphorIcons.bowlFood()),
                  onTap: () => context.push(Routes.profileFoods),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Mi nutricionista',
                  subtitle: 'Darle acceso a tu seguimiento, y cortarlo',
                  leading: Icon(PhosphorIcons.stethoscope()),
                  onTap: () => context.push(Routes.profileCare),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Qué ven mis pals',
                  subtitle: palRequests > 0
                      ? '$palRequests ${palRequests == 1 ? 'solicitud' : 'solicitudes'} sin responder'
                      : 'Fotos, agua, sueño y detalle de ejercicio',
                  leading: Icon(PhosphorIcons.users()),
                  trailing: palRequests == 0
                      ? null
                      : NmTag(
                          label: '$palRequests',
                          variant: NmTagVariant.accent,
                        ),
                  onTap: () => context.push(Routes.palSharing),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Configuración',
                  leading: Icon(PhosphorIcons.gear()),
                  onTap: () => context.push(Routes.settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s8),
          NmButton.secondary(
            label: 'Cerrar sesión',
            block: true,
            icon: PhosphorIcons.signOut(),
            onPressed: () async {
              // Lo pendiente **antes** de cerrar nada.
              //
              // El push tiene 8 s de espera y el respaldo 5, así que un
              // registro hecho justo antes de tocar acá no llegó ni a las
              // tablas ni a la copia. Y `repo.signOut()` resetea el documento:
              // ese dato no quedaba en ningún lado. Los comentarios de
              // `flush()` y `push()` decían desde siempre "se usa al cerrar
              // sesión" y no los llamaba nadie.
              //
              // Cerrar sesión sin conexión no puede quedar bloqueado, así que
              // los dos ya traen su propio plazo y un fallo no frena el cierre.
              await ref.read(relationalSyncProvider)?.push();
              await ref.read(cloudBackupProvider)?.flush();

              // Y recién ahora el servidor y después lo local: al revés, si el
              // cierre remoto fallara, quedaría una sesión abierta sin ninguna
              // pantalla desde donde cerrarla.
              await ref.read(authGatewayProvider).signOut();
              await repo.signOut();
              if (!context.mounted) return;
              context.go(Routes.welcome);
            },
          ),
          const SizedBox(height: NmSpace.s8),
          Center(
            child: Column(
              children: <Widget>[
                const BrandMark(size: 28, monochrome: true),
                const SizedBox(height: NmSpace.s2),
                Text(
                  ref
                      .watch(installedVersionLabelProvider)
                      .maybeWhen(
                        data: (v) => 'Ceres $v',
                        orElse: () => 'Ceres',
                      ),
                  style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que hay cargado, en una línea: "Vegetariano, sin gluten y 1 más".
///
/// El subtítulo dice lo que hay y no "Configurado", que obligaría a entrar para
/// saber si la alergia que uno cargó sigue estando.
String _dietarySummary(UserProfile profile) {
  final labels = <String>[for (final f in profile.dietaryFlags) f.label];
  if (labels.isEmpty) return 'Una nota tuya';
  if (labels.length <= 2) return labels.join(', ');
  return '${labels.take(2).join(', ')} y ${labels.length - 2} más';
}

/// Cambiar el nombre visible.
///
/// Es el único dato que ve un pal, así que tiene que poder cambiarse sin pasar
/// por el servidor de correo ni por soporte. Se guarda local siempre y, si hay
/// sesión contra Supabase, también en `profiles`.
Future<void> showDisplayNameSheet(BuildContext context) => showNmSheet<void>(
  context: context,
  builder: (context) => const _DisplayNameSheet(),
);

class _DisplayNameSheet extends ConsumerStatefulWidget {
  const _DisplayNameSheet();

  @override
  ConsumerState<_DisplayNameSheet> createState() => _DisplayNameSheetState();
}

class _DisplayNameSheetState extends ConsumerState<_DisplayNameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(profileProvider).displayName ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _name.text.trim();
    if (value.length < 2 || value.length > 80) {
      setState(() => _error = 'Poné entre 2 y 80 caracteres.');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    await repo.updateProfile(repo.profile.copyWith(displayName: value));

    // Si falla el servidor, el nombre local ya cambió: se avisa y se reintenta
    // la próxima vez, en vez de perder la edición.
    String? remoteError;
    try {
      await ref.read(palsClientProvider)?.setDisplayName(value);
    } on AppError catch (error) {
      remoteError = error.message;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    NmSnackbar.show(context, remoteError ?? 'Listo, ahora sos $value');
  }

  @override
  Widget build(BuildContext context) => NmSheet(
    title: 'Tu nombre',
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
        NmTextField(
          label: 'Nombre',
          controller: _name,
          error: _error,
          autofocus: true,
          hint: 'Como querés que te vean',
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: NmSpace.s4),
        const InfoNote(
          text: 'Es lo único que ven tus pals. Tu correo no se muestra nunca.',
        ),
      ],
    ),
  );
}
