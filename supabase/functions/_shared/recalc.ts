// Recalcular una comida que ya está cargada.
//
// La diferencia con estimar de cero es el punto de partida: no hay una foto en
// blanco sino una lista que una persona ya vio, corrigió y guardó. Volver a
// analizar desde la nada tiraría ese trabajo — es lo que obligaba a sacar la
// foto de nuevo y rehacer todo para cambiar un peso.
//
// Lo comparten las dos funciones que estiman: con foto va contra la imagen que
// ya tiene la comida (o una nueva), sin foto va solo contra la lista y la
// corrección. El contrato de salida es el mismo de siempre, así que la app lee
// la respuesta con el mismo código.

/** Un ítem tal como está hoy en la comida. Sin confianza: puede venir del
 * catálogo, donde no hay estimación que puntuar. */
export interface CurrentItem {
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/** Mismo techo que la respuesta del modelo. */
const MAX_CURRENT_ITEMS = 12;

/**
 * Sanea los ítems que manda la app antes de meterlos en el prompt.
 *
 * Los rangos son los mismos que aplica `validate` a la salida: lo que no
 * podría salir del modelo tampoco tiene por qué entrar, y un número absurdo en
 * el prompt arrastra la estimación entera.
 */
export function parseCurrentItems(raw: unknown): CurrentItem[] {
  if (!Array.isArray(raw)) return [];

  const clean: CurrentItem[] = [];
  for (const entry of raw.slice(0, MAX_CURRENT_ITEMS)) {
    if (!entry || typeof entry !== 'object') continue;
    const i = entry as Record<string, unknown>;

    const name = typeof i.name === 'string' ? i.name.trim() : '';
    if (!name || name.length > 120) continue;

    const quantity = Number(i.quantity);
    const kcal = Number(i.kcal);
    const proteinG = Number(i.proteinG);
    const carbsG = Number(i.carbsG);
    const fatG = Number(i.fatG);
    const unit = typeof i.unit === 'string' ? i.unit.slice(0, 20) : '';

    const inRange = (v: number, min: number, max: number) =>
      Number.isFinite(v) && v >= min && v <= max;

    if (!inRange(quantity, 0.1, 5000)) continue;
    if (!inRange(kcal, 0, 3000)) continue;
    if (!inRange(proteinG, 0, 500)) continue;
    if (!inRange(carbsG, 0, 500)) continue;
    if (!inRange(fatG, 0, 500)) continue;
    if (!unit) continue;

    clean.push({
      name,
      quantity,
      unit,
      kcal: Math.round(kcal),
      proteinG,
      carbsG,
      fatG,
    });
  }
  return clean;
}

const redondear = (v: number) => Math.round(v * 10) / 10;

/**
 * La comida que ya está cargada más lo que la persona quiere corregir.
 *
 * Dos reglas sostienen todo lo demás:
 *
 * - **Se devuelve la comida entera**, no el cambio. Si el modelo contestara
 *   solo lo corregido, la app tendría que adivinar cómo mezclarlo con lo que
 *   había, y ahí es donde se pierden ítems.
 * - **Lo que la corrección no toca vuelve igual.** La lista ya pasó por el ojo
 *   de quien comió: reestimarla entera cada vez cambiaría números que la
 *   persona había dado por buenos, y encima sin avisar.
 */
export const recalculatedFrom = (
  items: CurrentItem[],
  correction: string,
  // `perHundred` es el contrato v4: el modelo da gramos y valores cada 100 g, y
  // los números de lo que no cambió los repone `validate`. Con v3 el modelo
  // sigue devolviendo totales y tiene que copiarlos él.
  { withPhoto, perHundred }: { withPhoto: boolean; perHundred: boolean },
) => `
Esto es un **recálculo**, no un análisis nuevo. La comida ya está cargada así:

${items.map((i) =>
  `- ${i.name} · ${redondear(i.quantity)} ${i.unit} · ${i.kcal} kcal · ` +
  `P ${redondear(i.proteinG)} g / C ${redondear(i.carbsG)} g / ` +
  `G ${redondear(i.fatG)} g`
).join('\n')}

${
  correction
    ? `La persona corrige: "${correction}"`
    : withPhoto
    ? 'La persona no aclaró nada: revisá la estimación contra la foto.'
    : 'La persona no aclaró nada.'
}

Devolvé la comida **completa** ya corregida:

${
  perHundred
    ? `- Lo que la corrección no menciona vuelve tal cual: mismo nombre, misma
  cantidad y misma unidad. No la reestimes; sus números los conservamos
  nosotros.
- Si la corrección da un peso, una cantidad o una preparación, aplicala a
  **ese** ítem: el peso va en \`grams\`, y la preparación cambia sus valores
  cada 100 g. Subí su \`confidence\`, porque es información que vos no podías
  medir.
- Interpretá la corrección aunque no traiga números: "era una capa finita" o
  "le puse poquito" bajan los gramos de ese ítem a una porción chica real (una
  capa fina untada son ~10 g); "la empanada era de verdura" cambia sus valores
  cada 100 g; "el café tenía azúcar" agrega el azúcar (una cucharadita, 5 g,
  si no dice cuánto).
- "Comí la mitad" es la mitad de todo. Pero si la corrección es una impresión
  sobre el total ("me parece mucho", "no era tanto"), revisá los ítems que la
  explican —los que más kcal aportan o los de porción más dudosa— y bajá
  esos, en vez de recortar todo parejo.`
    : `- Lo que la corrección no menciona vuelve tal cual: mismo nombre, misma
  cantidad y los mismos números. No la reestimes.
- Si la corrección da un peso, una cantidad o una preparación, aplicala y
  recalculá los macros de **ese** ítem con ese dato; subí su \`confidence\`,
  porque es información que vos no podías medir.`
}
- Si nombra algo que falta, agregalo. Si dice que algo no estaba, no lo
  devuelvas.
- \`title\` describe la comida corregida **entera**, con la misma regla de
  siempre: el plato, no el primer ingrediente.
- No agregues nada que no esté en la lista${withPhoto ? ', en la foto' : ''} ni en la corrección.${
  withPhoto
    ? `
- La foto sirve para calibrar porciones y para lo que la corrección no
  menciona. La lista de arriba ya la revisó una persona: no la reemplaces por
  una lectura nueva de la imagen.`
    : ''
}
`;
