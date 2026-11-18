import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/remote/pals_client.dart';
import '../../../domain/models/pal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';

/// Pals: quién ve tu día y de quién ves el suyo.
class PalsScreen extends ConsumerStatefulWidget {
  const PalsScreen({super.key});

  @override
  ConsumerState<PalsScreen> createState() => _PalsScreenState();
}

class _PalsScreenState extends ConsumerState<PalsScreen> {
  final TextEditingController _code = TextEditingController();
  bool _sending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Releer al entrar, siempre. Una solicitud que llegó mientras la app estaba
    // abierta no se anuncia sola: si la lista no se vuelve a pedir acá, la
    // pantalla muestra lo que había la primera vez que se abrió.
    //
    // Pals ahora es la raíz de una tab del shell: invalidar en el mismo
    // `initState` en el que se monta rompe con "dependOnInheritedWidgetOf...
    // called before initState() completed", porque este widget se está
    // montando todavía dentro del build de otro (la tab que cambia). Se
    // corre después del primer frame, no antes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(palsProvider);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final client = ref.read(palsClientProvider);
    if (client == null) return;

    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      final result = await client.request(_code.text);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = switch (result) {
          PalRequestResult.sent => null,
          PalRequestResult.notFound => 'No hay nadie con ese código.',
          PalRequestResult.self => 'Ese es tu propio código.',
          // El servidor no dice de qué lado está el vínculo —el código no
          // revela nada de su dueño—, así que la respuesta la da la lista, que
          // se recarga justo abajo.
          PalRequestResult.already =>
            'Ya hay un vínculo con esa persona. Mirá la lista de abajo.',
          PalRequestResult.rateLimited =>
            'Mandaste muchas solicitudes hoy. Probá de nuevo mañana.',
        };
      });
      // También cuando dice "already": el vínculo que lo provoca es
      // exactamente lo que hay que mostrar.
      ref.invalidate(palsProvider);
      if (result == PalRequestResult.sent) {
        _code.clear();
        if (mounted) NmSnackbar.show(context, 'Solicitud enviada');
      }
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = error.message;
      });
    }
  }

  /// Aceptar y quitar salen a la red, así que pueden fallar — y hasta acá el
  /// fallo era un `await` sin capturar: una excepción asincrónica sin dueño,
  /// sin mensaje y sin estado. Del lado de quien usa la app eso se vive como
  /// "toco Aceptar y no pasa nada", que es exactamente la clase de bug que ya
  /// se reportó por otro lado.
  Future<void> _responder(Future<void> Function() accion) async {
    try {
      await accion();
    } on AppError catch (error) {
      if (!mounted) return;
      NmSnackbar.show(context, error.message);
      return;
    } on Object {
      if (!mounted) return;
      NmSnackbar.show(context, 'No pudimos completar la acción.');
      return;
    }
    if (!mounted) return;
    ref.invalidate(palsProvider);
  }

  Future<void> _accept(Pal pal) =>
      _responder(() async => ref.read(palsClientProvider)?.accept(pal.id));

  Future<void> _remove(Pal pal) async {
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Quitar a ${pal.label}?',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Quitar',
            variant: NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _responder(() async => ref.read(palsClientProvider)?.remove(pal.id));
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    if (ref.watch(palsClientProvider) == null) {
      return const NmScreen(
        title: 'Pals',
        child: Padding(
          padding: EdgeInsets.only(top: NmSpace.s6),
          child: InfoNote(
            text: 'Esta versión no tiene servidor: Pals necesita cuenta.',
            tone: NmNoteTone.caution,
          ),
        ),
      );
    }

    final pals = ref.watch(palsProvider);
    final myCode = ref.watch(myPalCodeProvider);

    return NmScreen(
      title: 'Pals',
      actions: <Widget>[
        NmIconButton(
          icon: PhosphorIcons.arrowsClockwise(),
          tooltip: 'Actualizar',
          onPressed: () => ref.invalidate(palsProvider),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),

          const NmSectionHeader(title: 'Tu código'),
          NmCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    myCode.maybeWhen(
                      data: (code) => code ?? '—',
                      orElse: () => '…',
                    ),
                    style: NmTextStyles.from(NmType.h2, color: nm.text).tnum,
                  ),
                ),
                NmButton.ghost(
                  label: 'Copiar',
                  onPressed: () {
                    final code = myCode.valueOrNull;
                    if (code == null) return;
                    Clipboard.setData(ClipboardData(text: code));
                    NmSnackbar.show(context, 'Código copiado');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Agregar un pal'),
          NmTextField(
            label: 'Código',
            controller: _code,
            error: _message,
            hint: 'ABCD2345',
            onChanged: (_) => setState(() => _message = null),
          ),
          const SizedBox(height: NmSpace.s3),
          NmButton.secondary(
            label: 'Enviar solicitud',
            block: true,
            loading: _sending,
            onPressed: _code.text.trim().length < 8 ? null : _request,
          ),

          const SizedBox(height: NmSpace.s8),
          pals.when(
            loading: () => const SkeletonList(rows: 3, withAvatar: false),
            error: (error, _) => ErrorState(
              message: error is AppError
                  ? error.message
                  : 'No pudimos cargar tus pals.',
              onRetry: () => ref.invalidate(palsProvider),
            ),
            data: (list) =>
                _PalList(pals: list, onAccept: _accept, onRemove: _remove),
          ),

          const SizedBox(height: NmSpace.s6),
          // Qué ven tus pals y de qué te avisa la app. Antes vivía en Perfil
          // y en un engranaje de la barra: acá, a la vista.
          NmButton.secondary(
            label: 'Configurar Pals',
            block: true,
            icon: PhosphorIcons.slidersHorizontal(),
            onPressed: () => context.push(Routes.palSharing),
          ),
        ],
      ),
    );
  }
}

