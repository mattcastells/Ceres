import { serverClient } from '@/lib/supabase';
import { hoyISO } from '@/lib/format';
import { fetchLatestReport, type CareReport } from '@/lib/queries';
import type { OverviewRow } from '@/lib/team';
import {
  PatientsList,
  type DischargedRow,
  type PatientRow,
} from '@/components/patients-list';
import type { CareInvite } from '@/components/invite-patient';

export const dynamic = 'force-dynamic';

/**
 * El tablero del equipo.
 *
 * Siete pedidos en paralelo y ninguno por paciente: la lista (`care_patients`),
 * los números de todos (`care_overview()`), el plan, la organización y el
 * último análisis del equipo. Uno por paciente sería una cascada que crece con
 * la cartera.
 *
 * Solo la lista es imprescindible. Si fallan los números, la lista se muestra
 * sin ellos; si falla el plan o la organización, no aparecen la etiqueta ni el
 * enlace; si falla el último análisis, se ofrece generar uno. Lo que no se hace
 * es mostrar un cero donde hubo un error: los números ausentes se dicen
 * ausentes.
 */
export default async function PatientsPage() {
  const supabase = await serverClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Las rechazadas se muestran dos semanas; las pendientes, siempre.
  const dosSemanas = new Date(Date.now() - 14 * 86_400_000).toISOString();

  const [lista, overview, plan, org, teamReport, invites, discharged] = await Promise.all([
    supabase
      .from('care_patients')
      .select(
        'grant_id, patient_id, patient_name, birth_date, share_meals, ' +
          'share_photos, share_body, share_wellbeing, expires_at',
      )
      .order('patient_name'),
    supabase.rpc('care_overview'),
    supabase.rpc('effective_plan'),
    supabase.rpc('my_organization'),
    user
      ? fetchLatestReport(supabase, user.id, 'team', null).catch(
          (): CareReport | null => null,
        )
      : Promise.resolve(null),
    supabase
      .from('care_invites')
      .select('id, email, status, created_at, responded_at')
      .or(`status.eq.pending,and(status.eq.declined,responded_at.gte.${dosSemanas})`)
      .order('created_at', { ascending: false }),
    supabase.rpc('care_discharged'),
  ]);

  const patients = (lista.data ?? []) as unknown as PatientRow[];

  return (
    <PatientsList
      patients={patients}
      overview={overview.error ? null : ((overview.data ?? []) as OverviewRow[])}
      hoy={hoyISO()}
      error={!!lista.error}
      plan={typeof plan.data === 'string' ? plan.data : null}
      hasOrg={!org.error && Array.isArray(org.data) && org.data.length > 0}
      teamReport={teamReport}
      invites={invites.error ? [] : ((invites.data ?? []) as CareInvite[])}
      discharged={discharged.error ? [] : ((discharged.data ?? []) as DischargedRow[])}
    />
  );
}
