'use client';

import { useMemo, useRef, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { FEEDBACK_COLUMNS, type CareFeedback, type Goal } from '@/lib/queries';
import { invokeCareReport, planPermiteInformes } from '@/lib/care-report';
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
import { AiProgress } from '@/components/ai-progress';
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
 * Tres reglas que vienen de la base y que la pantalla hace visibles:
 *
 * - **Mientras no se publica, es privado.** Un borrador lo ve solo quien lo
 *   escribió.
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
  plan,
  objetivoActual = null,
  conoceObjetivo = true,
  titulosDeComidas = {},
}: {
  patientId: string;
  authorId: string;
  initial: CareFeedback[];
  hoy: string;
  plan: string | null;
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
      f.published_at === null
        ? '¿Borrar este borrador?'
        : f.kind === 'indication'
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

  // El objetivo recomendado va en su propia sección y no en las listas de
  // abajo: es una indicación, pero se edita con números y no con texto.
  const textos = items.filter((f) => !esObjetivo(f));
  const objetivos = items.filter(esObjetivo);
  const indicaciones = textos.filter((f) => f.kind === 'indication' && f.published_at);
  const borradores = textos.filter((f) => !f.published_at);
  const publicadas = textos.filter((f) => f.kind === 'feedback' && f.published_at);
  const largo = editor.body.trim().length;

  return (
    <>
      <Section
        className="no-print"
        title={editor.id === null ? 'Escribirle' : 'Editar'}
        hint="Los borradores son privados. Lo publicado lo ve el paciente en la app."
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
              <span className="caption">Queda en el Inicio del paciente hasta que la saques.</span>
            )}
          </div>

          <textarea
            ref={textoRef}
            value={editor.body}
            rows={6}
            maxLength={MAX + 200}
            placeholder={
              editor.kind === 'feedback'
                ? 'Por ejemplo: "Muy bien los desayunos de esta semana."'
                : 'Por ejemplo: "Sumá una porción de proteína en el desayuno."'
            }
            onChange={(e) => setEditor((x) => ({ ...x, body: e.target.value }))}
            aria-label="Texto"
          />

          <div className="row fb-actions">
            <span className="caption tnum" style={largo > MAX ? { color: 'var(--caution)' } : undefined}>
              {editor.publicada ? 'Publicada: el paciente ve los cambios · ' : ''}
              {miles(largo)} / {miles(MAX)}
            </span>
            <span style={{ flex: 1 }} />
            <button
              type="button"
              className="button--primary"
              onClick={() => guardar(true)}
              disabled={!!busy || largo === 0}
            >
              {busy === 'publicar' ? 'Publicando…' : editor.publicada ? 'Guardar cambios' : 'Publicar'}
            </button>
            {!editor.publicada && (
              <button type="button" onClick={() => guardar(false)} disabled={!!busy || largo === 0}>
                {busy === 'guardar' ? 'Guardando…' : 'Guardar borrador'}
              </button>
            )}
            {editor.id !== null && (
              <button type="button" className="button--quiet" onClick={() => setEditor(VACIO)} disabled={!!busy}>
                Cancelar
              </button>
            )}
          </div>

          {error && <p className="form-error" role="alert">{error}</p>}
        </div>

        <div className="card fb-ia">
          <div>
            <h3>Borrador con IA</h3>
            <p className="caption" style={{ margin: 'var(--s1) 0 0' }}>
              Sobre las últimas dos semanas. Queda como borrador para que lo revises.
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
            <button type="button" onClick={borradorConIA} disabled={generando || !conIA}>
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
        onPublicar={publicar}
        onBorrar={borrar}
      />
      <Lista
        noPrint
        titulo="Borradores"
        vacio="Sin borradores."
        hint="Privados: el paciente no los ve."
        items={borradores}
        busy={busy}
        titulosDeComidas={titulosDeComidas}
        onEditar={abrirEnEditor}
        onPublicar={publicar}
        onBorrar={borrar}
      />
      <Lista
        titulo="Devoluciones"
        vacio="Ninguna devolución publicada."
        items={publicadas}
        busy={busy}
        titulosDeComidas={titulosDeComidas}
        onEditar={abrirEnEditor}
        onPublicar={publicar}
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
 * Hay a lo sumo un objetivo vigente y un borrador. Publicar uno nuevo saca el
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
  const borrador = objetivos.find((f) => !f.published_at) ?? null;
  const base = borrador ?? vigente;

  const [campos, setCampos] = useState<Campos>(() => camposDe(base ? objetivoDe(base) : null));
  const [nota, setNota] = useState(() => (base ? notaDe(base.body) : ''));
  const [error, setError] = useState<string | null>(null);

  const leido = validarObjetivo(campos);
  const macrosKcal = leido.ok ? kcalDeMacros(leido.objetivo) : null;
  const sinCambios =
    !borrador &&
    vigente !== null &&
    leido.ok &&
    mismoObjetivo(leido.objetivo, objetivoDe(vigente)!) &&
    nota.trim() === notaDe(vigente.body);

  async function guardar(publicar: boolean) {
    if (!leido.ok) return setError(leido.error);
    const body = cuerpoObjetivo(leido.objetivo, nota);
    if (body.length > MAX) return setError(`La nota es demasiado larga (máximo ${miles(MAX)} caracteres en total).`);

    setBusy(publicar ? 'obj-pub' : 'obj-guardar');
    setError(null);
    const ahora = new Date().toISOString();
    const res = await guardarFila(borrador?.id ?? null, {
      kind: 'indication',
      local_date: null,
      body,
      target_kcal: leido.objetivo.kcal,
      target_protein_g: leido.objetivo.proteinas,
      target_carbs_g: leido.objetivo.carbohidratos,
      target_fat_g: leido.objetivo.grasas,
      ...(publicar ? { published_at: ahora } : borrador ? {} : { published_at: null }),
    });
    if (res.error !== undefined) {
      setBusy(null);
      return setError(res.error);
    }
    onGuardado(res.row);
    if (publicar) {
      const e = await borrarFilas(publicados.map((f) => f.id).filter((id) => id !== res.row.id));
      if (e) setError(e);
    }
    setBusy(null);
  }

  async function sacar(f: CareFeedback) {
    const pregunta = f.published_at
      ? '¿Sacar el objetivo recomendado? El paciente deja de verlo.'
      : '¿Descartar el borrador?';
    if (!window.confirm(pregunta)) return;
    setBusy(`obj-del-${f.id}`);
    setError(null);
    const e = await borrarFilas([f.id]);
    setBusy(null);
    if (e) return setError(e);
    if (!f.published_at) {
      setCampos(camposDe(vigente ? objetivoDe(vigente) : null));
      setNota(vigente ? notaDe(vigente.body) : '');
    }
  }

  const ph = (n: number | null | undefined) => (n ? String(n) : undefined);

  return (
    <Section
      title="Objetivo recomendado"
      hint="Calorías y macros que el paciente ve en la app y aplica con un toque."
    >
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
          placeholder="Nota opcional para el paciente"
          onChange={(e) => setNota(e.target.value)}
          aria-label="Nota"
        />

        <div className="row fb-actions">
          <span className="caption tnum">
            {[
              borrador ? `Borrador del ${fechaHora(borrador.created_at)}` : null,
              macrosKcal !== null ? `Los macros suman ${miles(macrosKcal)} kcal` : null,
            ]
              .filter(Boolean)
              .join(' · ')}
          </span>
          <span style={{ flex: 1 }} />
          <button
            type="button"
            className="button--primary"
            onClick={() => guardar(true)}
            disabled={!!busy || !campos.kcal.trim() || sinCambios}
          >
            {busy === 'obj-pub' ? 'Publicando…' : vigente ? 'Publicar y reemplazar' : 'Publicar'}
          </button>
          <button
            type="button"
            onClick={() => guardar(false)}
            disabled={!!busy || !campos.kcal.trim() || sinCambios}
          >
            {busy === 'obj-guardar' ? 'Guardando…' : 'Guardar borrador'}
          </button>
          {borrador && (
            <button type="button" className="button--quiet" onClick={() => sacar(borrador)} disabled={!!busy}>
              {busy === `obj-del-${borrador.id}` ? 'Descartando…' : 'Descartar'}
            </button>
          )}
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
  hint,
  vacio,
  items,
  busy,
  titulosDeComidas,
  onEditar,
  onPublicar,
  onBorrar,
  noPrint = false,
}: {
  noPrint?: boolean;
  titulo: string;
  hint?: string;
  vacio: string;
  items: CareFeedback[];
  busy: string | null;
  titulosDeComidas: Record<string, string>;
  onEditar: (f: CareFeedback) => void;
  onPublicar: (f: CareFeedback) => void;
  onBorrar: (f: CareFeedback) => void;
}) {
  return (
    <Section
      title={`${titulo}${items.length ? ` · ${items.length}` : ''}`}
      hint={hint}
      className={noPrint ? 'no-print' : undefined}
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
                  {f.published_at
                    ? `Publicada el ${fechaHora(f.published_at)}`
                    : `Creado el ${fechaHora(f.created_at)}`}
                </span>
                <span style={{ flex: 1 }} />
                {!f.published_at && (
                  <button type="button" className="button--primary" onClick={() => onPublicar(f)} disabled={!!busy}>
                    {busy === `pub-${f.id}` ? 'Publicando…' : 'Publicar'}
                  </button>
                )}
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

/** Borrador, publicada sin leer, o leída. "Leída" lo marca el paciente al
 *  abrirla en la app (`mark_care_feedback_read`); el panel no puede tocarlo. */
function estado(f: CareFeedback): string {
  if (!f.published_at) return 'borrador';
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
