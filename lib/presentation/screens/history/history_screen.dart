import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/summaries.dart';
import '../../components/feedback/feedback.dart';
import '../../components/plan/ad_banner.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Filtros del Historial (S-21 · `sheet.filters`), como chips removibles.
///
/// **Viven en memoria**: se pierden al cerrar la app. El comentario anterior
/// decía que se persistían en preferencias, y la plomería está —`LocalStore`
/// tiene un `historyFilters` en el documento— pero nadie la escribe:
/// `historyFiltersProvider` es un `StateProvider` y nada más. Queda así a
/// propósito hasta que alguien lo pida; lo que no puede quedar es el comentario
/// prometiendo lo contrario.
class HistoryFilters {
  const HistoryFilters({
    this.show = HistoryShow.all,
    this.rangeDays = 30,
    this.onlyOutsideTarget = false,
  });

  final HistoryShow show;
  final int rangeDays;
  final bool onlyOutsideTarget;

  bool get isDefault =>
      show == HistoryShow.all && rangeDays == 30 && !onlyOutsideTarget;

  HistoryFilters copyWith({
    HistoryShow? show,
    int? rangeDays,
    bool? onlyOutsideTarget,
  }) => HistoryFilters(
    show: show ?? this.show,
    rangeDays: rangeDays ?? this.rangeDays,
    onlyOutsideTarget: onlyOutsideTarget ?? this.onlyOutsideTarget,
  );
}

enum HistoryShow {
  all('Todo'),
  meals('Solo comidas'),
  activities('Solo ejercicio');

  const HistoryShow(this.label);
  final String label;
}

final historyFiltersProvider = StateProvider<HistoryFilters>(
  (ref) => const HistoryFilters(),
);

