import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/pal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/meal_photo.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// Hasta cuántos días atrás se puede mirar el día de un pal.
const int palDayHistoryDays = 7;

/// El día de un pal, organizado por categoría igual que Inicio.
///
/// Lo que aparece depende de lo que esa persona decidió compartir (Perfil →
/// Pals → Qué ven mis pals): comida y el agregado de actividad siempre están;
/// fotos, agua, sueño y el detalle de cada actividad, solo si los prendió.
///
/// `autoDispose` a propósito, igual que [palsProvider]. Sin eso la consulta se
/// hacía **una sola vez por sesión de app** y por par (persona, fecha): quien
/// abría el día de alguien antes de que esa persona cargara sus comidas no las
/// veía aparecer nunca —ni saliendo de la pantalla y volviendo— hasta cerrar y
/// reabrir la app. Las comidas estaban en el servidor desde el momento en que se
/// cargaron; lo que no se rehacía era la consulta.
final palDayProvider = FutureProvider.autoDispose
    .family<PalDay?, ({String userId, DateTime date})>((ref, args) async {
      final client = ref.watch(palsClientProvider);
      if (client == null) return null;
      return client.dayOf(args.userId, args.date);
    });

class PalDayScreen extends ConsumerStatefulWidget {
  const PalDayScreen({required this.userId, this.name, super.key});

  final String userId;
  final String? name;

  @override
  ConsumerState<PalDayScreen> createState() => _PalDayScreenState();
}

class _PalDayScreenState extends ConsumerState<PalDayScreen> {
  late DateTime _date = today();

  /// Vuelve a preguntarle a la base.
  ///
  /// Entrar a la pantalla ya consulta —el provider es `autoDispose`, así que
  /// salir tira lo que trajo y volver lo pide de nuevo—; esto es para mirar otra
  /// vez sin salir, que es lo que uno hace cuando sabe que la otra persona está
  /// cargando algo en ese momento.
  void _refresh() {
    if (!mounted) return;
    ref.invalidate(palDayProvider((userId: widget.userId, date: _date)));
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(palDayProvider((userId: widget.userId, date: _date)));
    final isToday = isSameDay(_date, today());

    return NmScreen(
      title: widget.name ?? 'Su día',
      actions: <Widget>[
        NmIconButton(
          icon: PhosphorIcons.arrowsClockwise(),
          tooltip: 'Actualizar',
          onPressed: _refresh,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          _DaySelector(date: _date, onChange: (d) => setState(() => _date = d)),
          const SizedBox(height: NmSpace.s4),

          day.when(
            loading: () => const SkeletonList(rows: 4, withAvatar: false),
            error: (error, _) => ErrorState(
              message: error is AppError
                  ? error.message
                  : 'No pudimos cargar su día.',
              onRetry: _refresh,
            ),
            data: (value) => value == null || value.isEmpty
                ? EmptyState(
                    icon: PhosphorIcons.forkKnife(),
                    title: isToday
                        ? 'Todavía no cargó nada hoy'
                        : 'No cargó nada ese día',
                    body: isToday
                        ? 'Cuando registre algo va a aparecer acá.'
                        : 'No hay nada compartido para esta fecha.',
                  )
                : _Day(day: value),
          ),
        ],
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({required this.date, required this.onChange});

  final DateTime date;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final oldestVisible = today().subtract(
      const Duration(days: palDayHistoryDays),
    );
    final canGoBack = date.isAfter(oldestVisible);
    final canGoForward = date.isBefore(today());

    return Row(
      children: <Widget>[
        NmIconButton(
          icon: PhosphorIcons.caretLeft(),
          tooltip: 'Día anterior',
          onPressed: canGoBack
              ? () => onChange(date.subtract(const Duration(days: 1)))
              : null,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                friendlyDay(date),
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.h3, color: nm.text),
              ),
              Text(
                longDay(date),
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ),
        NmIconButton(
          icon: PhosphorIcons.caretRight(),
          tooltip: 'Día siguiente',
          onPressed: canGoForward
              ? () => onChange(date.add(const Duration(days: 1)))
              : null,
        ),
      ],
    );
  }
}

/// El día de un pal, agrupado por categoría y en un orden fijo: comida, agua,
/// deporte y sueño.
///
/// Antes las cuatro comidas eran cuatro secciones al mismo nivel que el agua y
/// el sueño, así que "Desayuno" y "Sueño" se leían como cosas del mismo tipo y
/// había que recorrer la pantalla para saber si esa persona comparte el agua.
/// Ahora cada categoría es una sola caja, con las comidas adentro por momento
/// del día, y **solo aparece la que esa persona decidió compartir**.
///
/// El orden es el mismo siempre. Que una categoría se corra de lugar según lo
/// que haya cargado obliga a leer todo de nuevo cada vez.
class _Day extends ConsumerWidget {
  const _Day({required this.day});

  final PalDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final weightToday =
        day.weightDate == null || isSameDay(day.weightDate!, day.date);

