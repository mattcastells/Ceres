import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../components/brand/brand_mark.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';

/// S-02 · Bienvenida. Explica la propuesta en una pantalla y ofrece entrada.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  static const List<(IconData, String, String)> _bullets =
      <(IconData, String, String)>[
        (
          Icons.bolt_outlined,
          'Registro rápido',
          'Una comida o una actividad en menos de 15 segundos.',
        ),
        (
          Icons.calculate_outlined,
          'El cálculo a la vista',
          'Objetivo base, comida, actividad y ajuste, siempre por separado.',
        ),
        (
          Icons.tune_outlined,
          'Vos decidís cuánto suma el ejercicio',
          'Por defecto no suma nada a tu objetivo.',
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;

    return Scaffold(
      backgroundColor: nm.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: NmLayout.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.screenPadding,
                vertical: NmSpace.s10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const BrandWordmark(markSize: 36),
                  const SizedBox(height: NmSpace.s12),
                  Text(
                    'Comida y movimiento, en un solo número honesto',
                    style: NmTextStyles.from(NmType.h1, color: nm.text),
                  ),
                  const SizedBox(height: NmSpace.s8),
                  for (final bullet in _bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: NmSpace.s6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            height: 36,
                            width: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: nm.accentFill,
                              borderRadius: NmRadius.brMd,
                            ),
                            child: Icon(
                              bullet.$1,
                              size: NmIconSize.md,
                              color: nm.accentOnFill,
                            ),
                          ),
                          const SizedBox(width: NmSpace.s4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  bullet.$2,
                                  style: NmTextStyles.from(
                                    NmType.h4,
                                    color: nm.text,
                                  ),
                                ),
                                const SizedBox(height: NmSpace.s1),
                                Text(
                                  bullet.$3,
                                  style: NmTextStyles.from(
                                    NmType.bodySm,
                                    color: nm.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: NmSpace.s6),
                  NmButton(
                    label: 'Crear cuenta',
                    block: true,
                    onPressed: () => context.push(Routes.signUp),
                  ),
                  const SizedBox(height: NmSpace.s3),
                  NmButton.secondary(
                    label: 'Ya tengo cuenta',
                    block: true,
                    onPressed: () => context.push(Routes.signIn),
                  ),
                  const SizedBox(height: NmSpace.s3),
                  NmButton.ghost(
                    label: 'Probar sin cuenta',
                    block: true,
                    icon: PhosphorIcons.sparkle(),
                    onPressed: () async {
                      final repo = ref.read(repositoryProvider);

                      // Sembrada o no, la sesión de prueba arranca de cero y
                      // para eso vacía la base local. Si hay algo cargado, eso
                      // es borrar los datos de alguien con un solo toque desde
                      // una pantalla a la que se puede llegar sin querer —por
                      // ejemplo si la sesión no se pudo restaurar al arrancar.
                      if (repo.hasUserData) {
                        final confirmed = await showNmDialog<bool>(
                          context: context,
                          builder: (context) => NmDialog(
                            title: 'Esto borra lo que tenés en el teléfono',
                            body:
                                'El modo de prueba arranca de cero, así que '
                                'reemplaza tus registros. Si tenés cuenta, '
                                'entrá en vez de probar: tus datos vuelven '
                                'desde el respaldo.',
                            actions: <Widget>[
                              NmButton.ghost(
                                label: 'Mejor entro',
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                              ),
                              NmButton(
                                label: 'Borrar y probar',
                                variant: NmButtonVariant.danger,
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }

                      // Modo demo: usuario local anónimo, sin respaldo (D-15).
                      //
                      // **Vacío**, salvo mientras se desarrolla sin servidor.
                      // Los datos de ejemplo son una herramienta para ver la
                      // app llena mientras se la hace, no algo que alguien
                      // tenga que encontrarse y después distinguir de lo suyo.
                      await repo.startDemoSession(
                        seeded: FeatureFlags.seededDemoData,
                      );
                      if (context.mounted) context.go(Routes.home);
                    },
                  ),
                  const SizedBox(height: NmSpace.s4),
                  // Acá decía "y podés migrarlos cuando te registres". No es
                  // cierto y nunca lo fue: crear la cuenta llama a
                  // `startDemoSession`, que vacía la base local. Prometer una
                  // migración que no existe es peor que no ofrecer nada —
                  // alguien carga una semana confiando en eso y la pierde.
                  Text(
                    'Sin cuenta no hay respaldo, y lo que cargues probando no '
                    'pasa a una cuenta nueva.',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
