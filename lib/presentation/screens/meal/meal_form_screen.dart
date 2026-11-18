import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/calculations/meal_title.dart';
import '../../../domain/enums/enums.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/food_widgets.dart';
import '../../components/food/meal_photo.dart';
import '../../components/food/meal_photo_field.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../photo/photo_screens.dart';
import 'edit_portion_sheet.dart';
import 'meal_draft.dart';
import 'quick_add_item.dart';
import 'recalculate_sheet.dart';

/// S-15 · Nueva comida. Compone una comida a partir de ítems.
class MealFormScreen extends ConsumerStatefulWidget {
  const MealFormScreen({
    this.slot,
    this.date,
    this.mealId,
    this.scanOnOpen = false,
    super.key,
  });

  final MealSlot? slot;
  final DateTime? date;

  /// Cuando viene, se edita una comida existente (RN-16, D-20).
  final String? mealId;

  /// Abre el escáner encima, con la comida ya abierta debajo.
  ///
  /// Es cómo entra "Escanear alimento" del menú Agregar. Antes ese camino iba
  /// derecho al escáner, sin comida abierta, y el alimento elegido se agregaba
  /// a un borrador que no existía: `addItem` sobre `null` no hace nada y no
  /// avisa, así que escanear desde ahí no dejaba nada cargado.
  final bool scanOnOpen;

  @override
  ConsumerState<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends ConsumerState<MealFormScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(mealDraftProvider.notifier);
      final current = ref.read(mealDraftProvider);

      if (widget.mealId != null) {
        final meal = ref.read(repositoryProvider).mealById(widget.mealId!);
        if (meal != null) controller.edit(meal);
        return;
      }
      // Si ya hay un borrador de esta misma comida, se retoma. "La misma" es
      // mismo momento del día y mismo día cuando la ruta los trae: antes se
      // retomaba cualquier borrador nuevo, así que abrir la cena mostraba los
      // ítems del almuerzo que habían quedado colgados. Sin parámetros —el
      // caso de las sugerencias y de "cargar a mano", que arman el borrador y
      // recién después navegan— se retoma el que haya.
      final resume =
          current != null &&
          current.editingMealId == null &&
          (widget.slot == null || widget.slot == current.slot) &&
          (widget.date == null ||
              dateOnly(widget.date!) == dateOnly(current.date));
      if (!resume) {
        controller.start(
          slot: widget.slot ?? MealSlot.forHour(DateTime.now().hour),
          date: widget.date ?? ref.read(selectedDateProvider),
        );
      }

