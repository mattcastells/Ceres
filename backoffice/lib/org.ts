import { diasEntre } from './format.ts';
import { DIAS_SIN_REGISTRO, MARGEN_OBJETIVO } from './team.ts';

/** Una fila de `public.org_patients()` (migración 56): un paciente del
 *  consultorio con la profesional que lo atiende y los números del tablero. */
export type OrgPatientRow = {
  patient_id: string;
  patient_name: string | null;
  birth_date: string | null;
  height_cm: number | string | null;
  tracking_since: string | null;
  professional_id: string;
  professional_name: string | null;
  accepted_at: string | null;
  last_meal_date: string | null;
  days_logged_7: number | null;
  avg_kcal_7: number | null;
  target_kcal: number | null;
  weight_first_30: number | string | null;
  weight_last_30: number | string | null;
};

/** Cómo viene el consultorio, en cuatro números. Todos sobre los pacientes que
 *  tienen el dato: un promedio que cuenta como cero a quien no se pesó no dice
 *  nada del consultorio. */
export type ResumenConsultorio = {
  pacientes: number;
  /** Registraron comidas en los últimos `DIAS_SIN_REGISTRO` días. */
  activos: number;
  /** Días con comidas de 7, en promedio. `null` sin pacientes. */
  adherencia: number | null;
  /** Con promedio semanal dentro de ±10 % de su objetivo, de los que tienen
   *  objetivo y comidas. */
  dentroObjetivo: { si: number; de: number };
  /** Cambio de peso de 30 días, de los que tienen dos pesajes. */
  peso: { bajan: number; estables: number; suben: number; promedio: number | null };
};

/** Debajo de este cambio en 30 días el peso se cuenta como estable: es el
 *  ruido de una balanza de baño entre un día y otro. */
export const PESO_ESTABLE_KG = 0.5;

export function cambioPeso(r: OrgPatientRow): number | null {
  if (r.weight_first_30 === null || r.weight_last_30 === null) return null;
  return Math.round((Number(r.weight_last_30) - Number(r.weight_first_30)) * 10) / 10;
}

export function estaActivo(r: OrgPatientRow, hoy: string): boolean {
  return r.last_meal_date !== null && diasEntre(r.last_meal_date, hoy) < DIAS_SIN_REGISTRO;
}

export function dentroDelObjetivo(r: OrgPatientRow): boolean | null {
  if (!r.avg_kcal_7 || !r.target_kcal) return null;
  return Math.abs(r.avg_kcal_7 / r.target_kcal - 1) <= MARGEN_OBJETIVO;
}

export function resumirConsultorio(rows: OrgPatientRow[], hoy: string): ResumenConsultorio {
  const conObjetivo = rows.map(dentroDelObjetivo).filter((x): x is boolean => x !== null);
  const cambios = rows.map(cambioPeso).filter((x): x is number => x !== null);
  return {
    pacientes: rows.length,
    activos: rows.filter((r) => estaActivo(r, hoy)).length,
    adherencia: rows.length
      ? Math.round((rows.reduce((a, r) => a + (r.days_logged_7 ?? 0), 0) / rows.length) * 10) / 10
      : null,
    dentroObjetivo: { si: conObjetivo.filter(Boolean).length, de: conObjetivo.length },
    peso: {
      bajan: cambios.filter((c) => c <= -PESO_ESTABLE_KG).length,
      estables: cambios.filter((c) => Math.abs(c) < PESO_ESTABLE_KG).length,
      suben: cambios.filter((c) => c >= PESO_ESTABLE_KG).length,
      promedio: cambios.length
        ? Math.round((cambios.reduce((a, c) => a + c, 0) / cambios.length) * 10) / 10
        : null,
    },
  };
}

/** Los mismos números, por profesional, en el orden en que llegan las
 *  profesionales (titular primero). */
export function porProfesional(
  rows: OrgPatientRow[],
  profesionales: { id: string; nombre: string }[],
  hoy: string,
): { id: string; nombre: string; resumen: ResumenConsultorio }[] {
  return profesionales.map((p) => ({
    ...p,
    resumen: resumirConsultorio(
      rows.filter((r) => r.professional_id === p.id),
      hoy,
    ),
  }));
}
