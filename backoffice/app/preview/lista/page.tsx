/** El tablero del equipo con datos de ejemplo. **Solo en desarrollo**: ver
 *  `app/preview/page.tsx`. El análisis del equipo con IA se mudó a
 *  /organizacion el 15/11/2026. */
import { notFound } from 'next/navigation';
import { PatientsList, type PatientRow } from '@/components/patients-list';
import { haceISO, hoyISO } from '@/lib/format';
import type { OverviewRow } from '@/lib/team';

export const dynamic = 'force-dynamic';

const PACIENTES: PatientRow[] = [
  {
    grant_id: 'g1',
    patient_id: 'demo',
    patient_name: 'Ana Pérez',
    birth_date: '1989-04-12',
    share_meals: true,
    share_photos: true,
    share_body: true,
    share_wellbeing: true,
    expires_at: null,
  },
  {
    grant_id: 'g2',
    patient_id: 'demo2',
    patient_name: 'Bruno Gómez',
    birth_date: '1976-11-02',
    share_meals: true,
    share_photos: false,
    share_body: true,
    share_wellbeing: false,
    expires_at: null,
  },
  {
    grant_id: 'g3',
    patient_id: 'demo3',
    patient_name: 'Carla Suárez',
    birth_date: '2001-01-30',
    share_meals: false,
    share_photos: false,
    share_body: true,
    share_wellbeing: true,
    expires_at: '2026-12-31',
  },
  {
    grant_id: 'g4',
    patient_id: 'demo4',
    patient_name: 'Diego Ríos',
    birth_date: '1994-07-19',
    share_meals: true,
    share_photos: true,
    share_body: true,
    share_wellbeing: true,
    expires_at: null,
  },
];

function overview(): OverviewRow[] {
  const base = {
    share_photos: true,
    share_wellbeing: true,
    weight_first_30: null,
    weight_last_30: null,
    unread_feedback: 0,
  };
  return [
    {
      ...base,
      patient_id: 'demo',
      patient_name: 'Ana Pérez',
      share_meals: true,
      share_body: true,
      tracking_since: haceISO(80),
      last_meal_date: hoyISO(),
      days_logged_7: 6,
      days_logged_14: 12,
      avg_kcal_7: 2290,
      target_kcal: 2000,
      weight_first_30: 78.4,
      weight_last_30: 77.2,
      unread_feedback: 1,
    },
    {
      ...base,
      patient_id: 'demo2',
      patient_name: 'Bruno Gómez',
      share_meals: true,
      share_body: true,
      share_wellbeing: false,
      tracking_since: haceISO(40),
      last_meal_date: haceISO(5),
      days_logged_7: 2,
      days_logged_14: 6,
      avg_kcal_7: 1400,
      target_kcal: 2200,
    },
    {
      ...base,
      patient_id: 'demo3',
      patient_name: 'Carla Suárez',
      share_meals: false,
      share_body: true,
      tracking_since: haceISO(20),
      last_meal_date: null,
      days_logged_7: null,
      days_logged_14: null,
      avg_kcal_7: null,
      target_kcal: null,
      weight_first_30: 61,
      weight_last_30: 61.4,
    },
    {
      ...base,
      patient_id: 'demo4',
      patient_name: 'Diego Ríos',
      share_meals: true,
      share_body: true,
      tracking_since: haceISO(4),
      last_meal_date: haceISO(1),
      days_logged_7: 4,
      days_logged_14: 4,
      avg_kcal_7: 1950,
      target_kcal: 2100,
    },
  ];
}

export default async function PreviewLista() {
  // Solo en desarrollo, por lo mismo que `app/preview/page.tsx`.
  if (process.env.NODE_ENV === 'production') notFound();

  return (
    <PatientsList
      patients={PACIENTES}
      overview={overview()}
      hoy={hoyISO()}
      plan="pro"
      hasOrg
    />
  );
}
