import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/pal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';

/// Qué ve un pal, además de la comida y si te moviste (eso siempre se
/// comparte, no es parte de esta pantalla).
///
/// Los cuatro interruptores arrancan apagados para toda cuenta: nadie
/// comparte de más sin haber entrado acá a prenderlo a propósito.
class PalSharingScreen extends ConsumerWidget {
  const PalSharingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(myPalSharingPrefsProvider);

    return NmScreen(
      title: 'Qué ven mis pals',
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
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      NmSnackbar.show(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: NmSpace.s4),
        Text(
          'Un pal siempre ve qué comiste y si te moviste. Elegí qué más '
          'puede ver.',
          style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s6),
        NmCard(
          padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
          child: Column(
            children: <Widget>[
              NmSwitchRow(
                title: 'Fotos de mis comidas',
                subtitle: 'La foto que sacaste al cargar cada comida.',
                value: _prefs.photos,
                onChanged: (v) => _update(_prefs.copyWith(photos: v)),
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
                title: 'Detalle de actividad',
                subtitle: 'Cada actividad con su nombre y duración, no solo '
                    'el total.',
                value: _prefs.activityDetail,
                onChanged: (v) => _update(_prefs.copyWith(activityDetail: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: NmSpace.s6),
        const InfoNote(
          text: 'Tu peso y tus medidas nunca se comparten.',
        ),
      ],
    );
  }
}