class _PalList extends StatelessWidget {
  const _PalList({
    required this.pals,
    required this.onAccept,
    required this.onRemove,
  });

  final List<Pal> pals;
  final void Function(Pal) onAccept;
  final void Function(Pal) onRemove;

  @override
  Widget build(BuildContext context) {
    final incoming = pals
        .where((p) => p.status == PalStatus.pending && p.isIncoming)
        .toList();
    final sent = pals
        .where((p) => p.status == PalStatus.pending && !p.isIncoming)
        .toList();
    final accepted = pals.where((p) => p.status == PalStatus.accepted).toList();

    if (pals.isEmpty) {
      return EmptyState(
        icon: PhosphorIcons.users(),
        title: 'Todavía no tenés pals',
        body: 'Pedile el código a alguien y agregalo acá.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (incoming.isNotEmpty) ...<Widget>[
          const NmSectionHeader(title: 'Te quieren agregar'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                for (final pal in incoming)
                  NmListRow(
                    title: pal.label,
                    subtitle: 'Quiere ver tu día',
                    leading: Icon(PhosphorIcons.userPlus()),
                    trailing: NmButton.ghost(
                      label: 'Aceptar',
                      onPressed: () => onAccept(pal),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
        ],

        if (accepted.isNotEmpty) ...<Widget>[
          const NmSectionHeader(title: 'Tus pals'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                for (final pal in accepted)
                  NmListRow(
                    title: pal.label,
                    leading: Icon(PhosphorIcons.user()),
                    onTap: () => context.push(
                      '${Routes.palDay(pal.userId)}'
                      '?name=${Uri.encodeComponent(pal.label)}',
                    ),
                    trailing: NmIconButton(
                      icon: PhosphorIcons.dotsThree(),
                      tooltip: 'Quitar',
                      onPressed: () => onRemove(pal),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
        ],

        if (sent.isNotEmpty) ...<Widget>[
          const NmSectionHeader(title: 'Esperando respuesta'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                for (final pal in sent)
                  NmListRow(
                    title: pal.label,
                    subtitle: 'Todavía no aceptó',
                    leading: Icon(PhosphorIcons.clock()),
                    trailing: NmButton.ghost(
                      label: 'Cancelar',
                      onPressed: () => onRemove(pal),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
