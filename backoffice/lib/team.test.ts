// Los avisos del tablero del equipo.
//
// Lo que se prueba es sobre todo lo que **no** tiene que pasar: que alguien
// que empezó anteayer no "lleve días sin registrar", que comer por encima del
// objetivo no sea un aviso de atención (el panel no pinta el exceso), y que
// quien no comparte comidas no aparezca con un "0 días". Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  alertasDe,
  cambioPeso30,
  ordenarEquipo,
  type OverviewRow,
} from './team.ts';

const HOY = '2026-11-10';

const fila = (o: Partial<OverviewRow>): OverviewRow => ({
  patient_id: 'p',
  patient_name: 'Ana',
  share_meals: true,
  share_body: true,
  share_wellbeing: true,
  share_photos: true,
  tracking_since: '2026-09-01',
  last_meal_date: HOY,
  days_logged_7: 7,
  days_logged_14: 14,
  avg_kcal_7: 2000,
  target_kcal: 2000,
  weight_first_30: null,
  weight_last_30: null,
  unread_feedback: 0,
  ...o,
});

const ids = (r: OverviewRow) => alertasDe(r, HOY).map((a) => a.id);

describe('los avisos de cada paciente', () => {
  test('quien registra todos los días y come cerca del objetivo no tiene avisos', () => {
    assert.deepEqual(ids(fila({})), []);
  });

  test('tres días sin comidas es atención', () => {
    const a = alertasDe(fila({ last_meal_date: '2026-11-07' }), HOY);
    assert.equal(a[0].id, 'sin-registro');
    assert.equal(a[0].tono, 'atencion');
    assert.equal(a[0].texto, '3 días sin registrar');
  });

  test('dos días sin comidas todavía no', () => {
    assert.deepEqual(ids(fila({ last_meal_date: '2026-11-08' })), []);
  });

  test('alguien que empezó anteayer y no cargó nada no lleva días sin registrar', () => {
    assert.deepEqual(
      ids(fila({ tracking_since: '2026-11-09', last_meal_date: null })),
      [],
    );
  });

  test('sin ningún registro todavía se dice así, sin tono de atención', () => {
    const a = alertasDe(fila({ tracking_since: null, last_meal_date: null }), HOY);
    assert.deepEqual(a.map((x) => [x.id, x.tono]), [['nunca-registro', 'info']]);
  });

  test('comer más de un 10 % sobre el objetivo se menciona, pero no es atención', () => {
    const a = alertasDe(fila({ avg_kcal_7: 2300 }), HOY);
    assert.deepEqual(a.map((x) => [x.id, x.tono]), [['sobre-objetivo', 'info']]);
    assert.equal(a[0].texto, 'Promedio 15 % sobre el objetivo');
  });

  test('un promedio muy por debajo del objetivo se lee como posible sub-registro', () => {
    assert.deepEqual(ids(fila({ avg_kcal_7: 1200 })), ['bajo-objetivo']);
  });

  test('quien no comparte comidas tiene solo ese aviso, no "0 días"', () => {
    assert.deepEqual(
      ids(fila({ share_meals: false, last_meal_date: null, days_logged_14: null })),
      ['no-comparte-comidas'],
    );
  });

  test('carga salteado en las últimas dos semanas', () => {
    assert.deepEqual(
      ids(fila({ last_meal_date: '2026-11-09', days_logged_14: 4 })),
      ['pocos-dias'],
    );
  });
});

describe('el tablero', () => {
  test('el cambio de peso sale de los dos extremos, aunque PostgREST mande texto', () => {
    assert.equal(cambioPeso30(fila({ weight_first_30: '80.40', weight_last_30: '79.10' })), -1.3);
    assert.equal(cambioPeso30(fila({ weight_first_30: null, weight_last_30: 79 })), null);
  });

  test('primero quien pide atención y después por nombre', () => {
    const atencion = alertasDe(fila({ last_meal_date: '2026-11-01' }), HOY);
    const orden = ordenarEquipo([
      { nombre: 'Ana', alertas: [] },
      { nombre: 'Zoe', alertas: atencion },
      { nombre: 'Bruno', alertas: [] },
    ]);
    assert.deepEqual(orden.map((x) => x.nombre), ['Zoe', 'Ana', 'Bruno']);
  });
});
