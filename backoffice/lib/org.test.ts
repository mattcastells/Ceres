// Los números del consultorio (`lib/org.ts`).
//
// Lo que importa es que un dato ausente no cuente como cero: quien no se pesó
// no "mantiene el peso", y quien no tiene objetivo no está "fuera" de él.
// Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { porProfesional, resumirConsultorio, type OrgPatientRow } from './org.ts';

const HOY = '2026-11-14';

const fila = (o: Partial<OrgPatientRow>): OrgPatientRow => ({
  patient_id: 'p',
  patient_name: 'Ana',
  birth_date: null,
  height_cm: null,
  tracking_since: '2026-09-01',
  professional_id: 'v',
  professional_name: 'Valentina',
  accepted_at: null,
  last_meal_date: HOY,
  days_logged_7: 7,
  avg_kcal_7: 2000,
  target_kcal: 2000,
  weight_first_30: 80,
  weight_last_30: 79,
  ...o,
});

describe('resumirConsultorio', () => {
  test('sin pacientes no inventa promedios', () => {
    const r = resumirConsultorio([], HOY);
    assert.equal(r.pacientes, 0);
    assert.equal(r.adherencia, null);
    assert.equal(r.peso.promedio, null);
    assert.deepEqual(r.dentroObjetivo, { si: 0, de: 0 });
  });

  test('activo = comió en los últimos tres días', () => {
    const r = resumirConsultorio(
      [
        fila({ last_meal_date: HOY }),
        fila({ last_meal_date: '2026-11-12' }),
        fila({ last_meal_date: '2026-11-11' }),
        fila({ last_meal_date: null }),
      ],
      HOY,
    );
    assert.equal(r.activos, 2);
  });

  test('sin objetivo o sin comidas no cuenta para "dentro del objetivo"', () => {
    const r = resumirConsultorio(
      [
        fila({ avg_kcal_7: 2100, target_kcal: 2000 }), // +5 %: dentro
        fila({ avg_kcal_7: 2400, target_kcal: 2000 }), // +20 %: fuera
        fila({ target_kcal: null }),
        fila({ avg_kcal_7: null }),
      ],
      HOY,
    );
    assert.deepEqual(r.dentroObjetivo, { si: 1, de: 2 });
  });

  test('el peso: quien no se pesó dos veces no cuenta como estable', () => {
    const r = resumirConsultorio(
      [
        fila({ weight_first_30: 80, weight_last_30: 78 }),
        fila({ weight_first_30: '70.0', weight_last_30: '70.2' }),
        fila({ weight_first_30: 60, weight_last_30: 61 }),
        fila({ weight_first_30: null }),
      ],
      HOY,
    );
    assert.equal(r.peso.bajan, 1);
    assert.equal(r.peso.estables, 1);
    assert.equal(r.peso.suben, 1);
    assert.equal(r.peso.promedio, -0.3);
  });
});

describe('porProfesional', () => {
  test('una profesional sin pacientes aparece con cero, no desaparece', () => {
    const rows = [fila({ professional_id: 'v' }), fila({ professional_id: 'v' })];
    const r = porProfesional(
      rows,
      [
        { id: 'v', nombre: 'Valentina' },
        { id: 'm', nombre: 'Martín' },
      ],
      HOY,
    );
    assert.deepEqual(
      r.map((x) => [x.nombre, x.resumen.pacientes]),
      [
        ['Valentina', 2],
        ['Martín', 0],
      ],
    );
  });
});
