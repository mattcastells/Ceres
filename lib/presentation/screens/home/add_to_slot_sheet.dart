import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/meal.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../photo/photo_screens.dart';

/// Qué se agrega a un slot concreto (Desayuno, Almuerzo, Cena, Snacks).
///
/// El "+" de cada sección antes iba derecho al buscador de alimentos, así que
/// la foto con IA solo existía en el menú general de Agregar — y ahí no se
/// elige el slot, se adivina por la hora. Este sheet ofrece las entradas **con
/// el slot y el día ya resueltos**: lo que se cargue cae donde se tocó.
Future<void> showAddToSlotSheet(
  BuildContext context, {
  required MealSlot slot,
  required DateTime date,
}) => showNmSheet<void>(
  context: context,
  builder: (context) => _AddToSlotSheet(slot: slot, date: date),
);

class _AddToSlotSheet extends ConsumerWidget {
  const _AddToSlotSheet({required this.slot, required this.date});

  final MealSlot slot;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    ref.watch(appRevisionProvider);
    final frequent = repo.frequentMeals(slot: slot, limit: 5);

    void go(String location) {
      Navigator.of(context).pop();
      context.push(location);
    }

    final manualLocation =
        '${Routes.mealNew}?slot=${slot.wire}&date=${isoDate(date)}';

    Future<void> repeat(Meal meal) async {
      // El messenger se toma **antes** del `pop`. Después, el `context` del
      // sheet ya está desmontado y `context.mounted` da false según cómo caiga
      // la carrera: la comida se agregaba igual, pero el aviso no aparecía
      // nunca y quedaba sin confirmación de que algo había pasado.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      await repo.duplicateMeal(meal.id, date, slot);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Agregado a ${slot.label.toLowerCase()}')),
        );
    }

    return NmSheet(
      title: 'Agregar a ${slot.label.toLowerCase()}',
      subtitle: friendlyDay(date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Las tres puertas fijas primero, y después lo que se repite.
          //
          // Estaba al revés, con el argumento de que repetir el desayuno es lo
          // más frecuente. Pero la lista de repetidos mide entre cero y cinco
          // filas según el día y según el slot, así que empujaba a las tres
          // fijas una cantidad distinta cada vez: "Sacar foto" nunca caía dos
          // veces en el mismo lugar. Lo que siempre está tiene que estar
          // siempre en el mismo lado; lo que varía va abajo, donde variar no
          // le mueve el piso a nadie.
          ActionRow(
            icon: PhosphorIcons.forkKnife(),
            label: 'Buscar alimentos',
            subtitle: 'Del catálogo, de los tuyos o por código de barras',
            onTap: () => go(manualLocation),
          ),
          ActionRow(
            icon: PhosphorIcons.chatText(),
            label: 'Describir lo que comiste',
            subtitle: '"dos empanadas de carne y una coca"',
            enabled: FeatureFlags.aiPhotoAnalysis && SupabaseConfig.isConfigured,
            disabledNote: 'La estimación con IA necesita servidor configurado',
            onTap: () {
              ref.read(photoTargetProvider.notifier).state = PhotoTarget(
                slot: slot,
                date: date,
              );
              go(Routes.mealDescribe);
            },
          ),
          ActionRow(
            icon: PhosphorIcons.camera(),
            // El mismo nombre que en la pantalla de la comida.
            label: 'Sacar foto y analizarla',
            subtitle: 'La IA estima los ítems y vos los revisás',
            // Sin servidor no hay Edge Function a la que preguntarle, así que
            // se muestra deshabilitado en vez de fallar al tocarlo.
            enabled: FeatureFlags.aiPhotoAnalysis && SupabaseConfig.isConfigured,
            disabledNote: 'El análisis con IA necesita servidor configurado',
            onTap: () {
              ref.read(photoTargetProvider.notifier).state = PhotoTarget(
                slot: slot,
                date: date,
              );
              go(Routes.photoCapture);
            },
          ),

          if (frequent.isNotEmpty) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: NmSpace.s3,
                vertical: NmSpace.s2,
              ),
              child: NmDivider(),
            ),
            const Padding(
              padding: EdgeInsets.only(
                left: NmSpace.s3,
                bottom: NmSpace.s2,
              ),
              child: NmSectionHeader(title: 'De lo que repetís'),
            ),
            for (final meal in frequent)
              ActionRow(
                icon: meal.isFavorite
                    ? PhosphorIcons.star(PhosphorIconsStyle.fill)
                    : PhosphorIcons.arrowCounterClockwise(),
                label: meal.title,
                subtitle:
                    '${Fmt.kcal(meal.totalKcal)} · '
                    '${meal.items.length} '
                    '${meal.items.length == 1 ? 'ítem' : 'ítems'}',
                onTap: () => repeat(meal),
              ),
          ] else ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NmSpace.s3),
              child: Text(
                // Decía "acá arriba" y la lista se mudó abajo. El cartel
                // ocupa exactamente el lugar donde van a aparecer, así que
                // ahora alcanza con "acá".
                'Las comidas que repitas o marques con la estrella van a '
                'aparecer acá.',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
