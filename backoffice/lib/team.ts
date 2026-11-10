import { diasEntre } from './format.ts';

/** Una fila de `public.care_overview()` (migración 48). Los campos de una
 *  categoría no compartida vienen en `null`, no en cero. */
export type OverviewRow = {
  patient_id: string;
  patient_name: string | null;
  share_meals: boolean;
  share_body: boolean;
  share_wellbeing: boolean;
  share_photos: boolean;
  tracking_since: string | null;
  last_meal_date: string | null;
  days_logged_7: number | null;
  days_logged_14: number | null;
  avg_kcal_7: number | null;
  target_kcal: number | null;
  weight_first_30: number | string | null;
  weight_last_30: number | string | null;
  unread_feedback: number | null;
};

export type Alerta = {
  id: 'sin-registro' | 'nunca-registro' | 'pocos-dias' | 'sobre-objetivo' | 'bajo-objetivo' | 'no-comparte-comidas';
  texto: string;
  /**
   * `atencion` es lo único que lleva acento (el ámbar de `chip--warn`), y es
   * solo para "dejó de registrar": es lo que cambia a quién se escribe hoy.
   * Comer por encima del objetivo **no** es atención: el panel no pinta el
   * exceso de rojo, y un tablero que marca en ámbar a medio equipo porque comió
   * un 10 % de más es un tablero que dejó de leerse.
   */
  tono: 'atencion' | 'info';
};

/** Desde cuántos días sin comidas se avisa. Dos días sin cargar es un fin de
 *  semana; tres ya es la pregunta "¿pasó algo?". */
export const DIAS_SIN_REGISTRO = 3;

/** Cuánto por encima del objetivo, en promedio de la semana, se menciona. Un
 *  10 % es lo que el informe con IA cuenta como "dentro del objetivo" (±10 %). */
export const MARGEN_OBJETIVO = 0.1;

/** Por debajo de esta fracción del objetivo el promedio dice más del registro
 *  que de la dieta: es la pista de sub-registro de `docs/panel-proximas-features.md`
 *  §6, y quedarse por debajo no es un logro (README, "lo que la pantalla no
 *  califica"). */
export const PISO_OBJETIVO = 0.75;

/** Días desde la última comida hasta hoy. `null` = no hay ninguna en la ventana
 *  que mira `care_overview` (60 días). */
export function diasDesde(fecha: string | null, hoy: string): number | null {
  return fecha ? Math.max(diasEntre(fecha, hoy), 0) : null;
}

/** El cambio de peso de los últimos 30 días, o `null` sin dos pesajes. */
export function cambioPeso30(r: OverviewRow): number | null {
  if (r.weight_first_30 === null || r.weight_last_30 === null) return null;
  return Math.round((Number(r.weight_last_30) - Number(r.weight_first_30)) * 10) / 10;
}

/**
 * Las fichas de aviso de un paciente, calculadas en el navegador sobre la fila
 * del tablero.
 *
 * Son pocas y sin semáforo a propósito (ver `docs/panel-proximas-features.md`,
 * "lo que no propongo"): no hay un "score" ni un rojo, hay una frase corta que
 * dice qué mirar. Respetan la ventana efectiva igual que la ficha
 * (`lib/tracking.ts`): alguien que empezó anteayer no "lleva dos días sin
 * registrar", y "registró 3 de 14" no se dice de quien tiene la app hace cinco.
 */
export function alertasDe(r: OverviewRow, hoy: string): Alerta[] {
  const out: Alerta[] = [];

  if (!r.share_meals) {
    out.push({ id: 'no-comparte-comidas', texto: 'No comparte comidas', tono: 'info' });
    return out;
  }

  // Días que la persona pudo registrar, contando hoy. Sin `tracking_since` no
  // empezó nunca.
  const antiguedad = r.tracking_since ? diasEntre(r.tracking_since.slice(0, 10), hoy) + 1 : 0;

  if (!r.tracking_since) {
    out.push({ id: 'nunca-registro', texto: 'Todavía no registró nada', tono: 'info' });
    return out;
  }

  const sinRegistro = diasDesde(r.last_meal_date, hoy);
  if (sinRegistro === null) {
    if (antiguedad > DIAS_SIN_REGISTRO) {
      out.push({ id: 'sin-registro', texto: 'Sin comidas en los últimos 60 días', tono: 'atencion' });
    }
  } else if (sinRegistro >= DIAS_SIN_REGISTRO) {
    out.push({
      id: 'sin-registro',
      texto: `${sinRegistro} días sin registrar`,
      tono: 'atencion',
    });
  } else if (
    r.days_logged_14 !== null &&
    antiguedad >= 14 &&
    r.days_logged_14 < 7
  ) {
    // Carga, pero salteado: el caso que los siete puntitos de la lista
    // mostraban y un "cargó ayer" esconde.
    out.push({
      id: 'pocos-dias',
      texto: `Registró ${r.days_logged_14} de los últimos 14 días`,
      tono: 'info',
    });
  }

  if (r.avg_kcal_7 !== null && r.target_kcal && r.target_kcal > 0) {
    const razon = r.avg_kcal_7 / r.target_kcal;
    if (razon > 1 + MARGEN_OBJETIVO) {
      out.push({
        id: 'sobre-objetivo',
        texto: `Promedio ${Math.round((razon - 1) * 100)} % sobre el objetivo`,
        tono: 'info',
      });
    } else if (razon < PISO_OBJETIVO) {
      out.push({
        id: 'bajo-objetivo',
        texto: `Promedio ${Math.round((1 - razon) * 100)} % bajo el objetivo: ¿registra todo?`,
        tono: 'info',
      });
    }
  }

  return out;
}

/** Si la ficha va arriba en el tablero: tiene algo que pide un mensaje hoy. */
export function pideAtencion(alertas: Alerta[]): boolean {
  return alertas.some((a) => a.tono === 'atencion');
}

/**
 * El orden del tablero: primero quien pide atención, después el resto, y
 * dentro de cada grupo por nombre.
 *
 * El nombre solo era el orden de la lista; el tablero contesta "¿a quién le
 * escribo hoy?", y la respuesta tiene que estar arriba. Dentro de cada grupo
 * sigue siendo alfabético —y no "el que más días lleva"— para que una ficha no
 * salte de lugar cada mañana.
 */
export function ordenarEquipo<T extends { nombre: string; alertas: Alerta[] }>(
  filas: T[],
): T[] {
  return [...filas].sort((a, b) => {
    const pa = pideAtencion(a.alertas) ? 0 : 1;
    const pb = pideAtencion(b.alertas) ? 0 : 1;
    return pa - pb || a.nombre.localeCompare(b.nombre, 'es');
  });
}
