'use client';

import { useEffect } from 'react';

/**
 * La hoja de la consulta (`docs/panel-proximas-features.md` §8): imprime la
 * ficha con todas las pestañas desplegadas, sin los controles, en claro. No es
 * otra ruta ni otro armado: son los mismos paneles que se ven, así que el
 * papel y la pantalla no pueden decir números distintos. El cómo está en el
 * `@media print` de `globals.css`.
 *
 * Los colapsables (`<details>`) no se abren con CSS: se abren antes de
 * imprimir —también con Ctrl+P, por eso es un listener y no solo el botón— y
 * vuelven como estaban después.
 */
export function PrintButton() {
  useEffect(() => {
    let abiertos: HTMLDetailsElement[] = [];
    const antes = () => {
      abiertos = [...document.querySelectorAll('details:not([open])')] as HTMLDetailsElement[];
      abiertos.forEach((d) => (d.open = true));
    };
    const despues = () => {
      abiertos.forEach((d) => (d.open = false));
      abiertos = [];
    };
    window.addEventListener('beforeprint', antes);
    window.addEventListener('afterprint', despues);
    return () => {
      window.removeEventListener('beforeprint', antes);
      window.removeEventListener('afterprint', despues);
    };
  }, []);

  return (
    <button type="button" className="button--quiet" onClick={() => window.print()}>
      Imprimir
    </button>
  );
}
