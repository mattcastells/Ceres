// Que un error de `care-report` llegue a la pantalla como una frase, y nunca
// como "undefined" ni como el HTML de un gateway. Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { leerError, planPermiteInformes } from './care-report.ts';

describe('los errores de la función de informes', () => {
  test('el mensaje de la función se muestra tal cual', () => {
    assert.deepEqual(
      leerError(429, { error: { code: 'ERR_QUOTA_EXCEEDED', message: 'Llegaste a los 40 informes de hoy.' } }),
      { code: 'ERR_QUOTA_EXCEEDED', message: 'Llegaste a los 40 informes de hoy.' },
    );
  });

  test('un cuerpo que no es el esperado cae a una frase con el código HTTP', () => {
    const e = leerError(502, null);
    assert.equal(e.code, 'ERR_UNKNOWN');
    assert.match(e.message, /\(502\)/);
  });

  test('un timeout del gateway se dice como timeout', () => {
    assert.equal(leerError(504, '<html>').code, 'ERR_TIMEOUT');
  });
});

describe('el plan', () => {
  test('free y patient no tienen informes del panel; Pro, Premium y desconocido sí', () => {
    assert.equal(planPermiteInformes('free'), false);
    assert.equal(planPermiteInformes('patient'), false);
    assert.equal(planPermiteInformes('pro'), true);
    assert.equal(planPermiteInformes('premium'), true);
    assert.equal(planPermiteInformes(null), true);
  });
});