    final shared = <String>[
      if (day.mealsShared) 'lo que comió',
      if (day.waterGlasses != null) 'el agua',
      if (day.activityShared) 'si se movió',
      if (day.sleepMinutes != null) 'el sueño',
      if (day.weightKg != null) 'su peso',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // El total del día arriba de las categorías.
        //
        // Acá había también un "Se movió" que decía lo mismo que la categoría
        // Deporte, dos cajas más abajo. El total de calorías se queda porque no
        // está en ningún otro lado —la categoría Comida muestra cada comida,
        // no la suma—; el de actividad se fue porque sí lo estaba.
        if (day.mealsShared)
          NmCard(
            child: ValueRow(
              label: 'Comió',
              value: Fmt.kcal(day.totalKcal),
              emphasis: true,
            ),
          ),

        // ── Comida ───────────────────────────────────────────────────────
        if (day.meals.isNotEmpty)
          _Category(
            icon: PhosphorIcons.forkKnife(),
            title: 'Comida',
            child: Column(
              children: <Widget>[
                for (final slot in MealSlot.values)
                  if (day.mealsIn(slot).isNotEmpty)
                    _Slot(slot: slot, meals: day.mealsIn(slot)),
              ],
            ),
          ),

        // ── Agua ─────────────────────────────────────────────────────────
        if (day.waterGlasses != null)
          _Category(
            icon: PhosphorIcons.drop(),
            title: 'Agua',
            child: ValueRow(
              label: 'Tomó',
              value:
                  '${day.waterGlasses} '
                  '${day.waterGlasses == 1 ? 'vaso' : 'vasos'}',
              emphasis: true,
            ),
          ),

        // ── Deporte ──────────────────────────────────────────────────────
        // El agregado se comparte siempre; el detalle de cada actividad, solo
        // si lo prendió. La categoría se muestra igual: "todavía no se movió"
        // también es información del día, y si desapareciera cuando no hay
        // nada, su ausencia se leería como "no lo comparte".
        if (day.activityShared)
          _Category(
            icon: PhosphorIcons.personSimpleRun(),
            title: 'Actividad',
            child: day.activities.isNotEmpty
                ? Column(
                    children: <Widget>[
                      for (final activity in day.activities)
                        ValueRow(
                          label: activity.name,
                          caption: Fmt.duration(activity.minutes),
                          value: activity.kcal == null
                              ? '—'
                              : Fmt.kcal(activity.kcal!),
                        ),
                    ],
                  )
                : day.activityCount == 0
                ? const ValueRow(
                    label: 'Se movió',
                    value: 'Todavía no',
                    muted: true,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ValueRow(
                        label: 'Sesiones',
                        value:
                            '${day.activityCount} · '
                            '${Fmt.duration(day.activityMinutes)}',
                        emphasis: true,
                      ),
                      const SizedBox(height: NmSpace.s1),
                      // Se dice por qué no hay más: sin esto, una categoría con
                      // un solo número se lee como que esa persona hizo una sola
                      // cosa, no como que eligió no contar cuáles.
                      Text(
                        'Comparte el total, no cada actividad.',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),

        // ── Sueño ────────────────────────────────────────────────────────
        if (day.sleepMinutes != null)
          _Category(
            icon: PhosphorIcons.moon(),
            title: 'Sueño',
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Durmió',
                  value: Fmt.duration(day.sleepMinutes!),
                  emphasis: true,
                ),
                if (day.sleepQuality != null)
                  ValueRow(
                    label: 'Cómo descansó',
                    value: day.sleepQuality!.label,
                    muted: true,
                  ),
              ],
            ),
          ),

        // ── Peso ─────────────────────────────────────────────────────────
        // El último registrado hasta este día; si no es de ese día, se dice
        // de cuándo es.
        if (day.weightKg != null)
          _Category(
            icon: PhosphorIcons.scales(),
            title: 'Peso',
            child: ValueRow(
              label: weightToday ? 'Pesó' : 'Último registro',
              caption: weightToday ? null : shortDay(day.weightDate!),
              value: Fmt.weight(
                day.weightKg!,
                // En las unidades de quien mira.
                ref.watch(profileProvider).unitSystem,
              ),
              emphasis: true,
            ),
          ),

        const SizedBox(height: NmSpace.s6),
        Text(
          shared.isEmpty
              ? 'Por ahora no comparte nada.'
              : 'Comparte ${shared.join(', ')}.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}

/// Una categoría del día: ícono, nombre y su caja.
///
/// Sin número al costado a propósito: el total de cada categoría ya está en la
/// tarjeta de arriba, y repetirlo a dos centímetros de distancia obliga a
/// comparar dos veces el mismo dato para descubrir que es el mismo.
class _Category extends StatelessWidget {
  const _Category({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Padding(
      padding: const EdgeInsets.only(top: NmSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: NmSpace.s3),
            child: Row(
              children: <Widget>[
                Icon(icon, size: NmIconSize.md, color: nm.textMuted),
                const SizedBox(width: NmSpace.s2),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: NmTextStyles.from(
                      NmType.overline,
                      color: nm.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          NmCard(child: child),
        ],
      ),
    );
  }
}

/// Un momento del día adentro de la categoría Comida.
class _Slot extends StatelessWidget {
  const _Slot({required this.slot, required this.meals});

  final MealSlot slot;
  final List<PalMeal> meals;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: NmSpace.s1),
          child: Text(
            slot.label,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ),
        for (final meal in meals) ...<Widget>[
          if (meal.photoPath != null) ...<Widget>[
            MealPhoto(path: meal.photoPath, height: 160),
            const SizedBox(height: NmSpace.s2),
          ],
          ValueRow(label: meal.name, value: Fmt.kcal(meal.kcal)),
        ],
      ],
    );
  }
}
