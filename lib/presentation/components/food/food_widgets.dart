import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/icons.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/food.dart';
import '../../../domain/models/meal.dart';
import '../activity/badges.dart';
import '../system/buttons.dart';
import '../system/surfaces.dart';

/// Sección de un slot en Inicio: título, total y botón "+".
class MealSection extends StatelessWidget {
  const MealSection({
    required this.slot,
    required this.meals,
    required this.onAdd,
    required this.onOpenMeal,
    this.onDeleteMeal,
    this.onDuplicateMeal,
    super.key,
  });

  final MealSlot slot;
  final List<Meal> meals;
  final VoidCallback onAdd;
  final void Function(Meal meal) onOpenMeal;
  final void Function(Meal meal)? onDeleteMeal;
  final void Function(Meal meal)? onDuplicateMeal;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final total = meals.fold(0, (acc, m) => acc + m.totalKcal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              NmIcons.mealSlot(slot),
              size: NmIconSize.md,
              color: nm.textMuted,
            ),
            const SizedBox(width: NmSpace.s2),
            Expanded(
              child: Text(
                slot.label,
                style: NmTextStyles.from(NmType.h4, color: nm.text),
              ),
            ),
            Text(
              Fmt.kcal(total),
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted).tnum,
            ),
            const SizedBox(width: NmSpace.s2),
            NmIconButton(
              icon: PhosphorIcons.plus(),
              onPressed: onAdd,
              tooltip: 'Agregar a ${slot.label.toLowerCase()}',
              size: NmIconSize.md,
            ),
          ],
        ),
        if (meals.isEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: NmSpace.s6,
              bottom: NmSpace.s2,
            ),
            child: Text(
              'Sin registros',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          )
        else
          for (final meal in meals)
            MealListItem(
              meal: meal,
              onTap: () => onOpenMeal(meal),
              onDelete: onDeleteMeal == null
                  ? null
                  : () => onDeleteMeal!(meal),
              onDuplicate: onDuplicateMeal == null
                  ? null
                  : () => onDuplicateMeal!(meal),
            ),
      ],
    );
  }
}

/// Fila de una comida. Mismo patrón de swipe que `ActivityListItem`.
class MealListItem extends StatelessWidget {
  const MealListItem({
    required this.meal,
    this.onTap,
    this.onDelete,
    this.onDuplicate,
    this.showDate = false,
    super.key,
  });

  final Meal meal;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final itemsLabel = meal.items.length == 1
        ? '1 ítem'
        : '${meal.items.length} ítems';

    final row = Semantics(
      button: onTap != null,
      label:
          '${meal.title}, $itemsLabel, ${Fmt.integer(meal.totalKcal)} '
          'kilocalorías',
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (onDuplicate != null)
          const CustomSemanticsAction(label: 'Duplicar'): onDuplicate!,
        if (onDelete != null)
          const CustomSemanticsAction(label: 'Eliminar'): onDelete!,
      },
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: NmRadius.brMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NmSpace.s3,
              vertical: NmSpace.s3,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Barrita de acento: separa la comida del título del slot,
                  // que también es texto alineado a la izquierda. Con ella la
                  // fila se lee como un ítem y no como otro encabezado.
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: (nm.isDark ? nm.accentText : nm.accent).withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: NmRadius.brSm,
                    ),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          meal.title,
                          overflow: TextOverflow.ellipsis,
                          style: NmTextStyles.from(NmType.body, color: nm.text),
                        ),
                        Text(
                          <String>[
                            if (showDate) shortDay(meal.localDate),
                            timeOfDay(meal.eatenAt),
                            itemsLabel,
                          ].join(' · '),
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ).tnum,
                        ),
                        if (meal.source == MealSource.aiPhoto ||
                            meal.syncStatus != SyncStatus.synced) ...<Widget>[
                          const SizedBox(height: NmSpace.s1),
                          Wrap(
                            spacing: NmSpace.s2,
                            children: <Widget>[
                              if (meal.source == MealSource.aiPhoto)
                                const DataOriginBadge(origin: DataOrigin.ai),
                              SyncStatusBadge(status: meal.syncStatus),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      Fmt.kcal(meal.totalKcal),
                      style: NmTextStyles.from(
                        NmType.bodySm,
                        color: nm.text,
                      ).tnum,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (onDelete == null) return row;

    return Dismissible(
      key: ValueKey<String>(meal.id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDuplicate?.call();
          return false;
        }
        onDelete?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: NmSpace.s6),
        decoration: BoxDecoration(
          color: nm.accent.withValues(alpha: 0.14),
          borderRadius: NmRadius.brMd,
        ),
        child: Icon(PhosphorIcons.copySimple(), color: nm.accent),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: NmSpace.s6),
        decoration: BoxDecoration(
          color: nm.danger.withValues(alpha: 0.14),
          borderRadius: NmRadius.brMd,
        ),
        child: Icon(PhosphorIcons.trash(), color: nm.danger),
      ),
      child: row,
    );
  }
}

