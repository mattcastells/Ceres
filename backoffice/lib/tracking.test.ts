// Que ninguna métrica del panel cuente como incumplimiento un día anterior al
// primero que el paciente registró.
//
// Este test existe por un número que se veía perfectamente bien estando mal.
// Alguien que instalaba la app el 18 aparecía, el 19, con:
//
//     Días con comidas: 1 de 30 · 29 sin registrar
//
// Los 29 no eran huecos: eran días en los que no tenía la app. El error no
// rompe nada, no tira ninguna excepción, y solo se nota si uno sabe cuándo
// empezó esa persona — que es exactamente la información que la pantalla no
// tenía.
//
// Corre con:  npm test    (node --test, sin dependencias: Node 22+ lee el
// TypeScript directo, y agregar un runner entero para un módulo de cien líneas
// sería más peso del que resuelve).
//
// El mismo contrato está probado del lado de la app en
// `test/domain/tracking_window_test.dart`, y tiene que dar lo mismo: si el PDF
// del teléfono y esta pantalla contaran distinto, estarían discutiendo sobre
// dos números que se llaman igual. Ver `docs/contexto-diario.md`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { ventanaEfectiva } from './tracking.ts';

describe('el período efectivo', () => {
  test('sin recorte, es el período pedido', () => {
    const v = ventanaEfectiva('2026-08-01', '2026-08-30', '2026-03-15');
    assert.equal(v.desdeEfectivo, '2026-08-01');
    assert.equal(v.dias, 30);
    assert.equal(v.diasPedidos, 30);
    assert.equal(v.empezoDespues, false);
  });

  test('cuenta creada a mitad de mes: arranca el día que arrancó ella', () => {
    const v = ventanaEfectiva('2026-08-01', '2026-08-30', '2026-08-18');
    assert.equal(v.desdeEfectivo, '2026-08-18');
    assert.equal(v.dias, 13);
    // El período pedido no cambia: es con lo que se rotula la pantalla.
    assert.equal(v.diasPedidos, 30);
    assert.equal(v.empezoDespues, true);
  });

  test('cuenta creada a mitad de semana: 4 de 4, no 4 de 7', () => {
    // Semana del lunes 17 al domingo 23; empezó el jueves 20.
    const v = ventanaEfectiva('2026-08-17', '2026-08-23', '2026-08-20');
    // 4 de 4, no 4 de 7: no faltó ni un día.
    assert.equal(v.dias, 4);
    assert.deepEqual(v.fechas, [
      '2026-08-20',
      '2026-08-21',
      '2026-08-22',
      '2026-08-23',
    ]);
  });

  test('sin ningún dato no hay días que contar ni división por cero', () => {
    const v = ventanaEfectiva('2026-08-01', '2026-08-30', null);
    assert.equal(v.dias, 0);
    assert.equal(v.vacia, true);
    assert.equal(v.empezoDespues, false);
    assert.deepEqual(v.fechas, []);
    // El rótulo del período **sí** sigue diciendo 30: lo que no hay es
    // denominador. "0 de 30 · 0 %" sobre una cuenta que nunca registró nada es
    // un reproche por días que no se sabe si existieron.
    assert.equal(v.diasPedidos, 30);
  });

  test('empezó después del final del período: cero, nunca negativo', () => {
    // "La semana pasada" de alguien que empezó ayer.
    const v = ventanaEfectiva('2026-08-01', '2026-08-07', '2026-08-18');
    assert.equal(v.dias, 0);
    assert.equal(v.vacia, true);
    assert.ok(!v.fechas.includes('2026-08-03'));
  });

  test('un solo día: el período efectivo es 1, no 0', () => {
    const v = ventanaEfectiva('2026-08-19', '2026-08-19', '2026-08-19');
    assert.equal(v.dias, 1);
    assert.deepEqual(v.fechas, ['2026-08-19']);
  });

  test('el cambio de mes no pierde ni suma un día', () => {
    const v = ventanaEfectiva('2026-07-28', '2026-08-03', '2026-07-30');
    assert.equal(v.desdeEfectivo, '2026-07-30');
    assert.equal(v.dias, 5); // 30, 31, 1, 2, 3
    assert.equal(v.fechas[0], '2026-07-30');
    assert.equal(v.fechas.at(-1), '2026-08-03');
  });

  test('el cambio de año tampoco', () => {
    const v = ventanaEfectiva('2025-12-28', '2026-01-03', '2025-12-31');
    assert.equal(v.dias, 4); // 31, 1, 2, 3
    assert.equal(v.fechas[0], '2025-12-31');
    assert.equal(v.fechas.at(-1), '2026-01-03');
  });

  test('un año bisiesto cuenta el 29 de febrero', () => {
    const v = ventanaEfectiva('2028-02-27', '2028-03-01', '2028-02-27');
    assert.equal(v.dias, 4); // 27, 28, 29, 1
    assert.ok(v.fechas.includes('2028-02-29'));
  });

  test('un timestamp completo se recorta al día', () => {
    // `tracking_since` llega como `date` de PostgREST, pero una vista futura
    // podría mandar un `timestamptz`: el corte por los primeros diez caracteres
    // es lo que evita que "2026-08-18T00:00:00+00:00" no matchee nunca contra
    // un `YYYY-MM-DD`.
    const v = ventanaEfectiva(
      '2026-08-01',
      '2026-08-30',
      '2026-08-18T03:00:00+00:00',
    );
    assert.equal(v.desdeEfectivo, '2026-08-18');
    assert.equal(v.dias, 13);
  });

  test('la ventana no incluye lo anterior al inicio ni lo posterior al fin', () => {
    const v = ventanaEfectiva('2026-08-01', '2026-08-30', '2026-08-18');
    assert.ok(!v.fechas.includes('2026-08-17'));
    assert.equal(v.fechas[0], '2026-08-18');
    assert.equal(v.fechas.at(-1), '2026-08-30');
    assert.ok(!v.fechas.includes('2026-08-31'));
  });

  test('el período de un año se cuenta entero', () => {
    // 2026 no es bisiesto: 365 días.
    const v = ventanaEfectiva('2026-01-01', '2026-12-31', '2026-01-01');
    assert.equal(v.dias, 365);
  });
});
