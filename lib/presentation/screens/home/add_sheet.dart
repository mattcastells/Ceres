import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/icons.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../sleep/sleep_sheet.dart';
import '../weight/measurement_sheet.dart';
import '../weight/weight_sheet.dart';
import 'alcohol_sheet.dart';
import 'sick_day_sheet.dart';

/// S-08 · Menú Agregar y S-09 · Menú Ejercicio.
///
/// Un bottom sheet nunca abre otro en el mismo nivel: `sheet.add` **reemplaza**
/// su contenido por `sheet.activity_add` con animación lateral, para que
/// "Atrás" vuelva al menú anterior y no cierre todo (IA §3).
Future<void> showAddSheet(BuildContext context, {bool activityFirst = false}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _AddSheet(activityFirst: activityFirst),
    );

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.activityFirst});

  final bool activityFirst;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  late bool _activityPane = widget.activityFirst;

  void _go(String location) {
    Navigator.of(context).pop();
    context.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return AnimatedSwitcher(
      duration: motion.move(NmMotion.base),
      switchInCurve: NmMotion.ease,
      switchOutCurve: NmMotion.easeOut,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<bool>(_activityPane);
        final offset = Tween<Offset>(
          begin: Offset(incoming ? 1 : -1, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: motion.reduced
              ? child
              : SlideTransition(position: offset, child: child),
        );
      },
      child: _activityPane
          ? _ActivityPane(
              key: const ValueKey<bool>(true),
              onBack: () => setState(() => _activityPane = false),
              onGo: _go,
            )
          : _MainPane(
              key: const ValueKey<bool>(false),
              onActivity: () => setState(() => _activityPane = true),
              onGo: _go,
            ),
    );
  }
}

class _MainPane extends ConsumerWidget {
  const _MainPane({required this.onActivity, required this.onGo, super.key});

  final VoidCallback onActivity;
  final void Function(String location) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final slot = MealSlot.forHour(DateTime.now().hour);

