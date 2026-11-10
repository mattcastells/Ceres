// Qué plan tiene quien llama, y si le alcanza para usar IA.
//
// La regla de negocio es una sola: **todo lo que usa IA es premium**. El plan
// gratis registra todo a mano y ve anuncios; Premium, los pacientes de una
// profesional Pro y la propia Pro usan la IA.
//
// La decide la base (`effective_plan()`, migración 49) y no la app: un botón
// escondido se puede llamar igual. Una cuenta sin plan asignado es Premium,
// así que las cuentas reales no notan nada.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { fail } from './estimation.ts';

export type Plan = 'free' | 'premium' | 'pro' | 'patient';

export async function effectivePlan(db: SupabaseClient): Promise<Plan> {
  const { data, error } = await db.rpc('effective_plan');
  // Si la función no existe todavía (base sin la migración 49) o falla, no se
  // le corta la IA a nadie: el error sería nuestro, no de quien paga.
  if (error || typeof data !== 'string') return 'premium';
  return (['free', 'premium', 'pro', 'patient'] as const).includes(data as Plan)
    ? data as Plan
    : 'premium';
}

/** `null` si puede seguir; si no, la respuesta que corta con un 402. */
export async function requireAiPlan(db: SupabaseClient): Promise<Response | null> {
  const plan = await effectivePlan(db);
  if (plan !== 'free') return null;
  return fail(
    'ERR_PLAN_REQUIRED',
    'Esto usa IA y es parte de Ceres Premium. Podés cargar la comida a mano, ' +
      'o pasarte a Premium para hacerlo con una foto.',
    402,
    { plan },
  );
}
