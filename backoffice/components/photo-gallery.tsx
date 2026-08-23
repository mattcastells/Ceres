'use client';

import { useEffect, useRef, useState } from 'react';
import { SLOT_LABEL, esEstimacionIA, type Meal } from '@/lib/queries';
import { fechaCorta, fechaLarga, hora, miles, num } from '@/lib/format';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * Todas las fotos del período, agrupadas por momento del día.
 *
 * Es la otra forma de leer un seguimiento, y la que una nutricionista hace
 * primero: veintiocho desayunos uno al lado del otro cuentan de un vistazo lo
 * que la tabla de ítems no —que siempre es lo mismo, que el fin de semana
 * cambia, que hay tres días con la misma milanesa— y para eso hay que poder
 * comparar sin abrir nada. Por eso la grilla es **solo la foto**: cualquier
 * número al lado de cada una convierte la comparación de imágenes en lectura.
 *
 * El orden de los grupos es fijo —desayuno, almuerzo, cena, snacks— y no por
 * cantidad: un orden que cambia entre pacientes obliga a leer los títulos para
 * saber dónde mirar. Adentro de cada grupo van de la más reciente a la más
 * vieja, que es el sentido en el que se revisa desde una consulta.
 *
 * Los números están a un clic, en el modal, con el mismo detalle que la ficha
 * del día. Se usa un `<dialog>` nativo: Escape, el foco atrapado adentro y el
 * fondo inerte ya vienen resueltos por el navegador, y hechos a mano son tres
 * de los cuatro errores clásicos de accesibilidad de un modal.
 */
