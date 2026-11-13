import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/plan.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/plan_providers.dart';

/// Planes: Gratis, Premium y Pro.
///
/// **La compra es simulada.** No hay cobro ni tienda: el botón llama a
/// `demo_switch_plan`, que solo existe para las cuentas de demostración, y la
/// app cambia en el acto —sin anuncios y con la IA—. Es la pieza que haría un
/// sistema de pagos, y la pantalla lo dice en vez de disfrazarlo.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _busy = false;
  String? _error;

  /// Cuál se está pidiendo, para poner el spinner en ese botón y no en todos.
  AppPlan? _requesting;

  Future<void> _switch(AppPlan target) async {
    setState(() {
      _busy = true;
      _requesting = target;
      _error = null;
    });
    try {
      final now = await ref.read(planProvider.notifier).switchDemo(target);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _requesting = null;
      });
      NmSnackbar.show(
        context,
        now.includesAi
            ? 'Listo: ya tenés ${now == AppPlan.premium ? 'Premium' : now.label}. '
                  'Compra simulada, no se cobró nada.'
            : 'Volviste al plan Gratis.',
      );
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _requesting = null;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final plan = ref.watch(planProvider);
    final cloud = ref.watch(isCloudEnabledProvider);
    // El mail sale de la sesión y no del perfil local: el perfil que se trae
    // del servidor no lo tiene (la tabla `profiles` no guarda correos), así
    // que en una cuenta que entró por "Ya tengo cuenta" venía vacío.
    final isDemo = isDemoAccountEmail(
      ref.watch(authGatewayProvider).currentAccount?.email ??
          ref.watch(profileProvider).email,
    );

    return NmScreen(
      title: 'Planes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          if (!cloud)
            const InfoNote(
              tone: NmNoteTone.info,
              text:
                  'Esta versión no tiene servidor: la app funciona '
                  'completa en este teléfono y no hay plan que elegir.',
            )
          else
            Row(
              children: <Widget>[
                Text(
                  'Tu plan:',
                  style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
                ),
                const SizedBox(width: NmSpace.s2),
                Flexible(
                  child: NmTag(label: plan.label, variant: NmTagVariant.accent),
                ),
              ],
            ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(tone: NmNoteTone.caution, text: _error!),
          ],
          const SizedBox(height: NmSpace.s6),

          _PlanCard(
            name: 'Gratis',
            price: 'US\$ 0',
            current: plan == AppPlan.free,
            features: const <String>[
              'Registro completo: comidas, actividad, peso, agua y sueño',
              'Buscador de alimentos y escáner de códigos',
              'Progreso, historial e informe en PDF',
              'Sin IA, con anuncios discretos',
            ],
            action: cloud && isDemo && plan == AppPlan.premium
                // Chico y secundario: está para poder repetir la demo, no
                // para invitar a nadie a bajar de plan.
                ? NmButton.ghost(
                    label: 'Volver al plan Gratis (demo)',
                    loading: _requesting == AppPlan.free,
                    onPressed: _busy ? null : () => _switch(AppPlan.free),
                  )
                : null,
          ),
          const SizedBox(height: NmSpace.s4),
          _PlanCard(
            name: 'Premium',
            price: 'US\$ 4,99 por mes',
            highlighted: true,
            current: plan == AppPlan.premium,
            features: const <String>[
              'Todo lo del plan Gratis',
              'Foto de la comida analizada con IA',
              'Describirla por texto o por voz',
              '¿Qué como? y recalcular con IA',
              'Resumen semanal redactado con IA',
              'Sin anuncios',
            ],
            action: cloud && plan == AppPlan.free
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      NmButton(
                        label: 'Pasarme a Premium',
                        block: true,
                        icon: PhosphorIcons.sparkle(),
                        loading: _requesting == AppPlan.premium,
                        onPressed: _busy
                            ? null
                            : () => _switch(AppPlan.premium),
                      ),
                      const SizedBox(height: NmSpace.s2),
                      Text(
                        'Compra simulada · demostración. No se cobra nada.',
                        textAlign: TextAlign.center,
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: NmSpace.s4),
          _PlanCard(
            name: 'Pro · para nutricionistas',
            price: 'Por profesional',
            current: plan == AppPlan.pro,
            features: const <String>[
              'Panel web con el tablero del equipo',
              'Informes de consulta redactados con IA',
              'Devoluciones e indicaciones a cada paciente',
              'IA incluida para sus pacientes vinculados',
            ],
            footnote: plan == AppPlan.patient
                ? 'Tu nutricionista tiene Pro: la IA te viene incluida '
                      'mientras le des acceso.'
                : 'Si tu nutricionista tiene Pro y le das acceso, la IA te '
                      'viene incluida.',
          ),
          const SizedBox(height: NmSpace.s6),
          const InfoNote(
            text:
                'Los anuncios del plan Gratis son de comercios y '
                'actividades, nunca de dietas, pastillas, detox ni alcohol. Y '
                'nunca se eligen con lo que registrás.',
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.features,
    required this.current,
    this.highlighted = false,
    this.action,
    this.footnote,
  });

  final String name;
  final String price;
  final List<String> features;
  final bool current;
  final bool highlighted;
  final Widget? action;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmCard(
      raised: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: NmTextStyles.from(NmType.h3, color: nm.text),
                ),
              ),
              if (current)
                const NmTag(label: 'Tu plan', variant: NmTagVariant.accent),
            ],
          ),
          const SizedBox(height: NmSpace.s1),
          Text(
            price,
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted).tnum,
          ),
          const SizedBox(height: NmSpace.s4),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    PhosphorIcons.check(),
                    size: NmIconSize.sm,
                    color: nm.textMuted,
                  ),
                  const SizedBox(width: NmSpace.s2),
                  Expanded(
                    child: Text(
                      feature,
                      style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                    ),
                  ),
                ],
              ),
            ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            Text(
              footnote!,
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            action!,
          ],
        ],
      ),
    );
  }
}
