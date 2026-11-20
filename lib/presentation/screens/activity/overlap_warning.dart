import 'package:material_ui/material_ui.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/repositories/repositories.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';

// Antes esto vivía en `duplicate_dialog.dart` junto con el diálogo S-14 para
// resolver duplicados importados ("quedarme con este / con el otro / con los
// dos"). Ese diálogo no se abría desde ningún lado: nada marca hoy una
// actividad como `needsReview`, porque la importación de sesiones de ejercicio
// sigue afuera. Se fue con su banner y su sección en Integraciones; queda lo
// único que sí se usa, y `duplicateScore` sigue en el dominio para cuando esa
// importación exista.

/// Advertencia no bloqueante de solapamiento al guardar (F-08).
Future<bool> showOverlapWarning(
  BuildContext context,
  DuplicateCandidate candidate,
) async {
  final result = await showNmDialog<bool>(
    context: context,
    builder: (context) => NmDialog(
      title: 'Ya tenés una actividad en ese horario',
      body:
          '${candidate.existing.displayName} · '
          '${timeOfDay(candidate.existing.startedAt)} · '
          '${Fmt.duration(candidate.existing.durationMinutes)}. '
          '¿Es otra distinta?',
      actions: <Widget>[
        NmButton.ghost(
          label: 'Volver a revisar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NmButton(
          label: 'Sí, es otra',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
