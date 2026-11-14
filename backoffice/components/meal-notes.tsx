'use client';

import {
  createContext,
  useContext,
  useMemo,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { FEEDBACK_COLUMNS, type CareFeedback } from '@/lib/queries';
import { fechaHora } from '@/lib/format';

type Store = {
  items: CareFeedback[];
  setItems: Dispatch<SetStateAction<CareFeedback[]>>;
  patientId: string;
  authorId: string;
  /** `false` para quien mira la ficha sin ser la profesional del paciente
   *  (la titular del consultorio): lee, pero no le escribe. */
  canWrite: boolean;
};

const FeedbackContext = createContext<Store | null>(null);

/**
 * Lo que la profesional le escribió a este paciente, en un solo lugar.
 *
 * Lo leen la pestaña Devoluciones y los comentarios de cada comida (en el día
 * a día y en las fotos). Con un solo estado, un comentario que se escribe
 * desde el modal de un día aparece en Devoluciones sin recargar, y lo que se
 * borra allá desaparece de la comida.
 */
export function FeedbackStore({
  initial,
  patientId,
  authorId,
  canWrite,
  children,
}: {
  initial: CareFeedback[];
  patientId: string;
  authorId: string;
  canWrite: boolean;
  children: ReactNode;
}) {
  const [items, setItems] = useState(initial);
  const value = useMemo(
    () => ({ items, setItems, patientId, authorId, canWrite }),
    [items, patientId, authorId, canWrite],
  );
  return <FeedbackContext.Provider value={value}>{children}</FeedbackContext.Provider>;
}

/** El estado compartido si hay un `FeedbackStore` arriba; si no, uno local
 *  (la vista previa con datos de ejemplo monta el panel suelto). */
export function useFeedbackItems(
  initial: CareFeedback[],
): [CareFeedback[], Dispatch<SetStateAction<CareFeedback[]>>] {
  const store = useContext(FeedbackContext);
  const local = useState(initial);
  return store ? [store.items, store.setItems] : local;
}

/**
 * Los comentarios de la profesional sobre una comida, y cómo escribir uno.
 *
 * Es una devolución común (`care_feedback`) anclada a la comida con
 * `meal_id`: el paciente la ve en la app junto a esa comida y en su lista de
 * devoluciones. Se publica directo —es un comentario corto sobre algo que ya
 * pasó—; para un borrador está la pestaña Devoluciones.
 */
export function MealComments({
  mealId,
  localDate,
}: {
  mealId: string;
  localDate: string;
}) {
  const store = useContext(FeedbackContext);
  const [abierto, setAbierto] = useState(false);
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!store) return null;
  const notas = store.items
    .filter((f) => f.meal_id === mealId)
    .sort((a, b) => a.created_at.localeCompare(b.created_at));
  if (notas.length === 0 && !store.canWrite) return null;

  async function publicar() {
    const body = texto.trim();
    if (!body || !store) return;
    setBusy(true);
    setError(null);
    const { data, error } = await browserClient()
      .from('care_feedback')
      .insert({
        author_id: store.authorId,
        patient_id: store.patientId,
        kind: 'feedback',
        local_date: localDate,
        meal_id: mealId,
        body,
        source: 'manual',
        published_at: new Date().toISOString(),
      })
      .select(FEEDBACK_COLUMNS)
      .single();
    setBusy(false);
    if (error || !data) {
      setError(
        /row-level security|42501/i.test(error?.message ?? '')
          ? 'No se pudo publicar: el acceso de esta persona ya no está vigente.'
          : 'No se pudo publicar. Probá de nuevo.',
      );
      return;
    }
    store.setItems((xs) => [data as unknown as CareFeedback, ...xs]);
    setTexto('');
    setAbierto(false);
  }

  return (
    <div className="meal-notes">
      {notas.map((n) => (
        <div key={n.id} className="meal-note">
          <p>{n.body}</p>
          <span className="caption tnum">
            {n.published_at
              ? `Tu comentario · ${fechaHora(n.published_at)}${n.read_at ? ' · leído' : ''}`
              : 'Borrador · no lo ve el paciente'}
          </span>
        </div>
      ))}

      {store.canWrite &&
        (abierto ? (
          <div className="meal-note-editor">
            <textarea
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              placeholder="Un comentario sobre esta comida. Lo ve el paciente en la app."
              rows={2}
              maxLength={4000}
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) publicar();
              }}
            />
            {error && <p className="form-error" style={{ margin: 0 }}>{error}</p>}
            <div className="row" style={{ justifyContent: 'flex-end' }}>
              <button
                type="button"
                className="button--quiet"
                onClick={() => {
                  setAbierto(false);
                  setError(null);
                }}
                disabled={busy}
              >
                Cancelar
              </button>
              <button
                type="button"
                className="button--primary"
                onClick={publicar}
                disabled={busy || !texto.trim()}
              >
                {busy ? 'Publicando…' : 'Publicar'}
              </button>
            </div>
          </div>
        ) : (
          <button type="button" className="button--link meal-note-add" onClick={() => setAbierto(true)}>
            Comentar esta comida
          </button>
        ))}
    </div>
  );
}