/// Fila de un ítem dentro de `/meal/new`.
class MealItemRow extends StatelessWidget {
  const MealItemRow({
    required this.item,
    this.onEditPortion,
    this.onRemove,
    super.key,
  });

  final MealItem item;
  final VoidCallback? onEditPortion;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.name,
                  style: NmTextStyles.from(NmType.body, color: nm.text),
                ),
                Text(
                  item.portionLabel,
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ).tnum,
                ),
              ],
            ),
          ),
          Text(
            Fmt.kcal(item.kcal),
            style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
          ),
          if (onEditPortion != null)
            NmIconButton(
              icon: PhosphorIcons.pencilSimple(),
              onPressed: onEditPortion,
              tooltip: 'Cambiar porción',
              size: NmIconSize.md,
            ),
          if (onRemove != null)
            NmIconButton(
              icon: PhosphorIcons.x(),
              onPressed: onRemove,
              tooltip: 'Quitar ${item.name}',
              size: NmIconSize.md,
            ),
        ],
      ),
    );
  }
}

/// Barra fija inferior con los totales de la comida en edición.
class MealTotalsBar extends StatelessWidget {
  const MealTotalsBar({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.child,
    super.key,
  });

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      padding: EdgeInsets.fromLTRB(
        NmSpace.s4,
        NmSpace.s3,
        NmSpace.s4,
        NmSpace.s4 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: nm.surface,
        border: Border(top: BorderSide(color: nm.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  Fmt.kcal(kcal),
                  style: NmTextStyles.from(NmType.h3, color: nm.text).tnum,
                ),
              ),
              Text(
                'P ${Fmt.grams(proteinG)} · C ${Fmt.grams(carbsG)} · '
                'G ${Fmt.grams(fatG)}',
                style: NmTextStyles.from(
                  NmType.caption,
                  color: nm.textMuted,
                ).tnum,
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s3),
          child,
        ],
      ),
    );
  }
}

/// Fila de resultado del buscador, con badge de origen.
class FoodResultRow extends StatelessWidget {
  const FoodResultRow({required this.food, required this.onTap, super.key});

