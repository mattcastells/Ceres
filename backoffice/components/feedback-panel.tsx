'use client';

import { useMemo, useRef, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { FEEDBACK_COLUMNS, type CareFeedback } from '@/lib/queries';
import { invokeCareReport, planPermiteInformes } from '@/lib/care-report';
import { fechaCorta, fechaHora, miles } from '@/lib/format';
import { Section } from '@/components/stat';
import { AiProgress } from '@/components/ai-progress';

type Kind = CareFeedback['kind'];

type Editor = {
  /** `null` = una nueva; si no, la que se está editando. */
  id: string | null;
  kind: Kind;
  localDate: string;
  body: string;
  /** Si la que se edita ya está publicada: el cambio lo ve el paciente. */
  publicada: boolean;
};

const VACIO: Editor = { id: null, kind: 'feedback', localDate: '', body: '', publicada: false };

/** El tope de la base (`care_feedback_body_len`). Se valida acá también para
 *  decirlo antes de mandar, y no con el mensaje de un `check constraint`. */
const MAX = 4000;

/**
 * Lo que la profesional le escribe al paciente: devoluciones e indicaciones.
 *
 * Es **lo único que el panel escribe**, junto con los informes. Los datos del
 * paciente siguen siendo de solo lectura —no hay una política de escritura
 * sobre ellos para la profesional—; esto es texto propio, en `care_feedback`
 * (migración 48).
 *
 * Tres reglas que vienen de la base y que la pantalla hace visibles:
 *
 * - **Mientras no se publica, es privado.** Un borrador lo ve solo quien lo
 *   escribió. Es la regla de las viejas notas privadas (`care_notes`, que se
 *   fueron en la misma migración): una nota para mí es un borrador que no
 *   publico nunca.
 * - **Borrar es `deleted_at`**, no un `DELETE`: la base no deja borrar de
 *   verdad, y el paciente deja de verlo en el próximo refresco.
 * - **Escribir exige un acceso vigente.** Si el paciente cortó el acceso, lo
 *   escrito se sigue viendo acá pero ya no se toca, y el error lo dice así.
 *
 * Las indicaciones son lo que queda vigente ("sumá proteína en el desayuno"):
 * el paciente las ve en Inicio hasta que se sacan. Las devoluciones son sobre
 * un día o una semana, y pueden anclarse a una fecha.
 */
export function FeedbackPanel({
  patientId,
  authorId,
  initial,
  hoy,
  plan,
}: {
  patientId: string;
  authorId: string;
  initial: CareFeedback[];
  hoy: string;
  plan: string | null;
}) {
  const db = useMemo(() => browserClient(), []);
  const [items, setItems] = useState(initial);
  const [editor, setEditor] = useState<Editor>(VACIO);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [foco, setFoco] = useState('');
  const [focoFecha, setFocoFecha] = useState('');
  const [generando, setGenerando] = useState(false);
  const [errorIA, setErrorIA] = useState<string | null>(null);
  const editorRef = useRef<HTMLDivElement>(null);
  const textoRef = useRef<HTMLTextAreaElement>(null);

  const conIA = planPermiteInformes(plan);

  function reemplazar(row: CareFeedback) {
    setItems((xs) => {
      const sin = xs.filter((x) => x.id !== row.id);
      return [row, ...sin].sort((a, b) => b.created_at.localeCompare(a.created_at));
    });
  }

  function abrirEnEditor(f: CareFeedback) {
    setEditor({
      id: f.id,
      kind: f.kind,
      localDate: f.local_date ?? '',
      body: f.body,
      publicada: f.published_at !== null,
    });
    setError(null);
    // El editor está arriba de la lista: sin esto, "Editar" en la décima
    // devolución no muestra ningún cambio en pantalla.
    requestAnimationFrame(() => {
      editorRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      textoRef.current?.focus();
    });
  }

  async function guardar(publicar: boolean) {
    const body = editor.body.trim();
    if (!body) return setError('Escribí algo antes de guardar.');
    if (body.length > MAX) return setError(`Son ${miles(body.length)} caracteres; el máximo es ${miles(MAX)}.`);

    setBusy(publicar ? 'publicar' : 'guardar');
    setError(null);
    // Las indicaciones no llevan fecha: son sobre el seguimiento en general y
    // siguen vigentes hasta que se sacan.
    const localDate = editor.kind === 'feedback' && editor.localDate ? editor.localDate : null;
    const ahora = new Date().toISOString();

    const res = editor.id === null
      ? await db
          .from('care_feedback')
          .insert({
            author_id: authorId,
            patient_id: patientId,
            kind: editor.kind,
            local_date: localDate,
            body,
            source: 'manual',
            published_at: publicar ? ahora : null,
          })
          .select(FEEDBACK_COLUMNS)
          .single()
      : await db
          .from('care_feedback')
          .update({
            kind: editor.kind,
            local_date: localDate,
            body,
            ...(publicar && !editor.publicada ? { published_at: ahora } : {}),
          })
          .eq('id', editor.id)
          .eq('author_id', authorId)
          .select(FEEDBACK_COLUMNS)
          .single();

    setBusy(null);
    if (res.error || !res.data) return setError(mensajeDeEscritura(res.error?.message));
    reemplazar(res.data as unknown as CareFeedback);
    setEditor(VACIO);
  }

  async function publicar(f: CareFeedback) {
    setBusy(`pub-${f.id}`);
    setError(null);
    const res = await db
      .from('care_feedback')
      .update({ published_at: new Date().toISOString() })
      .eq('id', f.id)
      .eq('author_id', authorId)
      .select(FEEDBACK_COLUMNS)
      .single();
    setBusy(null);
    if (res.error || !res.data) return setError(mensajeDeEscritura(res.error?.message));
    reemplazar(res.data as unknown as CareFeedback);
  }

  async function borrar(f: CareFeedback) {
    const pregunta =
      f.published_at === null
        ? '¿Borrar este borrador?'
        : f.kind === 'indication'
          ? '¿Sacar esta indicación? El paciente deja de verla en Inicio.'
          : '¿Borrar esta devolución? El paciente deja de verla.';
    if (!window.confirm(pregunta)) return;

    setBusy(`del-${f.id}`);
    setError(null);
    // Borrado suave: la base no deja un DELETE (`care_feedback_no_hard_delete`)
    // y la limpieza diaria lo purga a los 30 días.
    const res = await db
      .from('care_feedback')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', f.id)
      .eq('author_id', authorId);
    setBusy(null);
    if (res.error) return setError(mensajeDeEscritura(res.error.message));
    setItems((xs) => xs.filter((x) => x.id !== f.id));
    if (editor.id === f.id) setEditor(VACIO);
  }

  async function borradorConIA() {
    setGenerando(true);
    setErrorIA(null);
    const res = await invokeCareReport<{
      draft: { id: string; body: string; local_date: string | null; created_at: string };
    }>(db, {
      kind: 'feedback_draft',
      patientId,
      ...(foco.trim() ? { focus: foco.trim() } : {}),
      ...(focoFecha ? { localDate: focoFecha } : {}),
    });
    setGenerando(false);
    if (!res.ok) return setErrorIA(res.message);

    // La función ya lo guardó como borrador privado (`source: 'ai_draft'`): se
    // suma a la lista y se abre para revisarlo. No se publica nunca solo.
    const d = res.data.draft;
    const fila: CareFeedback = {
      id: d.id,
      patient_id: patientId,
      kind: 'feedback',
      local_date: d.local_date,
      body: d.body,
      source: 'ai_draft',
      published_at: null,
      read_at: null,
      created_at: d.created_at,
      updated_at: d.created_at,
    };
    reemplazar(fila);
    setFoco('');
    abrirEnEditor(fila);
  }

  const indicaciones = items.filter((f) => f.kind === 'indication' && f.published_at);
  const borradores = items.filter((f) => !f.published_at);
  const publicadas = items.filter((f) => f.kind === 'feedback' && f.published_at);
  const largo = editor.body.trim().length;

  return (
    <>
      <Section
        title={editor.id === null ? 'Escribirle' : 'Editar'}
        hint="Lo que guardes queda como borrador privado hasta que lo publiques. El paciente ve lo publicado en la app; las indicaciones le quedan en Inicio hasta que las saques."
      >
        <div className="card fb-editor" ref={editorRef}>
          <div className="row" style={{ flexWrap: 'wrap', gap: 'var(--s4)' }}>
            <div className="seg seg--buttons" role="group" aria-label="Tipo">
              {(['feedback', 'indication'] as const).map((k) => (
                <button
                  key={k}
                  type="button"
                  aria-pressed={editor.kind === k}
                  onClick={() => setEditor((e) => ({ ...e, kind: k }))}
                >
                  {k === 'feedback' ? 'Devolución' : 'Indicación'}
                </button>
              ))}
            </div>
            {editor.kind === 'feedback' ? (
              <label className="caption row" style={{ gap: 'var(--s3)' }}>
                Sobre el día
                <input
                  type="date"
                  value={editor.localDate}
                  max={hoy}
                  onChange={(e) => setEditor((x) => ({ ...x, localDate: e.target.value }))}
                />
                {editor.localDate && (
                  <button
                    type="button"
                    className="button--link"
                    onClick={() => setEditor((x) => ({ ...x, localDate: '' }))}
                  >
                    sin fecha
                  </button>
                )}
              </label>
            ) : (
              <span className="caption">
                Queda en el Inicio del paciente hasta que la saques.
              </span>
            )}
          </div>

          <textarea
            ref={textoRef}
            value={editor.body}
            rows={6}
            maxLength={MAX + 200}
            placeholder={
              editor.kind === 'feedback'
                ? 'Por ejemplo: "Muy bien el desayuno de esta semana. El jueves y el viernes la cena fue tarde; ¿lo charlamos el martes?"'
                : 'Por ejemplo: "Sumá una porción de proteína en el desayuno (huevo, yogur o queso)."'
            }
            onChange={(e) => setEditor((x) => ({ ...x, body: e.target.value }))}
            aria-label="Texto"
          />

          {editor.publicada && (
            <p className="caption" style={{ margin: 0 }}>
              Ya está publicada: lo que cambies lo ve el paciente.
            </p>
          )}

          <div className="row fb-actions">
            <span className="caption tnum" style={largo > MAX ? { color: 'var(--caution)' } : undefined}>
              {miles(largo)} / {miles(MAX)}
            </span>
            <span style={{ flex: 1 }} />
            {editor.id !== null && (
              <button type="button" className="button--quiet" onClick={() => setEditor(VACIO)} disabled={!!busy}>
                Cancelar
              </button>
            )}
            {!editor.publicada && (
              <button type="button" onClick={() => guardar(false)} disabled={!!busy || largo === 0}>
                {busy === 'guardar' ? 'Guardando…' : 'Guardar borrador'}
              </button>
            )}
            <button
              type="button"
              className="button--primary"
              onClick={() => guardar(true)}
              disabled={!!busy || largo === 0}
            >
              {busy === 'publicar' ? 'Publicando…' : editor.publicada ? 'Guardar cambios' : 'Publicar'}
            </button>
          </div>

          {error && <p className="form-error" role="alert">{error}</p>}
        </div>

        <div className="card fb-ia">
          <div>
            <h3>Borrador con IA</h3>
            <p className="caption" style={{ margin: 'var(--s1) 0 0' }}>
              Propone una devolución a partir de las últimas dos semanas. Queda
              como borrador para que la revises: no se publica sola.
            </p>
          </div>
          <div className="row" style={{ flexWrap: 'wrap', gap: 'var(--s3)' }}>
            <input
              type="text"
              value={foco}
              maxLength={300}
              placeholder="Opcional: sobre qué (el desayuno, los fines de semana…)"
              onChange={(e) => setFoco(e.target.value)}
              style={{ flex: '1 1 260px', minWidth: 0 }}
              disabled={generando}
              aria-label="Foco del borrador"
            />
            <input
              type="date"
              value={focoFecha}
              max={hoy}
              onChange={(e) => setFocoFecha(e.target.value)}
              disabled={generando}
              aria-label="Día (opcional)"
              title="Opcional: un día puntual"
            />
            <button
              type="button"
              onClick={borradorConIA}
              disabled={generando || !conIA}
            >
              {generando ? 'Escribiendo…' : 'Proponer borrador'}
            </button>
          </div>
          {!conIA && (
            <p className="caption" style={{ margin: 0 }}>
              Los borradores con IA son parte del plan Pro.
            </p>
          )}
          {generando && (
            <AiProgress
              etapas={['Leyendo las últimas dos semanas', 'Escribiendo el borrador']}
              rango="entre 10 y 30 segundos"
            />
          )}
          {errorIA && <p className="form-error" role="alert">{errorIA}</p>}
        </div>
      </Section>

      <Lista
        titulo="Indicaciones en Inicio"
        vacio="Ninguna indicación vigente."
        items={indicaciones}
        busy={busy}
        onEditar={abrirEnEditor}
        onPublicar={publicar}
        onBorrar={borrar}
      />
      <Lista
        titulo="Borradores"
        vacio="Sin borradores."
        hint="Privados: el paciente no los ve."
        items={borradores}
        busy={busy}
        onEditar={abrirEnEditor}
        onPublicar={publicar}
        onBorrar={borrar}
      />
      <Lista
        titulo="Devoluciones publicadas"
        vacio="Todavía no le publicaste ninguna devolución."
        items={publicadas}
        busy={busy}
        onEditar={abrirEnEditor}
        onPublicar={publicar}
        onBorrar={borrar}
      />
    </>
  );
}

function Lista({
  titulo,
  hint,
  vacio,
  items,
  busy,
  onEditar,
  onPublicar,
  onBorrar,
}: {
  titulo: string;
  hint?: string;
  vacio: string;
  items: CareFeedback[];
  busy: string | null;
  onEditar: (f: CareFeedback) => void;
  onPublicar: (f: CareFeedback) => void;
  onBorrar: (f: CareFeedback) => void;
}) {
  return (
    <Section title={`${titulo}${items.length ? ` · ${items.length}` : ''}`} hint={hint}>
      {items.length === 0 ? (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>{vacio}</p>
        </div>
      ) : (
        <div className="fb-list">
          {items.map((f) => (
            <article key={f.id} className="card fb-item">
              <div className="chips">
                <span className="chip chip--on">
                  {f.kind === 'indication' ? 'Indicación' : 'Devolución'}
                </span>
                {f.local_date && (
                  <span className="chip tnum">sobre el {fechaCorta(f.local_date)}</span>
                )}
                <Estado f={f} />
                {f.source === 'ai_draft' && (
                  // Como en la app: lo que salió de la IA se marca en ámbar
                  // aunque después se haya editado, para que quede constancia
                  // de dónde salió el primer texto.
                  <span className="chip chip--warn">propuesto por IA</span>
                )}
              </div>
              <p className="fb-body">{f.body}</p>
              <div className="row fb-actions">
                <span className="caption tnum">
                  {f.published_at
                    ? `publicada el ${fechaHora(f.published_at)}`
                    : `creado el ${fechaHora(f.created_at)}`}
                </span>
                <span style={{ flex: 1 }} />
                <button type="button" className="button--quiet" onClick={() => onEditar(f)} disabled={!!busy}>
                  Editar
                </button>
                <button type="button" className="button--quiet" onClick={() => onBorrar(f)} disabled={!!busy}>
                  {busy === `del-${f.id}`
                    ? 'Borrando…'
                    : f.kind === 'indication' && f.published_at
                      ? 'Sacar'
                      : 'Borrar'}
                </button>
                {!f.published_at && (
                  <button type="button" className="button--primary" onClick={() => onPublicar(f)} disabled={!!busy}>
                    {busy === `pub-${f.id}` ? 'Publicando…' : 'Publicar'}
                  </button>
                )}
              </div>
            </article>
          ))}
        </div>
      )}
    </Section>
  );
}

/** Borrador, publicada sin leer, o leída. "Leída" lo marca el paciente al
 *  abrirla en la app (`mark_care_feedback_read`); el panel no puede tocarlo. */
function Estado({ f }: { f: CareFeedback }) {
  if (!f.published_at) return <span className="chip">Borrador</span>;
  if (f.read_at) return <span className="chip chip--on tnum">Leída el {fechaHora(f.read_at)}</span>;
  return <span className="chip">Publicada · sin leer</span>;
}

/** El error de una escritura, en una frase que diga qué hacer.
 *
 *  El caso que importa es RLS: si el paciente cortó el acceso, la policy de
 *  escritura rechaza y PostgREST dice "new row violates row-level security
 *  policy", que no le dice nada a nadie. */
function mensajeDeEscritura(msg: string | undefined): string {
  if (!msg) return 'No se pudo guardar. Probá de nuevo.';
  if (/row-level security|permission denied|42501/i.test(msg)) {
    return 'No se pudo guardar: el acceso de esta persona ya no está vigente. Lo escrito se sigue viendo, pero no se puede cambiar.';
  }
  if (/body_len/i.test(msg)) return `El texto tiene que tener entre 1 y ${miles(MAX)} caracteres.`;
  return `No se pudo guardar: ${msg}`;
}
