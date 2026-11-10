// El plan decide qué se ofrece: la IA, los anuncios, la compra simulada.
//
// Lo que más importa probar es para qué lado se equivoca. Un valor que la app
// no entiende —un plan nuevo del servidor, una respuesta rota— tiene que caer
// en Premium y nunca en Gratis: equivocarse para el lado de Gratis le sacaría
// la IA y le pondría anuncios a alguien que pagó.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/remote/plan_client.dart';
import 'package:ceres/domain/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppPlan.fromWire', () {
    test('lee los cuatro planes del servidor', () {
      expect(AppPlan.fromWire('free'), AppPlan.free);
      expect(AppPlan.fromWire('premium'), AppPlan.premium);
      expect(AppPlan.fromWire('pro'), AppPlan.pro);
      expect(AppPlan.fromWire('patient'), AppPlan.patient);
    });

    test('tolera mayúsculas y espacios', () {
      expect(AppPlan.fromWire(' FREE '), AppPlan.free);
    });

    test('lo que no entiende cae en Premium, nunca en Gratis', () {
      expect(AppPlan.fromWire('enterprise'), AppPlan.premium);
      expect(AppPlan.fromWire(null), AppPlan.premium);
      expect(AppPlan.fromWire(42), AppPlan.premium);
      expect(AppPlan.fromWire(''), AppPlan.premium);
      expect(AppPlan.fallback, AppPlan.premium);
    });
  });

  group('qué incluye cada plan', () {
    test('solo Gratis se queda sin IA', () {
      expect(AppPlan.free.includesAi, isFalse);
      expect(AppPlan.premium.includesAi, isTrue);
      expect(AppPlan.pro.includesAi, isTrue);
      // La IA se la paga la nutricionista Pro.
      expect(AppPlan.patient.includesAi, isTrue);
    });

    test('solo Gratis ve anuncios', () {
      expect(AppPlan.free.showsAds, isTrue);
      for (final plan in <AppPlan>[
        AppPlan.premium,
        AppPlan.pro,
        AppPlan.patient,
      ]) {
        expect(plan.showsAds, isFalse, reason: plan.wire);
      }
    });

    test('los nombres que muestra Perfil', () {
      expect(AppPlan.free.label, 'Gratis');
      expect(AppPlan.premium.label, 'Premium');
      expect(AppPlan.patient.label, 'IA incluida por tu nutricionista');
      expect(AppPlan.pro.label, 'Pro');
    });
  });

  group('cuentas de demostración', () {
    test('se reconocen por el dominio, como en el servidor', () {
      expect(isDemoAccountEmail('ana@demo.ceres.app'), isTrue);
      expect(isDemoAccountEmail('Ana@DEMO.Ceres.App'), isTrue);
      expect(isDemoAccountEmail('ana@gmail.com'), isFalse);
      expect(isDemoAccountEmail('demo.ceres.app@gmail.com'), isFalse);
      expect(isDemoAccountEmail(null), isFalse);
    });
  });

  group('PlanClient.translate', () {
    test('ERR_FORBIDDEN explica que una cuenta real no cambia de plan', () {
      final error = PlanClient.translate(
        'ERR_FORBIDDEN',
        hint: 'Solo las cuentas de demostración cambian de plan así.',
      );
      expect(error.code, ApiErrorCode.forbidden);
      expect(error.message, contains('cuentas reales'));
    });

    test('otro fallo usa el texto del servidor', () {
      final error = PlanClient.translate(
        'ERR_VALIDATION',
        hint: 'Plan desconocido.',
      );
      expect(error.code, ApiErrorCode.validation);
      expect(error.message, 'Plan desconocido.');
    });
  });

  test('ERR_PLAN_REQUIRED y ERR_NO_DATA tienen su propio código', () {
    // Sin esto caían en `upstreamFailed` por el `orElse` de las traducciones,
    // y la app mostraba un error rojo en vez de ofrecer los planes.
    expect(
      ApiErrorCode.values.firstWhere((c) => c.wire == 'ERR_PLAN_REQUIRED'),
      ApiErrorCode.planRequired,
    );
    expect(
      ApiErrorCode.values.firstWhere((c) => c.wire == 'ERR_NO_DATA'),
      ApiErrorCode.noData,
    );
    expect(ApiErrorCode.planRequired.isRetryable, isFalse);
  });
}
