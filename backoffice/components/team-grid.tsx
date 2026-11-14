'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { conSigno, diasEntre, fechaCorta, miles } from '@/lib/format';
import { cambioPeso30, diasDesde, type Alerta, type OverviewRow } from '@/lib/team';
import type { PatientRow } from '@/components/patients-list';

export type FilaEquipo = {
  patient: PatientRow;
  o: OverviewRow | null;
  nombre: string;
  alertas: Alerta[];
};

type Orden = 'prioridad' | 'nombre' | 'ultima' | 'objetivo';

const ORDENES: { id: Orden; label: string }[] = [
  { id: 'prioridad', label: 'Quién pide atención' },
  { id: 'nombre', label: 'Nombre' },
  { id: 'ultima', label: 'Última comida' },
  { id: 'objetivo', label: 'Calorías contra objetivo' },
];

/**
 * La grilla del equipo, con búsqueda y orden.
 *
 * Llega ya ordenada por prioridad (`ordenarEquipo`, en el servidor): ese es el
 * orden por defecto porque contesta "a quién le escribo hoy". Los otros
 * órdenes son para buscar a alguien en una cartera grande, no para
 * reemplazarlo.
 */
export function TeamGrid({ filas, hoy }: { filas: FilaEquipo[]; hoy: string }) {
  const [q, setQ] = useState('');
  const [orden, setOrden] = useState<Orden>('prioridad');

  const visibles = useMemo(() => {
    const texto = normalizar(q.trim());
    const filtradas = texto
      ? filas.filter((f) => normalizar(f.nombre).includes(texto))
      : filas;
    if (orden === 'prioridad') return filtradas;
    const copia = [...filtradas];
    if (orden === 'nombre') copia.sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
    if (orden === 'ultima') {
      // La más reciente primero; quien nunca registró, al final.
      copia.sort((a, b) =>
        (b.o?.last_meal_date ?? '').localeCompare(a.o?.last_meal_date ?? ''),
      );
    }
    if (orden === 'objetivo') {
      // Quien más se aleja de su objetivo (para los dos lados) primero.
      const desvio = (f: FilaEquipo) =>
        f.o?.avg_kcal_7 && f.o.target_kcal
          ? Math.abs(f.o.avg_kcal_7 / f.o.target_kcal - 1)
          : -1;
      copia.sort((a, b) => desvio(b) - desvio(a));
    }
    return copia;
  }, [filas, q, orden]);

  return (
    <>
      {filas.length > 4 && (
        <div className="row team-tools">
          <input
            type="search"
            placeholder="Buscar por nombre"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            aria-label="Buscar paciente por nombre"
          />
          <label className="caption row" style={{ gap: 'var(--s3)' }}>
            Ordenar por
            <select value={orden} onChange={(e) => setOrden(e.target.value as Orden)}>
              {ORDENES.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      )}

      {visibles.length === 0 ? (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Nadie se llama así en tu equipo.
          </p>
        </div>
      ) : (
        <div className="grid grid--auto">
          {visibles.map((f, i) => (
            <Card
              key={f.patient.grant_id}
              patient={f.patient}
              o={f.o}
              alertas={f.alertas}
              hoy={hoy}
              // Las cartas entran escalonadas, como el resto del panel: un
              // fundido corto, y tope para que la vigésima no tarde.
              delay={Math.min(i, 8) * 30}
            />
          ))}
        </div>
      )}
    </>
  );
}

function normalizar(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();
}

function Card({
  patient: p,
  o,
  alertas,
  hoy,
  delay,
}: {
  patient: PatientRow;
  o: OverviewRow | null;
  alertas: Alerta[];
  hoy: string;
  delay: number;
}) {
  const ultima = o ? diasDesde(o.last_meal_date, hoy) : null;
  const peso = o ? cambioPeso30(o) : null;
  // Los denominadores salen de la ventana efectiva, como en la ficha: quien
  // empezó hace cuatro días registró 4 de 4, no 4 de 7. Ver `lib/tracking.ts`.
  const antiguedad = o?.tracking_since
    ? diasEntre(o.tracking_since.slice(0, 10), hoy) + 1
    : null;
  const de7 = antiguedad === null ? 7 : Math.max(Math.min(7, antiguedad), 0);
  const de14 = antiguedad === null ? 14 : Math.max(Math.min(14, antiguedad), 0);
  const pct =
    o?.avg_kcal_7 && o.target_kcal ? Math.round((o.avg_kcal_7 / o.target_kcal) * 100) : null;
  const sinLeer = o?.unread_feedback ?? 0;

  return (
    <Link
      href={`/paciente/${p.patient_id}`}
      className="card card-link plist plist--in"
      style={{ animationDelay: `${delay}ms` }}
    >
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h3>{p.patient_name || 'Sin nombre'}</h3>
        {p.birth_date && (
          <span className="caption tnum">{edad(p.birth_date)} años</span>
        )}
      </div>

      {alertas.length > 0 && (
        <div className="chips">
          {alertas.map((a) => (
            <span key={a.id} className={a.tono === 'atencion' ? 'chip chip--warn' : 'chip chip--on'}>
              {a.texto}
            </span>
          ))}
        </div>
      )}

      {o && (
        <dl className="team-stats">
          <div>
            <dt className="caption">Última comida</dt>
            <dd className="tnum">
              {ultima === null
                ? '—'
                : ultima === 0
                  ? 'hoy'
                  : ultima === 1
                    ? 'ayer'
                    : `hace ${ultima} días`}
            </dd>
          </div>
          <div>
            <dt className="caption">Días con comidas</dt>
            <dd className="tnum">
              {o.days_logged_7 ?? 0}
              <span className="muted"> de {de7}</span>
              <span className="caption"> · {o.days_logged_14 ?? 0} de {de14}</span>
            </dd>
          </div>
          <div>
            <dt className="caption">Calorías, últimos 7 días</dt>
            <dd className="tnum">
              {o.avg_kcal_7 ? `${miles(o.avg_kcal_7)} kcal` : '—'}
              {pct !== null && (
                <span
                  className="caption"
                  // El mismo ámbar del resto del panel para lo que pasó el
                  // objetivo, y nada para lo que quedó debajo: ni verde de
                  // logro ni rojo de alarma.
                  style={pct > 100 ? { color: 'var(--caution)' } : undefined}
                >
                  {' '}· {pct} % de {miles(o.target_kcal!)}
                </span>
              )}
            </dd>
          </div>
          <div>
            <dt className="caption">Peso, 30 días</dt>
            <dd className="tnum">{peso === null ? '—' : `${conSigno(peso)} kg`}</dd>
          </div>
          <div>
            <dt className="caption">Devoluciones</dt>
            <dd className="tnum">
              {sinLeer > 0 ? `${sinLeer} sin leer` : <span className="muted">al día</span>}
            </dd>
          </div>
        </dl>
      )}

      {p.expires_at && (
        <p className="caption" style={{ margin: 'auto 0 0' }}>
          El acceso vence el {fechaCorta(p.expires_at.slice(0, 10))}
        </p>
      )}
    </Link>
  );
}

function edad(birthDate: string): number {
  const nacimiento = new Date(birthDate);
  const hoy = new Date();
  let años = hoy.getFullYear() - nacimiento.getFullYear();
  const mes = hoy.getMonth() - nacimiento.getMonth();
  if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) años--;
  return años;
}
