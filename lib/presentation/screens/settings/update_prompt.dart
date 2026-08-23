import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/app_release.dart';
import '../../components/system/overlays.dart';
import '../../providers/update_providers.dart';
import 'update_dialog.dart';

/// Busca si hay una versión nueva al abrir la app y, si la hay, avisa.
///
/// Ceres se distribuye por fuera de Play Store: nadie le avisa a nadie que
/// salió una versión. Mientras la comprobación fue solo manual —Configuración →
/// Actualizaciones, y había que acordarse de entrar— el resultado fue gente
/// corriendo versiones de meses atrás sin enterarse, incluida la que tenía rota
/// justamente la actualización. Un aviso que hay que ir a buscar no es un aviso.
///
/// Lo que se hace sin permiso es **preguntar**, no bajar: la consulta es un JSON
/// de unos kilobytes contra la API de releases. Los 25 MB del APK siguen
/// necesitando que alguien los pida, ahora desde el mismo aviso
/// ([showUpdateDialog]).
///
/// El aviso es un toast y no un diálogo, y eso es la diferencia entre avisar e
/// interrumpir: no tapa la pantalla, no hay que contestarle nada y se va solo.
/// Por eso tampoco hace falta acordarse de a quién ya se le preguntó — antes
/// había un intervalo de seis horas y un "ahora no" por versión, que existían
/// para que un diálogo en cada arranque no se volviera algo que se aprende a
/// descartar sin leer. Un toast no tiene ese problema.
///
/// Si la consulta falla —sin conexión, con la API caída, en una plataforma sin
/// `package_info`— no se dice nada: esto es un extra silencioso, no una función
/// que pueda fallar a la vista.
Future<void> maybePromptForUpdate(BuildContext context, WidgetRef ref) async {
  final UpdateStatus status;
  try {
    final current = await ref.read(installedVersionProvider.future);
    status = await ref.read(updateServiceProvider).check(current: current);
  } on Object {
    return;
  }

  if (status is! UpdateAvailable) return;
  // En una variable propia y no `status` a secas: la promoción de tipo de una
  // local asignada dentro de un `try` no entra a la clausura de abajo.
  final available = status;
  if (!context.mounted) return;

  NmSnackbar.show(
    context,
    'Hay una versión nueva: ${available.release.version}',
    actionLabel: 'Actualizar',
    // Más que los 3,6 s de un aviso corriente: si el toast se va antes de que
    // alguien levante la vista del teléfono, el aviso no existió.
    duration: const Duration(seconds: 8),
    onAction: () {
      if (context.mounted) showUpdateDialog(context, available);
    },
  );
}
