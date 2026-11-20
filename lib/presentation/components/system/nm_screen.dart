import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';

/// Andamiaje de pantalla con los márgenes del sistema (16 px en móvil, 24 px
/// ≥ 600 px) y el ancho de contenido limitado a 720 px (§3 y §6).
class NmScreen extends StatelessWidget {
  const NmScreen({
    required this.child,
    this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.scrollable = true,
    this.banner,
    this.bottom,
    this.floatingActionButton,
    this.padded = true,
    this.centerContent = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final List<Widget> actions;
  final Widget? leading;
  final bool scrollable;

  /// Banner no bloqueante bajo la cabecera (sin conexión, datos guardados).
  final Widget? banner;
  final Widget? bottom;
  final Widget? floatingActionButton;
  final bool padded;
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final padding = EdgeInsets.symmetric(
      horizontal: padded ? context.screenPadding : 0,
    );

    Widget content = Padding(padding: padding, child: child);
    if (centerContent) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: NmLayout.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }
    if (scrollable) {
      content = SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: NmSpace.s12),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              leading: leading,
              actions: actions,
            ),
      body: SafeArea(
        top: title == null,
        child: Column(
          children: <Widget>[
            ?banner,
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Cabecera de pantalla modal: título + cerrar.
class NmModalHeader extends StatelessWidget implements PreferredSizeWidget {
  const NmModalHeader({
    required this.title,
    this.onClose,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final VoidCallback? onClose;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title, style: NmTextStyles.from(NmType.h4)),
    leading: IconButton(
      onPressed: onClose ?? () => Navigator.of(context).maybePop(),
      tooltip: 'Cerrar',
      icon: Icon(PhosphorIcons.x(), size: NmIconSize.lg),
    ),
    actions: actions,
  );
}
