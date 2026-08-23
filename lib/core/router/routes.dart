/// Constantes de ruta tipadas (02-information-architecture.md §2).
///
/// Kebab en la URL, constante en código. El esquema `ceres://` resuelve
/// estas mismas rutas (§6); los App Links verificados quedan para la fase 15.
abstract final class Routes {
  static const String splash = '/splash';
  static const String welcome = '/welcome';
  static const String signIn = '/auth/sign-in';
  static const String signUp = '/auth/sign-up';
  static const String forgotPassword = '/auth/forgot-password';
  static const String checkEmail = '/auth/check-email';

  /// Los datos con los que la app calcula, antes de entrar por primera vez.
  ///
  /// No se llega tocando nada: manda el `redirect` del router mientras
  /// `needsOnboarding` sea `true`, y de ahí solo se sale completándolo o
  /// cerrando sesión.
  static const String onboarding = '/welcome/setup';

  static const String home = '/home';
  static const String progress = '/progress';
  static const String profile = '/profile';

  // `dailyBreakdown` y `historyExport` estaban declaradas y no las registraba
  // el router ni las usaba ninguna pantalla: el desglose diario se muestra
  // como sheet y la exportación vive en Configuración → Privacidad. Se sacaron
  // porque una constante de ruta sugiere que hay una pantalla detrás.

  // Historial vive adentro de Progreso, no en su propia tab: se llega
  // tocando "Historial" ahí, no desde la barra inferior.
  static const String progressHistory = '/progress/history';
  static String progressHistoryDay(String date) => '/progress/history/$date';

  static const String progressWeight = '/progress/weight';
  static const String progressCalories = '/progress/calories';
  static const String progressActivity = '/progress/activity';
  static const String progressMeasurements = '/progress/measurements';
  static const String progressGoals = '/progress/goals';

  static const String profileBody = '/profile/body';

  /// Preferencias, alergias y condiciones: lo que la IA no puede sugerir.
  static const String profileDietary = '/profile/dietary';
  static const String profileGoal = '/profile/goal';
  static const String profileTarget = '/profile/target';

  // `welcomeGoal` se sacó: era la elección de objetivo suelta después del alta,
  // y ahora es el último paso de [onboarding]. Dos caminos a la misma decisión
  // significan uno que en algún momento queda sin arreglar.
  // `profileTemplates` y `profileFavorites` se sacaron por lo mismo que
  // `welcomeGoal`: eran atajos a la segunda y la tercera solapa de "Mis cosas"
  // que **nadie navegaba** —ninguna pantalla los usaba— y que igual había que
  // mantener andando. Se llega por `profileFoods` y se toca la solapa.
  static const String profileFoods = '/profile/foods';

  /// A quién le diste acceso a tu seguimiento, y qué ve.
  static const String profileCare = '/profile/care';

  static const String settings = '/settings';
  static const String exerciseCredit = '/settings/exercise-credit';
  static const String units = '/settings/units';
  static const String appearance = '/settings/appearance';
  static const String notifications = '/settings/notifications';
  static const String integrations = '/settings/integrations';
  static const String privacy = '/settings/privacy';
  static const String deleteAccount = '/settings/privacy/delete-account';
  static const String pals = '/pals';
  static String palDay(String userId) => '/pals/$userId';
  static const String palSharing = '/pals/sharing';

  /// El informe del período en PDF, para tener afuera de la app.
  static const String report = '/settings/report';

  static const String cloudBackup = '/settings/cloud-backup';
  static const String water = '/settings/water';
  static const String updates = '/settings/updates';
  static const String about = '/settings/about';

  static const String mealNew = '/meal/new';

  /// Estimar una comida a partir de una descripción escrita.
  static const String mealDescribe = '/meal/describe';

  /// Tres platos que entran en las calorías que quedan del día.
  static const String mealSuggestions = '/meal/suggestions';
  static String meal(String id) => '/meal/$id';
  static String mealEdit(String id) => '/meal/$id/edit';
  static const String photoCapture = '/meal/photo/capture';

  /// Entre sacar la foto y analizarla: aclarar qué es, si hace falta. La foto
  /// no muestra el relleno de una empanada y quien la sacó sí lo sabe.
  static const String photoDescribe = '/meal/photo/describe';
  static const String photoAnalyzing = '/meal/photo/analyzing';
  static const String photoReview = '/meal/photo/review';

  static const String foodSearch = '/food/search';
  static String food(String id) => '/food/$id';
  static const String foodNew = '/food/new';
  static const String foodScan = '/food/scan';

  static const String activityNew = '/activity/new';
  static const String activitySearch = '/activity/search';
  static String activity(String id) => '/activity/$id';
  static String activityEdit(String id) => '/activity/$id/edit';
}
