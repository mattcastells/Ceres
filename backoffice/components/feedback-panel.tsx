'use client';

import { useMemo, useRef, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { FEEDBACK_COLUMNS, type CareFeedback, type Goal } from '@/lib/queries';
import { fechaCorta, fechaHora, miles } from '@/lib/format';
import {
  camposDe,
  cuerpoObjetivo,
  esObjetivo,
  kcalDeMacros,
  notaDe,
  objetivoDe,
  validarObjetivo,
  type Campos,
  type Objetivo,
} from '@/lib/objetivo';
import { Section } from '@/components/stat';
import { useFeedbackItems } from '@/components/meal-notes';

type Kind = CareFeedback['kind'];

type Editor = {
  /** `null` = una nueva; si no, la que se está editando. */
  id: string | null;
  kind: Kind;
  localDate: string;
  body: string;
  /** Si la que se edita ya está publicada: el cambio lo ve el paciente. */
  publicada: boolean;
  /** Es un comentario sobre una comida: tipo y día quedan fijos (son los de
   *  la comida; la base rechaza una indicación con comida). */
  deComida?: boolean;
};

const VACIO: Editor = { id: null, kind: 'feedback', localDate: '', body: '', publicada: false };

/** El tope de la base (`care_feedback_body_len`). Se valida acá también para
 *  decirlo antes de mandar, y no con el mensaje de un `check constraint`. */
const MAX = 4000;

/**
 * Lo que la profesional le escribe al paciente: devoluciones, indicaciones y
 * el objetivo recomendado.
 *
 * Es texto propio, en `care_feedback` (migraciones 48 y 53). Los datos del
 * paciente siguen siendo de solo lectura —no hay una política de escritura
 * sobre ellos para la profesional—, y por eso el objetivo **se recomienda** y
 * no se fija: el paciente lo aplica desde la app.
 *
 * Se publica al guardar: no hay borradores. La base los sigue admitiendo
 * (`published_at` nulo) y las filas viejas sin publicar no se muestran.
 *
 * Dos reglas que vienen de la base:
 *
 * - **Borrar es `deleted_at`**, no un `DELETE`.
 * - **Escribir exige un acceso vigente.** Si el paciente cortó el acceso, lo
 *   escrito se sigue viendo pero ya no se toca, y el error lo dice así.
 *
 * Las acciones van siempre en el mismo orden en todo el panel: la principal
 * primero, después las secundarias y lo que borra al final.
 */
export function FeedbackPanel({
  patientId,
  authorId,
  initial,
  hoy,
  objetivoActual = null,
  conoceObjetivo = true,
  titulosDeComidas = {},
}: {
  patientId: string;
  authorId: string;
  initial: CareFeedback[];
  hoy: string;
  /** El objetivo vigente del paciente en la app, si comparte comidas. */
  objetivoActual?: Goal | null;
  /** `false` si no comparte comidas: su objetivo no se puede ver. */
  conoceObjetivo?: boolean;
  /** "Milanesa con puré · 5 nov", por id de comida: para decir sobre qué
   *  comida es un comentario. */
  titulosDeComidas?: Record<string, string>;
}) {
  const db = useMemo(() => browserClient(), []);
  // Compartido con los comentarios de cada comida (`components/meal-notes`).
  const [items, setItems] = useFeedbackItems(initial);
  const [editor, setEditor] = useState<Editor>(VACIO);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const editorRef = useRef<HTMLDivElement>(null);
  const textoRef = useRef<HTMLTextAreaElement>(null);

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
      deComida: !!f.meal_id,
    });
    setError(null);
    // El editor está arriba de la lista: sin esto, "Editar" en la décima
    // devolución no muestra ningún cambio en pantalla.
    requestAnimationFrame(() => {
      editorRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      textoRef.current?.focus();
    });
  }

  async function guardar() {
    const body = editor.body.trim();
    if (!body) return setError('Escribí algo antes de guardar.');
    if (body.length > MAX) return setError(`Son ${miles(body.length)} caracteres; el máximo es ${miles(MAX)}.`);

    setBusy('publicar');
    setError(null);
    // Las indicaciones no llevan fecha: siguen vigentes hasta que se sacan.
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
            published_at: ahora,
          })
          .select(FEEDBACK_COLUMNS)
          .single()
      : await db
          .from('care_feedback')
          .update({
            ...(editor.deComida ? {} : { kind: editor.kind, local_date: localDate }),
            body,
            ...(!editor.publicada ? { published_at: ahora } : {}),
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

  /** Borrado suave: la base no deja un DELETE (`care_feedback_no_hard_delete`)
   *  y la limpieza diaria lo purga a los 30 días. */
  async function borrarFilas(ids: string[]): Promise<string | null> {
    if (ids.length === 0) return null;
    const res = await db
      .from('care_feedback')
      .update({ deleted_at: new Date().toISOString() })
      .in('id', ids)
      .eq('author_id', authorId);
    if (res.error) return mensajeDeEscritura(res.error.message);
    setItems((xs) => xs.filter((x) => !ids.includes(x.id)));
    return null;
  }

  async function borrar(f: CareFeedback) {
    const pregunta =
      f.kind === 'indication'
          ? '¿Sacar esta indicación? El paciente deja de verla.'
          : '¿Borrar esta devolución? El paciente deja de verla.';
    if (!window.confirm(pregunta)) return;

    setBusy(`del-${f.id}`);
    setError(null);
    const e = await borrarFilas([f.id]);
    setBusy(null);
    if (e) return setError(e);
    if (editor.id === f.id) setEditor(VACIO);
  }

  // El objetivo recomendado va en su propia sección y no en las listas de
  // abajo: es una indicación, pero se edita con números y no con texto.
  const publicados = items.filter((f) => f.published_at);
  const textos = publicados.filter((f) => !esObjetivo(f));
  const objetivos = publicados.filter(esObjetivo);
  const indicaciones = textos.filter((f) => f.kind === 'indication' && f.published_at);
  const publicadas = textos.filter((f) => f.kind === 'feedback' && f.published_at);
  const largo = editor.body.trim().length;

  return (
    <>
      <Section
        className="no-print"
        title={editor.id === null ? 'Escribirle' : 'Editar'}
      >
        <div className="card fb-editor" ref={editorRef}>
          {!editor.deComida && (
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
            ) : null}
          </div>
          )}

          <textarea
            ref={textoRef}
            value={editor.body}
            rows={6}
            maxLength={MAX + 200}
            onChange={(e) => setEditor((x) => ({ ...x, body: e.target.value }))}
            aria-label="Texto"
          />

          <div className="row fb-actions">
            <span className="caption tnum" style={largo > MAX ? { color: 'var(--caution)' } : undefined}>
              {miles(largo)} / {miles(MAX)}
            </span>
            <span style={{ flex: 1 }} />
            <button
              type="button"
              className="button--primary"
              onClick={guardar}
              disabled={!!busy || largo === 0}
            >
              {busy === 'publicar' ? 'Publicando…' : editor.publicada ? 'Guardar cambios' : 'Publicar'}
            </button>
            {editor.id !== null && (
              <button type="button" className="button--quiet" onClick={() => setEditor(VACIO)} disabled={!!busy}>
                Cancelar
              </button>
            )}
          </div>

          {error && <p className="form-error" role="alert">{error}</p>}
        </div>

      </Section>

      <ObjetivoRecomendado
        objetivos={objetivos}
        actual={objetivoActual}
        conoceActual={conoceObjetivo}
        busy={busy}
        setBusy={setBusy}
        onGuardado={reemplazar}
        borrarFilas={borrarFilas}
        guardarFila={async (id, cols) => {
          const res = id === null
            ? await db
                .from('care_feedback')
                .insert({ author_id: authorId, patient_id: patientId, source: 'manual', ...cols })
                .select(FEEDBACK_COLUMNS)
                .single()
            : await db
                .from('care_feedback')
                .update(cols)
                .eq('id', id)
                .eq('author_id', authorId)
                .select(FEEDBACK_COLUMNS)
                .single();
          if (res.error || !res.data) return { error: mensajeDeEscritura(res.error?.message) };
          return { row: res.data as unknown as CareFeedback };
        }}
      />

      <Lista
        titulo="Indicaciones"
        vacio="Ninguna indicación vigente."
        items={indicaciones}
        busy={busy}
        titulosDeComidas={titulosDeComidas}
        onEditar={abrirEnEditor}
        onBorrar={borrar}
      />
      <Lista
        titulo="Devoluciones"
        vacio="Ninguna devolución publicada."
        items={publicadas}
        busy={busy}
        titulosDeComidas={titulosDeComidas}
        onEditar={abrirEnEditor}
        onBorrar={borrar}
      />
    </>
  );
}

