import Link from 'next/link';
import { redirect } from 'next/navigation';
import { serverClient } from '@/lib/supabase';
import { OrgView, type OrgRow } from '@/components/org-view';
import { TeamReport } from '@/components/team-report';
import type { OrgPatientRow } from '@/lib/org';
import { fetchLatestReport, type CareReport } from '@/lib/queries';
import { hoyISO } from '@/lib/format';

export const dynamic = 'force-dynamic';

/**
 * La portada: la organización de quien mira (desde el 15/11/2026; antes la
 * portada era la lista de pacientes, que pasó a /pacientes).
 *
 * Una profesional que no es parte de ninguna organización va directo a sus
 * pacientes: una portada vacía no le sirve de nada.
 */
export default async function OrganizacionPage() {
  const supabase = await serverClient();
  // `org_patients()` devuelve vacío a quien no administra: la vista decide
  // por el rol, no por si llegaron filas.
  const { data: auth } = await supabase.auth.getUser();
  // El análisis con IA es de los pacientes **propios** de quien mira (lo que
  // devuelve `care_overview()`), no de todo el consultorio: por eso los
  // nombres salen de `care_patients` y no de `org_patients()`.
  const [{ data, error }, pacientes, propios, plan, teamReport] = await Promise.all([
    supabase.rpc('my_organization'),
    supabase.rpc('org_patients'),
    supabase.from('care_patients').select('patient_id, patient_name'),
    supabase.rpc('effective_plan'),
    auth.user
      ? fetchLatestReport(supabase, auth.user.id, 'team', null).catch(
          (): CareReport | null => null,
        )
      : Promise.resolve(null),
  ]);
  const nombres = Object.fromEntries(
    ((propios.data ?? []) as { patient_id: string; patient_name: string | null }[]).map(
      (p) => [p.patient_id, p.patient_name || 'Sin nombre'],
    ),
  );

  const rows = (data ?? []) as OrgRow[];

  if (!error && rows.length === 0) redirect('/pacientes');
  if (error) {
    return (
      <main className="page">
        <p className="topbar-back caption">
          <Link href="/pacientes">← Pacientes</Link>
        </p>
        <h1 style={{ marginTop: 'var(--s4)' }}>Organización</h1>
        <div className="card" style={{ marginTop: 'var(--s5)' }}>
          <p style={{ margin: 0 }}>No pudimos traer los datos de la organización.</p>
          <pre className="error-detail">{error.message}</pre>
        </div>
      </main>
    );
  }

  const viewerId = auth.user?.id ?? null;
  const rol = rows.find((r) => r.member_id === viewerId)?.member_role;
  const administra = rol === 'owner' || rol === 'admin';

  const lista = administra && !pacientes.error ? ((pacientes.data ?? []) as OrgPatientRow[]) : null;

  return (
    <OrgView
      rows={rows}
      viewerId={viewerId}
      pacientes={lista}
      hoy={hoyISO()}
      plan={typeof plan.data === 'string' ? plan.data : null}
      analisis={
        Object.keys(nombres).length > 0 ? (
          <TeamReport
            initial={teamReport}
            nombres={nombres}
            plan={typeof plan.data === 'string' ? plan.data : null}
            titulo={`Pacientes · ${lista ? lista.length : Object.keys(nombres).length}`}
          />
        ) : null
      }
    />
  );
}
