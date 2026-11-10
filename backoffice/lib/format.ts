/**
 * Fechas y números, en un solo lado.
 *
 * Lo importante de este archivo es el huso. La app guarda `local_date`: la
 * fecha que era **para quien registró**, calculada en el teléfono. El panel
 * tiene que preguntar por ese mismo día, y no por el que sea en el servidor.
 *
 * Antes el rango salía de `new Date().toISOString().slice(0, 10)`, que es la
 * fecha en UTC: en Buenos Aires, a partir de las 21:00, "hoy" pasaba a ser
 * mañana y el período terminaba en un día que todavía no existe —una fila
 * "sin registros" en el futuro, arriba de todo, y un día de más en "días con
 * comidas de 30"—. Desplegado en un servidor al este de Greenwich el error se
 * da vuelta y es peor: la comida de esta noche queda afuera del período.
 */

/** El huso con el que se cuentan los días.
 *
 *  Está fijo y no sale del reloj del servidor a propósito: en Vercel el
 *  servidor corre en UTC, así que `getDate()` ahí no es el día de nadie. La
 *  app es argentina —el catálogo, los textos, el locale— y el corte del día
 *  del panel tiene que ser el mismo que el del teléfono que cargó la comida.
 *  Si algún día hay pacientes en otro huso, esto sale del perfil. */
const TZ = 'America/Argentina/Buenos_Aires';

/** `YYYY-MM-DD` de una fecha en el huso de arriba.
 *
 *  Se arma con `formatToParts` y no con un locale que ya devuelva ese formato
 *  (`en-CA`) porque un Node compilado con ICU chico se cae a `en-US` y
 *  devolvería `8/3/2026`. Las partes se llaman igual en cualquier locale. */
function isoEnTz(date: Date): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);

  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

export function hoyISO(): string {
  return isoEnTz(new Date());
}

/** La fecha de hace N días, contada desde hoy en el huso. */
export function haceISO(dias: number): string {
  const [y, m, d] = hoyISO().split('-').map(Number);
  // Aritmética sobre la fecha ya resuelta, a mediodía: sumar y restar días a
  // medianoche es lo que se rompe cuando hay cambio de hora.
  const base = new Date(y, m - 1, d, 12);
  base.setDate(base.getDate() - dias);
  return `${base.getFullYear()}-${pad(base.getMonth() + 1)}-${pad(base.getDate())}`;
}

/** Todos los días del período, incluidos los dos extremos. */
export function rangoDeFechas(from: string, to: string): string[] {
  const out: string[] = [];
  const [y, m, d] = from.split('-').map(Number);
  const cursor = new Date(y, m - 1, d, 12);
  const [ty, tm, td] = to.split('-').map(Number);
  const fin = new Date(ty, tm - 1, td, 12);

  while (cursor <= fin) {
    out.push(
      `${cursor.getFullYear()}-${pad(cursor.getMonth() + 1)}-${pad(cursor.getDate())}`,
    );
    cursor.setDate(cursor.getDate() + 1);
  }
  return out;
}

/** Un `YYYY-MM-DD` como `Date` local, sin que el huso lo corra un día. */
export function comoFecha(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/** Cuántos días hay de una fecha a la otra.
 *
 *  Se redondea porque entre las dos puede haber un cambio de hora: de un 23 de
 *  marzo a un 24 de marzo con cambio de horario median 23 horas, y sin
 *  redondear eso da 0,958 días y la barra se dibuja en el día equivocado. */
export function diasEntre(desde: string, hasta: string): number {
  return Math.round(
    (comoFecha(hasta).getTime() - comoFecha(desde).getTime()) / 86400000,
  );
}

/** Lunes = 0 … domingo = 6. La semana argentina empieza el lunes. */
export function diaDeSemana(iso: string): number {
  return (comoFecha(iso).getDay() + 6) % 7;
}

/** "Domingo 3 de agosto".
 *
 *  La mayúscula la pone esta función y no `text-transform: capitalize`, que en
 *  castellano escribe "Domingo 3 De Agosto": el CSS capitaliza cada palabra y
 *  no sabe que "de" no lleva mayúscula. */
export function fechaLarga(iso: string): string {
  const texto = comoFecha(iso).toLocaleDateString('es-AR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

export function fechaCorta(iso: string): string {
  return comoFecha(iso).toLocaleDateString('es-AR', {
    day: 'numeric',
    month: 'short',
  });
}

export function fechaMedia(iso: string): string {
  return comoFecha(iso).toLocaleDateString('es-AR', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
}

export function hora(iso: string): string {
  return new Date(iso).toLocaleTimeString('es-AR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** Minutos desde la medianoche de un instante, **en el huso del paciente**.
 *
 *  `eaten_at` es un `timestamptz`: en Vercel, `getHours()` daría la hora UTC y
 *  el almuerzo de las 13 aparecería a las 16. Se resuelve con el mismo huso
 *  fijo que define el día (`TZ`, arriba) y con `formatToParts`, por lo mismo que
 *  `isoEnTz`. `null` si el texto no es una fecha. */
export function minutosDelDia(iso: string): number | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TZ,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(d);
  const h = Number(parts.find((p) => p.type === 'hour')?.value);
  const m = Number(parts.find((p) => p.type === 'minute')?.value);
  return Number.isFinite(h) && Number.isFinite(m) ? (h % 24) * 60 + m : null;
}

/** El día (`YYYY-MM-DD`) de un instante, en el huso de arriba. */
export function diaDeInstante(iso: string): string {
  return isoEnTz(new Date(iso));
}

/** "10 nov · 14:32" de un `timestamptz`, en el huso de arriba.
 *
 *  Se arma con las mismas piezas deterministas y no con `toLocaleString`: lo
 *  renderizan Client Components que también pasan por el servidor, y con el
 *  huso del servidor (UTC en Vercel) y el del navegador la hora no coincidiría
 *  y React tiraría la hidratación. */
export function fechaHora(iso: string): string {
  const min = minutosDelDia(iso);
  return `${fechaCorta(diaDeInstante(iso))}${min === null ? '' : ` · ${hhmm(min)}`}`;
}

/** "08:30" a partir de minutos desde la medianoche. */
export function hhmm(minutos: number): string {
  const total = Math.round(minutos);
  return `${pad(Math.floor(total / 60) % 24)}:${pad(total % 60)}`;
}

export function horas(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

/** Miles con punto, a mano.
 *
 *  `toLocaleString` acá sería lo mismo salvo por una cosa: esto se renderiza
 *  en el servidor y se hidrata en el navegador, y si los dos no tienen los
 *  mismos datos de locale el texto no coincide y React tira el árbol. */
export function miles(n: number): string {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/** Un decimal solo cuando hace falta, con coma. */
export function num(v: number): string {
  const n = Number(v);
  return Number.isInteger(n) ? String(n) : n.toFixed(1).replace('.', ',');
}

/** Decimales fijos, con coma.
 *
 *  Va por acá y no por `toFixed` pelado porque `toFixed` escribe el punto de
 *  inglés: "76.0 kg" y "−2.1 kg" en una pantalla que en todo el resto —el
 *  catálogo, las fechas, los miles— está en castellano rioplatense. */
export function dec(v: number, digits = 1): string {
  return Number(v).toFixed(digits).replace('.', ',');
}

/** Un número con signo, con el menos tipográfico y no el guion del teclado. */
export function conSigno(v: number, digits = 1): string {
  return v > 0 ? `+${dec(v, digits)}` : dec(v, digits).replace('-', '−');
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}
