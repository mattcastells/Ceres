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

/// S-35 · Dar acceso a un profesional que te sigue.
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
              const NmSectionHeader(title: 'Con acceso'),
              for (final grant in grants)
                Padding(
                  padding: const EdgeInsets.only(bottom: NmSpace.s3),
                  child: _GrantCard(grant: grant),
                ),
              const SizedBox(height: NmSpace.s4),
            ],

            NmButton.secondary(
              label: 'Dar acceso con un código',
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

/// Un permiso vigente, con qué ve y el botón para cortarlo.
class _GrantCard extends ConsumerWidget {
  const _GrantCard({required this.grant});

  final CareGrant grant;

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: 'Cortar el acceso',
        body: grant.displayName.isEmpty
            ? 'Deja de ver tus datos en el acto.'
            : '${grant.displayName} deja de ver tus datos en el acto.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Cortar',
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
      // Dar o cortar un acceso puede cambiar el plan: con una profesional Pro
      // del otro lado, una cuenta gratis pasa a tener la IA incluida, y al
      // revés.
      unawaited(ref.read(planProvider.notifier).refresh());
      if (context.mounted) NmSnackbar.show(context, 'Acceso cortado');
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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  grant.displayName.isEmpty ? 'Profesional' : grant.displayName,
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
              ),
              NmButton.ghost(
                label: 'Cortar',
                onPressed: () => _revoke(context, ref),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s2),

          // Un permiso con todo apagado existe y desde afuera se ve igual que
          // uno activo. Decirlo evita creer que alguien está siguiendo un
          // tratamiento con datos que en realidad no le llegan.
          if (grant.sharesNothing)
            Text(
              'No ve nada: apagaste todas las categorías.',
              style: NmTextStyles.from(NmType.caption, color: nm.caution),
            )
          else
            Wrap(
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: <Widget>[
                for (final label in grant.categoryLabels)
                  NmTag(label: label, variant: NmTagVariant.outline),
              ],
            ),

          if (grant.expiresAt != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            Text(
              'Vence el ${shortDay(grant.expiresAt!)}',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],

          const SizedBox(height: NmSpace.s3),
          NmButton.ghost(
            label: 'Cambiar qué ve',
            onPressed: () => _openGrantSheet(context, ref, editing: grant),
          ),
        ],
      ),
    );
  }
}

/// Conceder y cambiar son el mismo formulario: cambiar qué ve es volver a
/// decir qué ve. Dos caminos al mismo lugar es uno que en algún momento queda
/// sin arreglar.
Future<void> _openGrantSheet(
  BuildContext context,
  WidgetRef ref, {
  CareGrant? editing,
}) => showNmSheet<void>(
  context: context,
  builder: (context) => _GrantSheet(editing: editing),
);

class _GrantSheet extends ConsumerStatefulWidget {
  const _GrantSheet({this.editing});

  final CareGrant? editing;

  @override
  ConsumerState<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends ConsumerState<_GrantSheet> {
  late final TextEditingController _code = TextEditingController();

  late CareCategories _categories = widget.editing == null
      ? const CareCategories()
      : CareCategories(
          meals: widget.editing!.shareMeals,
          photos: widget.editing!.sharePhotos,
          body: widget.editing!.shareBody,
          wellbeing: widget.editing!.shareWellbeing,
        );

  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(careClientProvider);
    if (client == null) return;

    // Al editar no se vuelve a pedir el código: ya hay un vínculo y hacerlo
    // dictar de nuevo para apagar una categoría sería pedir una llave para
    // entrar a una puerta que ya está abierta.
    final code = _code.text.trim();
    if (!_isEditing && code.length < 3) {
      setState(() => _error = 'Cargá el código que te pasó.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await client.updateCategories(
          grantId: widget.editing!.id,
          categories: _categories,
        );
      } else {
        await client.grant(code: code, categories: _categories);
      }
      ref.invalidate(careGrantsProvider);
      // Dar o cortar un acceso puede cambiar el plan: con una profesional Pro
      // del otro lado, una cuenta gratis pasa a tener la IA incluida, y al
      // revés.
      unawaited(ref.read(planProvider.notifier).refresh());
      if (!mounted) return;
      Navigator.of(context).pop();
      NmSnackbar.show(
        context,
        _isEditing ? 'Cambios guardados' : 'Acceso dado',
      );
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
      title: _isEditing ? 'Qué ve' : 'Dar acceso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!_isEditing) ...<Widget>[
            Text(
              'Pedile el código que le muestra su panel.',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s4),
            NmTextField(
              label: 'Código',
              controller: _code,
              hint: 'CE-K7M2QP',
              autofocus: true,
            ),
            const SizedBox(height: NmSpace.s5),
          ],

          Text(
            'Qué puede ver',
            style: NmTextStyles.from(NmType.h4, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s2),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                NmSwitchRow(
                  title: 'Comidas',
                  subtitle: 'Ítems, calorías, macros y tu objetivo.',
                  value: _categories.meals,
                  onChanged: (v) => setState(
                    () => _categories = _categories.copyWith(meals: v),
                  ),
                ),
                const NmDivider(indent: NmSpace.s3),
                NmSwitchRow(
                  title: 'Fotos',
                  subtitle: 'De las comidas que analizaste.',
                  value: _categories.photos,
                  onChanged: (v) => setState(
                    () => _categories = _categories.copyWith(photos: v),
                  ),
                ),
                const NmDivider(indent: NmSpace.s3),
                NmSwitchRow(
                  title: 'Peso y medidas',
                  subtitle: 'Peso y perímetros.',
                  value: _categories.body,
                  onChanged: (v) => setState(
                    () => _categories = _categories.copyWith(body: v),
                  ),
                ),
                const NmDivider(indent: NmSpace.s3),
                NmSwitchRow(
                  title: 'Actividad, agua y sueño',
                  subtitle: 'Ejercicio, vasos de agua y horas de sueño.',
                  value: _categories.wellbeing,
                  onChanged: (v) => setState(
                    () => _categories = _categories.copyWith(wellbeing: v),
                  ),
                ),
              ],
            ),
          ),

          if (_categories.none) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            const InfoNote(
              tone: NmNoteTone.caution,
              text: 'Sin ninguna categoría prendida no va a ver nada.',
            ),
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            Text(
              _error!,
              style: NmTextStyles.from(NmType.bodySm, color: nm.danger),
            ),
          ],

          const SizedBox(height: NmSpace.s5),
          NmButton(
            label: _isEditing ? 'Guardar' : 'Dar acceso',
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
