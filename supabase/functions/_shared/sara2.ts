// La tabla SARA 2, tal como la usa la estimación de comidas (prompt v5).
//
// El reparto es este: el modelo mira la comida, elige la fila de la tabla que
// corresponde y estima los gramos; los valores cada 100 g salen de acá. Es la
// mitad de la cuenta que el modelo hacía de memoria —"¿cuántas kcal tiene el
// arroz hervido?"— reemplazada por la tabla oficial argentina, que es lo que
// usaría una nutricionista.
//
// Al modelo se le pasa solo el código y el nombre de cada fila, no los
// números: no los necesita para elegir, y si los viera los copiaría, que es
// justo lo que no queremos que haga.

import { SARA2, type Sara2Food } from './sara2_data.ts';

export type { Sara2Food };

/** Las filas por código. El código es corto (`S150`) para que copiarlo no falle. */
export const SARA2_BY_ID: ReadonlyMap<string, Sara2Food> = new Map(
  SARA2.map((f) => [f.id, f]),
);

/**
 * Busca una fila por el código que devolvió el modelo.
 *
 * Tolera lo que un modelo puede hacer al copiar —minúsculas, espacios, el
 * nombre pegado detrás ("S150 Arroz blanco")— pero nada más: un código que no
 * existe es `undefined`, y ahí el ítem sigue con los valores del modelo.
 */
export function sara2Row(raw: unknown): Sara2Food | undefined {
  if (typeof raw !== 'string') return undefined;
  const match = /\bS\d{1,4}\b/i.exec(raw.trim());
  return match ? SARA2_BY_ID.get(match[0].toUpperCase()) : undefined;
}

/** Los grupos de la tabla, con mayúscula inicial: el PDF los trae mezclados. */
const grupo = (g: string) => g.charAt(0).toUpperCase() + g.slice(1).toLowerCase();

/**
 * La parte del prompt que presenta la tabla y cómo usarla.
 *
 * Se arma una vez por instancia de la función. Va **después** de las reglas de
 * siempre y vale igual para foto y para texto: lo que cambia entre las dos es
 * cómo se estima la porción, no de dónde salen las kcal.
 */
export const SARA2_PROMPT = (() => {
  const porGrupo = new Map<string, string[]>();
  for (const f of SARA2) {
    const g = grupo(f.group);
    if (!porGrupo.has(g)) porGrupo.set(g, []);
    porGrupo.get(g)!.push(`${f.id} ${f.name}`);
  }
  const catalogo = [...porGrupo]
    .map(([g, filas]) => `## ${g}\n${filas.join('\n')}`)
    .join('\n\n');

  return `
## Tabla SARA 2

Abajo está la tabla oficial de composición de alimentos de Argentina (SARA 2,
Ministerio de Salud), con el código de cada fila. Para cada alimento:

- Si hay una fila que **es** ese alimento en ese estado, poné su código en
  \`saraId\` (por ejemplo "S150"). Los valores cada 100 g los tomamos de la
  tabla. Igual devolvé tus propios valores cada 100 g: los usamos para
  controlar que la fila sea la correcta.
- El estado tiene que coincidir. Si está cocido y la tabla solo tiene la
  versión cruda (una milanesa frita contra "Milanesa ... rebozada", que es
  antes de cocinar), no uses esa fila. Si hay versión hervida u
  "horno/parrilla", usá esa.
- Si no hay una fila que sea ese alimento —un plato que la tabla no tiene,
  como hummus, empanada entera o pizza—, dejá \`saraId\` vacío y estimá los
  valores cada 100 g como siempre. No fuerces una fila parecida: una fila
  equivocada es peor que ninguna.
- Lo armado a la vista se busca por partes: el pan por un lado, lo untado por
  el otro.
- "Tostadas de mesa", "Tostadas integrales" y "Tostadas light" son las
  tostadas envasadas, secas como galletitas. Una rebanada de pan tostada en
  casa es la fila de ese pan.
- Los "PROMEDIO" sirven cuando no se puede distinguir la variedad (qué corte
  de carne, qué queso de pasta dura).

${catalogo}
`;
})();
