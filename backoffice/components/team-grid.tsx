'use client';

import Link from 'next/link';
import { useState } from 'react';
import { conSigno, diasEntre, fechaCorta, horas, miles, num } from '@/lib/format';
import { cambioPeso30, diasDesde, type Alerta, type OverviewRow } from '@/lib/team';
import type { PatientRow } from '@/components/patients-list';

export type FilaEquipo = {
  patient: PatientRow;
  o: OverviewRow | null;
  nombre: string;
  alertas: Alerta[];
  /** URL firmada de la foto de perfil, o `null` para mostrar iniciales. */
  avatar?: string | null;
};

/**
 * La grilla del equipo, en el orden en que llega (por nombre).
 *
 * Sin buscador ni selector de orden desde el 15/11/2026: la lista es estable
 * y cada ficha dice lo suyo.
 */
export function TeamGrid({ filas, hoy }: { filas: FilaEquipo[]; hoy: string }) {
  return (
    <div className="grid grid--auto">
      {filas.map((f, i) => (
        <Card
          key={f.patient.grant_id}
          patient={f.patient}
          o={f.o}
          alertas={f.alertas}
          avatar={f.avatar ?? null}
          hoy={hoy}
          // Las cartas entran escalonadas, como el resto del panel: un
          // fundido corto, y tope para que la vigésima no tarde.
          delay={Math.min(i, 8) * 30}
        />
      ))}
    </div>
  );
}

/**
 * La foto de perfil, o las iniciales si no hay (o si la URL firmada falla al
 * cargar: venció la hora, o la foto se borró desde que se armó la página).
 */
export function Avatar({ nombre, src }: { nombre: string; src: string | null }) {
  const [rota, setRota] = useState(false);
  if (src && !rota) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- URL firmada de Supabase, sin optimizador
      <img className="avatar" src={src} alt="" onError={() => setRota(true)} />
    );
  }
  return (
    <span className="avatar avatar--iniciales" aria-hidden="true">
      {iniciales(nombre)}
    </span>
  );
}

function iniciales(nombre: string): string {
  const partes = nombre.trim().split(/\s+/).filter(Boolean);
  if (partes.length === 0) return '?';
  const a = partes[0][0] ?? '';
  const b = partes.length > 1 ? partes[partes.length - 1][0] ?? '' : '';
  return (a + b).toUpperCase();
}

function Card({
  patient: p,
  o,
  alertas,
  avatar,
  hoy,
  delay,
}: {
  patient: PatientRow;
  o: OverviewRow | null;
  alertas: Alerta[];
  avatar: string | null;
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
  // Una base sin la migración 59 no trae las columnas: el bloque no aparece,
  // en vez de decir "no comparte" de alguien que sí comparte.
  const bienestar = o !== null && o.activity_sessions_7 !== undefined;

  return (
    <Link
      href={`/paciente/${p.patient_id}`}
      className="card card-link plist plist--in"
      style={{ animationDelay: `${delay}ms` }}
    >
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div className="row plist-nombre">
          <Avatar nombre={p.patient_name || 'Sin nombre'} src={avatar} />
          <h3>{p.patient_name || 'Sin nombre'}</h3>
        </div>
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
          {bienestar && <Bienestar o={o} />}
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

/**
 * Actividad, descanso, agua y sueño de los últimos 7 días (migración 59).
 *
 * Van debajo de una línea porque son otra pregunta —cómo vive la semana, no
 * cuánto come—, y cada uno dice cuántos días tuvieron registro: "7 h por
 * noche" sobre dos noches no es lo mismo que sobre siete. Lo que no se cargó
 * se dice así, sin un cero que se lea como "no durmió".
 */
function Bienestar({ o }: { o: OverviewRow }) {
  if (!o.share_wellbeing) {
    return (
      <div className="team-stats-full team-stats-sep">
        <dt className="caption">Actividad, descanso, agua y sueño</dt>
        <dd className="muted">No los comparte</dd>
      </div>
    );
  }
  const sesiones = o.activity_sessions_7 ?? 0;
  const minutos = o.activity_minutes_7 ?? 0;
  const descansos = o.rest_days_7 ?? 0;
  const agua = o.water_avg_7 === null || o.water_avg_7 === undefined ? null : Number(o.water_avg_7);
  const sueno = o.sleep_avg_7 ?? null;
  const sinDatos = <span className="muted">sin registros</span>;

  return (
    <>
      <div className="team-stats-sep">
        <dt className="caption">Actividad, 7 días</dt>
        <dd className="tnum">
          {sesiones === 0 ? (
            sinDatos
          ) : (
            <>
              {sesiones} {sesiones === 1 ? 'sesión' : 'sesiones'}
              <span className="caption"> · {horas(minutos)}</span>
            </>
          )}
        </dd>
      </div>
      <div className="team-stats-sep">
        <dt className="caption">Días de descanso</dt>
        <dd className="tnum">
          {descansos === 0 ? (
            <span className="muted">ninguno</span>
          ) : (
            `${descansos} ${descansos === 1 ? 'día' : 'días'}`
          )}
        </dd>
      </div>
      <div>
        <dt className="caption">Agua, por día</dt>
        <dd className="tnum">
          {agua === null ? (
            sinDatos
          ) : (
            <>
              {num(agua)} {agua === 1 ? 'vaso' : 'vasos'}
              <span className="caption"> · {o.water_days_7 ?? 0} de 7 días</span>
            </>
          )}
        </dd>
      </div>
      <div>
        <dt className="caption">Sueño, por noche</dt>
        <dd className="tnum">
          {sueno === null ? (
            sinDatos
          ) : (
            <>
              {horas(sueno)}
              <span className="caption"> · {o.sleep_days_7 ?? 0} de 7 noches</span>
            </>
          )}
        </dd>
      </div>
    </>
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
