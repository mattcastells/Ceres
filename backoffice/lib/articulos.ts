/**
 * Artículos y recetas (migración 52): validar y leer el texto.
 *
 * El cuerpo es texto plano con un markdown mínimo —párrafos, listas con
 * "- " o "1. ", títulos con "# " y **negrita**— porque es lo que se escribe sin
 * pensar en un formato y lo que la app puede dibujar sin una librería. Lo que
 * no entra en esas reglas se muestra tal cual, como texto.
 *
 * El parser vive acá y con test porque la app va a necesitar las mismas
 * reglas: si el panel muestra una lista y el teléfono un párrafo con guiones,
 * la vista previa miente.
 */

export const MAX_TITULO = 140;
export const MAX_CUERPO = 20000;
export const MAX_ETIQUETA = 40;

export type Bloque =
  | { tipo: 'titulo'; texto: string }
  | { tipo: 'parrafo'; texto: string }
  | { tipo: 'lista'; ordenada: boolean; items: string[] };

const VINETA = /^\s*[-*•]\s+/;
const NUMERO = /^\s*\d+[.)]\s+/;
const TITULO = /^\s*#{1,3}\s+/;

/** El cuerpo, en bloques. Una línea en blanco separa bloques; dentro de un
 *  párrafo, el salto de línea se respeta. */
export function bloques(body: string): Bloque[] {
  const out: Bloque[] = [];
  let parrafo: string[] = [];
  let lista: { ordenada: boolean; items: string[] } | null = null;

  const cerrar = () => {
    if (parrafo.length) out.push({ tipo: 'parrafo', texto: parrafo.join('\n') });
    if (lista) out.push({ tipo: 'lista', ...lista });
    parrafo = [];
    lista = null;
  };

  for (const linea of body.replace(/\r\n?/g, '\n').split('\n')) {
    if (!linea.trim()) {
      cerrar();
      continue;
    }
    if (TITULO.test(linea)) {
      cerrar();
      out.push({ tipo: 'titulo', texto: linea.replace(TITULO, '').trim() });
      continue;
    }
    const vineta = VINETA.test(linea);
    const numero = NUMERO.test(linea);
    if (vineta || numero) {
      if (parrafo.length || (lista && lista.ordenada !== numero)) cerrar();
      lista ??= { ordenada: numero, items: [] };
      lista.items.push(linea.replace(vineta ? VINETA : NUMERO, '').trim());
      continue;
    }
    if (lista) {
      // Una línea sin viñeta pegada a una lista sigue el ítem anterior.
      lista.items[lista.items.length - 1] += ` ${linea.trim()}`;
      continue;
    }
    parrafo.push(linea.trim());
  }
  cerrar();
  return out;
}

/** "Hola **mundo**" → [texto, negrita]. Un `**` sin cerrar queda como texto. */
export function enLinea(texto: string): { texto: string; negrita: boolean }[] {
  const out: { texto: string; negrita: boolean }[] = [];
  const re = /\*\*(.+?)\*\*/g;
  let desde = 0;
  for (const m of texto.matchAll(re)) {
    if (m.index! > desde) out.push({ texto: texto.slice(desde, m.index), negrita: false });
    out.push({ texto: m[1], negrita: true });
    desde = m.index! + m[0].length;
  }
  if (desde < texto.length) out.push({ texto: texto.slice(desde), negrita: false });
  return out;
}

/** Las primeras palabras, sin marcas, para la lista. Sale de los párrafos;
 *  si no hay ninguno —una receta que es solo listas—, de las listas. */
export function extracto(body: string, largo = 180): string {
  const bs = bloques(body);
  const parrafos = bs.filter((b) => b.tipo === 'parrafo');
  const plano = (parrafos.length ? parrafos : bs.filter((b) => b.tipo === 'lista'))
    .map((b) => (b.tipo === 'lista' ? b.items.join(' · ') : b.texto))
    .join(' ')
    .replace(/\*\*/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (plano.length <= largo) return plano;
  const corte = plano.lastIndexOf(' ', largo);
  return `${plano.slice(0, corte > largo * 0.6 ? corte : largo)}…`;
}

/** El primer problema de un artículo, o `null`. Los mismos topes que la base
 *  (`care_articles_*_len`), dichos antes de mandar. */
export function validarArticulo(a: { title: string; body: string; tag: string }): string | null {
  const titulo = a.title.trim();
  if (!titulo) return 'Falta el título.';
  if (titulo.length > MAX_TITULO) return `El título tiene ${titulo.length} caracteres; el máximo es ${MAX_TITULO}.`;
  if (!a.body.trim()) return 'Falta el texto.';
  if (a.body.length > MAX_CUERPO) return `El texto es demasiado largo (máximo ${MAX_CUERPO.toLocaleString('es-AR')} caracteres).`;
  if (a.tag.trim().length > MAX_ETIQUETA) return `La etiqueta tiene más de ${MAX_ETIQUETA} caracteres.`;
  return null;
}
