/** La organización con datos de ejemplo. **Solo en desarrollo**: ver
 *  `app/preview/page.tsx`. */
import { notFound } from 'next/navigation';
import { OrgView, type OrgRow } from '@/components/org-view';

export const dynamic = 'force-dynamic';

const ORG = { org_id: 'o1', org_name: 'Consultorio Nutrir', ai_monthly_quota: 1800, ai_used_month: 1132 };

const FILAS: OrgRow[] = [
  { ...ORG, member_id: 'm1', member_name: 'Natalia Ruiz', member_role: 'owner', member_patients: 14 },
  { ...ORG, member_id: 'm2', member_name: 'Laura Méndez', member_role: 'admin', member_patients: 9 },
  { ...ORG, member_id: 'm3', member_name: 'Sofía Paz', member_role: 'professional', member_patients: 11 },
];

export default function PreviewOrganizacion() {
  if (process.env.NODE_ENV === 'production') notFound();
  return <OrgView rows={FILAS} viewerId="m1" hoy="2026-11-14" />;
}