export function PhotoGallery({
  meals,
  photoUrls,
}: {
  /** Solo las comidas que tienen foto firmada: el filtro lo hace la página. */
  meals: Meal[];
  photoUrls: Record<string, string>;
}) {
  const grupos = SLOT_ORDER.map((slot) => ({
    slot,
    fotos: meals.filter((m) => m.slot === slot),
  })).filter((g) => g.fotos.length > 0);

  // La lista plana es la que recorre el modal con las flechas: se arma en el
  // mismo orden en que se ven las fotos, así "siguiente" es la de al lado.
  const plano = grupos.flatMap((g) => g.fotos);

  const [abierta, setAbierta] = useState<number | null>(null);
  const dialogo = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const d = dialogo.current;
    if (!d) return;
    if (abierta === null) {
      if (d.open) d.close();
    } else if (!d.open) {
      d.showModal();
    }
  }, [abierta]);

  function mover(paso: number) {
    setAbierta((i) =>
      i === null ? null : (i + paso + plano.length) % plano.length,
    );
  }

  if (plano.length === 0) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin fotos en este período. Las fotos se sacan al cargar una comida
          desde la app; una comida escrita a mano no tiene.
        </p>
      </div>
    );
  }

  const meal = abierta === null ? null : plano[abierta];

  return (
    <>
      {grupos.map((g) => {
        const kcal = g.fotos.reduce((a, m) => a + m.total_kcal, 0);
        return (
          <div className="gal-group" key={g.slot}>
            <div className="slot-head">
              <strong style={{ fontWeight: 500 }}>{SLOT_LABEL[g.slot]}</strong>
              <span className="caption tnum">
                {g.fotos.length} {g.fotos.length === 1 ? 'foto' : 'fotos'} ·{' '}
                {miles(kcal / g.fotos.length)} kcal promedio
              </span>
            </div>

            <div className="gal-grid">
              {g.fotos.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  className="gal-item"
                  onClick={() => setAbierta(plano.indexOf(m))}
                  aria-label={`${SLOT_LABEL[m.slot]} del ${fechaLarga(m.local_date)}, ${miles(m.total_kcal)} kcal`}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={photoUrls[m.photo_path!]}
                    alt=""
                    loading="lazy"
                    decoding="async"
                  />
                  <span className="gal-date caption tnum">
                    {fechaCorta(m.local_date)}
                  </span>
                </button>
              ))}
            </div>
          </div>
        );
      })}

      <dialog
        ref={dialogo}
        className="modal"
        aria-label="Detalle de la comida"
        onClose={() => setAbierta(null)}
        // Clic en el fondo: el `<dialog>` ocupa toda la pantalla y el recuadro
        // es un hijo, así que un clic cuyo destino sea el diálogo mismo cayó
        // afuera de la caja.
        onClick={(e) => {
          if (e.target === dialogo.current) setAbierta(null);
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowRight') {
            e.preventDefault();
            mover(1);
          }
          if (e.key === 'ArrowLeft') {
            e.preventDefault();
            mover(-1);
          }
        }}
      >
        {meal && (
          // `showModal()` le da el foco al primer control que encuentra, que es
          // la flecha de "anterior": se abre con un anillo de foco en un botón
          // secundario y el lector de pantalla empieza por ahí. Con `autoFocus`
          // sobre la caja —que es enfocable pero no tabulable— el foco arranca
          // en el contenido, que es lo que uno abrió a mirar.
          <div className="modal-box" tabIndex={-1} autoFocus>
            <div className="modal-photo">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={photoUrls[meal.photo_path!]} alt="" />
              {plano.length > 1 && (
                <>
                  <button
                    type="button"
                    className="modal-nav modal-nav--prev"
                    onClick={() => mover(-1)}
                    aria-label="Foto anterior"
                  >
                    ‹
                  </button>
                  <button
                    type="button"
                    className="modal-nav modal-nav--next"
                    onClick={() => mover(1)}
                    aria-label="Foto siguiente"
                  >
                    ›
                  </button>
                </>
              )}
            </div>

            <div className="modal-data">
              <div className="modal-head">
                <div style={{ minWidth: 0 }}>
                  <h3>{meal.name || SLOT_LABEL[meal.slot] || 'Comida'}</h3>
                  <p className="caption tnum" style={{ margin: 0 }}>
                    {SLOT_LABEL[meal.slot]} · {fechaLarga(meal.local_date)} ·{' '}
                    {hora(meal.eaten_at)}
                  </p>
                </div>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setAbierta(null)}
                  aria-label="Cerrar"
                >
                  ✕
                </button>
              </div>

              {esEstimacionIA(meal) && (
                <p className="caption estimate" style={{ margin: 0 }}>
                  Estimado por IA a partir de la foto. Son valores aproximados,
                  no una medición.
                </p>
              )}

              <div className="modal-totals">
                <Total label="Calorías" value={miles(meal.total_kcal)} unit="kcal" />
                <Total label="Proteínas" value={num(meal.total_protein_g)} unit="g" />
                <Total label="Carbohidratos" value={num(meal.total_carbs_g)} unit="g" />
                <Total label="Grasas" value={num(meal.total_fat_g)} unit="g" />
              </div>

              <div className="scroll-x">
                <table>
                  <thead>
                    <tr>
                      <th>Ítem</th>
                      <th style={{ textAlign: 'right' }}>Cantidad</th>
                      <th style={{ textAlign: 'right' }}>kcal</th>
                      <th style={{ textAlign: 'right' }}>P</th>
                      <th style={{ textAlign: 'right' }}>C</th>
                      <th style={{ textAlign: 'right' }}>G</th>
                    </tr>
                  </thead>
                  <tbody>
                    {meal.meal_items.map((it) => (
                      <tr key={it.id}>
                        <td>
                          {it.name}
                          {it.ai_confidence !== null && it.ai_confidence < 0.5 && (
                            <span
                              className="caption estimate"
                              style={{ marginLeft: 6 }}
                            >
                              confianza baja
                            </span>
                          )}
                        </td>
                        <td className="tnum" style={{ textAlign: 'right' }}>
                          {num(it.quantity)} {it.unit}
                        </td>
                        <td className="tnum" style={{ textAlign: 'right' }}>
                          {it.kcal}
                        </td>
                        <td className="tnum" style={{ textAlign: 'right' }}>
                          {num(it.protein_g)}
                        </td>
                        <td className="tnum" style={{ textAlign: 'right' }}>
                          {num(it.carbs_g)}
                        </td>
                        <td className="tnum" style={{ textAlign: 'right' }}>
                          {num(it.fat_g)}
                        </td>
                      </tr>
                    ))}
                    {meal.meal_items.length === 0 && (
                      <tr>
                        <td colSpan={6} className="muted">
                          Esta comida no tiene el detalle cargado.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}
      </dialog>
    </>
  );
}

function Total({
  label,
  value,
  unit,
}: {
  label: string;
  value: string;
  unit: string;
}) {
  return (
    <div>
      <div className="caption">{label}</div>
      <div className="tnum modal-total-value">
        {value}
        <span className="muted modal-total-unit">{unit}</span>
      </div>
    </div>
  );
}
