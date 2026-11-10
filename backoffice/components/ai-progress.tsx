'use client';

import { useEffect, useState } from 'react';

/**
 * Lo que se ve mientras la IA trabaja: una barra que se mueve, los segundos
 * que van y cuánto suele tardar.
 *
 * Un informe tarda entre 10 y 40 segundos. Con un botón deshabilitado y nada
 * más, a los quince segundos se lee como "se colgó" y se vuelve a tocar —que
 * es pagar dos veces—. Los segundos que corren dicen que sigue vivo, y el
 * rango dice cuánto falta sin prometer un número.
 *
 * Las etapas son orientativas (la función no informa progreso): cambian por
 * tiempo, y están para que la espera tenga forma, no para medirla.
 */
export function AiProgress({
  etapas,
  rango = 'entre 10 y 40 segundos',
}: {
  etapas: string[];
  rango?: string;
}) {
  const [segundos, setSegundos] = useState(0);

  useEffect(() => {
    const inicio = Date.now();
    const id = setInterval(() => setSegundos(Math.floor((Date.now() - inicio) / 1000)), 500);
    return () => clearInterval(id);
  }, []);

  const etapa = etapas[Math.min(Math.floor(segundos / 8), etapas.length - 1)];

  return (
    <div className="ai-progress" role="status" aria-live="polite">
      <div className="ai-progress-bar" aria-hidden>
        <span />
      </div>
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
        <span>{etapa}…</span>
        <span className="caption tnum">
          {segundos} s · suele tardar {rango}
        </span>
      </div>
    </div>
  );
}
