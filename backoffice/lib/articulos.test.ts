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
