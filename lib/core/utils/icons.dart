import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/calculations/alcohol.dart';
import '../../domain/enums/enums.dart';

/// Iconografía Phosphor, peso `regular`; `fill` solo para el estado activo del
/// tab bar (06-design-tokens.md §4).
///
/// El nombre del ícono viaja en `activity_types.icon_name`, junto con el MET:
/// el catálogo es dato, no código (D-06).
abstract final class NmIcons {
  static IconData activity(String? iconName) => switch (iconName) {
    'PersonSimpleWalk' => PhosphorIcons.personSimpleWalk(),
    'PersonSimpleRun' => PhosphorIcons.personSimpleRun(),
    'PersonSimpleBike' => PhosphorIcons.personSimpleBike(),
    'PersonSimpleSwim' => PhosphorIcons.personSimpleSwim(),
    'Barbell' => PhosphorIcons.barbell(),
    'Boxing' => PhosphorIcons.boxingGlove(),
    'PersonSimpleTaiChi' => PhosphorIcons.personSimpleTaiChi(),
    'SoccerBall' => PhosphorIcons.soccerBall(),
    'MusicNotes' => PhosphorIcons.musicNotes(),
    'Mountains' => PhosphorIcons.mountains(),
    'Wind' => PhosphorIcons.wind(),
    'Boat' => PhosphorIcons.boat(),
    'Stairs' => PhosphorIcons.stairs(),
    _ => PhosphorIcons.dotsThreeCircle(),
  };

  /// Cada bebida con su forma.
  ///
  /// Sirve para algo más que decorar: en la tarjeta del día se dibuja **un
  /// ícono por consumo**, así que la silueta es lo que deja ver de un vistazo
  /// que el sábado fueron dos copas de vino y una cerveza, y no "tres tragos"
  /// a secas.
  static IconData drink(DrinkType type) => switch (type) {
    DrinkType.beer => PhosphorIcons.beerStein(),
    DrinkType.wine => PhosphorIcons.wine(),
    DrinkType.spirits => PhosphorIcons.brandy(),
    DrinkType.cocktail => PhosphorIcons.martini(),
    DrinkType.cider => PhosphorIcons.champagne(),
    DrinkType.other => PhosphorIcons.beerBottle(),
  };

  static IconData mealSlot(MealSlot slot) => switch (slot) {
    MealSlot.breakfast => PhosphorIcons.coffee(),
    MealSlot.lunch => PhosphorIcons.forkKnife(),
    MealSlot.dinner => PhosphorIcons.bowlFood(),
    MealSlot.snack => PhosphorIcons.cookie(),
  };

  static IconData activityGoal(ActivityGoalType type) => switch (type) {
    ActivityGoalType.activeMinutes => PhosphorIcons.timer(),
    ActivityGoalType.sessions => PhosphorIcons.checkCircle(),
    ActivityGoalType.steps => PhosphorIcons.footprints(),
    ActivityGoalType.distance => PhosphorIcons.path(),
    ActivityGoalType.strengthSessions => PhosphorIcons.barbell(),
    ActivityGoalType.activeDays => PhosphorIcons.calendarBlank(),
  };

  static IconData measurement(MeasurementMetric metric) => switch (metric) {
    MeasurementMetric.bodyFatPct => PhosphorIcons.chartLine(),
    _ => PhosphorIcons.ruler(),
  };
}