type Columnas = {
  kind?: 'indication';
  local_date?: null;
  body?: string;
  published_at?: string | null;
  target_kcal?: number;
  target_protein_g?: number | null;
  target_carbs_g?: number | null;
  target_fat_g?: number | null;
};

/**
 * "La profesional fija el objetivo calórico y de macros", hecho recomendación.
 *
 * Es una indicación con cuatro números (migración 53). El paciente la ve en la
 * app con un botón para aplicarla, y aplicar es cosa de la app: crea el
 * objetivo nuevo con su propia sesión. Acá se ve si lo leyó y si lo aplicó.
 *
 * Hay a lo sumo un objetivo vigente. Publicar uno nuevo saca el
 * anterior después de guardar el nuevo, no antes: si la segunda escritura
 * falla, la app igual toma el más reciente.
 */
function ObjetivoRecomendado({
  objetivos,
  actual,
  conoceActual,
  busy,
  setBusy,
  onGuardado,
  borrarFilas,
  guardarFila,
}: {
  objetivos: CareFeedback[];
  actual: Goal | null;
  conoceActual: boolean;
  busy: string | null;
  setBusy: (b: string | null) => void;
  onGuardado: (row: CareFeedback) => void;
  borrarFilas: (ids: string[]) => Promise<string | null>;
  guardarFila: (
    id: string | null,
    cols: Columnas,
  ) => Promise<{ row: CareFeedback; error?: undefined } | { error: string; row?: undefined }>;
}) {
  const publicados = objetivos
    .filter((f) => f.published_at)
    .sort((a, b) => (b.published_at ?? '').localeCompare(a.published_at ?? ''));
  const vigente = publicados[0] ?? null;
  const base = vigente;

  const [campos, setCampos] = useState<Campos>(() => camposDe(base ? objetivoDe(base) : null));
  const [nota, setNota] = useState(() => (base ? notaDe(base.body) : ''));
  const [error, setError] = useState<string | null>(null);

  const leido = validarObjetivo(campos);
  const macrosKcal = leido.ok ? kcalDeMacros(leido.objetivo) : null;
  const sinCambios =
    vigente !== null &&
    leido.ok &&
    mismoObjetivo(leido.objetivo, objetivoDe(vigente)!) &&
    nota.trim() === notaDe(vigente.body);

  async function guardar() {
    if (!leido.ok) return setError(leido.error);
    const body = cuerpoObjetivo(leido.objetivo, nota);
    if (body.length > MAX) return setError(`La nota es demasiado larga (máximo ${miles(MAX)} caracteres en total).`);

    setBusy('obj-pub');
    setError(null);
    const ahora = new Date().toISOString();
    const res = await guardarFila(null, {
      kind: 'indication',
      local_date: null,
      body,
      target_kcal: leido.objetivo.kcal,
      target_protein_g: leido.objetivo.proteinas,
      target_carbs_g: leido.objetivo.carbohidratos,
      target_fat_g: leido.objetivo.grasas,
      published_at: ahora,
    });
    if (res.error !== undefined) {
      setBusy(null);
      return setError(res.error);
    }
    onGuardado(res.row);
    const e = await borrarFilas(publicados.map((f) => f.id).filter((id) => id !== res.row.id));
    if (e) setError(e);
    setBusy(null);
  }

  async function sacar(f: CareFeedback) {
    if (!window.confirm('¿Sacar el objetivo recomendado? El paciente deja de verlo.')) return;
    setBusy(`obj-del-${f.id}`);
    setError(null);
    const e = await borrarFilas([f.id]);
    setBusy(null);
    if (e) setError(e);
  }

  const ph = (n: number | null | undefined) => (n ? String(n) : undefined);

  return (
    <Section title="Objetivo recomendado">
      <div className="card fb-editor">
        <dl className="obj-resumen">
          <div>
            <dt className="caption">En la app hoy</dt>
            <dd className="tnum">
              {!conoceActual
                ? <span className="muted">No comparte comidas</span>
                : actual?.base_calorie_target
                  ? textoObjetivo({
                      kcal: actual.base_calorie_target,
                      proteinas: actual.protein_g || null,
                      carbohidratos: actual.carbs_g || null,
                      grasas: actual.fat_g || null,
                    })
                  : <span className="muted">Sin objetivo</span>}
            </dd>
          </div>
          <div>
            <dt className="caption">Recomendado</dt>
            <dd className="tnum">
              {vigente ? textoObjetivo(objetivoDe(vigente)!) : <span className="muted">Ninguno</span>}
            </dd>
            {vigente && (
              <dd className="chips" style={{ marginTop: 'var(--s2)' }}>
                {/* "Leído" y "aplicado" los marca el paciente desde la app
                    (`mark_care_target_applied`); el panel no puede. */}
                {vigente.applied_at ? (
                  <span className="chip chip--on tnum">Aplicado el {fechaHora(vigente.applied_at)}</span>
                ) : vigente.read_at ? (
                  <span className="chip chip--on tnum">Leído el {fechaHora(vigente.read_at)} · sin aplicar</span>
                ) : (
                  <span className="chip tnum">Publicado el {fechaHora(vigente.published_at!)} · sin leer</span>
                )}
                <button
                  type="button"
                  className="button--link"
                  onClick={() => sacar(vigente)}
                  disabled={!!busy}
                >
                  {busy === `obj-del-${vigente.id}` ? 'Sacando…' : 'Sacar'}
                </button>
              </dd>
            )}
          </div>
        </dl>

        <div className="obj-campos">
          {(
            [
              ['kcal', 'Calorías', 'kcal', actual?.base_calorie_target],
              ['proteinas', 'Proteínas', 'g', actual?.protein_g],
              ['carbohidratos', 'Carbohidratos', 'g', actual?.carbs_g],
              ['grasas', 'Grasas', 'g', actual?.fat_g],
            ] as const
          ).map(([k, label, unidad, actualV]) => (
            <label key={k} className="obj-campo">
              <span className="caption">
                {label} <span className="muted">({unidad}{k === 'kcal' ? '' : ', opcional'})</span>
              </span>
              <input
                type="text"
                inputMode="numeric"
                value={campos[k]}
                placeholder={ph(actualV)}
                onChange={(e) => setCampos((c) => ({ ...c, [k]: e.target.value }))}
              />
            </label>
          ))}
        </div>

        <textarea
          value={nota}
          rows={2}
          maxLength={MAX}
          placeholder="Nota"
          onChange={(e) => setNota(e.target.value)}
          aria-label="Nota"
        />

        <div className="row fb-actions">
          <span className="caption tnum">
            {macrosKcal !== null ? `Los macros suman ${miles(macrosKcal)} kcal` : null}
          </span>
          <span style={{ flex: 1 }} />
          <button
            type="button"
            className="button--primary"
            onClick={guardar}
            disabled={!!busy || !campos.kcal.trim() || sinCambios}
          >
            {busy === 'obj-pub' ? 'Publicando…' : vigente ? 'Publicar y reemplazar' : 'Publicar'}
          </button>
        </div>

        {error && <p className="form-error" role="alert">{error}</p>}
      </div>
    </Section>
  );
}