  final Food food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      button: true,
      label:
          '${food.displayName}, ${Fmt.integer(food.kcal)} kilocalorías por '
          '${Fmt.decimal1(food.servingSize)} ${food.servingUnit}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: NmRadius.brMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NmSpace.s3,
              vertical: NmSpace.s3,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        food.name,
                        overflow: TextOverflow.ellipsis,
                        style: NmTextStyles.from(NmType.body, color: nm.text),
                      ),
                      const SizedBox(height: NmSpace.s1),
                      Row(
                        children: <Widget>[
                          if (food.brand != null) ...<Widget>[
                            Flexible(
                              child: Text(
                                food.brand!,
                                overflow: TextOverflow.ellipsis,
                                style: NmTextStyles.from(
                                  NmType.caption,
                                  color: nm.textMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: NmSpace.s2),
                          ],
                          Text(
                            '${Fmt.decimal1(food.servingSize)} '
                            '${food.servingUnit}',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ).tnum,
                          ),
                        ],
                      ),
                      const SizedBox(height: NmSpace.s1),
                      NmTag(
                        label: food.source.label,
                        variant: food.source == FoodSource.user
                            ? NmTagVariant.accent
                            : NmTagVariant.outline,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Text(
                  Fmt.kcal(food.kcal),
                  style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabla nutricional por 100 g y por porción (S-17).
class NutritionTable extends StatelessWidget {
  const NutritionTable({
    required this.food,
    required this.quantity,
    super.key,
  });

  final Food food;

  /// Múltiplo de la porción de referencia.
  final double quantity;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final factor100 = food.servingSize <= 0 ? 0.0 : 100 / food.servingSize;

    // La columna "por 100 g" solo tiene sentido si la porción se mide en peso o
    // volumen. Para ARGENFOODS, Open Food Facts y USDA la porción **es** 100 g,
    // así que la cuenta es trivial; pero un alimento propio se puede crear con
    // porción "1 unidad" —el formulario lo permite— y ahí dividir por la
    // porción daba "por 100 g: 7.000 kcal" para un huevo de 70. Un disparate
    // con forma de dato, que es justo lo que la app no se permite.
    const unidadesDePeso = <String>{'g', 'gr', 'gramos', 'ml', 'cc'};
    final mostrarPor100 =
        unidadesDePeso.contains(food.servingUnit.trim().toLowerCase());

    Widget row(String label, double perServing, String unit) => Padding(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: NmTextStyles.from(NmType.bodySm, color: nm.text),
            ),
          ),
          if (mostrarPor100)
            SizedBox(
              width: 80,
              child: Text(
                '${Fmt.decimal1(perServing * factor100)}$unit',
                textAlign: TextAlign.right,
                style: NmTextStyles.from(
                  NmType.caption,
                  color: nm.textMuted,
                ).tnum,
              ),
            ),
          SizedBox(
            width: 80,
            child: Text(
              '${Fmt.decimal1(perServing * quantity)}$unit',
              textAlign: TextAlign.right,
              style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
            ),
          ),
        ],
      ),
    );

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: SizedBox.shrink()),
            if (mostrarPor100)
              SizedBox(
                width: 80,
                child: Text(
                  'por 100 ${food.servingUnit.trim().toLowerCase() == 'ml' ? 'ml' : 'g'}',
                  textAlign: TextAlign.right,
                  style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
                ),
              ),
            SizedBox(
              width: 80,
              child: Text(
                'porción',
                textAlign: TextAlign.right,
                style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
              ),
            ),
          ],
        ),
        const NmDivider(),
        row('Calorías', food.kcal.toDouble(), ' kcal'),
        row('Proteínas', food.proteinG, ' g'),
        row('Carbohidratos', food.carbsG, ' g'),
        row('Grasas', food.fatG, ' g'),
        if (food.fiberG != null) row('Fibra', food.fiberG!, ' g'),
        if (food.sugarG != null) row('Azúcares', food.sugarG!, ' g'),
        if (food.sodiumMg != null) row('Sodio', food.sodiumMg!, ' mg'),
      ],
    );
  }
}

/// Banner ámbar obligatorio de la pantalla de revisión (S-20).
class AiEstimateBanner extends StatelessWidget {
  const AiEstimateBanner({required this.confidenceAvg, super.key});

  final double confidenceAvg;

  @override
  Widget build(BuildContext context) => InfoNote(
    tone: NmNoteTone.caution,
    icon: PhosphorIcons.sparkle(),
    text: 'Estimación de IA: revisá antes de guardar. Con una foto, las '
        'porciones tienen un error típico de ±25 %.',
  );
}

/// Fila compacta de peso en Inicio.
class WeightRow extends StatelessWidget {
  const WeightRow({
    required this.units,
    required this.onLog,
    this.weightKg,
    this.deltaKg,
    super.key,
  });

  final double? weightKg;
  final double? deltaKg;
  final UnitSystem units;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    if (weightKg == null) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Sin peso registrado',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ),
          NmButton.ghost(label: 'Registrar peso', onPressed: onLog),
        ],
      );
    }

    final delta = deltaKg ?? 0;
    return Row(
      children: <Widget>[
        Icon(PhosphorIcons.scales(), size: NmIconSize.md, color: nm.textMuted),
        const SizedBox(width: NmSpace.s2),
        Expanded(
          child: Text(
            Fmt.weight(weightKg!, units),
            style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
          ),
        ),
        if (delta != 0)
          Text(
            Fmt.signedWeight(delta, units),
            style: NmTextStyles.from(
              NmType.caption,
              color: nm.textMuted,
            ).tnum,
          ),
        const SizedBox(width: NmSpace.s2),
        NmButton.ghost(label: 'Actualizar', onPressed: onLog),
      ],
    );
  }
}
