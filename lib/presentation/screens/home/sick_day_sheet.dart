import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/day_marker.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Marcar un día como día de enfermedad.
///
/// **No cambia ningún cálculo.** No baja el objetivo, no se saltea del promedio
/// y no se descuenta de la adherencia. Lo que hace es dar contexto: que un
/// hueco en el gráfico de actividad se pueda leer como lo que fue.
///
/// Eso está dicho en la pantalla y no solo acá, porque es exactamente lo que
/// alguien se pregunta al marcarlo —"¿esto me arregla el día o me lo arruina?"—
/// y una feature de salud que no contesta esa pregunta no se usa.
Future<void> showSickDaySheet(BuildContext context, {DateTime? date}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _SickDaySheet(date: date ?? today()),
    );

class _SickDaySheet extends ConsumerStatefulWidget {
  const _SickDaySheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_SickDaySheet> createState() => _SickDaySheetState();
}

class _SickDaySheetState extends ConsumerState<_SickDaySheet> {
  late final TextEditingController _note;
  SickSeverity? _severity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref
        .read(repositoryProvider)
        .markerOn(widget.date, DayMarkerKind.sick);
    _severity = existing?.severity ?? SickSeverity.mild;
    _note = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final texto = _note.text.trim();
    await ref.read(repositoryProvider).setMarker(
      date: widget.date,
      kind: DayMarkerKind.sick,
      on: true,
      severity: _severity,
      note: texto.isEmpty ? null : texto,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    NmSnackbar.show(context, 'Día marcado');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final existing = ref
        .watch(repositoryProvider)
        .markerOn(widget.date, DayMarkerKind.sick);

    return NmSheet(
      title: existing == null ? 'Día de enfermedad' : 'Editar el día',
      subtitle: friendlyDay(widget.date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const InfoNote(
            text: 'No cambia tu objetivo ni tus promedios: queda como '
                'contexto.',
          ),
          const SizedBox(height: NmSpace.s5),

          Text(
            'Cómo la pasaste',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final s in SickSeverity.values)
                NmChip(
                  label: s.label,
                  selected: s == _severity,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _severity = s),
                ),
            ],
          ),
          if (_severity != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            Text(
              _severity!.hint,
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],

          const SizedBox(height: NmSpace.s5),
          NmTextField(
            controller: _note,
            label: 'Nota (opcional)',
            hint: 'Qué te pasó, si tomaste algo',
            maxLength: DayMarker.maxNoteLength,
            maxLines: 3,
          ),

          const SizedBox(height: NmSpace.s5),
          NmButton(
            label: existing == null ? 'Marcar el día' : 'Guardar',
            block: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (existing != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            NmButton.ghost(
              label: 'Quitar la marca',
              onPressed: () async {
                await ref.read(repositoryProvider).setMarker(
                  date: widget.date,
                  kind: DayMarkerKind.sick,
                  on: false,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}
