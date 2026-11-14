import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/care_article.dart';
import '../../../domain/models/care_grant.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';
import '../../providers/plan_providers.dart';

/// S-35 · Tu nutricionista: sumarte con su código y darte de baja.
///
/// Desde la migración 55 no hay categorías que elegir: sumarse es darle a la
/// profesional acceso a todo lo que registrás.
///
/// Es lo mismo que Pals en la forma —un código, un vínculo, categorías— y algo
/// muy distinto en el fondo. Un pal ve una proyección: qué comiste y si te
/// moviste. Acá se abre lo que esa proyección deja afuera a propósito: el
/// detalle de cada ítem, los macros, el peso, las medidas.
///
/// Por eso la pantalla dice qué se abre en cada interruptor en vez de dejarlo
/// en "compartir mi progreso". La decisión de conceder esto tiene que poder
/// tomarse leyendo, no adivinando.
class CareAccessScreen extends ConsumerWidget {
  const CareAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sin servidor no hay nada que conceder y decirlo es más honesto que
    // mostrar una pantalla vacía que parece rota.
    if (!SupabaseConfig.isConfigured) {
      return NmScreen(
        title: 'Mi nutricionista',
        child: EmptyState(
          icon: PhosphorIcons.stethoscope(),
          title: 'Necesitás una cuenta',
          body:
              'Sin cuenta tus datos viven solo en este teléfono, así que no '
              'hay nada a lo que darle acceso desde otro lado.',
        ),
      );
    }

    final grantsAsync = ref.watch(careGrantsProvider);
    final articles =
        ref.watch(careArticlesProvider).valueOrNull ?? const <CareArticle>[];
    final seen = ref.watch(articleSeenProvider).valueOrNull;
    final unseen = seen == null ? 0 : articles.where(seen.isNew).length;

    return NmScreen(
      title: 'Mi nutricionista',
      child: grantsAsync.when(
        loading: () => const SkeletonList(rows: 3, withAvatar: false),
        error: (error, _) => ErrorState(
          message: error is AppError
              ? error.message
              : 'No pudimos cargar los accesos.',
          onRetry: () => ref.invalidate(careGrantsProvider),
        ),
        data: (grants) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: NmSpace.s4),

            // Lo que la profesional devuelve. Vive acá además de en Inicio
            // porque Inicio lo muestra solo cuando hay algo nuevo o vigente, y
            // las devoluciones viejas también se buscan.
            //
            // Los artículos van debajo solo si hay alguno: sin nada publicado
            // la fila sería una promesa vacía, y si la consulta falla tampoco
            // se muestra.
            NmCard(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
              child: Column(
                children: <Widget>[
                  NmListRow(
                    title: 'Devoluciones e indicaciones',
                    subtitle: _feedbackSubtitle(
                      ref
                              .watch(careFeedbackProvider)
                              .valueOrNull
                              ?.unreadCount ??
                          0,
                    ),
                    leading: Icon(PhosphorIcons.chatCircleText()),
                    onTap: () => context.push(Routes.careFeedback),
                  ),
                  if (articles.isNotEmpty)
                    NmListRow(
                      title: 'Artículos y recetas',
                      subtitle: _articlesSubtitle(articles.length, unseen),
                      leading: Icon(PhosphorIcons.bookOpenText()),
                      onTap: () => context.push(Routes.careArticles),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NmSpace.s6),

            if (grants.isNotEmpty) ...<Widget>[
              const NmSectionHeader(title: 'Tu nutricionista'),
              for (final grant in grants)
                Padding(
                  padding: const EdgeInsets.only(bottom: NmSpace.s3),
                  child: _GrantCard(grant: grant),
                ),
              const SizedBox(height: NmSpace.s4),
            ],

            NmButton.secondary(
              label: 'Sumarme con un código',
              block: true,
              icon: PhosphorIcons.plus(),
              onPressed: () => _openGrantSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// La nutricionista a la que estás sumado, y cómo darte de baja.
class _GrantCard extends ConsumerWidget {
  const _GrantCard({required this.grant});

  final CareGrant grant;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final name = grant.displayName.isEmpty
        ? 'Tu nutricionista'
        : grant.displayName;
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Darte de baja?',
        body:
            '$name deja de ver tus datos. Si la IA te la pagaba ella, '
            'volvés a tu plan.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Darme de baja',
            variant: NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(careClientProvider)?.revoke(grant.id);
      ref.invalidate(careGrantsProvider);
      // Con una profesional Pro del otro lado la IA venía incluida: al darse
      // de baja, el plan cambia.
      unawaited(ref.read(planProvider.notifier).refresh());
      if (context.mounted) NmSnackbar.show(context, 'Te diste de baja');
    } on AppError catch (error) {
      if (context.mounted) NmSnackbar.show(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;

    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            grant.displayName.isEmpty ? 'Profesional' : grant.displayName,
            style: NmTextStyles.from(NmType.h4, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s1),
          Text(
            'Ve todo lo que registrás'
            '${grant.expiresAt == null ? '' : ' · hasta el ${shortDay(grant.expiresAt!)}'}.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s3),
          NmButton.ghost(
            label: 'Darme de baja',
            onPressed: () => _leave(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Sumarse a una nutricionista con el código que le muestra su panel.
Future<void> _openGrantSheet(BuildContext context, WidgetRef ref) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => const _GrantSheet(),
    );

class _GrantSheet extends ConsumerStatefulWidget {
  const _GrantSheet();

  @override
  ConsumerState<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends ConsumerState<_GrantSheet> {
  late final TextEditingController _code = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(careClientProvider);
    if (client == null) return;

    final code = _code.text.trim();
    if (code.length < 3) {
      setState(() => _error = 'Cargá el código que te pasó.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await client.grant(code: code);
      ref.invalidate(careGrantsProvider);
      // Con una profesional Pro del otro lado, una cuenta gratis pasa a tener
      // la IA incluida.
      unawaited(ref.read(planProvider.notifier).refresh());
      if (!mounted) return;
      Navigator.of(context).pop();
      NmSnackbar.show(context, 'Listo, ya estás con tu nutricionista');
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return NmSheet(
      title: 'Sumarme a mi nutricionista',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Pedile el código que le muestra su panel. Va a ver todo lo que '
            'registrás.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s4),
          NmTextField(
            label: 'Código',
            controller: _code,
            hint: 'CE-K7M2QP',
            autofocus: true,
            error: _error,
          ),
          const SizedBox(height: NmSpace.s5),
          NmButton(
            label: 'Sumarme',
            block: true,
            loading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

String _articlesSubtitle(int total, int unseen) => switch (unseen) {
  0 => total == 1 ? '1 publicado' : '$total publicados',
  1 => '1 sin leer',
  _ => '$unseen sin leer',
};

String? _feedbackSubtitle(int unread) => switch (unread) {
  0 => null,
  1 => '1 nueva sin leer',
  _ => '$unread nuevas sin leer',
};
