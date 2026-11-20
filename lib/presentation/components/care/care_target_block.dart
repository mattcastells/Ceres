import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/models/care_feedback.dart';
import '../../../domain/models/goal.dart';
import '../../providers/app_providers.dart';
import '../../providers/care_providers.dart';
import '../system/buttons.dart';
import '../system/overlays.dart';
import '../system/surfaces.dart';

const _uuid = Uuid();

/// El objetivo recomendado por la nutricionista: los números, la nota y
/// "Aplicar".
///
/// Va en la tarjeta de Inicio y en la pantalla de devoluciones. El botón
/// aparece solo si aplicarlo cambia algo: si ya se aplicó dice cuándo, y si
/// los números ya son los del objetivo vigente lo dice en vez de ofrecer un
/// botón que no haría nada.
class CareTargetBlock extends ConsumerStatefulWidget {
  const CareTargetBlock({
    required this.feedback,
    this.compact = false,
    this.showLabel = true,
    super.key,
  });

  /// La indicación con números. Si no trae un objetivo, no se dibuja nada.
  final CareFeedback feedback;

  /// En Inicio la nota va recortada: la entera está en la lista.
  final bool compact;

  /// "Objetivo recomendado" arriba de los números. La lista ya lo dice en el
  /// encabezado de la sección.
  final bool showLabel;

  @override
  ConsumerState<CareTargetBlock> createState() => _CareTargetBlockState();
}

class _CareTargetBlockState extends ConsumerState<CareTargetBlock> {
  bool _applying = false;

  /// Lo que se aplicó en esta visita, hasta que la consulta lo traiga del
  /// servidor. Sin esto el botón volvía a aparecer un instante, y si la marca
  /// no llegaba (sin conexión), no cambiaba nunca.
  DateTime? _appliedHere;

  Future<void> _apply() async {
    setState(() => _applying = true);
    final applied = await applyCareTarget(context, ref, widget.feedback);
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (applied) _appliedHere = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.feedback.target;
    if (target == null) return const SizedBox.shrink();
    final nm = context.nm;
    final goal = ref.watch(currentGoalProvider);
    final appliedAt = widget.feedback.appliedAt ?? _appliedHere;
    final note = widget.feedback.note;

    final Widget status;
    if (appliedAt != null) {
      status = NmTag(
        label: 'Aplicado el ${shortDay(appliedAt)}',
        variant: NmTagVariant.success,
        icon: PhosphorIcons.check(),
      );
    } else if (target.differsFrom(goal)) {
      status = NmButton(
        label: 'Aplicar',
        loading: _applying,
        onPressed: _apply,
      );
    } else {
      status = Text(
        'Es tu objetivo actual',
        style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.showLabel) ...<Widget>[
          Text(
            'Objetivo recomendado',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s1),
        ],
        Text(
          target.compact,
          style: NmTextStyles.from(
            NmType.body,
            color: nm.text,
          ).tnum.copyWith(fontWeight: FontWeight.w600),
        ),
        if (note.isNotEmpty) ...<Widget>[
          const SizedBox(height: NmSpace.s1),
          Text(
            note,
            maxLines: widget.compact ? 2 : null,
            overflow: widget.compact ? TextOverflow.ellipsis : null,
            style: NmTextStyles.from(NmType.bodySm, color: nm.text),
          ),
        ],
        const SizedBox(height: NmSpace.s3),
        status,
      ],
    );
  }
}

/// Confirma y aplica el objetivo recomendado. Devuelve si se aplicó.
///
/// Aplicar es lo mismo que cambiar el objetivo a mano: `saveGoal` cierra el
/// vigente (`ends_on = ayer`) y abre este desde hoy, y sube con la
/// sincronización de siempre. Después se avisa al servidor con
/// `mark_care_target_applied`, en ese orden: si el aviso falla, el objetivo
/// ya quedó puesto y la profesional simplemente no ve "Aplicado".
Future<bool> applyCareTarget(
  BuildContext context,
  WidgetRef ref,
  CareFeedback feedback,
) async {
  final target = feedback.target;
  if (target == null) return false;
  final current = ref.read(currentGoalProvider);
  final next = target.toGoal(
    current: current,
    weightKg: ref.read(currentWeightProvider) ?? 70,
    id: _uuid.v4(),
    startsOn: today(),
  );

  final confirmed = await showNmDialog<bool>(
    context: context,
    builder: (context) => NmDialog(
      title: 'Aplicar el objetivo recomendado',
      body: 'Rige desde hoy; los días anteriores no cambian.',
      content: _Comparison(current: current, next: next),
      actions: <Widget>[
        NmButton.ghost(
          label: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NmButton(
          label: 'Aplicar',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  await ref.read(repositoryProvider).saveGoal(next);

  var told = true;
  final client = ref.read(careFeedbackClientProvider);
  if (client != null) {
    try {
      await client.markTargetApplied(feedback.id);
    } on AppError {
      told = false;
    }
  }
  if (told) ref.invalidate(careFeedbackProvider);

  if (context.mounted) {
    NmSnackbar.show(
      context,
      told
          ? 'Objetivo: ${Fmt.kcal(next.baseCalorieTarget)} desde hoy'
          : 'Objetivo actualizado. No pudimos avisarle a tu nutricionista.',
    );
  }
  return true;
}

/// Lo que cambia, fila por fila: el valor nuevo y, al lado, el de ahora.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.current, required this.next});

  final Goal? current;
  final Goal next;

  @override
  Widget build(BuildContext context) {
    String? now(int? v, String Function(num) fmt) =>
        v == null ? null : 'ahora ${fmt(v)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ValueRow(
          label: 'Calorías',
          caption: now(current?.baseCalorieTarget, Fmt.kcal),
          value: Fmt.kcal(next.baseCalorieTarget),
          emphasis: true,
        ),
        ValueRow(
          label: 'Proteínas',
          caption: now(current?.proteinG, Fmt.grams),
          value: Fmt.grams(next.proteinG),
        ),
        ValueRow(
          label: 'Carbohidratos',
          caption: now(current?.carbsG, Fmt.grams),
          value: Fmt.grams(next.carbsG),
        ),
        ValueRow(
          label: 'Grasas',
          caption: now(current?.fatG, Fmt.grams),
          value: Fmt.grams(next.fatG),
        ),
      ],
    );
  }
}
