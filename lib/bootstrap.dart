import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/utils/dates.dart';
import 'data/local/android_reminder_scheduler.dart';
import 'data/local/health_connect_gateway.dart';
import 'data/local/home_widget_publisher.dart';
import 'data/local/local_auth_gateway.dart';
import 'data/local/local_store.dart';
import 'data/remote/calorie_target_client.dart';
import 'data/remote/care_client.dart';
import 'data/remote/cloud_backup_client.dart';
import 'data/remote/gemini_analysis_client.dart';
import 'data/remote/meal_suggestions_client.dart';
import 'data/remote/pals_client.dart';
import 'data/remote/photo_storage_client.dart';
import 'data/remote/relational_sync_client.dart';
import 'data/remote/supabase_auth_gateway.dart';
import 'data/remote/usda_food_client.dart';
import 'data/repositories/local_repository.dart';
import 'domain/models/pal.dart';
import 'domain/repositories/auth_gateway.dart';
import 'domain/services/cloud_backup_service.dart';
import 'domain/services/pal_publisher.dart';
import 'domain/services/photo_sync_service.dart';
import 'domain/services/relational_sync_service.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/reminder_providers.dart';

/// Arranque: base local, formatos de fecha, sesión y contenedor de providers.
///
/// Los datos siguen viviendo en el teléfono (`data/local/`). Lo que sí es real
/// es la **sesión**: si la compilación trae credenciales de Supabase, se
/// autentica contra el servidor; si no, cae a una sesión local que no
/// autentica nada y lo dice (19-project-structure.md §5).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  await initializeDateFormatting(appLocale);

  // Con credenciales, `supabase_flutter` restaura la sesión guardada y se
  // encarga de refrescar el token. Sin ellas la app arranca igual, en local.
  final AuthGateway auth;
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    auth = SupabaseAuthGateway.fromInstance();
  } else {
    auth = LocalAuthGateway();
  }

  final store = await LocalStore.open();

  // Con servidor, cada cambio local dispara un respaldo a la nube. Sin
  // servidor no hay a dónde subir y el servicio queda en null: el respaldo
  // sigue siendo el archivo JSON de Configuración → Privacidad.
  // Recordatorios locales: no necesitan servidor ni cuenta.
  final reminderScheduler = await AndroidReminderScheduler.create();

  final CloudBackupService? backup = SupabaseConfig.isConfigured
      ? CloudBackupService(
          client: CloudBackupClient.fromInstance(),
          auth: auth,
          readDocument: () => jsonEncode(store.toDocument()),
          localHasData: () => store.hasUserData,
        )
      : null;

  // Las fotos van al bucket, no al respaldo: una ruta de archivo del teléfono
  // guardada en el JSON apunta a algo que en otro dispositivo no existe.
  final photos = SupabaseConfig.isConfigured
      ? PhotoSyncService(
          client: PhotoStorageClient.fromInstance(),
          auth: auth,
        )
      : null;

  // Persistencia relacional: lo mismo que va al respaldo JSON, además como
  // filas en las tablas. Los dos escriben en paralelo; el documento sigue
  // siendo la fuente de verdad hasta que las filas estén verificadas contra
  // varios días de uso real.
  final RelationalSyncService? relationalSync = SupabaseConfig.isConfigured
      ? RelationalSyncService(
          client: RelationalSyncClient.fromInstance(),
          auth: auth,
          store: store,
        )
      : null;

  // Lo que ven los pals. Se arma acá y no en el repositorio para que quede a
  // la vista qué se publica: momento, nombre y calorías por comida, más
  // minutos y sesiones — siempre— y fotos/agua/sueño/detalle de actividad
  // solo si `prefs` los tiene prendidos. Nada de peso, medidas ni ítems de
  // cada comida, prenda lo que prenda la persona.
  PalPublisher? palPublisher;

  // El repositorio avisa a la UI por el contador de revisión; se enlaza
  // después de crear el contenedor para evitar la dependencia circular. El
  // widget de la pantalla de inicio del teléfono va por el mismo camino, porque
  // necesita al repositorio que todavía no existe.
  void Function() notify = () {};
  void Function() publishToWidget = () {};
  final repository = LocalRepository(
    store,
    photos: photos,
    aiAnalysis: SupabaseConfig.isConfigured
        ? GeminiAnalysisClient.fromInstance()
        : null,
    // Sugerencias de comida para lo que queda del día. Misma Edge Function
    // detrás, misma cuota diaria: la clave del modelo no baja al teléfono.
    suggestions: SupabaseConfig.isConfigured
        ? MealSuggestionsClient.fromInstance()
        : null,
    // La propuesta de objetivo calórico del alta guiada. Misma cuota que las
    // otras tres, y la misma razón para estar del lado del servidor: acá,
    // además, es él quien rehace la cuenta con la que acota al modelo.
    calorieTargets: SupabaseConfig.isConfigured
        ? CalorieTargetClient.fromInstance()
        : null,
    // Alimentos genéricos por Edge Function: la clave de USDA no baja al
    // teléfono. Sin servidor, la búsqueda sigue con Open Food Facts y con la
    // tabla argentina que viaja adentro del APK.
    usdaFoods: SupabaseConfig.isConfigured
        ? UsdaFoodClient.fromInstance()
        : null,
    // Health Connect no necesita servidor ni cuenta: es el almacén de salud
    // del propio teléfono. Solo Android lo tiene.
    health: defaultTargetPlatform == TargetPlatform.android
        ? const HealthConnectGateway()
        : null,
    onChanged: () {
      notify();
      backup?.markDirty();
      relationalSync?.markDirty();
      palPublisher?.markDirty();
      // El widget de la pantalla de inicio del teléfono. Sin debounce, al
      // revés que los tres de arriba: no sale a la red —escribe un dato local—
      // y si no hay ningún widget puesto, el lado nativo corta antes de
      // dibujar nada.
      publishToWidget();
    },
  );

  // Antes de que nada intente subir: una fila vieja que el servidor rechaza
  // deja fuera a **todas** las de su tabla, así que sanear tiene que pasar
  // antes del primer push y no después. Es idempotente y sale enseguida si no
  // hay nada que corregir.
  await repository.repararRegistrosViejos();

  // Sale del mismo cálculo del día que muestra Inicio, así que el widget no
  // puede decir un número distinto del de la app.
  const widgetPublisher = HomeWidgetPublisher();
  publishToWidget = () => unawaited(
    widgetPublisher.publish(
      repository.daily(today()),
      glasses: repository.glassesOn(today()),
      waterGoal: repository.profile.waterGoalGlasses,
      sleepMinutes: repository.sleepOn(today())?.minutes,
      daysWithRecords: repository.daysWithRecords,
    ),
  );

  final PalsClient? palsClient = SupabaseConfig.isConfigured
      ? PalsClient.fromInstance()
      : null;

  // Sin servidor no hay a quién darle acceso: los datos no salieron del
  // teléfono, así que la pantalla lo dice y no ofrece nada.
  final CareClient? careClient = SupabaseConfig.isConfigured
      ? CareClient.fromInstance()
      : null;

  if (palsClient != null) {
    palPublisher = PalPublisher(
      client: palsClient,
      auth: auth,
      buildDay: (date, prefs) {
        final activities = repository.activitiesOn(date);
        final sleep = prefs.sleep ? repository.sleepOn(date) : null;
        return PalDay(
          userId: auth.currentAccount?.id ?? '',
          date: date,
          meals: <PalMeal>[
            for (final meal in repository.mealsOn(date))
              PalMeal(
                slot: meal.slot,
                // El título de la comida, que resume lo que tiene adentro sin
                // publicar la lista de ítems. Antes era `items.first.name` —el
                // primer ingrediente que se hubiera cargado—, así que una
                // milanesa con puré y ensalada le llegaba al pal como "Puré de
                // papa" si el puré había entrado primero.
                name: meal.title,
                kcal: meal.totalKcal,
                photoPath: prefs.photos ? meal.photoPath : null,
              ),
          ],
          activityMinutes: activities.fold(0, (acc, a) => acc + a.durationMinutes),
          activityCount: activities.length,
          activities: prefs.activityDetail
              ? <PalActivity>[
                  for (final a in activities)
                    PalActivity(
                      name: a.displayName,
                      minutes: a.durationMinutes,
                      kcal: a.estimatedCalories,
                    ),
                ]
              : const <PalActivity>[],
          waterGlasses: prefs.water ? repository.glassesOn(date) : null,
          sleepMinutes: sleep?.minutes,
          sleepQuality: sleep?.quality,
        );
      },
    );

    // Una publicación al arrancar, sin esperar a que cambie nada.
    //
    // Es lo que repara una cuenta que quedó con el día viejo del otro lado: un
    // teléfono nuevo, una restauración desde la nube, o una subida que falló
    // hace días y nunca se reintentó. Sube **solo lo que difiere** de lo que ya
    // está publicado, así que en el caso normal —nada cambió— es un pedido de
    // lectura de preferencias y nada más.
    palPublisher.markDirty();
  }

  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(auth),
      if (backup != null) cloudBackupProvider.overrideWithValue(backup),
      if (relationalSync != null)
        relationalSyncProvider.overrideWithValue(relationalSync),
      if (photos != null) photoSyncProvider.overrideWithValue(photos),
      if (palsClient != null) palsClientProvider.overrideWithValue(palsClient),
      if (careClient != null) careClientProvider.overrideWithValue(careClient),
      if (reminderScheduler != null)
        reminderSchedulerProvider.overrideWithValue(reminderScheduler),
    ],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CeresApp(),
    ),
  );
}
