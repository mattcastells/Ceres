import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/palettes.dart';

/// El tema elegido en Apariencia se guarda en el teléfono, como los avisos de
/// pals: es cómo se ve este dispositivo, no un dato de la cuenta, y así no
/// hace falta tocar la base ni la sincronización.
class ThemePaletteStore {
  static const String _key = 'ceres.appearance.palette';

  Future<AppPalette> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPalette.fromWire(prefs.getString(_key));
  }

  Future<void> save(AppPalette palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, palette.wire);
  }
}
