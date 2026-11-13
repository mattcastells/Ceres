'use client';

import { useMemo, useRef, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { ARTICLE_COLUMNS, type CareArticle } from '@/lib/queries';
import { MAX_CUERPO, MAX_ETIQUETA, MAX_TITULO, extracto, validarArticulo } from '@/lib/articulos';
import { fechaHora, miles } from '@/lib/format';
import { Section } from '@/components/stat';
import { ArticleBody } from '@/components/article-body';

type Kind = CareArticle['kind'];

type Editor = {
  /** `null` = uno nuevo; si no, el que se está editando. */
  id: string | null;
  kind: Kind;
  title: string;
  body: string;
  tag: string;
  publicado: boolean;
};

const VACIO: Editor = { id: null, kind: 'article', title: '', body: '', tag: '', publicado: false };

const TIPO: Record<Kind, string> = { article: 'Artículo', recipe: 'Receta' };

/**
 * Artículos y recetas para todo el equipo (migración 52).
 *
 * Mismas reglas que las devoluciones, para no pensar dos veces lo mismo: un
 * borrador es privado, borrar es `deleted_at`, y lo publicado lo leen en la app
 * los pacientes con un acceso vigente. Lo que cambia es el destinatario: una
 * devolución es para una persona; un artículo, para todas.
 *
 * Las acciones van en el orden de todo el panel: la principal primero,
 * después las secundarias y lo que borra al final.
 */
export function ArticlesPanel({ authorId, initial }: { authorId: string; initial: CareArticle[] }) {
  const db = useMemo(() => browserClient(), []);
  const [items, setItems] = useState(initial);
  const [editor, setEditor] = useState<Editor>(VACIO);
  const [vista, setVista] = useState<'escribir' | 'previa'>('escribir');
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [errorLista, setErrorLista] = useState<string | null>(null);
  const editorRef = useRef<HTMLDivElement>(null);

  function reemplazar(row: CareArticle) {
    setItems((xs) =>
      [row, ...xs.filter((x) => x.id !== row.id)].sort((a, b) =>
        b.created_at.localeCompare(a.created_at),
      ),
    );
  }

  function abrir(a: CareArticle) {
    setEditor({
      id: a.id,
      kind: a.kind,
      title: a.title,
      body: a.body,
      tag: a.tag ?? '',
      publicado: a.published_at !== null,
    });
    setVista('escribir');
    setError(null);
    requestAnimationFrame(() =>
      editorRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }),
    );
  }

  async function guardar(publicar: boolean) {
    const problema = validarArticulo(editor);
    if (problema) return setError(problema);

    setBusy(publicar ? 'publicar' : 'guardar');
    setError(null);
    const cols = {
      kind: editor.kind,
      title: editor.title.trim(),
      body: editor.body.trim(),
      tag: editor.tag.trim() || null,
    };
    const ahora = new Date().toISOString();
    const res = editor.id === null
      ? await db
          .from('care_articles')
          .insert({ author_id: authorId, ...cols, published_at: publicar ? ahora : null })
          .select(ARTICLE_COLUMNS)
          .single()
      : await db
          .from('care_articles')
          .update({ ...cols, ...(publicar && !editor.publicado ? { published_at: ahora } : {}) })
          .eq('id', editor.id)
          .eq('author_id', authorId)
          .select(ARTICLE_COLUMNS)
          .single();
    setBusy(null);
    if (res.error || !res.data) return setError(mensaje(res.error?.message));
    reemplazar(res.data as unknown as CareArticle);
    setEditor(VACIO);
    setVista('escribir');
  }

  async function cambiarPublicacion(a: CareArticle, publicar: boolean) {
    if (!publicar && !window.confirm('¿Despublicar? Tus pacientes dejan de verlo; queda como borrador.')) return;
    setBusy(`pub-${a.id}`);
    setErrorLista(null);
    const res = await db
      .from('care_articles')
      .update({ published_at: publicar ? new Date().toISOString() : null })
      .eq('id', a.id)
      .eq('author_id', authorId)
      .select(ARTICLE_COLUMNS)
      .single();
    setBusy(null);
    if (res.error || !res.data) return setErrorLista(mensaje(res.error?.message));
    reemplazar(res.data as unknown as CareArticle);
    if (editor.id === a.id) setEditor((e) => ({ ...e, publicado: publicar }));
  }

  async function borrar(a: CareArticle) {
    const pregunta = a.published_at
      ? '¿Borrar este artículo? Tus pacientes dejan de verlo.'
      : '¿Borrar este borrador?';
    if (!window.confirm(pregunta)) return;
    setBusy(`del-${a.id}`);
    setErrorLista(null);
    // Borrado suave: la base no deja un DELETE y la limpieza diaria lo purga a
    // los 30 días.
    const res = await db
      .from('care_articles')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', a.id)
      .eq('author_id', authorId);
    setBusy(null);
    if (res.error) return setErrorLista(mensaje(res.error.message));
    setItems((xs) => xs.filter((x) => x.id !== a.id));
    if (editor.id === a.id) setEditor(VACIO);
  }

  const publicados = items
    .filter((a) => a.published_at)
    .sort((a, b) => (b.published_at ?? '').localeCompare(a.published_at ?? ''));
  const borradores = items.filter((a) => !a.published_at);
  const vacio = !editor.title.trim() || !editor.body.trim();

  return (
    <>
      <Section
        title={editor.id === null ? 'Escribir' : 'Editar'}
        hint="Los borradores son privados. Lo publicado lo ve todo tu equipo en la app."
      >
        <div className="card fb-editor" ref={editorRef}>
          <div className="row" style={{ flexWrap: 'wrap', gap: 'var(--s4)' }}>
            <div className="seg seg--buttons" role="group" aria-label="Tipo">
              {(['article', 'recipe'] as const).map((k) => (
                <button
                  key={k}
                  type="button"
                  aria-pressed={editor.kind === k}
                  onClick={() => setEditor((e) => ({ ...e, kind: k }))}
                >
                  {TIPO[k]}
                </button>
              ))}
            </div>
            <input
              type="text"
              value={editor.tag}
              maxLength={MAX_ETIQUETA}
              placeholder="Etiqueta (opcional)"
              aria-label="Etiqueta"
              onChange={(e) => setEditor((x) => ({ ...x, tag: e.target.value }))}
              style={{ flex: '0 1 220px', minWidth: 0 }}
            />
          </div>

          <input
            type="text"
            className="art-titulo"
            value={editor.title}
            maxLength={MAX_TITULO}
            placeholder={editor.kind === 'recipe' ? 'Por ejemplo: Budín de avena y banana' : 'Por ejemplo: Cómo armar una vianda'}
            aria-label="Título"
            onChange={(e) => setEditor((x) => ({ ...x, title: e.target.value }))}
          />

          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 'var(--s3)' }}>
            <div className="seg seg--buttons" role="group" aria-label="Vista">
              <button type="button" aria-pressed={vista === 'escribir'} onClick={() => setVista('escribir')}>
                Escribir
              </button>
              <button
                type="button"
                aria-pressed={vista === 'previa'}
                onClick={() => setVista('previa')}
                disabled={!editor.body.trim()}
              >
                Vista previa
              </button>
            </div>
            <span className="caption">Párrafos, listas con «- » o «1. », títulos con «# » y **negrita**.</span>
          </div>

          {vista === 'escribir' ? (
            <textarea
              value={editor.body}
              rows={12}
              maxLength={MAX_CUERPO}
              placeholder={
                editor.kind === 'recipe'
                  ? '# Ingredientes\n- 1 taza de avena\n- 2 bananas\n\n# Preparación\n1. Mezclar…'
                  : 'Escribí el texto. Una línea en blanco separa los párrafos.'
              }
              onChange={(e) => setEditor((x) => ({ ...x, body: e.target.value }))}
              aria-label="Texto"
            />
          ) : (
            <div className="art-previa">
              <h3>{editor.title.trim() || 'Sin título'}</h3>
              <ArticleBody body={editor.body} />
            </div>
          )}

          <div className="row fb-actions">
            <span className="caption tnum">
              {editor.publicado ? 'Publicado: tu equipo ve los cambios · ' : ''}
              {miles(editor.body.trim().length)} caracteres
            </span>
            <span style={{ flex: 1 }} />
            <button
              type="button"
              className="button--primary"
              onClick={() => guardar(true)}
              disabled={!!busy || vacio}
            >
              {busy === 'publicar' ? 'Publicando…' : editor.publicado ? 'Guardar cambios' : 'Publicar'}
            </button>
            {!editor.publicado && (
              <button type="button" onClick={() => guardar(false)} disabled={!!busy || vacio}>
                {busy === 'guardar' ? 'Guardando…' : 'Guardar borrador'}
              </button>
            )}
            {editor.id !== null && (
              <button
                type="button"
                className="button--quiet"
                onClick={() => {
                  setEditor(VACIO);
                  setVista('escribir');
                  setError(null);
                }}
                disabled={!!busy}
              >
                Cancelar
              </button>
            )}
          </div>
          {error && <p className="form-error" role="alert">{error}</p>}
        </div>
      </Section>

      {errorLista && (
        <p className="form-error" role="alert" style={{ marginTop: 'var(--s5)' }}>
          {errorLista}
        </p>
      )}

      <Lista
        titulo="Publicados"
        vacio="Todavía no publicaste nada."
        items={publicados}
        busy={busy}
        onEditar={abrir}
        onPublicar={(a) => cambiarPublicacion(a, true)}
        onDespublicar={(a) => cambiarPublicacion(a, false)}
        onBorrar={borrar}
      />
      <Lista
        titulo="Borradores"
        hint="Privados: tu equipo no los ve."
        vacio="Sin borradores."
        items={borradores}
        busy={busy}
        onEditar={abrir}
        onPublicar={(a) => cambiarPublicacion(a, true)}
        onDespublicar={(a) => cambiarPublicacion(a, false)}
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
  onDespublicar,
  onBorrar,
}: {
  titulo: string;
  hint?: string;
  vacio: string;
  items: CareArticle[];
  busy: string | null;
  onEditar: (a: CareArticle) => void;
  onPublicar: (a: CareArticle) => void;
  onDespublicar: (a: CareArticle) => void;
  onBorrar: (a: CareArticle) => void;
}) {
  return (
    <Section title={`${titulo}${items.length ? ` · ${items.length}` : ''}`} hint={hint}>
      {items.length === 0 ? (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>{vacio}</p>
        </div>
      ) : (
        <div className="fb-list">
          {items.map((a) => (
            <article key={a.id} className="card fb-item">
              <div className="chips">
                <span className="chip chip--on">{TIPO[a.kind]}</span>
                {a.tag && <span className="chip">{a.tag}</span>}
                {!a.published_at && <span className="chip">Borrador</span>}
              </div>
              <div>
                <h3>{a.title}</h3>
                <p className="muted art-extracto">{extracto(a.body)}</p>
              </div>
              <div className="row fb-actions">
                <span className="caption tnum">
                  {a.published_at
                    ? `Publicado el ${fechaHora(a.published_at)}`
                    : `Creado el ${fechaHora(a.created_at)}`}
                </span>
                <span style={{ flex: 1 }} />
                {!a.published_at && (
                  <button type="button" className="button--primary" onClick={() => onPublicar(a)} disabled={!!busy}>
                    {busy === `pub-${a.id}` ? 'Publicando…' : 'Publicar'}
                  </button>
                )}
                <button type="button" className="button--quiet" onClick={() => onEditar(a)} disabled={!!busy}>
                  Editar
                </button>
                {a.published_at && (
                  <button type="button" className="button--quiet" onClick={() => onDespublicar(a)} disabled={!!busy}>
                    {busy === `pub-${a.id}` ? 'Despublicando…' : 'Despublicar'}
                  </button>
                )}
                <button type="button" className="button--quiet" onClick={() => onBorrar(a)} disabled={!!busy}>
                  {busy === `del-${a.id}` ? 'Borrando…' : 'Borrar'}
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
    </Section>
  );
}

function mensaje(msg: string | undefined): string {
  if (!msg) return 'No se pudo guardar. Probá de nuevo.';
  if (/row-level security|permission denied|42501/i.test(msg)) return 'No se pudo guardar: no tenés permiso.';
  if (/_len/i.test(msg)) return 'Revisá el largo del título, el texto o la etiqueta.';
  return `No se pudo guardar: ${msg}`;
}