    return NmSheet(
      title: 'Agregar',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.forkKnife(),
            label: 'Agregar comida',
            // El subtítulo nombra los cuatro caminos porque ahora es el único
            // lugar desde donde se llega a ellos: si dijera solo "buscar
            // alimentos", sacar una foto quedaría escondida detrás de una
            // puerta que no la menciona.
            subtitle: 'Buscar, escanear, sacar una foto o describirla',
            onTap: () => onGo(
              '${Routes.mealNew}?slot=${slot.wire}'
              '&date=${date.toIso8601String().substring(0, 10)}',
            ),
          ),
          // Ni "describir" ni "sacar foto" están acá: las dos son formas de
          // sumar ítems a una comida, y las cuatro viven juntas en la pantalla
          // de la comida, adonde lleva "Agregar comida". El menú ofrece qué
          // registrar, no con qué método.
          //
          // "¿Qué como?" sí, porque no es un método de carga: parte de la
          // pregunta anterior, la que uno se hace parado en la heladera.
          ActionRow(
            icon: PhosphorIcons.cookingPot(),
            label: '¿Qué como?',
            subtitle: 'Tres platos que entran en lo que te queda del día',
            // Depende del servidor y de nada más: las sugerencias son su propia
            // Edge Function. Colgarlas de `aiPhotoAnalysis` —el flag de la
            // foto— apagaba "¿Qué como?" por algo que no tiene nada que ver.
            enabled: SupabaseConfig.isConfigured,
            disabledNote: 'Las sugerencias necesitan servidor configurado',
            onTap: () => onGo(Routes.mealSuggestions),
          ),
          // "Sacar foto" no está acá: es una forma de sumar ítems a una comida,
          // no una entrada paralela. Vive en la pantalla de la comida, junto al
          // buscador y al escáner, que es donde se decide con qué se arma.
          ActionRow(
            icon: PhosphorIcons.barcode(),
            label: 'Escanear alimento',
            subtitle: 'Buscar por código de barras',
            // Abre la comida y el escáner encima. Iba derecho al escáner, sin
            // comida abierta, y lo que se escaneaba se agregaba a un borrador
            // inexistente: no quedaba nada cargado y no lo decía.
            onTap: () => onGo(
              '${Routes.mealNew}?slot=${slot.wire}'
              '&date=${date.toIso8601String().substring(0, 10)}&scan=1',
            ),
          ),
          ActionRow(
            icon: PhosphorIcons.personSimpleRun(),
            label: 'Agregar actividad',
            // Sin número: cuántas opciones hay depende de si ya hay recientes
            // y favoritas, así que "nueve" mentía casi siempre.
            subtitle: 'Buscar, repetir, cargar a mano o importar',
            onTap: onActivity,
            trailing: Icon(PhosphorIcons.caretRight(), size: NmIconSize.md),
          ),
          ActionRow(
            icon: PhosphorIcons.scales(),
            label: 'Registrar peso',
            subtitle: 'Uno por día: si ya cargaste, se actualiza',
            onTap: () {
              Navigator.of(context).pop();
              // Al día elegido, como sueño y medidas: sin `date` el peso caía
              // siempre en hoy aunque se estuviera mirando otro día.
              showWeightSheet(context, date: date);
            },
          ),
          ActionRow(
            icon: PhosphorIcons.moon(),
            label: 'Registrar sueño',
            subtitle: 'Cuántas horas dormiste y cómo',
            onTap: () {
              Navigator.of(context).pop();
              showSleepSheet(context, date: date);
            },
          ),
          ActionRow(
            icon: PhosphorIcons.ruler(),
            label: 'Registrar medidas',
            subtitle: 'Perímetros, pliegues y lo que dijo la balanza',
            onTap: () {
              Navigator.of(context).pop();
              showMeasurementSheet(context, date: date);
            },
          ),
          // Las dos de contexto van al final y juntas: no son un registro más
          // del día como el peso o el sueño, son lo que explica al resto.
          ActionRow(
            icon: PhosphorIcons.wine(),
            label: 'Registrar alcohol',
            subtitle: 'Qué tomaste y cuánto',
            onTap: () {
              Navigator.of(context).pop();
              showAlcoholSheet(context, date: date);
            },
          ),
          ActionRow(
            icon: PhosphorIcons.thermometer(),
            label: 'Día de enfermedad',
            subtitle: 'Queda como contexto: no cambia tus números',
            onTap: () {
              Navigator.of(context).pop();
              showSickDaySheet(context, date: date);
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityPane extends ConsumerWidget {
  const _ActivityPane({required this.onBack, required this.onGo, super.key});

  final VoidCallback onBack;
  final void Function(String location) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final recent = ref.watch(recentActivitiesProvider);
    final favorites = ref.watch(favoriteActivitiesProvider);
    final integration = ref.watch(integrationProvider);
    final repo = ref.watch(repositoryProvider);

    Widget chips(List<String> labels) => Padding(
      padding: const EdgeInsets.only(
        left: NmSpace.s3,
        bottom: NmSpace.s3,
      ),
      child: Wrap(
        spacing: NmSpace.s2,
        children: <Widget>[
          for (final label in labels.take(3))
            NmTag(label: label, variant: NmTagVariant.outline),
        ],
      ),
    );

    return NmSheet(
      title: 'Agregar actividad',
      onBack: onBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.magnifyingGlass(),
            label: 'Buscar actividad',
            subtitle: 'Todo el catálogo, por categoría',
            onTap: () => onGo(Routes.activitySearch),
          ),
          if (recent.isNotEmpty) ...<Widget>[
            ActionRow(
              icon: PhosphorIcons.clockCounterClockwise(),
              label: 'Actividad reciente',
              subtitle: 'Repetir algo de los últimos días',
              onTap: () => onGo(
                '${Routes.activityNew}?activityTypeId='
                '${recent.first.activityTypeId}',
              ),
            ),
            chips(recent.map((a) => a.displayName).toList()),
          ],
          if (favorites.isNotEmpty) ...<Widget>[
            ActionRow(
              icon: PhosphorIcons.star(),
              label: 'Actividad favorita',
              onTap: () => onGo(
                '${Routes.activityNew}?activityTypeId='
                '${favorites.first.activityTypeId}',
              ),
            ),
            chips(favorites.map((a) => a.displayName).toList()),
          ],
          ActionRow(
            icon: PhosphorIcons.plusCircle(),
            label: 'Crear actividad personalizada',
            subtitle: 'Definir tu propio tipo y su MET',
            onTap: () => onGo('${Routes.activityNew}?mode=custom'),
          ),
          ActionRow(
            icon: PhosphorIcons.arrowsClockwise(),
            label: 'Importar desde un dispositivo',
            subtitle: integration.isConnected
                ? 'Health Connect · conectada'
                : 'Health Connect · sin conectar',
            enabled:
                repo.isPlatformSupported && FeatureFlags.healthConnectSync,
            disabledNote: repo.isPlatformSupported
                ? 'Health Connect todavía no está conectado'
                : 'Health Connect solo está disponible en Android',
            onTap: () => onGo(Routes.integrations),
          ),
          ActionRow(
            icon: NmIcons.activity('Barbell'),
            label: 'Entrenamiento de fuerza',
            subtitle: 'Nombre, duración e intensidad',
            onTap: () => onGo('${Routes.activityNew}?mode=strength'),
          ),
          ActionRow(
            icon: NmIcons.activity('PersonSimpleWalk'),
            label: 'Caminata o carrera',
            subtitle: 'Con distancia y pasos',
            onTap: () => onGo('${Routes.activityNew}?mode=walk_run'),
          ),
          ActionRow(
            icon: PhosphorIcons.timer(),
            label: 'Actividad por duración',
            onTap: () => onGo('${Routes.activityNew}?mode=duration'),
          ),
          ActionRow(
            icon: PhosphorIcons.path(),
            label: 'Actividad por distancia',
            onTap: () => onGo('${Routes.activityNew}?mode=distance'),
          ),
          const SizedBox(height: NmSpace.s3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NmSpace.s3),
            child: Text(
              'Las calorías de ejercicio son una estimación.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