function mismoObjetivo(a: Objetivo, b: Objetivo): boolean {
  return (
    a.kcal === b.kcal &&
    a.proteinas === b.proteinas &&
    a.carbohidratos === b.carbohidratos &&
    a.grasas === b.grasas
  );
}

/** "1.600 kcal · P 95 g · C 180 g · G 55 g". */
function textoObjetivo(o: Objetivo): string {
  return [
    `${miles(o.kcal)} kcal`,
    o.proteinas !== null ? `P ${miles(o.proteinas)} g` : null,
    o.carbohidratos !== null ? `C ${miles(o.carbohidratos)} g` : null,
    o.grasas !== null ? `G ${miles(o.grasas)} g` : null,
  ]
    .filter(Boolean)
    .join(' · ');
}

function Lista({
  titulo,
  vacio,
  items,
  busy,
  titulosDeComidas,
  onEditar,
  onBorrar,
}: {
  titulo: string;
  vacio: string;
  items: CareFeedback[];
  busy: string | null;
  titulosDeComidas: Record<string, string>;
  onEditar: (f: CareFeedback) => void;
  onBorrar: (f: CareFeedback) => void;
}) {
  return (
    <Section
      title={`${titulo}${items.length ? ` · ${items.length}` : ''}`}
    >
      {items.length === 0 ? (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>{vacio}</p>
        </div>
      ) : (
        <div className="fb-list">
          {items.map((f) => (
            <article key={f.id} className="card fb-item">
              {/* Una línea de texto y no una fila de pastillas: de qué es,
                  sobre qué y en qué estado. La única pastilla es la de la IA,
                  en ámbar como en la app, aunque después se haya editado. */}
              <div className="row fb-meta">
                <span className="caption tnum">
                  <strong className="fb-kind">
                    {f.meal_id ? 'Comentario' : f.kind === 'indication' ? 'Indicación' : 'Devolución'}
                  </strong>
                  {f.meal_id
                    ? ` · ${titulosDeComidas[f.meal_id] ?? `una comida del ${fechaCorta(f.local_date ?? '')}`}`
                    : f.local_date
                      ? ` · sobre el ${fechaCorta(f.local_date)}`
                      : ''}
                  {' · '}
                  {estado(f)}
                </span>
                {f.source === 'ai_draft' && <span className="chip chip--warn">Propuesto por IA</span>}
              </div>
              <p className="fb-body">{f.body}</p>
              <div className="row fb-actions">
                <span className="caption tnum">
                  Publicada el {fechaHora(f.published_at ?? f.created_at)}
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
              </div>
            </article>
          ))}
        </div>
      )}
    </Section>
  );
}

/** Sin leer o leída. "Leída" lo marca el paciente al abrirla en la app
 *  (`mark_care_feedback_read`); el panel no puede tocarlo. */
function estado(f: CareFeedback): string {
  if (f.read_at) return `leída el ${fechaHora(f.read_at)}`;
  return 'sin leer';
}

/** El error de una escritura, en una frase que diga qué hacer.
 *
 *  El caso que importa es RLS: si el paciente cortó el acceso, la policy de
 *  escritura rechaza y PostgREST dice "new row violates row-level security
 *  policy", que no le dice nada a nadie. */
function mensajeDeEscritura(msg: string | undefined): string {
  if (!msg) return 'No se pudo guardar. Probá de nuevo.';
  if (/row-level security|permission denied|42501/i.test(msg)) {
    return 'No se pudo guardar: el acceso de esta persona ya no está vigente.';
  }
  if (/body_len/i.test(msg)) return `El texto tiene que tener entre 1 y ${miles(MAX)} caracteres.`;
  if (/target_range/i.test(msg)) return 'Algún número está fuera de rango.';
  return `No se pudo guardar: ${msg}`;
}
