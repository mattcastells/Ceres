import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';

/// `sheet.date_picker` — calendario mensual con densidad de registro.
Future<void> showDatePickerSheet(BuildContext context) => showNmSheet<void>(
  context: context,
  builder: (context) => const _DatePickerSheet(),
);

class _DatePickerSheet extends ConsumerStatefulWidget {
  const _DatePickerSheet();

  @override
  ConsumerState<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends ConsumerState<_DatePickerSheet> {
  late DateTime _month = DateTime(
    ref.read(selectedDateProvider).year,
    ref.read(selectedDateProvider).month,
  );

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final selected = ref.watch(selectedDateProvider);
    final withRecords = ref.watch(daysWithRecordsProvider);
    final today_ = today();

    /// El calendario llega hasta donde llega la planificación.
    ///
    /// Antes deshabilitaba **todo** el futuro, así que los tres días que la app
    /// promociona para planificar comidas se podían alcanzar con las flechas de
    /// Inicio pero no acá. Dos caminos a lo mismo con reglas distintas es un
    /// bug aunque ninguno de los dos esté roto por su cuenta.
    final ultimoPlanificable = today_.add(
      const Duration(days: maxPlanningDays),
    );

    final firstWeekday = DateTime(_month.year, _month.month).weekday;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return NmSheet(
      title: 'Elegir día',
      trailing: NmButton.ghost(
        label: 'Hoy',
        onPressed: () {
          ref.read(selectedDateProvider.notifier).goToToday();
          Navigator.of(context).pop();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              NmIconButton(
                icon: Icons.chevron_left,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                tooltip: 'Mes anterior',
              ),
              Expanded(
                child: Text(
                  monthTitle(_month),
                  textAlign: TextAlign.center,
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
              ),
              NmIconButton(
                icon: Icons.chevron_right,
                // El tope es el mes del último día planificable, no el mes de
                // hoy: si no, del 29 de julio en adelante no había forma de
                // llegar al 1 de agosto desde el calendario, aunque las flechas
                // de Inicio sí dejaran ir.
                onPressed:
                    DateTime(_month.year, _month.month).isBefore(
                      DateTime(ultimoPlanificable.year,
                          ultimoPlanificable.month),
                    )
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      )
                    : null,
                tooltip: 'Mes siguiente',
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              for (final label in const <String>[
                'L',
                'M',
                'M',
                'J',
                'V',
                'S',
                'D',
              ])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: NmTextStyles.from(
                      NmType.micro,
                      color: nm.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s2),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: firstWeekday - 1 + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) return const SizedBox.shrink();
              final day = DateTime(
                _month.year,
                _month.month,
                index - firstWeekday + 2,
              );
              final isSelected = isSameDay(day, selected);
              final hasRecords = withRecords.contains(isoDate(day));
              // Los días de planificación se pueden tocar; lo que queda más
              // allá de la ventana, no. La regla es `isPlannable`, la misma que
              // usan las flechas de Inicio: tenerla en un solo lugar es lo que
              // evita que las dos puertas al mismo día digan cosas distintas,
              // que es exactamente lo que pasaba.
              final fueraDeAlcance = !isPlannable(day);
              final isFutureDay = day.isAfter(today_);

              return Center(
                child: Semantics(
                  selected: isSelected,
                  label: longDay(day),
                  child: ExcludeSemantics(
                    child: InkResponse(
                      onTap: fueraDeAlcance
                          ? null
                          : () {
                              ref
                                  .read(selectedDateProvider.notifier)
                                  .set(day);
                              Navigator.of(context).pop();
                            },
                      child: Container(
                        height: 38,
                        width: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? nm.accentFill : null,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: nm.accent)
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${day.day}',
                              style: NmTextStyles.from(
                                NmType.bodySm,
                                // Tres pesos: lo que no se puede tocar casi no
                                // se ve, un día de planificación se ve atenuado
                                // —se puede elegir, pero todavía no pasó— y el
                                // resto va entero.
                                color: fueraDeAlcance
                                    ? nm.textMuted.withValues(alpha: 0.4)
                                    : (isSelected
                                          ? nm.accentOnFill
                                          : (isFutureDay
                                                ? nm.textMuted
                                                : nm.text)),
                              ).tnum,
                            ),
                            SizedBox(
                              height: 4,
                              child: hasRecords
                                  ? Container(
                                      height: 3,
                                      width: 3,
                                      decoration: BoxDecoration(
                                        color: nm.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              Container(
                height: 4,
                width: 4,
                decoration: BoxDecoration(
                  color: nm.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Text(
                'Días con registros',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