      // Recién con el borrador abierto: el escáner necesita dónde poner lo que
      // lee.
      if (widget.scanOnOpen && mounted) context.push(Routes.foodScan);
    });
  }

  Future<void> _save() async {
    final draft = ref.read(mealDraftProvider);
    if (draft == null || draft.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    // Al editar se conserva cuándo se creó la comida: `toMeal` sin fecha pone
    // la de ahora, y corregir un gramo la hacía pasar por recién cargada.
    final editingId = draft.editingMealId;
    final meal = draft.toMeal(
      syncStatus: SyncStatus.synced,
      createdAt: editingId == null ? null : repo.mealById(editingId)?.createdAt,
    );
    await repo.saveMeal(meal);
    ref.read(mealDraftProvider.notifier).clear();
    if (!mounted) return;
    setState(() => _saving = false);

    context.pop();
    NmSnackbar.show(
      context,
      'Comida guardada',
      actionLabel: 'Ver',
      onAction: () => context.push(Routes.meal(meal.id)),
    );
  }

  Future<void> _recalculate() async {
    final done = await showRecalculateSheet(context);
    if (done != true || !mounted) return;
    NmSnackbar.show(context, 'Ítems recalculados. Revisalos y guardá.');
  }

  Future<void> _discard() async {
    final draft = ref.read(mealDraftProvider);
    if (draft != null && !draft.isEmpty) {
      final confirmed = await showNmDialog<bool>(
        context: context,
        builder: (context) => NmDialog(
          title: '¿Descartar la comida?',
          body: 'Vas a perder los ítems que agregaste.',
          actions: <Widget>[
            NmButton.ghost(
              label: 'Seguir editando',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NmButton(
              label: 'Descartar',
              variant: NmButtonVariant.danger,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    ref.read(mealDraftProvider.notifier).clear();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final draft = ref.watch(mealDraftProvider);
    final controller = ref.read(mealDraftProvider.notifier);
    // Sin servidor no hay Edge Function a la que preguntarle, así que los
    // botones de IA se muestran deshabilitados y con el motivo, en vez de
    // fallar al tocarlos.
    final aiAvailable = ref.watch(mealAiAvailableProvider);

    if (draft == null) {
      return const Scaffold(body: Center(child: NmSpinner()));
    }

    final Widget form = Scaffold(
      backgroundColor: nm.bg,
      appBar: NmModalHeader(
        title: widget.mealId == null ? 'Nueva comida' : 'Editar comida',
        onClose: _discard,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(context.screenPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: NmLayout.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Momento del día',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
                        const SizedBox(height: NmSpace.s2),
                        Wrap(
                          spacing: NmSpace.s2,
                          runSpacing: NmSpace.s2,
                          children: <Widget>[
                            for (final slot in MealSlot.values)
                              NmChip(
                                label: slot.label,
                                selected: slot == draft.slot,
                                semanticsInRadioGroup: true,
                                onTap: () => controller.setSlot(slot),
                              ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        Row(
                          children: <Widget>[
                            Icon(
                              PhosphorIcons.clockCounterClockwise(),
                              size: NmIconSize.md,
                              color: nm.textMuted,
                            ),
                            const SizedBox(width: NmSpace.s2),
                            // `Expanded` y no un `Text` suelto con `Spacer`:
                            // así estaba y se desbordaba. La app promete texto
                            // escalable hasta 200 % y con la fecha larga —un
                            // día que no es hoy ni ayer— más "Cambiar hora" al
                            // lado, la fila no daba. Ahora el que cede es el
                            // texto, con puntos suspensivos.
                            Expanded(
                              child: Text(
                                '${friendlyDay(draft.date)} · '
                                '${timeOfDay(draft.eatenAt)}',
                                overflow: TextOverflow.ellipsis,
                                style: NmTextStyles.from(
                                  NmType.bodySm,
                                  color: nm.textMuted,
                                ).tnum,
                              ),
                            ),
                            NmButton.ghost(
                              label: 'Cambiar hora',
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    draft.eatenAt,
                                  ),
                                );
                                if (picked == null) return;
                                controller.setEatenAt(
                                  DateTime(
                                    draft.date.year,
                                    draft.date.month,
                                    draft.date.day,
                                    picked.hour,
                                    picked.minute,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        // El título, con el resumen automático de placeholder.
                        //
                        // Un campo y no una pantalla: dejarlo vacío es lo
                        // normal y no cuesta nada, porque la comida ya se llama
                        // como lo que tiene adentro. Está acá para el caso en
                        // que ese resumen no alcance —"Cumpleaños de Ana"— o
                        // para corregir el que propuso la IA.
                        _TitleField(
                          key: ValueKey<String>(draft.id),
                          initial: draft.name ?? '',
                          hint: draft.autoTitle.isEmpty
                              ? 'Se arma con lo que cargues'
                              : draft.autoTitle,
                          onChanged: controller.setName,
                        ),
                        const SizedBox(height: NmSpace.s6),
                        const NmSectionHeader(title: 'Ítems'),
                        // El vacío solo cuenta qué se puede hacer; los botones
                        // de abajo lo hacen.
                        //
                        // Antes tenía sus propias acciones y terminaban
                        // repetidas: "Buscar alimento" arriba y "Agregar
                        // alimento" abajo iban al mismo buscador, y "Escanear un
                        // código" aparecía dos veces en la misma pantalla. Dos
                        // botones que hacen lo mismo a diez píxeles de distancia
                        // hacen dudar de si hacen lo mismo.
                        if (draft.items.isEmpty)
                          EmptyState(
                            compact: true,
                            icon: PhosphorIcons.magnifyingGlass(),
                            title: 'Agregá el primer alimento',
                            body: 'Escribilo abajo, buscalo en el catálogo o '
                                'sacale una foto.',
                          )
                        else
                          NmCard(
                            child: Column(
                              children: <Widget>[
                                for (var i = 0; i < draft.items.length; i++)
                                  MealItemRow(
                                    item: draft.items[i],
                                    // El lápiz existía en el componente y
                                    // nadie se lo pasaba, así que la cantidad
                                    // de un ítem ya cargado no se podía
                                    // corregir: había que borrarlo y volver a
                                    // buscarlo. Es lo primero que uno quiere
                                    // hacer con lo que estima la IA.
                                    onEditPortion: () async {
                                      final index = i;
                                      final editado =
                                          await showEditPortionSheet(
                                            context,
                                            item: draft.items[index],
                                          );
                                      if (editado == null) return;
                                      controller.replaceItem(index, editado);
                                    },
                                    onRemove: () => controller.removeItem(
                                      draft.items[i].id,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: NmSpace.s4),
                        // Sumar un ítem escribiéndolo, pegado a la lista: es
                        // la fila que le sigue al último ítem. Se estima, se
                        // suma al plato y el total de abajo cambia en el acto.
                        //
                        // Reemplaza a "Describir lo que comiste" en esta
                        // pantalla. Los dos eran texto que se estima y se suma
                        // a esta comida; la única diferencia era una pantalla
                        // de ida y otra de revisión antes de volver acá, donde
                        // la revisión es la misma lista. Describir sigue en el
                        // menú Agregar, que es donde se arranca una comida
                        // entera desde cero.
                        //
                        // La key es el borrador: abrir otra comida no hereda
                        // lo que había quedado escrito en el campo.
                        QuickAddItemField(
                          key: ValueKey<String>('sumar-${draft.id}'),
                        ),
                        const SizedBox(height: NmSpace.s4),
                        NmButton.secondary(
                          label: 'Buscar alimentos',
                          block: true,
                          icon: PhosphorIcons.plus(),
                          onPressed: () =>
                              context.push('${Routes.foodSearch}?target=meal'),
                        ),
                        const SizedBox(height: NmSpace.s2),
                        // El escáner no está acá: vive adentro del buscador, y
                        // "Buscar alimentos" abre el buscador. Tenerlo también
                        // afuera era el mismo camino ofrecido dos veces, y dos
                        // botones que hacen lo mismo hacen dudar de si lo hacen.
                        //
                        // Lo que se estime se agrega a **esta** comida: la
                        // revisión del análisis absorbe el borrador abierto en
                        // vez de empezar uno nuevo, si no lo que ya estaba
                        // cargado se perdía sin decirlo.
                        NmButton.secondary(
                          label: 'Sacar foto y analizarla',
                          block: true,
                          icon: PhosphorIcons.camera(),
                          onPressed: aiAvailable
                              ? () {
                                  // El slot y el día los manda el borrador, no
                                  // la hora: se limpia el objetivo por si quedó
                                  // uno de otra entrada.
                                  ref
                                      .read(photoTargetProvider.notifier)
                                      .state = null;
                                  context.push(Routes.photoCapture);
                                }
                              : null,
                        ),
                        if (!aiAvailable) ...<Widget>[
                          const SizedBox(height: NmSpace.s2),
                          Text(
                            'El análisis con IA necesita servidor configurado.',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.caution,
                            ),
                          ),
                        ],
                        // Corregir lo que la IA estimó mal, sin empezar de
                        // nuevo. Antes había que sacar la foto otra vez y
                        // rearmar la comida entera para cambiar un peso: el
                        // recálculo parte de lo que ya está cargado, así que lo
                        // que la corrección no toca queda como estaba.
                        //
                        // Solo editando: en el alta no hay comida que
                        // recalcular todavía.
                        if (widget.mealId != null) ...<Widget>[
                          const SizedBox(height: NmSpace.s2),
                          NmButton.secondary(
                            label: 'Recalcular con IA',
                            block: true,
                            icon: PhosphorIcons.sparkle(),
                            onPressed: aiAvailable && !draft.isEmpty
                                ? _recalculate
                                : null,
                          ),
                        ],
                        // Adjuntar una foto a mano es cosa de una comida que ya
                        // existe, no del alta. Crear una comida es buscar,
                        // cargar y guardar; ofrecer ahí un campo de foto que no
                        // analiza nada competía con el que sí analiza y alargaba
                        // el camino corto. Editando la comida sí está.
                        if (widget.mealId != null) ...<Widget>[
                          const SizedBox(height: NmSpace.s8),
                          const NmSectionHeader(title: 'Foto'),
                          MealPhotoField(
                            path: draft.photoPath,
                            onChanged: controller.setPhoto,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            MealTotalsBar(
              kcal: draft.totalKcal,
              proteinG: draft.proteinG,
              carbsG: draft.carbsG,
              fatG: draft.fatG,
              child: Column(
                children: <Widget>[
                  NmButton(
                    label: 'Guardar comida',
                    block: true,
                    loading: _saving,
                    onPressed: draft.isEmpty ? null : _save,
                  ),
                  if (draft.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: NmSpace.s2),
                      child: Text(
                        'Agregá al menos un alimento para poder guardar.',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // El atrás del sistema pasa por el mismo `_discard` que la X: antes salía
    // sin preguntar y dejaba el borrador vivo, listo para aparecer en la
    // próxima comida que se abriera.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: form,
    );
  }
}

/// El campo del título, con su propio controlador.
///
/// Vive aparte porque el borrador se abre después del primer frame: un
/// controlador creado en el `build` del formulario se reemplazaría en cada
/// tecla y el cursor volvería al principio. La `key` es el id del borrador, así
/// que abrir otra comida lo recrea con el nombre de esa.
class _TitleField extends StatefulWidget {
  const _TitleField({
    required this.initial,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NmTextField(
    label: 'Título',
    controller: _controller,
    hint: widget.hint,
    maxLength: MealTitle.maxLength,
    textInputAction: TextInputAction.done,
    onChanged: widget.onChanged,
  );
}

/// Detalle de una comida guardada.
class MealDetailScreen extends ConsumerWidget {
  const MealDetailScreen({required this.mealId, super.key});

  final String mealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    ref.watch(appRevisionProvider);
    final repo = ref.watch(repositoryProvider);
    final meal = repo.mealById(mealId);

    if (meal == null || meal.isDeleted) {
      return NmScreen(
        title: 'Comida',
        child: ErrorState(
          message: 'Este registro ya no existe.',
          onRetry: () => context.pop(),
          retryLabel: 'Volver',
        ),
      );
    }

    return NmScreen(
      // El título de la comida, no el momento del día: el momento ya está en la
      // línea de la fecha, dos renglones más abajo, y en una pantalla que
      // muestra **una** comida el dato que falta es cuál.
      title: meal.title,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.push(Routes.mealEdit(meal.id)),
          tooltip: 'Editar',
          icon: Icon(PhosphorIcons.pencilSimple()),
        ),
        IconButton(
          onPressed: () async {
            final confirmed = await confirmDelete(
              context,
              title: '¿Eliminar la comida?',
              body: 'Podés deshacer durante unos segundos.',
            );
            if (!confirmed || !context.mounted) return;
            await repo.deleteMeal(meal.id);
            if (!context.mounted) return;
            context.pop();
            NmSnackbar.show(
              context,
              'Comida eliminada',
              actionLabel: 'Deshacer',
              undo: true,
              onAction: () => repo.restoreMeal(meal.id),
            );
          },
          tooltip: 'Eliminar',
          icon: Icon(PhosphorIcons.trash()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          if (meal.photoPath != null) ...<Widget>[
            MealPhoto(path: meal.photoPath, height: 200),
            const SizedBox(height: NmSpace.s4),
          ],
          Text(
            '${meal.slot.label} · ${longDay(meal.localDate)} · '
            '${timeOfDay(meal.eatenAt)}',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted).tnum,
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Column(
              children: <Widget>[
                for (final item in meal.items) MealItemRow(item: item),
                const NmDivider(),
                ValueRow(
                  label: 'Total',
                  value: '${meal.totalKcal} kcal',
                  emphasis: true,
                ),
                ValueRow(
                  label: 'Proteínas',
                  value: '${meal.totalProteinG.round()} g',
                  muted: true,
                ),
                ValueRow(
                  label: 'Carbohidratos',
                  value: '${meal.totalCarbsG.round()} g',
                  muted: true,
                ),
                ValueRow(
                  label: 'Grasas',
                  value: '${meal.totalFatG.round()} g',
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              NmButton.ghost(
                label: meal.isFavorite
                    ? 'Quitar de favoritas'
                    : 'Marcar como favorita',
                onPressed: () => repo.toggleMealFavorite(meal.id),
              ),
              NmButton.ghost(
                label: 'Duplicar hoy',
                onPressed: () async {
                  await repo.duplicateMeal(meal.id, today(), meal.slot);
                  if (!context.mounted) return;
                  NmSnackbar.show(context, 'Comida duplicada en el día de hoy');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
