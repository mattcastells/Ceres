'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import { MAX_ADJUNTOS, miniaturaYoutube, youtubeId, type Adjunto } from '@/lib/articulos';

const BUCKET = 'article-media';
const MAX_MB = 5;

/**
 * Las imágenes y los videos de un artículo (migración 61), hasta cinco.
 *
 * Una imagen se sube al elegirla, a la carpeta de la autora en
 * `article-media`; lo que se guarda en el artículo es la ruta. Un video es un
 * enlace de YouTube del que se guarda solo el id. Sacar un adjunto no borra
 * el archivo: si se cancela la edición, el artículo guardado lo sigue usando.
 */
export function ArticleMedia({
  authorId,
  media,
  onChange,
}: {
  authorId: string;
  media: Adjunto[];
  onChange: (media: Adjunto[]) => void;
}) {
  const db = useMemo(() => browserClient(), []);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [video, setVideo] = useState('');
  const [subiendo, setSubiendo] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const archivo = useRef<HTMLInputElement>(null);
  const lleno = media.length >= MAX_ADJUNTOS;

  // Las imágenes que llegaron guardadas necesitan una URL firmada.
  useEffect(() => {
    const faltan = media
      .filter((m): m is Extract<Adjunto, { type: 'image' }> => m.type === 'image')
      .map((m) => m.path)
      .filter((p) => !urls[p]);
    if (!faltan.length) return;
    db.storage
      .from(BUCKET)
      .createSignedUrls(faltan, 60 * 60)
      .then(({ data }) => {
        const nuevas: Record<string, string> = {};
        for (const d of data ?? []) if (d.path && d.signedUrl) nuevas[d.path] = d.signedUrl;
        if (Object.keys(nuevas).length) setUrls((u) => ({ ...u, ...nuevas }));
      });
  }, [db, media, urls]);

  async function subir(file: File) {
    if (lleno) return;
    if (!file.type.startsWith('image/')) return setError('Elegí una imagen.');
    if (file.size > MAX_MB * 1024 * 1024) return setError(`La imagen pesa más de ${MAX_MB} MB.`);
    setSubiendo(true);
    setError(null);
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const path = `${authorId}/${crypto.randomUUID()}.${ext}`;
    const { error } = await db.storage.from(BUCKET).upload(path, file, { contentType: file.type });
    setSubiendo(false);
    if (error) return setError('No se pudo subir la imagen. Probá de nuevo.');
    setUrls((u) => ({ ...u, [path]: URL.createObjectURL(file) }));
    onChange([...media, { type: 'image', path }]);
  }

  function agregarVideo() {
    if (lleno) return;
    const id = youtubeId(video);
    if (!id) return setError('Ese enlace no es de un video de YouTube.');
    setError(null);
    setVideo('');
    onChange([...media, { type: 'youtube', id }]);
  }

  return (
    <div className="art-media">
      {media.length > 0 && (
        <div className="art-media-grid">
          {media.map((m, i) => {
            const src = m.type === 'image' ? urls[m.path] : miniaturaYoutube(m.id);
            return (
              <figure key={m.type === 'image' ? m.path : `${m.id}-${i}`} className="art-media-item">
                {src ? (
                  // eslint-disable-next-line @next/next/no-img-element -- URL firmada o miniatura de YouTube
                  <img src={src} alt="" />
                ) : (
                  <span className="art-media-cargando" />
                )}
                {m.type === 'youtube' && <span className="art-media-play" aria-hidden>▶</span>}
                <button
                  type="button"
                  className="art-media-quitar"
                  aria-label="Quitar"
                  onClick={() => onChange(media.filter((_, j) => j !== i))}
                >
                  ✕
                </button>
              </figure>
            );
          })}
        </div>
      )}

      <div className="row art-media-acciones">
        <button type="button" onClick={() => archivo.current?.click()} disabled={lleno || subiendo}>
          {subiendo ? 'Subiendo…' : 'Agregar imagen'}
        </button>
        <input
          ref={archivo}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0];
            e.target.value = '';
            if (f) void subir(f);
          }}
        />
        <input
          type="url"
          value={video}
          placeholder="Enlace de YouTube"
          aria-label="Enlace de YouTube"
          disabled={lleno}
          onChange={(e) => setVideo(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              agregarVideo();
            }
          }}
        />
        <button type="button" onClick={agregarVideo} disabled={lleno || !video.trim()}>
          Agregar video
        </button>
        <span className="caption tnum">
          {media.length} de {MAX_ADJUNTOS}
        </span>
      </div>
      {error && <p className="form-error" role="alert" style={{ margin: 0 }}>{error}</p>}
    </div>
  );
}
