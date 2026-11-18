'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { aHtml, aMarkdown } from '@/lib/articulos';

type Estado = { negrita: boolean; titulo: boolean; vinetas: boolean; numerada: boolean };

const APAGADO: Estado = { negrita: false, titulo: false, vinetas: false, numerada: false };

/**
 * El cuerpo de un artículo, editado como se ve: botones para título,
 * negrita y listas, sin escribir marcas.
 *
 * Usa `contentEditable` y los comandos del navegador (`execCommand`), que
 * están marcados como viejos pero son lo único que hace esto sin una librería
 * de edición, y alcanzan para cuatro formatos. Lo que se guarda sale de
 * `aMarkdown`: el mismo markdown mínimo que ya lee la app, así que nada cambia
 * del otro lado.
 *
 * No es controlado: arranca con `initial` al montarse y avisa cada cambio. Para
 * editar otro artículo, el padre lo vuelve a montar con otra `key`.
 */
export function RichEditor({
  initial,
  onChange,
  label,
}: {
  initial: string;
  onChange: (markdown: string) => void;
  label: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [estado, setEstado] = useState<Estado>(APAGADO);

  const leerEstado = useCallback(() => {
    const area = ref.current;
    const sel = typeof window !== 'undefined' ? window.getSelection() : null;
    if (!area || !sel || !sel.anchorNode || !area.contains(sel.anchorNode)) return;
    setEstado({
      negrita: document.queryCommandState('bold'),
      titulo: /^h\d$/i.test(String(document.queryCommandValue('formatBlock'))),
      vinetas: document.queryCommandState('insertUnorderedList'),
      numerada: document.queryCommandState('insertOrderedList'),
    });
  }, []);

  const emitir = useCallback(() => {
    if (ref.current) onChange(aMarkdown(ref.current));
    leerEstado();
  }, [onChange, leerEstado]);

  useEffect(() => {
    if (ref.current) ref.current.innerHTML = aHtml(initial);
    document.addEventListener('selectionchange', leerEstado);
    return () => document.removeEventListener('selectionchange', leerEstado);
    // Solo al montar: después manda lo que se escribe.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function comando(c: string, valor?: string) {
    ref.current?.focus();
    document.execCommand('defaultParagraphSeparator', false, 'p');
    document.execCommand(c, false, valor);
    emitir();
  }

  const botones: { id: keyof Estado; label: string; aria: string; hacer: () => void }[] = [
    { id: 'titulo', label: 'Título', aria: 'Título', hacer: () => comando('formatBlock', estado.titulo ? 'P' : 'H4') },
    { id: 'negrita', label: 'B', aria: 'Negrita', hacer: () => comando('bold') },
    { id: 'vinetas', label: '• Lista', aria: 'Lista', hacer: () => comando('insertUnorderedList') },
    { id: 'numerada', label: '1. Lista', aria: 'Lista numerada', hacer: () => comando('insertOrderedList') },
  ];

  return (
    <div className="rte">
      <div className="rte-barra" role="toolbar" aria-label="Formato">
        {botones.map((b) => (
          <button
            key={b.id}
            type="button"
            className={b.id === 'negrita' ? 'rte-b' : undefined}
            aria-label={b.aria}
            aria-pressed={estado[b.id]}
            // `mouseDown` y no `click`: con el clic el editor pierde la
            // selección antes de que el comando la use.
            onMouseDown={(e) => {
              e.preventDefault();
              b.hacer();
            }}
          >
            {b.label}
          </button>
        ))}
      </div>
      <div
        ref={ref}
        className="rte-area art-body"
        contentEditable
        suppressContentEditableWarning
        role="textbox"
        aria-multiline
        aria-label={label}
        onInput={emitir}
        onFocus={() => document.execCommand('defaultParagraphSeparator', false, 'p')}
        // Pegar trae el formato de donde venga (Word, una web): se pega como
        // texto y se le da formato con los botones.
        onPaste={(e) => {
          e.preventDefault();
          document.execCommand('insertText', false, e.clipboardData.getData('text/plain'));
        }}
      />
    </div>
  );
}
