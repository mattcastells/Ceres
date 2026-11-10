import { notFound } from 'next/navigation';
import { PatientView } from '@/components/patient-view';
import { sampleData } from './sample';

/**
 * La ficha con datos de ejemplo, para mirar el diseño sin una sesión.
 *
 * **Solo existe en desarrollo.** En una build de producción esto es un 404, y
 * eso es a propósito y no una precaución de más: una ruta sin autenticación en
 * un panel clínico es una ruta sin autenticación en un panel clínico, aunque lo
 * que muestre sean datos inventados. Hoy no filtra nada porque `sampleData` no
 * consulta la base; el problema es que el día que alguien la use para depurar
 * "con datos reales", ya está desplegada y abierta.
 *
 * El guard va acá **y** en el `matcher` del middleware: uno cierra la puerta y
 * el otro es el que la deja abierta en desarrollo, y separarlos es lo que
 * permite que sacar el segundo no habilite nada.
 *
 * `?medio=1` arranca la cuenta a mitad del período, que es el caso en el que se
 * ve si los denominadores respetan la ventana efectiva. Ver `lib/tracking.ts`.
 * `?vacio=1` saca el informe y las devoluciones de ejemplo, para mirar cómo se
 * ven esas pestañas la primera vez.
 */
export const dynamic = 'force-dynamic';

export default async function PreviewPage({
  searchParams,
}: {
  searchParams: Promise<{ t?: string; dias?: string; medio?: string; vacio?: string }>;
}) {
  if (process.env.NODE_ENV === 'production') notFound();
  const { t, dias, medio, vacio } = await searchParams;
  const data = sampleData(Number(dias) || 30, medio === '1');
  return (
    <PatientView
      tab={t}
      data={vacio === '1' ? { ...data, report: null, feedback: [] } : data}
    />
  );
}
