import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import 'buttons.dart';

/// Contenedor de bottom sheet: título, subtítulo y contenido con el padding
/// del sistema. Toma el foco al abrir y lo devuelve al cerrar.
class NmSheet extends StatelessWidget {
  const NmSheet({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.footer,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  /// "Atrás" cuando un sheet reemplaza a otro (regla del §3 de la IA).
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    // Dos cosas distintas comen espacio abajo y hay que respetar las dos: el
    // teclado (`viewInsets`) y la barra de navegación o la barra de gestos del
    // sistema (`viewPadding`). Antes solo se contemplaba el teclado, así que
    // con el teclado cerrado el botón del sheet quedaba **debajo** de la barra
    // del teléfono y no se podía tocar. Con el teclado abierto, `viewInsets`
    // ya incluye esa zona, por eso se toma el mayor y no la suma.
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.viewPadding.bottom;

    return Semantics(
      container: true,
      label: title,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NmSpace.s4,
                0,
                NmSpace.s4,
                NmSpace.s3,
              ),
              child: Row(
                children: <Widget>[
                  if (onBack != null)
                    NmIconButton(
                      icon: PhosphorIcons.caretLeft(),
                      onPressed: onBack,
                      tooltip: 'Atrás',
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: NmTextStyles.from(NmType.h3, color: nm.text),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: NmSpace.s1),
                            child: Text(
                              subtitle!,
                              style: NmTextStyles.from(
                                NmType.caption,
                                color: nm.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NmSpace.s4,
                  0,
                  NmSpace.s4,
                  NmSpace.s6,
                ),
                child: child,
              ),
            ),
            if (footer != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  NmSpace.s4,
                  NmSpace.s3,
                  NmSpace.s4,
                  NmSpace.s4 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: nm.surface,
                  border: Border(top: BorderSide(color: nm.divider)),
                ),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de acción de un `ActionSheet`: ícono, etiqueta y subtítulo.
class ActionRow extends StatelessWidget {
  const ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    this.disabledNote,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledNote;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      button: true,
      enabled: enabled,
      label: subtitle == null ? label : '$label. $subtitle',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : NmStateToken.disabledOpacity,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: NmRadius.brMd,
            highlightColor: nm.hoverNeutral,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: NmSpace.s3,
                vertical: NmSpace.s3,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    height: 40,
                    width: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: nm.surfaceRaised,
                      borderRadius: NmRadius.brMd,
                    ),
                    child: Icon(icon, size: NmIconSize.lg, color: nm.text),
                  ),
                  const SizedBox(width: NmSpace.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: NmTextStyles.from(NmType.body, color: nm.text),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ),
                          ),
                        if (!enabled && disabledNote != null)
                          Text(
                            disabledNote!,
                            style: NmTextStyles.from(
                              NmType.micro,
                              color: nm.caution,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre un bottom sheet con el estilo del sistema.
Future<T?> showNmSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool expand = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  isDismissible: isDismissible,
  enableDrag: isDismissible,
  useSafeArea: true,
  // Sobre el navigator raíz: el sheet va por encima del FAB y de la barra de
  // tabs, como manda el orden de elevación (sheet 30 · fab 20).
  useRootNavigator: true,
  backgroundColor: context.nm.surface,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * (expand ? 0.92 : 0.85),
    maxWidth: NmLayout.contentMaxWidth,
  ),
  builder: builder,
);

/// Diálogo modal: escala 0,96 → 1 + fundido (21-motion §2).
Future<T?> showNmDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final motion = context.motion;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: motion.move(NmMotion.base),
    pageBuilder: (context, a, b) => builder(context),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: NmMotion.ease,
        reverseCurve: NmMotion.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: motion.reduced
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
      );
    },
  );
}

/// Diálogo del sistema con título, cuerpo y acciones.
class NmDialog extends StatelessWidget {
  const NmDialog({
    required this.title,
    required this.actions,
    this.body,
    this.content,
    super.key,
  });

  final String title;
  final String? body;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    // `Dialog` contempla el teclado pero no la barra del sistema: un diálogo
    // alto terminaba con sus botones debajo de la barra de gestos.
    final safe = MediaQuery.viewPaddingOf(context);
    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(
        NmSpace.s6,
        NmSpace.s6 + safe.top,
        NmSpace.s6,
        NmSpace.s6 + safe.bottom,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(NmSpace.s6),
        decoration: BoxDecoration(
          color: nm.surface,
          borderRadius: NmRadius.brLg,
          boxShadow: nm.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: NmTextStyles.from(NmType.h3, color: nm.text)),
            if (body != null) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              Text(
                body!,
                style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
              ),
            ],
            if (content != null) ...<Widget>[
              const SizedBox(height: NmSpace.s4),
              Flexible(child: SingleChildScrollView(child: content!)),
            ],
            const SizedBox(height: NmSpace.s6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmación de borrado (`dialog.delete_confirm`).
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Eliminar',
}) async {
  final result = await showNmDialog<bool>(
    context: context,
    builder: (context) => NmDialog(
      title: title,
      body: body,
      actions: <Widget>[
        NmButton.ghost(
          label: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NmButton(
          label: confirmLabel,
          variant: NmButtonVariant.danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Mensajes al pie. Con "Deshacer" duran 8 s (RN-16); si no, 3,6 s.
///
/// [duration] es para los pocos avisos que no entran en ninguna de las dos
/// medidas —el de versión nueva, que trae una acción que conviene no perderse—.
/// Sin él manda [undo], que es lo que decide en el resto de la app.
abstract final class NmSnackbar {
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    bool undo = false,
    Duration? duration,
  }) {
    final nm = context.nm;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: NmTextStyles.from(NmType.bodySm, color: nm.text),
          ),
          duration: duration ?? Duration(milliseconds: undo ? 8000 : 3600),
          backgroundColor: nm.surfaceRaised,
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: nm.isDark ? nm.accentText : nm.accent,
                  onPressed: onAction ?? () {},
                ),
        ),
      );
  }
}
