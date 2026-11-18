import { serverClient } from '@/lib/supabase';
import { hoyISO } from '@/lib/format';
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
 * Seis pedidos en paralelo y ninguno por paciente: la lista (`care_patients`),
 * los números de todos (`care_overview()`), el plan, la organización, las
 * invitaciones y las bajas. Después, un solo pedido más para firmar todas las
 * fotos de perfil juntas. Uno por paciente sería una cascada que crece con la
 * cartera.
 *
 * Solo la lista es imprescindible. Si fallan los números, la lista se muestra
 * sin ellos; si falla el plan o la organización, no aparecen la etiqueta ni el
 * enlace; si fallan las fotos, van las iniciales. Lo que no se hace es mostrar
 * un cero donde hubo un error: los números ausentes se dicen ausentes.
 *
 * La lista de pacientes (/pacientes). La portada es la organización desde el
 * 15/11/2026, y el análisis del equipo con IA vive ahí.
 */
export default async function PatientsPage() {
  const supabase = await serverClient();

  // Las rechazadas se muestran dos semanas; las pendientes, siempre.
  const dosSemanas = new Date(Date.now() - 14 * 86_400_000).toISOString();

  const [lista, overview, plan, org, invites, discharged] = await Promise.all([
    supabase
      .from('care_patients')
      .select(
        'grant_id, patient_id, patient_name, birth_date, share_meals, ' +
          'share_photos, share_body, share_wellbeing, expires_at, avatar_path',
      )
      .order('patient_name'),
    supabase.rpc('care_overview'),
    supabase.rpc('effective_plan'),
    supabase.rpc('my_organization'),
    supabase
      .from('care_invites')
      .select('id, email, status, created_at, responded_at, patient_name, intake')
      .or(`status.eq.pending,and(status.eq.declined,responded_at.gte.${dosSemanas})`)
      .order('created_at', { ascending: false }),
    supabase.rpc('care_discharged'),
  ]);

  const patients = (lista.data ?? []) as unknown as PatientRow[];
  const avatars = await firmarAvatares(supabase, patients);

  return (
    <PatientsList
      patients={patients}
      overview={overview.error ? null : ((overview.data ?? []) as OverviewRow[])}
      hoy={hoyISO()}
      error={!!lista.error}
      plan={typeof plan.data === 'string' ? plan.data : null}
      hasOrg={!org.error && Array.isArray(org.data) && org.data.length > 0}
      avatars={avatars}
      invites={invites.error ? [] : ((invites.data ?? []) as CareInvite[])}
      discharged={discharged.error ? [] : ((discharged.data ?? []) as DischargedRow[])}
    />
  );
}

/**
 * patient_id → URL firmada de su foto de perfil, en un solo pedido.
 *
 * La política de Storage (migración 58) deja leer solo la foto de perfil de
 * un paciente vinculado; una foto que todavía no subió (la ruta es del
 * teléfono) o una firma que falla quedan afuera y la tarjeta muestra las
 * iniciales.
 */
async function firmarAvatares(
  supabase: Awaited<ReturnType<typeof serverClient>>,
  patients: PatientRow[],
): Promise<Record<string, string>> {
  const conFoto = patients.filter(
    (p) => p.avatar_path && p.avatar_path.split('/').length === 2,
  );
  if (conFoto.length === 0) return {};
  try {
    const { data, error } = await supabase.storage
      .from('progress-photos')
      .createSignedUrls(
        conFoto.map((p) => p.avatar_path!),
        60 * 60,
      );
    if (error || !data) return {};
    const porRuta = new Map(
      data.filter((d) => d.signedUrl && !d.error).map((d) => [d.path, d.signedUrl]),
    );
    return Object.fromEntries(
      conFoto
        .filter((p) => porRuta.has(p.avatar_path!))
        .map((p) => [p.patient_id, porRuta.get(p.avatar_path!)!]),
    );
  } catch {
    return {};
  }
}
