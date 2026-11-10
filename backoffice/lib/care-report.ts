import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * El contrato con la Edge Function `care-report`, del lado del panel.
 *
 * La función redacta con IA **sobre números que calcula ella misma**
 * (`supabase/functions/care-report/metrics.ts`) y guarda las dos cosas juntas:
 * el texto del modelo y, en `content.metricas`, los números. La pantalla los
 * muestra separados y rotulados —"calculado sobre los registros" contra
 * "redactado con IA, revisalo"— porque un promedio que dice el modelo puede
 * estar mal y nadie se entera, y uno que sale de `metrics.ts` tiene test.
 */

export type Alerta = { nivel: 'info' | 'atencion'; texto: string };

/** Los números del informe de consulta. Es el retorno de `personMetrics`, más
 *  lo que agrega `index.ts`. Todo opcional de este lado: un informe viejo,
 *  guardado con una versión anterior del prompt, puede no traer alguno, y eso
 *  no tiene que romper la pestaña. */
export type MetricasPaciente = {
  periodo?: { desde: string; hasta: string; dias: number };
  diasConRegistro?: number;
  comidasPorDia?: number;
  calorias?: {
    promedio: number | null;
    objetivo: number | null;
    diasDentroDelObjetivo: number | null;
    promedioFinDeSemana: number | null;
    promedioDiasDeSemana: number | null;
    porDia: { fecha: string; kcal: number }[];
  };
  macros?: {
    proteinaPromedioG: number;
    objetivoProteinaG: number | null;
    carbohidratosPromedioG: number;
    grasasPromedioG: number;
  } | null;
  momentos?: Record<string, number>;
  horarios?: { primeraComidaPromedio: string | null; ultimaComidaPromedio: string | null };
  alimentosFrecuentes?: { nombre: string; veces: number; kcal: number }[];
  porcentajeCargadoConIA?: number | null;
  peso?: {
    inicial: number;
    final: number;
    cambio: number;
    pesajes: number;
    fechaInicial: string;
    fechaFinal: string;
  } | null;
  balanceEstimado?: {
    gastoEstimadoDiario: number;
    deficitPromedioDiario: number;
    cambioEsperadoKg: number;
    sobreDias: number;
  } | null;
  actividad?: { sesiones: number; minutos: number; tipos: { tipo: string; veces: number }[] };
  sueno?: { promedioHoras: number; noches: number } | null;
  agua?: { promedioVasos: number; dias: number } | null;
  contexto?: { fecha: string; tipo: string; nota: string | null }[];
  alcohol?: { unidadesEstandar: number } | null;
  nombre?: string | null;
  categoriasCompartidas?: { meals: boolean; photos: boolean; body: boolean; wellbeing: boolean } | null;
};

export type InformeConsulta = {
  resumen: string;
  puntosClave: string[];
  alertas: Alerta[];
  balance: string;
  preguntas: string[];
  metricas?: MetricasPaciente;
};

export type InformeEquipo = {
  resumen: string;
  prioridades: { patientId: string; motivo: string; accion: string }[];
  observaciones: string[];
  metricas?: { hoy?: string; pacientes?: unknown[] };
};

export type CareReportBody =
  | { kind: 'professional'; patientId: string }
  | { kind: 'feedback_draft'; patientId: string; focus?: string; localDate?: string }
  | { kind: 'team' };

export type CareReportResult<T> =
  | { ok: true; data: T }
  | { ok: false; code: string; message: string };

/**
 * Lee el `{ error: { code, message } }` de una respuesta fallida.
 *
 * Es lo único de este archivo que tiene lógica propia, y por eso está aparte y
 * con test: supabase-js devuelve un `FunctionsHttpError` con la `Response` sin
 * leer adentro, y un cuerpo que no es el esperado —un 502 del gateway en HTML,
 * un timeout— no puede terminar en "undefined" en la pantalla.
 */
export function leerError(status: number | null, body: unknown): { code: string; message: string } {
  const e = (body as { error?: { code?: unknown; message?: unknown } } | null)?.error;
  const code = typeof e?.code === 'string' ? e.code : null;
  const message = typeof e?.message === 'string' && e.message.trim() ? e.message.trim() : null;
  if (code && message) return { code, message };

  if (status === 504 || status === 546) {
    return {
      code: code ?? 'ERR_TIMEOUT',
      message: 'El informe tardó demasiado en armarse. Probá de nuevo en un rato.',
    };
  }
  return {
    code: code ?? 'ERR_UNKNOWN',
    message:
      message ??
      `El servicio de informes respondió con un error${status ? ` (${status})` : ''}. Probá de nuevo en un rato.`,
  };
}

/**
 * Llama a `care-report` y devuelve el resultado o el error ya legible.
 *
 * El mensaje de la función está escrito para mostrarse ("Llegaste a los 40
 * informes de hoy", "Los informes con IA son parte del plan Pro") y se muestra
 * tal cual: inventar uno acá sería decir menos.
 */
export async function invokeCareReport<T>(
  db: SupabaseClient,
  body: CareReportBody,
): Promise<CareReportResult<T>> {
  try {
    const { data, error } = await db.functions.invoke('care-report', { body });
    if (!error) return { ok: true, data: data as T };

    if (error.name === 'FunctionsHttpError') {
      const res = (error as { context?: Response }).context;
      let json: unknown = null;
      try {
        json = res ? await res.clone().json() : null;
      } catch {
        // Un cuerpo que no es JSON (HTML de un gateway) cae al mensaje genérico.
      }
      return { ok: false, ...leerError(res?.status ?? null, json) };
    }

    // Fetch o relay: la función no contestó. Pasa cuando no está desplegada o
    // —en desarrollo— cuando el stack local no levanta las Edge Functions.
    return {
      ok: false,
      code: 'ERR_UNREACHABLE',
      message:
        'No pudimos comunicarnos con el servicio de informes. Revisá la conexión y probá de nuevo.',
    };
  } catch {
    return {
      ok: false,
      code: 'ERR_UNREACHABLE',
      message:
        'No pudimos comunicarnos con el servicio de informes. Revisá la conexión y probá de nuevo.',
    };
  }
}

/** Si el plan deja usar los informes del panel. Lo decide la función —esto es
 *  solo para avisarlo antes del clic y no después de 30 segundos—; con plan
 *  desconocido se deja intentar. */
export function planPermiteInformes(plan: string | null): boolean {
  return plan !== 'free' && plan !== 'patient';
}
