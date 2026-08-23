'use client';

import { useRef, useState, type ReactNode } from 'react';

export type Tab = {
  id: string;
  label: string;
  /** Marca la pestaña de una categoría que el paciente no comparte. */
  off?: boolean;
  content: ReactNode;
};

/**
 * La cabecera fija con las pestañas, y los paneles debajo.
 *
 * **Las pestañas no vuelven al servidor.** Los paneles llegan ya renderizados
 * —son Server Components pasados como `content`— y cambiar de pestaña solo
 * cambia cuál está visible. Si cada una fuera una navegación, moverse entre
 * "Comidas" y "Cuerpo" volvería a pedir las comidas, el peso, las medidas y a
 * firmar de nuevo las URLs de todas las fotos, para mostrar algo que ya
 * estaba en la página.
 *
 * La pestaña activa igual queda en la URL, con `replaceState`: así recargar
 * cae donde uno estaba y un enlace a "el día a día de Ana" es un enlace. Se usa
 * el History API nativo justamente porque no dispara la navegación de Next.
 *
 * Los paneles inactivos se ocultan con `hidden` en vez de desmontarse: un
 * `<details>` que alguien abrió sigue abierto al volver, y el navegador no
 * rearma un día entero cada vez que se cambia de pestaña.
 *
 * La cabecera **no se achica al bajar**. Lo hacía —escondía la línea de
 * contexto y encogía el nombre— y se sacó en agosto de 2026: la línea de
 * contexto es justo lo que uno quiere seguir viendo mientras lee, y los 45 px
 * que se ganaban no valían la maquinaria que hacía falta para que el documento
 * no se comiera el scroll al compactarse.
 */
export function Tabs({
  header,
  tabs,
  initial,
  param = 't',
}: {
  header: ReactNode;
  tabs: Tab[];
  initial: string;
  param?: string;
}) {
  const known = tabs.some((t) => t.id === initial) ? initial : tabs[0].id;
  const [active, setActive] = useState(known);
  const list = useRef<HTMLDivElement>(null);

  function select(id: string) {
    setActive(id);

    const url = new URL(window.location.href);
    if (id === tabs[0].id) url.searchParams.delete(param);
    else url.searchParams.set(param, id);
    window.history.replaceState(null, '', url);

    // Volver arriba: sin esto, entrar a "Cuerpo" desde el final del día a día
    // deja la pantalla en un panel más corto que el scroll, o sea en blanco.
    window.scrollTo({ top: 0 });
  }

  /** Flechas para moverse entre pestañas, que es lo que espera un `tablist`. */
  function onKeyDown(event: React.KeyboardEvent) {
    const delta =
      event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (delta === 0) return;
    event.preventDefault();

    const i = tabs.findIndex((t) => t.id === active);
    const next = tabs[(i + delta + tabs.length) % tabs.length];
    select(next.id);
    list.current
      ?.querySelector<HTMLButtonElement>(`#tab-${next.id}`)
      ?.focus();
  }

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          {header}

          <div
            className="tabs"
            role="tablist"
            aria-label="Secciones"
            ref={list}
            onKeyDown={onKeyDown}
          >
            {tabs.map((t) => (
              <button
                key={t.id}
                id={`tab-${t.id}`}
                className="tab"
                role="tab"
                type="button"
                aria-selected={t.id === active}
                aria-controls={`panel-${t.id}`}
                tabIndex={t.id === active ? 0 : -1}
                onClick={() => select(t.id)}
              >
                {t.label}
                {t.off && (
                  <span
                    className="tab-off"
                    title="No está compartido"
                    aria-label="no está compartido"
                    role="img"
                  />
                )}
              </button>
            ))}
          </div>
        </div>
      </header>

      <main className="page">
        {tabs.map((t) => (
          <div
            // Al pasar de `hidden` a visible el panel corre su animación de
            // entrada (`.panel` en `globals.css`): salir de `display: none`
            // reinicia las animaciones CSS, así que no hace falta remontarlo y
            // lo que tenía abierto se conserva.
            key={t.id}
            id={`panel-${t.id}`}
            className="panel"
            role="tabpanel"
            aria-labelledby={`tab-${t.id}`}
            tabIndex={0}
            hidden={t.id !== active}
          >
            {t.content}
          </div>
        ))}
      </main>
    </>
  );
}
