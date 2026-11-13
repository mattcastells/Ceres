import { miles } from './format.ts';
import type { CareFeedback } from './queries.ts';

/**
 * El objetivo recomendado (migración 53): calorías y macros que la profesional
 * propone y el paciente aplica desde la app.
 *
 * No se escribe en `goals` —el objetivo es del paciente y la profesional no
 * tiene permiso de escritura sobre sus datos—: es una indicación de
 * `care_feedback` con cuatro números. Lo que vive acá es lo que no depende de
 * la pantalla: validar, armar el texto y leerlo de vuelta.
 */

export type Objetivo = {
  kcal: number;
  proteinas: number | null;
  carbohidratos: number | null;
  grasas: number | null;
};

/** Los topes de la base (`care_feedback_target_range`), que son los de
 *  `goals`: no se recomienda un objetivo que la app no podría guardar. */
export const RANGOS = {
  kcal: [800, 6000],
  proteinas: [0, 500],
  carbohidratos: [0, 1000],
  grasas: [0, 400],
} as const;

/** La primera línea del texto. La escribe el panel, así que se puede leer de
 *  vuelta para separar la nota de los números al editar. */
export const PREFIJO = 'Objetivo recomendado:';

/** "Objetivo recomendado: 1.600 kcal por día · proteínas 95 g · …".
 *
 *  Va en `body` además de en las columnas: una versión de la app que no
 *  conoce las columnas lo muestra igual como una indicación más, con los
 *  números escritos. */
export function resumenObjetivo(o: Objetivo): string {
  const partes = [`${miles(o.kcal)} kcal por día`];
  if (o.proteinas !== null) partes.push(`proteínas ${miles(o.proteinas)} g`);
  if (o.carbohidratos !== null) partes.push(`carbohidratos ${miles(o.carbohidratos)} g`);
  if (o.grasas !== null) partes.push(`grasas ${miles(o.grasas)} g`);
  return `${PREFIJO} ${partes.join(' · ')}.`;
}

/** El `body` que se guarda: el resumen y, si hay, la nota debajo. */
export function cuerpoObjetivo(o: Objetivo, nota: string): string {
  const n = nota.trim();
  return n ? `${resumenObjetivo(o)}\n\n${n}` : resumenObjetivo(o);
}

/** La nota de un `body` armado por `cuerpoObjetivo`. Si el texto no empieza
 *  con el resumen —lo escribió otra cosa—, se devuelve entero. */
export function notaDe(body: string): string {
  if (!body.startsWith(PREFIJO)) return body.trim();
  const corte = body.indexOf('\n');
  return corte === -1 ? '' : body.slice(corte).trim();
}

/** Las kcal que suman los macros (4/4/9), o `null` si falta alguno. Se
 *  muestra al lado del formulario, sin juzgar: es para que un error de tipeo
 *  se note antes de publicar. */
export function kcalDeMacros(o: Objetivo): number | null {
  if (o.proteinas === null || o.carbohidratos === null || o.grasas === null) return null;
  return o.proteinas * 4 + o.carbohidratos * 4 + o.grasas * 9;
}

export type Campos = { kcal: string; proteinas: string; carbohidratos: string; grasas: string };

/** Lo que se tipeó, validado. Los macros son opcionales; las calorías no. */
export function validarObjetivo(c: Campos):
  | { ok: true; objetivo: Objetivo }
  | { ok: false; error: string } {
  const leer = (v: string): number | null | 'mal' => {
    const t = v.trim().replace(/\./g, '').replace(',', '.');
    if (!t) return null;
    const n = Number(t);
    return Number.isFinite(n) && Number.isInteger(n) ? n : 'mal';
  };
  const nombres = {
    kcal: 'Las calorías',
    proteinas: 'Las proteínas',
    carbohidratos: 'Los carbohidratos',
    grasas: 'Las grasas',
  } as const;

  const out: Partial<Record<keyof Campos, number | null>> = {};
  for (const k of Object.keys(nombres) as (keyof Campos)[]) {
    const v = leer(c[k]);
    if (v === 'mal') return { ok: false, error: `${nombres[k]} van en números enteros.` };
    if (v !== null) {
      const [min, max] = RANGOS[k];
      if (v < min || v > max) {
        return { ok: false, error: `${nombres[k]} van de ${miles(min)} a ${miles(max)}.` };
      }
    }
    out[k] = v;
  }
  if (out.kcal == null) return { ok: false, error: 'Faltan las calorías.' };
  return {
    ok: true,
    objetivo: {
      kcal: out.kcal,
      proteinas: out.proteinas ?? null,
      carbohidratos: out.carbohidratos ?? null,
      grasas: out.grasas ?? null,
    },
  };
}

/** El objetivo de una fila de `care_feedback`, o `null` si no es uno. */
export function objetivoDe(f: CareFeedback): Objetivo | null {
  if (f.kind !== 'indication' || f.target_kcal == null) return null;
  return {
    kcal: f.target_kcal,
    proteinas: f.target_protein_g ?? null,
    carbohidratos: f.target_carbs_g ?? null,
    grasas: f.target_fat_g ?? null,
  };
}

export function esObjetivo(f: CareFeedback): boolean {
  return objetivoDe(f) !== null;
}

export function camposDe(o: Objetivo | null): Campos {
  const s = (n: number | null | undefined) => (n == null ? '' : String(n));
  return {
    kcal: s(o?.kcal),
    proteinas: s(o?.proteinas),
    carbohidratos: s(o?.carbohidratos),
    grasas: s(o?.grasas),
  };
}
