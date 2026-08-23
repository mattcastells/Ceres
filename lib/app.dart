import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/dates.dart';
import 'data/local/home_widget_publisher.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/auth_providers.dart';

/// La app: tema, router y localización.
///
/// Idioma inicial español rioplatense; la estructura de i18n está desde el día
/// uno aunque se entregue un solo idioma (D-19, S-06 del PRD).
class CeresApp extends ConsumerStatefulWidget {
  const CeresApp({super.key});

  @override
  ConsumerState<CeresApp> createState() => _CeresAppState();
}

class _CeresAppState extends ConsumerState<CeresApp>
    with WidgetsBindingObserver {
  static const HomeWidgetPublisher _homeWidget = HomeWidgetPublisher();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Arranque en frío: el widget puede tener el número de ayer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishToWidget();
      // Las fotos huérfanas también se barren al arrancar, no solo al volver:
      // quien deja la app abierta días no pasaría nunca por el otro camino.
      unawaited(_purgePhotos());
    });
  }

  Future<void> _purgePhotos() async {
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    if (!repo.hasSession) return;
    await repo.purgeDeletedPhotos();
  }

  /// Refresca el widget de la pantalla de inicio del teléfono.
  ///
  /// El widget se actualiza solo cuando se registra algo (`onChanged` en
  /// `bootstrap`), y con eso alcanza salvo en un caso: **cambió el día**. Ahí el
  /// dato guardado es de ayer, el widget lo detecta y muestra "Abrí Ceres
  /// para hoy" — pero si no se publicara al volver a la app, seguiría diciendo
  /// eso justo después de que la persona la abrió, que es la peor versión de un
  /// aviso: el que sigue apareciendo cuando ya se hizo lo que pedía.
  void _publishToWidget() => unawaited(_syncWidget());

  Future<void> _syncWidget() async {
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);

    // Primero se aplican los vasos que se tocaron en el widget mientras la app
    // no corría. Va acá y no en `onChanged` de `bootstrap`: aplicarlos dispara
    // un cambio, que vuelve a publicar, y drenar ahí sería una vuelta infinita.
    final pending = await _homeWidget.drainPendingWater();
    for (final entry in pending.entries) {
      await repo.addGlasses(entry.key, entry.value);
    }
    if (!mounted) return;

    await _homeWidget.publish(
      repo.daily(today()),
      glasses: repo.glassesOn(today()),
      waterGoal: repo.profile.waterGoalGlasses,
      sleepMinutes: repo.sleepOn(today())?.minutes,
      daysWithRecords: repo.daysWithRecords,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Respaldar al salir de la app.
  ///
  /// La subida espera 5 segundos para agrupar cambios seguidos, así que
  /// registrar algo y cerrar la app enseguida —que es exactamente lo que uno
  /// hace después de anotar una comida— dejaba ese cambio sin respaldar hasta
  /// el próximo. Android puede matar el proceso en segundo plano sin volver a
  /// darle la palabra, así que este es el último momento seguro.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(cloudBackupProvider)?.flush() ?? Future<void>.value());
    }
    if (state == AppLifecycleState.resumed) {
      // Primero la fecha: si el día cambió mientras la app estaba en segundo
      // plano, todo lo que se dibuje después tiene que hablar de hoy. Sin esto,
      // dejarla abierta de noche y volver a la mañana dejaba Inicio en "Ayer" y
      // el desayuno se cargaba en el día anterior.
      ref.read(selectedDateProvider.notifier).refreshOnResume();
      _publishToWidget();
      unawaited(_pullFromTables());
    }
  }

  /// Reconciliar contra las tablas al volver a la app.
  ///
  /// Hasta acá esto pasaba solo al arrancar en frío, así que un registro
  /// cargado desde otro dispositivo aparecía recién al cerrar y reabrir la app
  /// —y "cerrar" en Android no es volver al inicio, es que el sistema mate el
  /// proceso, que puede tardar horas—. Las tablas son la fuente de verdad de la
  /// cuenta; el documento de este teléfono es la copia con la que trabaja.
  ///
  /// El servicio se encarga de no salir a la red en cada vuelta corta y la
  /// reconciliación no puede dejar menos registros de los que había, así que
  /// esto no puede hacer desaparecer nada.
  Future<void> _pullFromTables() async {
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    if (!repo.hasSession) return;
    await ref
        .read(relationalSyncProvider)
        ?.refresh(apply: repo.importDocument);

    // De paso, las fotos de comidas borradas hace más de un día. Es una
    // recorrida local que solo sale a la red cuando encuentra algo, y lo que
    // encuentra desaparece: casi siempre no hace nada. Va después de traer,
    // porque lo que trae puede incluir una comida borrada en otro dispositivo.
    await _purgePhotos();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Ceres',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: themeMode,
      theme: NmAppTheme.light(),
      darkTheme: NmAppTheme.dark(),
      locale: const Locale('es', 'AR'),
      supportedLocales: const <Locale>[Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Soporte de escalado de texto hasta 200 % sin pérdida de contenido
        // (05-component-library §5).
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
