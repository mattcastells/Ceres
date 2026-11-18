import { test } from 'node:test';
import assert from 'node:assert/strict';
import { intakeDe, leerAnamnesis, numero, validar, type DatosAlta } from './alta.ts';

test('leerAnamnesis: solo lo que tiene texto, en orden, sin claves raras', () => {
  assert.deepEqual(leerAnamnesis(null), []);
  assert.deepEqual(leerAnamnesis(['x']), []);
  assert.deepEqual(
    leerAnamnesis({ notas: ' ojo ', motivo: 'Bajar 6 kg', patologias: '  ', otra: 'x' }),
    [
      { titulo: 'Motivo de consulta', texto: 'Bajar 6 kg' },
      { titulo: 'Notas', texto: 'ojo' },
    ],
  );
});

const base: DatosAlta = {
  nombre: 'Ana Torres',
  email: 'ana@mail.com',
  sexo: '',
  nacimiento: '',
  altura: '',
  peso: '',
  actividad: '',
  objetivo: '',
  calorias: '',
};
const hoy = new Date('2026-11-15T12:00:00-03:00');

test('numero acepta coma decimal y distingue vacío de basura', () => {
  assert.equal(numero('70,5'), 70.5);
  assert.equal(numero('  '), null);
  assert.ok(Number.isNaN(numero('setenta')));
});

test('con nombre y mail alcanza: el resto es opcional', () => {
  assert.equal(validar(base, hoy), null);
});

test('valida con los rangos del onboarding de la app', () => {
  assert.match(validar({ ...base, nombre: ' ' }, hoy)!, /nombre/);
  assert.match(validar({ ...base, email: 'ana' }, hoy)!, /mail/);
  assert.match(validar({ ...base, altura: '1,65' }, hoy)!, /centímetros/);
  assert.match(validar({ ...base, peso: '500' }, hoy)!, /kilos/);
  assert.match(validar({ ...base, calorias: '600' }, hoy)!, /calorías/i);
  assert.match(validar({ ...base, nacimiento: '2020-01-01' }, hoy)!, /13 años/);
  assert.equal(
    validar({ ...base, altura: '165', peso: '70,5', calorias: '1800', nacimiento: '1990-04-12' }, hoy),
    null,
  );
});

test('intakeDe manda solo lo completado, con las claves de la app', () => {
  assert.deepEqual(intakeDe(base, []), {});
  assert.deepEqual(
    intakeDe(
      {
        ...base,
        sexo: 'female',
        nacimiento: '1990-04-12',
        altura: '165,4',
        peso: '70,55',
        actividad: 'light',
        objetivo: 'lose',
        calorias: '1800',
      },
      ['gluten_free'],
    ),
    {
      sex: 'female',
      birth_date: '1990-04-12',
      height_cm: 165,
      weight_kg: 70.6,
      activity_level: 'light',
      goal_type: 'lose',
      calorie_target: 1800,
      dietary_flags: ['gluten_free'],
    },
  );
});
