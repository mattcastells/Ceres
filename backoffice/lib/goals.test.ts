// El objetivo de cada día. Antes era el último para todo el período, y el día
// de julio se comparaba contra la meta de octubre. Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { currentGoal, goalForDay, targetsByDay } from './goals.ts';
import type { Goal } from './queries.ts';

const g = (starts_on: string, ends_on: string | null, kcal: number): Goal => ({
  base_calorie_target: kcal,
  protein_g: null,
  carbs_g: null,
  fat_g: null,
  goal_type: 'lose',
  starts_on,
  ends_on,
});

const viejo = g('2026-06-01', '2026-10-14', 1800);
const nuevo = g('2026-10-15', null, 2100);

describe('el objetivo vigente', () => {
  test('cada día tiene el suyo', () => {
    assert.equal(goalForDay([viejo, nuevo], '2026-10-14')?.base_calorie_target, 1800);
    assert.equal(goalForDay([viejo, nuevo], '2026-10-15')?.base_calorie_target, 2100);
  });

  test('un día sin objetivo devuelve null, no el más cercano', () => {
    assert.equal(goalForDay([nuevo], '2026-10-01'), null);
    assert.equal(targetsByDay([nuevo], ['2026-10-01']).get('2026-10-01'), null);
  });

  test('el de la cabecera es el del final del período, o el último que hubo', () => {
    assert.equal(currentGoal([viejo, nuevo], '2026-11-10')?.base_calorie_target, 2100);
    assert.equal(currentGoal([viejo], '2026-11-10')?.base_calorie_target, 1800);
    assert.equal(currentGoal([], '2026-11-10'), null);
  });
});
