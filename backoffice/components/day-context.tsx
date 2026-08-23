import {
  DRINK_LABEL,
  SEVERITY_LABEL,
  type AlcoholLog,
  type DayMarker,
} from '@/lib/queries';
import { num } from '@/lib/format';

/**
 * El contexto de un día, en una línea.
 *
 * **Aparece solo si hay algo que decir.** No es una tarjeta más: es lo que
 * explica al resto, y una fila permanente que diga "0 tragos · sin enfermedad"
 * convierte en ruido diario lo que tiene que saltar el día que pasó algo.
 *
 * Nada de esto cambia un cálculo. Un día de enfermedad no baja el objetivo ni
 * se saltea del promedio: la pantalla muestra distancias, no notas, y una
 * enfermedad que además "perdonara" el día sería la app opinando sobre una
 * semana que no vio. Ver `docs/contexto-diario.md`.
 */
export function DayContext({
  markers = [],
  alcohol = [],
  compacto = false,
}: {
  markers?: DayMarker[];
  alcohol?: AlcoholLog[];
  /** Solo las etiquetas, para un lugar chico. */
  compacto?: boolean;
}) {
  const enfermo = markers.find((m) => m.kind === 'sick');
  const descanso = markers.find((m) => m.kind === 'rest');
  const ube = alcohol.reduce((a, x) => a + x.std_drinks, 0);
  const kcal = alcohol.reduce((a, x) => a + x.kcal, 0);

  if (!enfermo && !descanso && alcohol.length === 0) {
    return null;
  }

  if (compacto) {
    return (
      <span className="chips">
        {enfermo && <span className="chip chip--warn">Enfermedad</span>}
        {descanso && <span className="chip">Descanso</span>}
        {ube > 0 && (
          <span className="chip tnum">{num(ube)} tragos</span>
        )}
      </span>
    );
  }

  return (
    <div className="day-context">
      {enfermo && (
        <p>
          <strong>Día de enfermedad</strong>
          {enfermo.severity ? ` · ${SEVERITY_LABEL[enfermo.severity]}` : ''}
          {enfermo.note ? ` — ${enfermo.note}` : ''}
        </p>
      )}
      {descanso && (
        <p>
          <strong>Descanso planificado</strong>
          {descanso.note ? ` — ${descanso.note}` : ''}
        </p>
      )}
      {alcohol.length > 0 && (
        <p>
          <strong className="tnum">{num(ube)} tragos</strong>{' '}
          <span className="muted">
            ({alcohol.map((a) => etiqueta(a)).join(', ')}) ·{' '}
            {/* Las calorías del alcohol van acá y **no** sumadas a las de las
                comidas: sumarlas ahí escondería de dónde salieron, que es justo
                el dato que se busca cuando el peso no baja y las comidas
                estaban bien. */}
            <span className="estimate tnum">≈ {kcal} kcal</span>, aparte de las
            comidas
          </span>
        </p>
      )}
    </div>
  );
}

function etiqueta(a: AlcoholLog): string {
  const tipo = DRINK_LABEL[a.drink_type] ?? a.drink_type;
  return `${num(a.quantity)} × ${tipo.toLowerCase()}`;
}
