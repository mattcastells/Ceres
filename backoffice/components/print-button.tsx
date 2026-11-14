'use client';

/**
 * La hoja de la consulta (`docs/panel-proximas-features.md` §8): imprime la
 * ficha con todas las pestañas desplegadas, sin los controles, en claro. No es
 * otra ruta ni otro armado: son los mismos paneles que se ven, así que el
 * papel y la pantalla no pueden decir números distintos. El cómo está en el
 * `@media print` de `globals.css`.
 */
export function PrintButton() {
  return (
    <button type="button" className="button--quiet" onClick={() => window.print()}>
      Imprimir
    </button>
  );
}
