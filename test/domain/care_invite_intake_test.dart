// Los datos que carga la nutricionista en el panel (migración 60) y que la
// app propone en el onboarding.
//
// Lo importante es lo que **no** tiene que pasar: que un valor desconocido se
// convierta en un default ("Moderado", "Prefiero no decirlo") y se proponga
// como si lo hubiera cargado ella.
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/care_grant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee lo que manda el panel, con las claves de la migración 60', () {
    final invite = CareInvite.fromRow(<String, dynamic>{
      'id': 'i1',
      'professional_name': 'Lic. Valentina Ruiz',
      'org_name': 'Consultorio Ruiz',
      'intake': <String, dynamic>{
        'sex': 'female',
        'birth_date': '1994-06-18',
        'height_cm': 163,
        'weight_kg': 72.4,
        'activity_level': 'light',
        'goal_type': 'lose',
        'calorie_target': 1700,
        'dietary_flags': <String>['gluten_free'],
      },
    })!;

    final i = invite.intake!;
    expect(i.isEmpty, isFalse);
    expect(i.sex, BiologicalSex.female);
    expect(i.birthDate, DateTime(1994, 6, 18));
    expect(i.heightCm, 163);
    expect(i.weightKg, 72.4);
    expect(i.activityLevel, ActivityLevel.light);
    expect(i.goalType, GoalType.lose);
    expect(i.calorieTarget, 1700);
    expect(i.dietaryFlags, <DietaryFlag>[DietaryFlag.glutenFree]);
  });

  test('un valor que la app no conoce se descarta, no se reemplaza', () {
    final i = CareInviteIntake.fromJson(<String, dynamic>{
      'sex': 'otro',
      'activity_level': 'extremo',
      'goal_type': 'recomp',
      'dietary_flags': <String>['keto'],
    });
    expect(i.sex, isNull);
    expect(i.activityLevel, isNull);
    expect(i.goalType, isNull);
    expect(i.dietaryFlags, isEmpty);
    expect(i.isEmpty, isTrue);
  });

  test('una invitación sin datos sigue siendo una invitación común', () {
    final invite = CareInvite.fromRow(<String, dynamic>{
      'id': 'i2',
      'professional_name': 'Lic. Martín Sosa',
      'intake': null,
    })!;
    expect(invite.intake, isNull);
  });
}
