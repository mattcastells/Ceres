import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/nm_theme.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../components/system/buttons.dart';
import '../providers/auth_providers.dart';
import '../screens/home/add_sheet.dart';
import '../screens/settings/update_prompt.dart';

/// Shell autenticado: `BottomTabBar` de 4 destinos + FAB central elevado
/// (02-information-architecture.md §4).
///
/// El FAB no es un tab: abre `sheet.add` sobre el tab activo y devuelve al
/// mismo tab. Cada tab conserva su stack y su posición de scroll.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sheetOpen = false;

  /// Que el aviso de versión nueva se pregunte una vez por sesión de app y no
  /// una por cada vez que el shell se reconstruye.
  static bool _updateAsked = false;

  @override
  void initState() {
    super.initState();
    // El aviso de versión nueva va acá y no en el arranque: el shell es lo
    // primero que se ve **estando adentro**, así que hay un `Navigator` sobre el
    // que mostrar el diálogo y no se le pisa la pantalla a quien está creando la
    // cuenta o completando sus datos.
    if (_updateAsked) return;
    _updateAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(maybePromptForUpdate(context, ref));
    });
  }

  static const List<({IconData icon, String label})> _tabs =
      <({IconData icon, String label})>[
        (icon: Icons.home_outlined, label: 'Inicio'),
        (icon: Icons.people_outline, label: 'Pals'),
        (icon: Icons.show_chart_outlined, label: 'Progreso'),
        (icon: Icons.person_outline, label: 'Perfil'),
      ];

  /// Índice de la tab de Pals: es la única que hoy necesita un aviso.
  static const int _palsTabIndex = 1;

  Future<void> _openAddSheet() async {
    setState(() => _sheetOpen = true);
    await showAddSheet(context);
    if (mounted) setState(() => _sheetOpen = false);
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      // Volver a tocar el tab activo lo devuelve a su raíz.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final expanded = context.isExpanded;
    // Antes vivía como aviso en Perfil; se muda acá, que es donde ahora se
    // entra a Pals.
    final palRequests = ref.watch(incomingPalRequestsProvider);

    if (expanded) {
      // ≥ 905 px: NavigationRail en lugar de BottomTabBar (§6).
      return Scaffold(
        backgroundColor: nm.bg,
        body: Row(
          children: <Widget>[
            NavigationRail(
              backgroundColor: nm.surface,
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: NmSpace.s6),
                child: NmFab(onPressed: _openAddSheet, expanded: _sheetOpen),
              ),
              destinations: <NavigationRailDestination>[
                for (var i = 0; i < _tabs.length; i++)
                  NavigationRailDestination(
                    icon: _TabIcon(
                      icon: _tabs[i].icon,
                      showDot: i == _palsTabIndex && palRequests > 0,
                    ),
                    label: Text(_tabs[i].label),
                  ),
              ],
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: nm.bg,
      body: widget.navigationShell,
      floatingActionButton: NmFab(
        onPressed: _openAddSheet,
        expanded: _sheetOpen,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomTabBar(
        current: widget.navigationShell.currentIndex,
        onSelect: _goBranch,
        tabs: _tabs,
        badgeDotIndex: palRequests > 0 ? _palsTabIndex : null,
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.current,
    required this.onSelect,
    required this.tabs,
    this.badgeDotIndex,
  });

  final int current;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, String label})> tabs;

  /// Índice de la tab que muestra un puntito de aviso, o `null` si ninguna.
  final int? badgeDotIndex;

  static const double _borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      // 56 de contenido + el borde superior + el área segura: si no se suma
      // el borde, el contenido queda 1 px corto.
      height: NmLayout.tabBarHeight + _borderWidth + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: nm.surface,
        border: Border(top: BorderSide(color: nm.divider)),
      ),
      child: Row(
        children: <Widget>[
          _tab(context, 0),
          _tab(context, 1),
          // Hueco central para el FAB (56 px + aire).
          const SizedBox(width: NmLayout.fabSize + NmSpace.s6),
          _tab(context, 2),
          _tab(context, 3),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index) {
    final nm = context.nm;
    final tab = tabs[index];
    final selected = current == index;
    final showDot = badgeDotIndex == index;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: showDot ? '${tab.label}, con solicitudes pendientes' : tab.label,
        child: ExcludeSemantics(
          child: InkResponse(
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: context.motion.fade(NmMotion.fast),
              curve: NmMotion.ease,
              height: NmLayout.tabBarHeight,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _TabIcon(
                    icon: tab.icon,
                    size: NmIconSize.lg,
                    fill: selected ? 1 : 0,
                    color: selected ? nm.accent : nm.textMuted,
                    showDot: showDot,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tab.label,
                    style: NmTextStyles.from(
                      NmType.micro,
                      color: selected ? nm.accent : nm.textMuted,
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

/// El ícono de una tab, con un puntito arriba a la derecha cuando hay algo
/// pendiente que todavía no se vio (hoy, solo solicitudes de Pals).
class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.icon,
    required this.showDot,
    this.size = NmIconSize.lg,
    this.fill = 0,
    this.color,
  });

  final IconData icon;
  final bool showDot;
  final double size;
  final double fill;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Icon(icon, size: size, fill: fill, color: color),
        if (showDot)
          Positioned(
            top: -1,
            right: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: nm.danger,
                shape: BoxShape.circle,
                border: Border.all(color: nm.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
