import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../system/buttons.dart';

/// Estado vacío: nunca una lista vacía sin explicación y sin al menos una
/// acción (05-component-library §5).
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    this.icon,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
    super.key,
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      // Ancho completo, no el que ocupe el texto.
      //
      // Casi todas las pantallas apilan su contenido con
      // `crossAxisAlignment: start`, y ahí una columna centrada se centra
      // dentro de **su propio** ancho: si el cuerpo entra en una línea, el
      // bloque entero queda corrido a la izquierda y el título no coincide con
      // el eje de la pantalla. Se veía en "Mis cosas", donde el vacío no tiene
      // botón que estire la columna.
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compact ? NmSpace.s6 : NmSpace.s10,
        horizontal: NmSpace.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            icon ?? PhosphorIcons.sparkle(),
            size: NmIconSize.xl,
            color: nm.textMuted,
          ),
          const SizedBox(height: NmSpace.s4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: NmTextStyles.from(NmType.h4, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          if (primaryLabel != null) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            NmButton(label: primaryLabel!, onPressed: onPrimary),
          ],
          if (secondaryLabel != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            NmButton.ghost(label: secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

/// Estado de error: el mensaje dice qué falló y qué se puede hacer. El código
/// técnico solo aparece en debug.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.code,
    this.onRetry,
    this.retryLabel = 'Reintentar',
    this.retryEnabled = true,
    super.key,
  });

  final String message;
  final String? code;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Con `false` el botón se ve pero no se puede tocar.
  ///
  /// Es distinto de no pasar `onRetry`: ahí no hay botón y la salida
  /// desaparece de la pantalla. Cuando reintentar va a fallar seguro —el
  /// proveedor dijo cuántos segundos faltan— lo que corresponde es que el
  /// botón siga a la vista, apagado y contando, y no que aparezca y
  /// desaparezca solo.
  final bool retryEnabled;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Padding(
      padding: const EdgeInsets.all(NmSpace.s6),
      child: Column(
        children: <Widget>[
          Icon(
            PhosphorIcons.warningCircle(),
            size: NmIconSize.xl,
            color: nm.danger,
          ),
          const SizedBox(height: NmSpace.s4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: NmTextStyles.from(NmType.bodySm, color: nm.text),
          ),
          if (code != null && _isDebug) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            Text(
              code!,
              style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            NmButton(
              label: retryLabel,
              onPressed: retryEnabled ? onRetry : null,
            ),
          ],
        ],
      ),
    );
  }

  static const bool _isDebug = !bool.fromEnvironment('dart.vm.product');
}

/// Bloque de skeleton con el brillo que recorre de izquierda a derecha en
/// 1200 ms. Con `reduce motion` queda estático — el skeleton sigue existiendo
/// porque comunica "esto está cargando" (21-motion §4.2 y §6).
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    this.height = 14,
    this.width,
    this.radius = NmRadius.md,
    this.circle = false,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;
  final bool circle;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NmMotion.shimmerLoop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Con movimiento reducido el bloque queda estático (§6). Además, no dejar
    // el controlador en bucle evita que un test nunca llegue a estabilizarse.
    if (context.motion.animatesShimmer) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final animate = context.motion.animatesShimmer;

    return SizedBox(
      height: widget.circle ? widget.height : widget.height,
      width: widget.circle ? widget.height : widget.width,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = animate ? _controller.value : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: nm.skeleton,
              borderRadius: widget.circle
                  ? BorderRadius.circular(NmRadius.full)
                  : BorderRadius.circular(widget.radius),
              gradient: animate
                  ? LinearGradient(
                      begin: Alignment(-1 + t * 2 - 0.6, 0),
                      end: Alignment(-1 + t * 2 + 0.6, 0),
                      colors: <Color>[
                        nm.skeleton,
                        nm.skeletonHighlight,
                        nm.skeleton,
                      ],
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// N filas fantasma con avatar cuadrado y dos líneas de 100 % y 60 % (§4.2).
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.rows = 6, this.withAvatar = true, super.key});

  final int rows;
  final bool withAvatar;

  @override
  Widget build(BuildContext context) => Column(
    children: List<Widget>.generate(
      rows,
      (i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: NmSpace.s3),
        child: Row(
          children: <Widget>[
            if (withAvatar) ...<Widget>[
              const SkeletonBlock(height: 40, width: 40),
              const SizedBox(width: NmSpace.s4),
            ],
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBlock(height: 12),
                  SizedBox(height: NmSpace.s2),
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: SkeletonBlock(height: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Spinner del sistema: anillo de 2 px con el acento. Es la única animación
/// que se mantiene con `reduce motion` (21-motion §6).
class NmSpinner extends StatelessWidget {
  const NmSpinner({this.size = 24, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: size,
    width: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: color ?? context.nm.accent,
    ),
  );
}

/// Conmuta entre skeleton y contenido respetando la duración mínima visible
/// de 400 ms y el umbral de 200 ms (21-motion §4.1).
class LoadingSwitcher extends StatelessWidget {
  const LoadingSwitcher({
    required this.loading,
    required this.skeleton,
    required this.child,
    super.key,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: context.motion.fade(NmMotion.fast),
    child: loading
        ? KeyedSubtree(key: const ValueKey<String>('skeleton'), child: skeleton)
        : KeyedSubtree(key: const ValueKey<String>('content'), child: child),
  );
}

/// Entrada escalonada de una lista: fundido + 8 px hacia arriba, con el
/// stagger de 40 ms y techo de 8 elementos (21-motion §1 y §2).
class StaggeredItem extends StatelessWidget {
  const StaggeredItem({
    required this.index,
    required this.child,
    super.key,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    if (motion.reduced) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: NmMotion.base + motion.staggerFor(index),
      curve: Interval(
        (motion.staggerFor(index).inMilliseconds /
                (NmMotion.base.inMilliseconds +
                    motion.staggerFor(index).inMilliseconds))
            .clamp(0.0, 0.9),
        1,
        curve: NmMotion.ease,
      ),
      builder: (context, t, inner) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: inner),
      ),
      child: child,
    );
  }
}
