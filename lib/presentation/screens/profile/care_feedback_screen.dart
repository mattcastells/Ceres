import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/care_feedback.dart';
import '../../components/care/care_feedback_card.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';
import '../../providers/plan_providers.dart';

/// Devoluciones e indicaciones de la nutricionista, de lo más nuevo a lo más
/// viejo.
///
/// Abrir la pantalla **es** leer: lo que estaba sin leer se marca en el
/// servidor al llegar, y la profesional lo ve en su tablero. Durante esta
/// visita lo recién leído conserva la marca de "Nueva", para que no se pierda
/// de vista qué era lo que había llegado.
class CareFeedbackScreen extends ConsumerStatefulWidget {
  const CareFeedbackScreen({super.key});

  @override
  ConsumerState<CareFeedbackScreen> createState() => _CareFeedbackScreenState();
}

class _CareFeedbackScreenState extends ConsumerState<CareFeedbackScreen> {
  /// Lo que estaba sin leer al entrar. Se muestra como "Nueva" hasta salir.
  final Set<String> _new = <String>{};

  /// Lo que ya se mandó a marcar, para no volver a pedirlo en cada recarga si
  /// la marca falló (sin conexión) y la fila sigue viniendo sin leer.
  final Set<String> _marked = <String>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<CareInbox>>(
      careFeedbackProvider,
      (_, next) => next.whenData(_markUnread),
      fireImmediately: true,
    );
  }

  Future<void> _markUnread(CareInbox inbox) async {
    final pending = <CareFeedback>[
      for (final f in inbox.unread)
        if (!_marked.contains(f.id)) f,
    ];
    if (pending.isEmpty) return;
    final client = ref.read(careFeedbackClientProvider);
    if (client == null) return;

    _marked.addAll(pending.map((f) => f.id));
    // Fuera del frame: `listenManual` con `fireImmediately` llama durante el
    // primer build, y ahí no se puede pedir otro.
    scheduleMicrotask(() {
      if (mounted) setState(() => _new.addAll(pending.map((f) => f.id)));
    });

    var any = false;
    for (final f in pending) {
      try {
        await client.markRead(f.id);
        any = true;
      } on AppError {
        // Se vuelve a intentar la próxima vez que se abra.
      }
    }
    // Para que Inicio deje de avisar. La lista de acá se vuelve a dibujar con
    // las mismas filas, ya leídas, y `_new` les conserva la marca.
    if (any && mounted) ref.invalidate(careFeedbackProvider);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    if (!ref.watch(isCloudEnabledProvider)) {
      return NmScreen(
        title: 'De tu nutricionista',
        child: EmptyState(
          icon: PhosphorIcons.stethoscope(),
          title: 'Necesitás una cuenta',
          body:
              'Las devoluciones llegan desde el panel de tu nutricionista, '
              'y sin cuenta tus datos viven solo en este teléfono.',
        ),
      );
    }

    final async = ref.watch(careFeedbackProvider);

    return NmScreen(
      title: 'De tu nutricionista',
      scrollable: false,
      child: RefreshIndicator(
        color: nm.accent,
        backgroundColor: nm.surface,
        onRefresh: () => ref.refresh(careFeedbackProvider.future),
        child: async.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.only(top: NmSpace.s4),
            child: SkeletonList(rows: 3, withAvatar: false),
          ),
          error: (error, _) => ListView(
            children: <Widget>[
              ErrorState(
                message: error is AppError
                    ? error.message
                    : 'No pudimos traer lo de tu nutricionista.',
                onRetry: () => ref.invalidate(careFeedbackProvider),
              ),
            ],
          ),
          data: (inbox) => _List(inbox: inbox, fresh: _new),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.inbox, required this.fresh});

  final CareInbox inbox;
  final Set<String> fresh;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final indications = inbox.indications;
    final feedback = inbox.items.where((f) => !f.isIndication).toList();

    if (inbox.items.isEmpty) {
      return ListView(
        children: <Widget>[
          EmptyState(
            icon: PhosphorIcons.stethoscope(),
            title: 'Todavía no hay nada',
            body:
                'Las devoluciones e indicaciones de tu nutricionista van a '
                'aparecer acá.',
            secondaryLabel: 'Ver quién tiene acceso',
            onSecondary: () =>
                GoRouter.maybeOf(context)?.push(Routes.profileCare),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: NmSpace.s12),
      children: <Widget>[
        const SizedBox(height: NmSpace.s4),
        if (indications.isNotEmpty) ...<Widget>[
          const NmSectionHeader(title: 'Indicaciones vigentes'),
          Text(
            'Siguen valiendo hasta que tu nutricionista las cambie.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s3),
          for (final f in indications)
            _Item(feedback: f, isNew: fresh.contains(f.id)),
          const SizedBox(height: NmSpace.s6),
        ],
        if (feedback.isNotEmpty) ...<Widget>[
          const NmSectionHeader(title: 'Devoluciones'),
          for (final f in feedback)
            _Item(feedback: f, isNew: fresh.contains(f.id)),
        ],
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.feedback, required this.isNew});

  final CareFeedback feedback;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final day = feedback.localDate;
    return Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s3),
      child: NmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    careFeedbackByline(feedback),
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                ),
                if (isNew)
                  const NmTag(label: 'Nueva', variant: NmTagVariant.accent),
              ],
            ),
            if (day != null) ...<Widget>[
              const SizedBox(height: NmSpace.s1),
              Text(
                'Sobre el ${longDay(day).toLowerCase()}',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
            const SizedBox(height: NmSpace.s2),
            SelectableText(
              feedback.body,
              style: NmTextStyles.from(NmType.body, color: nm.text),
            ),
          ],
        ),
      ),
    );
  }
}
