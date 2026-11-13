// El objetivo recomendado: validar lo tipeado, armar el texto y leerlo de
// vuelta. Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  camposDe,
  cuerpoObjetivo,
  kcalDeMacros,
  notaDe,
  objetivoDe,
  resumenObjetivo,
  validarObjetivo,
} from './objetivo.ts';
import type { CareFeedback } from './queries.ts';

const completo = { kcal: 1600, proteinas: 95, carbohidratos: 180, grasas: 55 };

describe('validarObjetivo', () => {
  test('acepta calorías solas', () => {
    assert.deepEqual(validarObjetivo({ kcal: '1800', proteinas: '', carbohidratos: '', grasas: '' }), {
      ok: true,
      objetivo: { kcal: 1800, proteinas: null, carbohidratos: null, grasas: null },
    });
  });

  test('lee el separador de miles', () => {
    const r = validarObjetivo({ kcal: '1.600', proteinas: '95', carbohidratos: '180', grasas: '55' });
    assert.deepEqual(r, { ok: true, objetivo: completo });
  });

  test('sin calorías no hay objetivo', () => {
    const r = validarObjetivo({ kcal: '', proteinas: '100', carbohidratos: '', grasas: '' });
    assert.equal(r.ok, false);
  });

  test('los topes son los de goals', () => {
    assert.equal(validarObjetivo({ kcal: '700', proteinas: '', carbohidratos: '', grasas: '' }).ok, false);
    assert.equal(validarObjetivo({ kcal: '6001', proteinas: '', carbohidratos: '', grasas: '' }).ok, false);
    assert.equal(validarObjetivo({ kcal: '2000', proteinas: '501', carbohidratos: '', grasas: '' }).ok, false);
  });

  test('decimales y letras, no', () => {
    assert.equal(validarObjetivo({ kcal: '1600,5', proteinas: '', carbohidratos: '', grasas: '' }).ok, false);
    assert.equal(validarObjetivo({ kcal: 'mil', proteinas: '', carbohidratos: '', grasas: '' }).ok, false);
  });
});

describe('el texto', () => {
  test('el resumen nombra solo lo que se fijó', () => {
    assert.equal(
      resumenObjetivo({ kcal: 1800, proteinas: 100, carbohidratos: null, grasas: null }),
      'Objetivo recomendado: 1.800 kcal por día · proteínas 100 g.',
    );
  });

  test('la nota va debajo y se recupera igual', () => {
    const body = cuerpoObjetivo(completo, '  Empezamos el lunes.  ');
    assert.equal(
      body,
      'Objetivo recomendado: 1.600 kcal por día · proteínas 95 g · carbohidratos 180 g · grasas 55 g.\n\nEmpezamos el lunes.',
    );
    assert.equal(notaDe(body), 'Empezamos el lunes.');
  });

  test('sin nota, el cuerpo es el resumen', () => {
    assert.equal(notaDe(cuerpoObjetivo(completo, '')), '');
  });

  test('un texto que no armó el panel se devuelve entero', () => {
    assert.equal(notaDe('Hola'), 'Hola');
  });
});

test('kcalDeMacros suma 4/4/9 y necesita los tres', () => {
  assert.equal(kcalDeMacros(completo), 95 * 4 + 180 * 4 + 55 * 9);
  assert.equal(kcalDeMacros({ ...completo, grasas: null }), null);
});

test('objetivoDe: solo una indicación con calorías', () => {
  const base: CareFeedback = {
    id: 'x', patient_id: 'p', kind: 'indication', local_date: null, body: 'b', source: 'manual',
    published_at: null, read_at: null, created_at: '', updated_at: '',
  };
  assert.equal(objetivoDe(base), null);
  assert.deepEqual(objetivoDe({ ...base, target_kcal: 1600, target_protein_g: 95 }), {
    kcal: 1600, proteinas: 95, carbohidratos: null, grasas: null,
  });
  assert.equal(objetivoDe({ ...base, kind: 'feedback', target_kcal: 1600 }), null);
  assert.deepEqual(camposDe(null), { kcal: '', proteinas: '', carbohidratos: '', grasas: '' });
});