/// S-21 · Historial. Lista de días agrupada por mes.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final filters = ref.watch(historyFiltersProvider);
    final days = ref
        .watch(historyProvider(filters.rangeDays))
        .where(
          (d) => !filters.onlyOutsideTarget || (d.hasRecords && !d.isWithinTarget),
        )
        .toList();
    final matching = days.where((d) => d.hasRecords).length;

    return NmScreen(
      title: 'Historial',
      scrollable: false,
      actions: <Widget>[
        IconButton(
          tooltip: 'Filtros',
          onPressed: () => _showFilters(context, ref),
          icon: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Icon(
                filters.isDefault
                    ? PhosphorIcons.sliders()
                    : PhosphorIcons.sliders(PhosphorIconsStyle.fill),
              ),
              if (!filters.isDefault)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    height: 6,
                    width: 6,
                    decoration: BoxDecoration(
                      color: nm.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!filters.isDefault)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s3),
              child: Wrap(
                spacing: NmSpace.s2,
                children: <Widget>[
                  if (filters.show != HistoryShow.all)
                    NmTag(
                      label: filters.show.label,
                      variant: NmTagVariant.accent,
                    ),
                  if (filters.rangeDays != 30)
                    NmTag(
                      label: '${filters.rangeDays} días',
                      variant: NmTagVariant.accent,
                    ),
                  if (filters.onlyOutsideTarget)
                    const NmTag(
                      label: 'Fuera del objetivo',
                      variant: NmTagVariant.accent,
                    ),
                ],
              ),
            ),
          Expanded(
            child: days.every((d) => !d.hasRecords)
                ? EmptyState(
                    icon: PhosphorIcons.clockCounterClockwise(),
                    title: filters.isDefault
                        ? 'Todavía no hay registros'
                        : 'No hay registros en este período',
                    body: filters.isDefault
                        ? 'A medida que registres comidas y actividades, los '
                              'días van a aparecer acá.'
                        : 'Probá ampliando el rango o quitando los filtros.',
                    primaryLabel: filters.isDefault ? null : 'Quitar filtros',
                    onPrimary: () => ref
                        .read(historyFiltersProvider.notifier)
                        .state = const HistoryFilters(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: NmSpace.s12),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final isFirstOfMonth =
                          index == 0 ||
                          days[index - 1].date.month != day.date.month;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (isFirstOfMonth)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: NmSpace.s6,
                                bottom: NmSpace.s2,
                              ),
                              child: Text(
                                monthTitle(day.date),
                                style: NmTextStyles.from(
                                  NmType.overline,
                                  color: nm.textMuted,
                                ),
                              ),
                            ),
                          StaggeredItem(
                            index: index,
                            child: _DayRow(
                              day: day,
                              show: filters.show,
                              onTap: () => context.push(
                                Routes.progressHistoryDay(isoDate(day.date)),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          // Fijo abajo y no entre los días: metido en la lista, un anuncio
          // quedaría pegado al balance de un día en particular. Solo en el
          // plan gratis.
          const AdBanner(padding: EdgeInsets.only(bottom: NmSpace.s3)),
          Padding(
            padding: const EdgeInsets.only(bottom: NmSpace.s4),
            child: Text(
              '$matching ${matching == 1 ? 'día coincide' : 'días coinciden'}',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilters(BuildContext context, WidgetRef ref) {
    showNmSheet<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final filters = ref.watch(historyFiltersProvider);
          final controller = ref.read(historyFiltersProvider.notifier);
          final days = ref.watch(historyProvider(filters.rangeDays));
          final matching = days
              .where(
                (d) =>
                    d.hasRecords &&
                    (!filters.onlyOutsideTarget || !d.isWithinTarget),
              )
              .length;

          return NmSheet(
            title: 'Filtros',
            subtitle:
                '$matching ${matching == 1 ? 'día coincide' : 'días coinciden'}',
            footer: Row(
              children: <Widget>[
                NmButton.ghost(
                  label: 'Limpiar',
                  onPressed: () =>
                      controller.state = const HistoryFilters(),
                ),
                const Spacer(),
                NmButton(
                  label: 'Aplicar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const NmSectionHeader(title: 'Qué mostrar'),
                for (final option in HistoryShow.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NmSpace.s2),
                    child: NmChip(
                      label: option.label,
                      selected: filters.show == option,
                      semanticsInRadioGroup: true,
                      onTap: () =>
                          controller.state = filters.copyWith(show: option),
                    ),
                  ),
                const SizedBox(height: NmSpace.s6),
                const NmSectionHeader(title: 'Rango de fechas'),
                Wrap(
                  spacing: NmSpace.s2,
                  children: <Widget>[
                    for (final range in const <int>[7, 30, 90, 366])
                      NmChip(
                        label: range == 366 ? '1 año' : '$range días',
                        selected: filters.rangeDays == range,
                        semanticsInRadioGroup: true,
                        onTap: () => controller.state = filters.copyWith(
                          rangeDays: range,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: NmSpace.s6),
                NmSwitchRow(
                  title: 'Solo días fuera del objetivo',
                  value: filters.onlyOutsideTarget,
                  onChanged: (v) => controller.state = filters.copyWith(
                    onlyOutsideTarget: v,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.show, required this.onTap});

  final HistoryDay day;
  final HistoryShow show;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    // Indicador neutral: punto lleno = dentro, hueco = fuera, gris = sin
    // registro. Nada de color de castigo (F-12).
    final Widget indicator = Container(
      height: 10,
      width: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: !day.hasRecords
            ? nm.divider
            : day.isWithinTarget
            ? nm.accent
            : Colors.transparent,
        border: Border.all(
          color: day.hasRecords ? nm.accent : nm.divider,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s2),
      child: NmCard(
        // Todos los días se abren, tengan registros o no: entrar a un día vacío
        // es justamente por dónde se carga lo que falta.
        onTap: onTap,
        padding: const EdgeInsets.all(NmSpace.s4),
        child: Row(
          children: <Widget>[
            indicator,
            const SizedBox(width: NmSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          friendlyDay(day.date),
                          overflow: TextOverflow.ellipsis,
                          style: NmTextStyles.from(NmType.body, color: nm.text),
                        ),
                      ),
                      if (day.isRestDay) ...<Widget>[
                        const SizedBox(width: NmSpace.s2),
                        const NmTag(
                          label: 'Descanso',
                          variant: NmTagVariant.outline,
                        ),
                      ],
                      // El contexto va en la fila y no en una columna aparte:
                      // "sin registros" y "estuve enfermo" se leen juntos o no
                      // se leen. Ver `docs/contexto-diario.md`.
                      if (day.isSickDay) ...<Widget>[
                        const SizedBox(width: NmSpace.s2),
                        const NmTag(
                          label: 'Enfermedad',
                          variant: NmTagVariant.outline,
                        ),
                      ],
                      if (day.standardDrinks > 0) ...<Widget>[
                        const SizedBox(width: NmSpace.s2),
                        NmTag(
                          label: Fmt.standardDrinks(day.standardDrinks),
                          variant: NmTagVariant.outline,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: NmSpace.s1),
                  Text(
                    day.hasRecords
                        ? <String>[
                            if (show != HistoryShow.activities)
                              Fmt.kcal(day.consumedKcal),
                            if (show != HistoryShow.meals &&
                                day.activityCount > 0)
                              '${Fmt.duration(day.exerciseMinutes)} · '
                                  '${Fmt.estimatedKcal(day.activityKcal)}',
                            if (day.steps != null)
                              '${Fmt.steps(day.steps!)} pasos',
                          ].join(' · ')
                        : 'Sin registros',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ).tnum,
                  ),
                ],
              ),
            ),
            if (day.hasRecords)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    day.isWithinTarget ? 'Dentro' : 'Fuera',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                  Text(
                    Fmt.signed(day.balanceKcal),
                    style: NmTextStyles.from(
                      NmType.bodySm,
                      color: nm.text,
                    ).tnum,
                  ),
                ],
              ),
            const SizedBox(width: NmSpace.s2),
            Icon(
              PhosphorIcons.caretRight(),
              size: NmIconSize.sm,
              color: nm.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
