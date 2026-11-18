import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/pal.dart';
import '../../../domain/services/pal_alerts.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';
import '../../providers/reminder_providers.dart';

/// Configurar Pals: qué ven tus pals y de qué te avisa la app.
///
/// Todo se elige. Comida y actividad arrancan prendidas (es lo que se venía
/// compartiendo); el resto, apagado. Las medidas no se comparten nunca.
class PalSharingScreen extends ConsumerWidget {
  const PalSharingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(myPalSharingPrefsProvider);

    return NmScreen(
      title: 'Configurar Pals',
      child: prefsAsync.when(
        loading: () => const SkeletonList(rows: 4, withAvatar: false),
        error: (error, _) => ErrorState(
          message: error is AppError
              ? error.message
              : 'No pudimos cargar tus preferencias.',
          onRetry: () => ref.invalidate(myPalSharingPrefsProvider),
        ),
        data: (prefs) => _SharingForm(initial: prefs),
      ),
    );
  }
}

class _SharingForm extends ConsumerStatefulWidget {
  const _SharingForm({required this.initial});

  final PalSharingPrefs initial;

  @override
  ConsumerState<_SharingForm> createState() => _SharingFormState();
}

class _SharingFormState extends ConsumerState<_SharingForm> {
  late PalSharingPrefs _prefs = widget.initial;

  Future<void> _update(PalSharingPrefs next) async {
    final previous = _prefs;
    setState(() => _prefs = next);
    try {
      await ref.read(palsClientProvider)?.setSharingPrefs(next);
      // Lo que se apaga lo limpia la base; lo que se prende hay que volver a
      // publicarlo, y no esperar a la próxima comida.
      ref.read(palPublisherProvider)?.markDirty();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      NmSnackbar.show(context, error.message);
    }
  }

  Future<void> _updateAlerts(PalAlertPrefs next) async {
    if (next.any) {
      final scheduler = ref.read(reminderSchedulerProvider);
      final granted = await scheduler?.requestPermission() ?? false;
      if (!granted) {
        if (mounted) {
          NmSnackbar.show(
            context,
            'Activá las notificaciones de Ceres en Android para recibir avisos.',
          );
        }
        return;
      }
    }
    await ref.read(palAlertPrefsProvider.notifier).set(next);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(palAlertPrefsProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: NmSpace.s4),
        const NmSectionHeader(title: 'Qué ven tus pals'),
        NmCard(
          padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
          child: Column(
            children: <Widget>[
              NmSwitchRow(
                title: 'Comida',
                subtitle: 'Qué comiste y cuántas calorías.',
                value: _prefs.meals,
                onChanged: (v) => _update(_prefs.copyWith(meals: v)),
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Fotos de mis comidas',
                subtitle: 'La foto que sacaste al cargar cada comida.',
                value: _prefs.meals && _prefs.photos,
                onChanged: _prefs.meals
                    ? (v) => _update(_prefs.copyWith(photos: v))
                    : null,
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Actividad',
                subtitle: 'Si te moviste y cuánto tiempo.',
                value: _prefs.activity,
                onChanged: (v) => _update(_prefs.copyWith(activity: v)),
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Detalle de actividad',
                subtitle: 'Cada actividad con su nombre y duración.',
                value: _prefs.activity && _prefs.activityDetail,
                onChanged: _prefs.activity
                    ? (v) => _update(_prefs.copyWith(activityDetail: v))
                    : null,
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Agua',
                subtitle: 'Cuántos vasos tomaste cada día.',
                value: _prefs.water,
                onChanged: (v) => _update(_prefs.copyWith(water: v)),
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Sueño',
                subtitle: 'Cuánto dormiste y cómo lo calificaste.',
                value: _prefs.sleep,
                onChanged: (v) => _update(_prefs.copyWith(sleep: v)),
              ),
              const NmDivider(indent: NmSpace.s3),
              NmSwitchRow(
                title: 'Peso',
                subtitle: 'Tu último peso registrado.',
                value: _prefs.weight,
                onChanged: (v) => _update(_prefs.copyWith(weight: v)),
              ),
            ],
          ),
        ),
        if (alerts != null) ...<Widget>[
          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Avisos'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                NmSwitchRow(
                  title: 'Cuando un pal carga una comida',
                  subtitle: 'Si vos todavía no cargaste la tuya.',
                  value: alerts.meals,
                  onChanged: (v) => _updateAlerts(alerts.copyWith(meals: v)),
                ),
                const NmDivider(indent: NmSpace.s3),
                NmSwitchRow(
                  title: 'Cuando un pal registra actividad',
                  subtitle: 'Si vos todavía no te moviste hoy.',
                  value: alerts.activity,
                  onChanged: (v) => _updateAlerts(alerts.copyWith(activity: v)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
