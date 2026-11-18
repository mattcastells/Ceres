import Link from 'next/link';
import { SignOut } from '@/components/sign-out';
import { InvitePatient } from '@/components/invite-patient';

type Seccion = 'organizacion' | 'pacientes' | 'articulos';

const SECCIONES: { id: Seccion; href: string; label: string }[] = [
  { id: 'organizacion', href: '/', label: 'Organización' },
  { id: 'pacientes', href: '/pacientes', label: 'Pacientes' },
  { id: 'articulos', href: '/articulos', label: 'Artículos y recetas' },
];

/**
 * El menú de arriba, igual en las tres pantallas principales: las secciones
 * siempre en el mismo orden, con la actual marcada en vez de desaparecer, y
 * después Dar de alta y Salir.
 */
export function MainNav({
  actual,
  plan = null,
  conOrganizacion = true,
}: {
  actual: Seccion;
  plan?: string | null;
  /** Sin organización no hay portada: la sección no se ofrece. */
  conOrganizacion?: boolean;
}) {
  return (
    <nav className="row topbar-nav">
      {SECCIONES.filter((s) => conOrganizacion || s.id !== 'organizacion').map((s) => (
        <Link
          key={s.id}
          href={s.href}
          className="nav-link"
          aria-current={s.id === actual ? 'page' : undefined}
        >
          {s.label}
        </Link>
      ))}
      <InvitePatient plan={plan} />
      <SignOut />
    </nav>
  );
}
