import { diasEntre, rangoDeFechas } from './format.ts';

/**
 * El período que **de verdad** se podía registrar.
 *
 * Los períodos del panel salen del calendario —"los últimos 30 días"— y los
 * denominadores salían de ahí también. Alguien que empezó el 18 de agosto
 * aparecía, el 19, con:
 *
 *     Días con comidas: 1 de 30 · 29 sin registrar
 *
 * Ninguno de esos 29 días es un incumplimiento: son días en que la app no
 * existía para esa persona. El calendario de adherencia mostraba media pantalla
 * en gris, "entre semana" salía del 4 % y el "hueco más largo" contaba
 * veintinueve días que nunca fueron un hueco.
 *
 * **La regla vale para toda métrica temporal**: ningún cálculo cuenta como "sin
 * registro" un día anterior al primero del que hay algo cargado.
 *
 * Esto vive acá y se calcula **una vez por pantalla** porque el error es
 * invisible cuando está bien: un número que respeta la ventana y otro que no se
 * ven exactamente igual hasta que alguien empieza a mitad de mes, y para
 * entonces ya hay quince lugares donde revisar.
 *
 * La misma fórmula está en `lib/domain/calculations/tracking_window.dart` y en
 * `public.tracking_since(uuid)`. Son tres y tienen que decir lo mismo: si el
 * PDF que genera el teléfono y esta pantalla contaran distinto, estarían
 * discutiendo sobre dos números que se llaman igual.
 * Ver `docs/contexto-diario.md`.
 */
export type Ventana = {
  /** Lo que pidió la pantalla. */
  desde: string;
  hasta: string;
  /** El primer día que cuenta: el del período, o el primero de la persona. */
  desdeEfectivo: string;
  /** El primer día del que hay algo cargado. `null` en una cuenta sin nada. */
  trackingSince: string | null;
  /** Los días del período efectivo, del más viejo al más nuevo. */
  fechas: string[];
  /** Cuántos días se podían registrar. Cero si no hay nada que contar. */
  dias: number;
  /** Los días que tiene el período **pedido**: con esto se lo rotula. */
  diasPedidos: number;
  /** La persona empezó después de que arrancara el período. */
  empezoDespues: boolean;
  /** No hay un solo día que contar. */
  vacia: boolean;
};

export function ventanaEfectiva(
  desde: string,
  hasta: string,
  trackingSince: string | null | undefined,
): Ventana {
  const inicio = trackingSince ? trackingSince.slice(0, 10) : null;
  const desdeEfectivo = inicio && inicio > desde ? inicio : desde;

  // Sin `trackingSince` no hay ningún momento en que la información válida haya
  // empezado, así que no hay período efectivo. Y si arrancó después del final
  // de la ventana —"la semana pasada" de alguien que empezó ayer— tampoco: cero
  // días, nunca negativo.
  const hayVentana = inicio !== null && desdeEfectivo <= hasta;

  const fechas = hayVentana ? rangoDeFechas(desdeEfectivo, hasta) : [];

  return {
    desde,
    hasta,
    desdeEfectivo,
    trackingSince: inicio,
    fechas,
    dias: fechas.length,
    diasPedidos: diasEntre(desde, hasta) + 1,
    empezoDespues: hayVentana && desdeEfectivo > desde,
    vacia: fechas.length === 0,
  };
}
