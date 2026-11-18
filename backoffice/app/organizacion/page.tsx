import { redirect } from 'next/navigation';

/** La organización es la portada desde el 15/11/2026: los enlaces viejos a
 *  /organizacion caen ahí. */
export default function OrganizacionPage() {
  redirect('/');
}
