import { Fragment } from 'react';
import { bloques, enLinea } from '@/lib/articulos';

/**
 * El cuerpo de un artículo, dibujado con las reglas de `lib/articulos.ts`:
 * párrafos, listas, títulos y negrita. Es lo que va a ver el paciente en la
 * app, así que la vista previa del editor usa esto y no un `<pre>`.
 */
export function ArticleBody({ body }: { body: string }) {
  return (
    <div className="art-body">
      {bloques(body).map((b, i) => {
        if (b.tipo === 'titulo') return <h4 key={i}>{texto(b.texto)}</h4>;
        if (b.tipo === 'parrafo') return <p key={i}>{texto(b.texto)}</p>;
        const Lista = b.ordenada ? 'ol' : 'ul';
        return (
          <Lista key={i}>
            {b.items.map((it, j) => (
              <li key={j}>{texto(it)}</li>
            ))}
          </Lista>
        );
      })}
    </div>
  );
}

function texto(t: string) {
  return enLinea(t).map((s, i) =>
    s.negrita ? <strong key={i}>{s.texto}</strong> : <Fragment key={i}>{s.texto}</Fragment>,
  );
}
