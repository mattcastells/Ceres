// El texto de los artículos: el markdown mínimo que dibujan el panel y la app.
// Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { bloques, enLinea, extracto, validarArticulo } from './articulos.ts';

describe('bloques', () => {
  test('párrafos separados por una línea en blanco', () => {
    assert.deepEqual(bloques('Uno\ndos\n\nTres'), [
      { tipo: 'parrafo', texto: 'Uno\ndos' },
      { tipo: 'parrafo', texto: 'Tres' },
    ]);
  });

  test('listas con guion y numeradas, y un título', () => {
    assert.deepEqual(bloques('# Ingredientes\n- Avena\n- Banana\n\n1. Mezclar\n2. Hornear'), [
      { tipo: 'titulo', texto: 'Ingredientes' },
      { tipo: 'lista', ordenada: false, items: ['Avena', 'Banana'] },
      { tipo: 'lista', ordenada: true, items: ['Mezclar', 'Hornear'] },
    ]);
  });

  test('una lista pegada a un párrafo empieza un bloque nuevo', () => {
    assert.deepEqual(bloques('Necesitás:\n- Huevo'), [
      { tipo: 'parrafo', texto: 'Necesitás:' },
      { tipo: 'lista', ordenada: false, items: ['Huevo'] },
    ]);
  });

  test('una línea sin viñeta sigue al ítem anterior', () => {
    assert.deepEqual(bloques('- Yogur natural\n  sin azúcar'), [
      { tipo: 'lista', ordenada: false, items: ['Yogur natural sin azúcar'] },
    ]);
  });

  test('CRLF de Windows', () => {
    assert.deepEqual(bloques('A\r\n\r\nB'), [
      { tipo: 'parrafo', texto: 'A' },
      { tipo: 'parrafo', texto: 'B' },
    ]);
  });
});

test('enLinea: negrita, y un ** sin cerrar queda como texto', () => {
  assert.deepEqual(enLinea('Sumá **proteína** al desayuno'), [
    { texto: 'Sumá ', negrita: false },
    { texto: 'proteína', negrita: true },
    { texto: ' al desayuno', negrita: false },
  ]);
  assert.deepEqual(enLinea('2 ** 3'), [{ texto: '2 ** 3', negrita: false }]);
});

test('extracto: los párrafos, sin títulos ni marcas, cortado en una palabra', () => {
  assert.equal(extracto('# Título\nUn **texto** corto.'), 'Un texto corto.');
  assert.equal(extracto('- Avena\n- Banana\n\nRinde 8.'), 'Rinde 8.');
  assert.equal(extracto('- Avena\n- Banana'), 'Avena · Banana');
  const largo = extracto('palabra '.repeat(60), 50);
  assert.ok(largo.endsWith('…'));
  assert.ok(largo.length <= 51);
});

test('validarArticulo', () => {
  assert.equal(validarArticulo({ title: ' ', body: 'x', tag: '' }), 'Falta el título.');
  assert.equal(validarArticulo({ title: 'T', body: '  ', tag: '' }), 'Falta el texto.');
  assert.match(validarArticulo({ title: 'T', body: 'x', tag: 'e'.repeat(41) }) ?? '', /etiqueta/);
  assert.equal(validarArticulo({ title: 'T', body: 'x', tag: '' }), null);
});

// ── Adjuntos y editor visual (migración 61) ──────────────────────────────
import { aHtml, aMarkdown, leerAdjuntos, youtubeId, type Nodo } from './articulos.ts';

test('youtubeId reconoce los enlaces que se pegan', () => {
  const id = 'dQw4w9WgXcQ';
  for (const u of [
    id,
    `https://www.youtube.com/watch?v=${id}&t=42s`,
    `youtube.com/watch?v=${id}`,
    `https://youtu.be/${id}?si=abc`,
    `https://m.youtube.com/shorts/${id}`,
    `https://www.youtube.com/embed/${id}`,
  ]) {
    assert.equal(youtubeId(u), id, u);
  }
  assert.equal(youtubeId('https://vimeo.com/123'), null);
  assert.equal(youtubeId('hola'), null);
});

test('leerAdjuntos descarta lo que no cierra y respeta el tope', () => {
  const bueno = { type: 'youtube', id: 'dQw4w9WgXcQ' };
  assert.deepEqual(leerAdjuntos(null), []);
  assert.deepEqual(leerAdjuntos([{ type: 'image' }, { type: 'youtube', id: 'x' }, bueno]), [bueno]);
  assert.equal(leerAdjuntos(Array(8).fill(bueno)).length, 5);
});

// Un DOM mínimo, para probar el editor sin navegador.
const t = (s: string): Nodo => ({ nodeType: 3, nodeName: '#text', childNodes: [], textContent: s });
const el = (name: string, ...kids: Nodo[]): Nodo => ({
  nodeType: 1,
  nodeName: name,
  childNodes: kids,
  textContent: kids.map((k) => k.textContent).join(''),
});

test('aMarkdown: títulos, negrita, listas y párrafos', () => {
  const raiz = el(
    'DIV',
    el('H4', t('Ingredientes')),
    el('UL', el('LI', t('1 taza de '), el('B', t('avena '))), el('LI', t('2 bananas'))),
    el('H4', t('Preparación')),
    el('OL', el('LI', t('Mezclar')), el('LI', t('Hornear'))),
    el('P', t('Sale '), el('STRONG', t('rico')), t('.')),
    el('DIV', el('BR')),
    t('Suelto al final'),
  );
  assert.equal(
    aMarkdown(raiz),
    '# Ingredientes\n\n- 1 taza de **avena**\n- 2 bananas\n\n# Preparación\n\n1. Mezclar\n2. Hornear\n\nSale **rico**.\n\nSuelto al final',
  );
});

test('aHtml y aMarkdown son ida y vuelta para lo que dibuja la app', () => {
  const md = '# Título\n\nUn párrafo con **negrita**.\n\n- uno\n- dos\n\n1. a\n2. b';
  const html = aHtml(md);
  assert.equal(
    html,
    '<h4>Título</h4><p>Un párrafo con <b>negrita</b>.</p><ul><li>uno</li><li>dos</li></ul><ol><li>a</li><li>b</li></ol>',
  );
  assert.equal(aHtml('<script>'), '<p>&lt;script&gt;</p>');
});
