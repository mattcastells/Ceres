import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/pal_alerts.dart';

/// Los avisos de pals se guardan en el teléfono: son del dispositivo que
/// suena, no de la cuenta. Arrancan prendidos.
class PalAlertStore {
  static const String _mealsKey = 'ceres.pals.alert_meals';
  static const String _activityKey = 'ceres.pals.alert_activity';

  Future<PalAlertPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PalAlertPrefs(
      meals: prefs.getBool(_mealsKey) ?? true,
      activity: prefs.getBool(_activityKey) ?? true,
    );
  }

  Future<void> save(PalAlertPrefs value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mealsKey, value.meals);
    await prefs.setBool(_activityKey, value.activity);
  }
}
