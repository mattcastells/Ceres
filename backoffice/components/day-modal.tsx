'use client';

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import type { Goal } from '@/lib/queries';
import { fechaLarga } from '@/lib/format';
import {
  DayDetail,
  resumenDelDia,
  type DayBundle,
} from '@/components/day-detail';

/**
 * `useAbrirDia()(fecha)` abre el modal del día, desde cualquier componente de
 * cliente de la ficha: una celda del calendario, una barra del gráfico de
 * calorías. Devuelve `null` fuera del provider, y abrir una fecha sin registro
 * no hace nada — el que llama no tiene que saber qué días tienen bolsa.
 */
const AbrirDiaContext = createContext<((fecha: string) => void) | null>(null);

export function useAbrirDia() {
  return useContext(AbrirDiaContext);
}

/**
 * El dueño del modal del día.
 *
 * Hay **un** modal por ficha y vive acá, no en el calendario: cuando el único
 * lugar que lo abría era el calendario podía ser suyo, pero el gráfico de
 * calorías también abre días, y son islas de cliente separadas —entre medio hay
 * Server Components, así que no pueden compartir estado por props—. El provider
 * envuelve a toda la ficha, publica "abrí esta fecha" por contexto, y el
 * contexto sí atraviesa el contenido renderizado en el servidor.
 *
 * El `<dialog>` es nativo: Escape, el foco atrapado adentro y el fondo inerte
 * ya vienen resueltos por el navegador. Las flechas del teclado pasan al día
 * con registro anterior o siguiente.
 */
export function DayModalProvider({
  dias,
  targetKcal,
  goal,
  photoUrls,
  shareMeals,
  sharePhotos,
  shareWellbeing,
  children,
}: {
  /** Solo los días con algo registrado, en cualquier orden. */
  dias: DayBundle[];
  targetKcal: number | null;
  goal: Goal | null;
  photoUrls: Record<string, string>;
  shareMeals: boolean;
  sharePhotos: boolean;
  shareWellbeing: boolean;
  children: ReactNode;
}) {
  const ordenados = useMemo(
    () => [...dias].sort((a, b) => a.date.localeCompare(b.date)),
    [dias],
  );

  const [abierto, setAbierto] = useState<number | null>(null);
  const dialogo = useRef<HTMLDialogElement>(null);
  const caja = useRef<HTMLDivElement>(null);

  const abrir = useMemo(() => {
    const indice = new Map(ordenados.map((d, i) => [d.date, i]));
    return (fecha: string) => {
      const i = indice.get(fecha);
      if (i !== undefined) setAbierto(i);
    };
  }, [ordenados]);

  useEffect(() => {
    const d = dialogo.current;
    if (!d) return;
    if (abierto === null) {
      if (d.open) d.close();
    } else {
      if (!d.open) d.showModal();
      // Al pasar de un día al otro, el modal arranca arriba: si no, el jueves se
      // abre scrolleado hasta donde uno había llegado leyendo el miércoles.
      caja.current?.scrollTo({ top: 0 });
      // El foco va a la caja y no al primer botón. `showModal()` se lo da al
      // primer control que encuentra —la flecha de "anterior"— y el modal se
      // abría con un anillo de foco en un botón secundario. React ignora
      // `autoFocus` en un `div`, así que se hace a mano.
      caja.current?.focus({ preventScroll: true });
    }
  }, [abierto]);

  // Las flechas del teclado pasan de día. Se escuchan en `window` mientras el
  // modal está abierto y no en el diálogo: así andan aunque el foco haya
  // quedado en cualquier parte, que es lo que pasa después de un clic en un
  // `<details>` o en el fondo.
  useEffect(() => {
    if (abierto === null) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'ArrowRight') {
        e.preventDefault();
        mover(1);
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        mover(-1);
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // `mover` es estable en lo que importa: solo usa el setter y el largo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [abierto, ordenados.length]);

  function mover(paso: number) {
    setAbierto((i) => {
      if (i === null) return null;
      const j = i + paso;
      return j < 0 || j >= ordenados.length ? i : j;
    });
  }

  const dia = abierto === null ? null : ordenados[abierto];
  const resumen = dia ? resumenDelDia(dia, photoUrls, sharePhotos) : '';

  return (
    <AbrirDiaContext.Provider value={abrir}>
      {children}

      <dialog
        ref={dialogo}
        className="modal modal--day"
        aria-label="Detalle del día"
        onClose={() => setAbierto(null)}
        // Clic en el fondo: el `<dialog>` ocupa toda la pantalla y el recuadro
        // es un hijo, así que un clic cuyo destino sea el diálogo mismo cayó
        // afuera de la caja.
        onClick={(e) => {
          if (e.target === dialogo.current) setAbierto(null);
        }}
      >
        {dia && (
          // Enfocable pero no tabulable: el foco arranca en el contenido, que
          // es lo que uno abrió a mirar. Ver el efecto de arriba.
          <div className="modal-box modal-box--day" tabIndex={-1} ref={caja}>
            <div className="modal-data">
              <div className="modal-head">
                <div style={{ minWidth: 0 }}>
                  <h3>{fechaLarga(dia.date)}</h3>
                  {resumen && (
                    <p className="caption tnum" style={{ margin: 0 }}>
                      {resumen}
                    </p>
                  )}
                </div>
                <div className="dd-actions">
                  <button
                    type="button"
                    className="modal-close dd-nav"
                    onClick={() => mover(-1)}
                    disabled={abierto === 0}
                    aria-label="Día anterior con registro"
                    title="Día anterior (←)"
                  >
                    ‹
                  </button>
                  <button
                    type="button"
                    className="modal-close dd-nav"
                    onClick={() => mover(1)}
                    disabled={abierto === ordenados.length - 1}
                    aria-label="Día siguiente con registro"
                    title="Día siguiente (→)"
                  >
                    ›
                  </button>
                  <button
                    type="button"
                    className="modal-close dd-close"
                    onClick={() => setAbierto(null)}
                    aria-label="Cerrar"
                    title="Cerrar (Esc)"
                  >
                    ✕
                  </button>
                </div>
              </div>

              <DayDetail
                dia={dia}
                targetKcal={targetKcal}
                goal={goal}
                photoUrls={photoUrls}
                shareMeals={shareMeals}
                sharePhotos={sharePhotos}
                shareWellbeing={shareWellbeing}
              />
            </div>
          </div>
        )}
      </dialog>
    </AbrirDiaContext.Provider>
  );
}
