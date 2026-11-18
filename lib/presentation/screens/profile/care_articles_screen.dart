import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/care_article.dart';
import '../../../domain/services/article_text.dart';
import '../../components/care/article_body.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';
import '../../providers/care_providers.dart';

/// Los artículos y recetas que publicó la nutricionista, de lo más nuevo a lo
/// más viejo.
///
/// Mirar la lista apaga el aviso de Inicio para lo publicado hasta ahora; cada
/// artículo dice "Nuevo" hasta que se abre. Todo eso vive en el teléfono: el
/// servidor no sabe qué se leyó.
class CareArticlesScreen extends ConsumerStatefulWidget {
  const CareArticlesScreen({super.key});

  @override
  ConsumerState<CareArticlesScreen> createState() => _CareArticlesScreenState();
}

class _CareArticlesScreenState extends ConsumerState<CareArticlesScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<CareArticle>>>(careArticlesProvider, (
      _,
      next,
    ) {
      if (next.hasValue) {
        // Fuera del frame: con `fireImmediately` esto corre durante el
        // primer build.
        scheduleMicrotask(() {
          if (mounted) {
            unawaited(ref.read(articleSeenProvider.notifier).markListVisited());
          }
        });
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    if (!ref.watch(isCloudEnabledProvider)) {
      return NmScreen(
        title: 'Artículos y recetas',
        child: EmptyState(
          icon: PhosphorIcons.bookOpenText(),
          title: 'Necesitás una cuenta',
          body: 'Los artículos llegan desde el panel de tu nutricionista.',
        ),
      );
    }

    final async = ref.watch(careArticlesProvider);
    final seen = ref.watch(articleSeenProvider).valueOrNull;

    return NmScreen(
      title: 'Artículos y recetas',
      scrollable: false,
      child: RefreshIndicator(
        color: nm.accent,
        backgroundColor: nm.surface,
        onRefresh: () => ref.refresh(careArticlesProvider.future),
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
                    : 'No pudimos traer los artículos.',
                onRetry: () => ref.invalidate(careArticlesProvider),
              ),
            ],
          ),
          data: (articles) => articles.isEmpty
              ? ListView(
                  children: <Widget>[
                    EmptyState(
                      icon: PhosphorIcons.bookOpenText(),
                      title: 'Todavía no hay nada',
                      body:
                          'Lo que publique tu nutricionista va a aparecer '
                          'acá.',
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(
                    top: NmSpace.s4,
                    bottom: NmSpace.s12,
                  ),
                  children: <Widget>[
                    for (final a in articles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NmSpace.s3),
                        child: _ArticleCard(
                          article: a,
                          isNew: seen?.isNew(a) ?? false,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.isNew});

  final CareArticle article;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final excerpt = articleExcerpt(article.body);
    return NmCard(
      onTap: () =>
          GoRouter.maybeOf(context)?.push(Routes.careArticle(article.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Tags(article: article, isNew: isNew),
          const SizedBox(height: NmSpace.s2),
          Text(
            article.title,
            style: NmTextStyles.from(NmType.h4, color: nm.text),
          ),
          if (excerpt.isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s1),
            Text(
              excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ],
          const SizedBox(height: NmSpace.s2),
          Text(
            articleByline(article),
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}

/// "Receta · Desayunos · Nuevo".
class _Tags extends StatelessWidget {
  const _Tags({required this.article, this.isNew = false});

  final CareArticle article;
  final bool isNew;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: NmSpace.s2,
    runSpacing: NmSpace.s1,
    children: <Widget>[
      NmTag(label: article.kind.label),
      if (article.tag != null)
        NmTag(label: article.tag!, variant: NmTagVariant.outline),
      if (isNew) const NmTag(label: 'Nuevo', variant: NmTagVariant.accent),
    ],
  );
}

/// "Lic. Valentina Ruiz · Ayer". Sin nombre, solo la fecha.
String articleByline(CareArticle a) {
  final day = friendlyDay(a.publishedAt);
  final name = a.authorName.trim();
  return name.isEmpty ? day : '$name · $day';
}

/// Un artículo entero. Abrirlo lo marca como visto en el teléfono.
class CareArticleScreen extends ConsumerStatefulWidget {
  const CareArticleScreen({required this.articleId, super.key});

  final String articleId;

  @override
  ConsumerState<CareArticleScreen> createState() => _CareArticleScreenState();
}

class _CareArticleScreenState extends ConsumerState<CareArticleScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<CareArticle>>>(careArticlesProvider, (
      _,
      next,
    ) {
      final found = next.valueOrNull?.any((a) => a.id == widget.articleId);
      if (found != true) return;
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(
            ref.read(articleSeenProvider.notifier).markOpened(widget.articleId),
          );
        }
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final async = ref.watch(careArticlesProvider);

    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const NmScreen(
        title: 'Artículo',
        child: Padding(
          padding: EdgeInsets.only(top: NmSpace.s4),
          child: SkeletonList(rows: 4, withAvatar: false),
        ),
      ),
      error: (error, _) => NmScreen(
        title: 'Artículo',
        child: ErrorState(
          message: error is AppError
              ? error.message
              : 'No pudimos traer el artículo.',
          onRetry: () => ref.invalidate(careArticlesProvider),
        ),
      ),
      data: (articles) {
        CareArticle? article;
        for (final a in articles) {
          if (a.id == widget.articleId) article = a;
        }
        if (article == null) {
          return NmScreen(
            title: 'Artículo',
            child: EmptyState(
              icon: PhosphorIcons.bookOpenText(),
              title: 'Este artículo ya no está',
              body: 'Puede que tu nutricionista lo haya sacado.',
            ),
          );
        }
        return NmScreen(
          title: article.kind.label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: NmSpace.s4),
              _Tags(article: article),
              const SizedBox(height: NmSpace.s3),
              Semantics(
                header: true,
                child: Text(
                  article.title,
                  style: NmTextStyles.from(NmType.h2, color: nm.text),
                ),
              ),
              const SizedBox(height: NmSpace.s2),
              Text(
                articleByline(article),
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
              const SizedBox(height: NmSpace.s6),
              ArticleBody(body: article.body),
              if (article.media.isNotEmpty) ...<Widget>[
                const SizedBox(height: NmSpace.s6),
                for (final m in article.media)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NmSpace.s3),
                    child: _MediaTile(media: m),
                  ),
              ],
              const SizedBox(height: NmSpace.s12),
            ],
          ),
        );
      },
    );
  }
}

/// Una imagen o un video del artículo. La imagen va a lo ancho con su
/// proporción; el video, con la miniatura de YouTube y un botón de play que lo
/// abre en la app de YouTube (o en el navegador).
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});

  final ArticleMedia media;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final url = media.previewUrl;
    if (url == null) return const SizedBox.shrink();
    final esVideo = media.kind == ArticleMediaKind.youtube;

    final imagen = Image.network(
      url,
      width: double.infinity,
      fit: esVideo ? BoxFit.cover : BoxFit.fitWidth,
      errorBuilder: (_, _, _) => Container(
        height: 160,
        color: nm.surfaceRaised,
        alignment: Alignment.center,
        child: Icon(PhosphorIcons.imageBroken(), color: nm.textMuted),
      ),
    );

    final cuadro = ClipRRect(
      borderRadius: NmRadius.brLg,
      child: esVideo
          ? AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  imagen,
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xCC000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhosphorIcons.play(PhosphorIconsStyle.fill),
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : imagen,
    );

    final abrir = media.openUri;
    if (abrir == null) return Semantics(image: true, label: 'Imagen', child: cuadro);
    return Semantics(
      button: true,
      label: 'Ver el video en YouTube',
      child: GestureDetector(
        onTap: () => launchUrl(abrir, mode: LaunchMode.externalApplication),
        child: cuadro,
      ),
    );
  }
}
