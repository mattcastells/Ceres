import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Preferencias, alergias y condiciones: lo que la IA no te va a proponer.
///
/// Es una pantalla de chips y un campo, sin botón de guardar: cada toque queda
/// escrito. Un formulario con "Guardar" abajo obligaría a acordarse de tocarlo
/// para que una alergia surta efecto, y ese es exactamente el olvido que no se
/// puede permitir.
class DietaryScreen extends ConsumerWidget {
  const DietaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Preferencias y alergias',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Sirve para que "¿Qué como?" no te proponga algo que no podés '
            'comer. No cambia tus calorías ni tus macros.',
            style: NmTextStyles.from(NmType.bodySm, color: context.nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),
          DietaryPicker(
            selected: profile.dietaryFlags,
            note: profile.dietaryNote,
            onFlags: (flags) => repo.updateProfile(
              repo.profile.copyWith(dietaryFlags: flags),
            ),
            onNote: (note) => repo.updateProfile(
              repo.profile.copyWith(dietaryNote: note),
            ),
          ),
        ],
      ),
    );
  }
}

/// El selector, aparte de la pantalla porque el alta guiada muestra el mismo.
///
/// Dos lugares para la misma decisión tienen que verse y comportarse igual: si
/// se dibujaran por separado, en algún momento uno de los dos quedaría con una
/// opción de menos.
class DietaryPicker extends StatefulWidget {
  const DietaryPicker({
    required this.selected,
    required this.note,
    required this.onFlags,
    required this.onNote,
    super.key,
  });

  final List<DietaryFlag> selected;
  final String note;
  final ValueChanged<List<DietaryFlag>> onFlags;
  final ValueChanged<String> onNote;

  /// Lo mismo que acepta la columna `dietary_note`.
  static const int maxNoteLength = 200;

  @override
  State<DietaryPicker> createState() => _DietaryPickerState();
}

class _DietaryPickerState extends State<DietaryPicker> {
  late final TextEditingController _note = TextEditingController(
    text: widget.note,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toggle(DietaryFlag flag) {
    final next = <DietaryFlag>[...widget.selected];
    if (!next.remove(flag)) next.add(flag);
    // En el orden del enum siempre, no en el de los toques: así los chips
    // elegidos no se reordenan solos entre una visita y la siguiente.
    next.sort((a, b) => a.index.compareTo(b.index));
    widget.onFlags(next);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in DietaryGroup.values) ...<Widget>[
          NmSectionHeader(title: group.label),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final flag in DietaryFlag.inGroup(group))
                NmChip(
                  label: flag.label,
                  subtitle: flag.description.isEmpty ? null : flag.description,
                  selected: widget.selected.contains(flag),
                  onTap: () => _toggle(flag),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
        ],

        // El campo libre no es un extra: la lista de arriba son ocho opciones y
        // las alergias no se terminan ahí. Sin esto, quien es alérgico a otra
        // cosa no tendría dónde decirlo y la pantalla le estaría prometiendo
        // algo que no cumple.
        NmTextField(
          label: 'Algo más que tengamos que saber',
          controller: _note,
          hint: 'alergia al kiwi, no como frito',
          maxLines: 2,
          maxLength: DietaryPicker.maxNoteLength,
          onChanged: widget.onNote,
        ),
        const SizedBox(height: NmSpace.s4),
        Text(
          'No se comparte con nadie.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}
