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

// ── Adjuntos (migración 61) ──────────────────────────────────────────────

export const MAX_ADJUNTOS = 5;

export type Adjunto = { type: 'image'; path: string } | { type: 'youtube'; id: string };

/** `care_articles.media`, sin lo que no cierra y con el tope. */
export function leerAdjuntos(raw: unknown): Adjunto[] {
  if (!Array.isArray(raw)) return [];
  const out: Adjunto[] = [];
  for (const x of raw) {
    if (!x || typeof x !== 'object') continue;
    const o = x as Record<string, unknown>;
    if (o.type === 'image' && typeof o.path === 'string' && o.path) out.push({ type: 'image', path: o.path });
    if (o.type === 'youtube' && typeof o.id === 'string' && /^[\w-]{11}$/.test(o.id)) out.push({ type: 'youtube', id: o.id });
  }
  return out.slice(0, MAX_ADJUNTOS);
}

/** El id de un video de YouTube a partir de lo que se pegue: el enlace de
 *  ver, el corto, un short, un embed o el id solo. `null` si no es uno. */
export function youtubeId(entrada: string): string | null {
  const t = entrada.trim();
  if (/^[\w-]{11}$/.test(t)) return t;
  let u: URL;
  try {
    u = new URL(/^https?:\/\//i.test(t) ? t : `https://${t}`);
  } catch {
    return null;
  }
  const host = u.hostname.replace(/^(www|m|music)\./, '');
  let id: string | null = null;
  if (host === 'youtu.be') id = u.pathname.slice(1).split('/')[0];
  else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    if (u.pathname === '/watch') id = u.searchParams.get('v');
    else {
      const m = u.pathname.match(/^\/(?:shorts|embed|live|v)\/([^/?#]+)/);
      id = m ? m[1] : null;
    }
  }
  return id && /^[\w-]{11}$/.test(id) ? id : null;
}

/** La miniatura pública de un video (no hace falta clave). */
export const miniaturaYoutube = (id: string) => `https://img.youtube.com/vi/${id}/hqdefault.jpg`;

// ── El editor visual ─────────────────────────────────────────────────────
// El editor del panel es visual (negrita, títulos y listas con botones), pero
// lo que se guarda sigue siendo el mismo markdown mínimo de arriba: la app lo
// dibuja con sus reglas y no hace falta migrar los artículos que ya existen.

const escapar = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const enLineaHtml = (t: string) =>
  enLinea(t)
    .map((s) => (s.negrita ? `<b>${escapar(s.texto)}</b>` : escapar(s.texto)))
    .join('');

/** Markdown → el HTML con el que arranca el editor. */
export function aHtml(body: string): string {
  return bloques(body)
    .map((b) => {
      if (b.tipo === 'titulo') return `<h4>${enLineaHtml(b.texto)}</h4>`;
      if (b.tipo === 'parrafo') return `<p>${b.texto.split('\n').map(enLineaHtml).join('<br>')}</p>`;
      const tag = b.ordenada ? 'ol' : 'ul';
      return `<${tag}>${b.items.map((i) => `<li>${enLineaHtml(i)}</li>`).join('')}</${tag}>`;
    })
    .join('');
}

/** Lo mínimo de un nodo del DOM que hace falta para leer el editor; con esta
 *  forma se prueba sin navegador. */
export type Nodo = {
  nodeType: number;
  nodeName: string;
  childNodes: ArrayLike<Nodo>;
  textContent: string | null;
};

const TEXTO = 3;
const BLOQUE = /^(P|DIV|H[1-6]|UL|OL|LI|BLOCKQUOTE)$/;

function hijos(n: Nodo): Nodo[] {
  return Array.from(n.childNodes);
}

/** El texto de una línea, con la negrita como `**`. */
function enLineaMd(n: Nodo): string {
  if (n.nodeType === TEXTO) return (n.textContent ?? '').replace(/\u00a0/g, ' ');
  if (n.nodeName === 'BR') return '\n';
  const dentro = hijos(n).map(enLineaMd).join('');
  if (n.nodeName === 'B' || n.nodeName === 'STRONG') {
    const m = dentro.match(/^(\s*)([\s\S]*?)(\s*)$/)!;
    return m[2] ? `${m[1]}**${m[2]}**${m[3]}` : dentro;
  }
  return dentro;
}

const limpiarParrafo = (t: string) =>
  t
    .split('\n')
    .map((l) => l.replace(/[ \t]+/g, ' ').trim())
    .filter(Boolean)
    .join('\n');

/** El contenido del editor → markdown. Cada bloque (párrafo, título, lista)
 *  queda separado por una línea en blanco, que es lo que lee `bloques`. */
export function aMarkdown(raiz: Nodo): string {
  const out: string[] = [];
  let suelto: Nodo[] = [];

  const cerrarSuelto = () => {
    const t = limpiarParrafo(suelto.map(enLineaMd).join(''));
    if (t) out.push(t);
    suelto = [];
  };

  const visitar = (n: Nodo) => {
    const tag = n.nodeName;
    if (n.nodeType === TEXTO || !BLOQUE.test(tag)) {
      suelto.push(n);
      return;
    }
    cerrarSuelto();
    if (/^H[1-6]$/.test(tag)) {
      const t = enLineaMd(n).replace(/\s+/g, ' ').trim();
      if (t) out.push(`# ${t}`);
    } else if (tag === 'UL' || tag === 'OL') {
      const items = hijos(n)
        .filter((h) => h.nodeName === 'LI')
        .map((li) => enLineaMd(li).replace(/\s+/g, ' ').trim())
        .filter(Boolean);
      if (items.length) out.push(items.map((t, i) => (tag === 'OL' ? `${i + 1}. ${t}` : `- ${t}`)).join('\n'));
    } else if (hijos(n).some((h) => h.nodeType !== TEXTO && BLOQUE.test(h.nodeName))) {
      // Un bloque con bloques adentro (lo que arma el navegador al pegar o al
      // apretar Enter): se recorre por dentro.
      hijos(n).forEach(visitar);
      cerrarSuelto();
    } else {
      const t = limpiarParrafo(enLineaMd(n));
      if (t) out.push(t);
    }
  };

  hijos(raiz).forEach(visitar);
  cerrarSuelto();
  return out.join('\n\n');
}
