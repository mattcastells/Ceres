import Link from 'next/link';
import { notFound } from 'next/navigation';
import { serverClient } from '@/lib/supabase';
import {
  fetchActivities,
  fetchAlcohol,
  fetchDayMarkers,
  fetchGoal,
  fetchMeals,
  fetchMeasurements,
  fetchSleep,
  fetchWater,
  fetchWeights,
  signPhotos,
} from '@/lib/queries';
import { ventanaEfectiva } from '@/lib/tracking';
import { hoyISO, haceISO } from '@/lib/format';
import {
  PatientView,
  type PatientProfile,
} from '@/components/patient-view';

export const dynamic = 'force-dynamic';

const RANGES: Record<string, number> = {
  '7': 7,
  '30': 30,
  '90': 90,
  '365': 365,
};

/**
 * Todo lo que la ficha necesita, pedido una sola vez.
 *
 * Acá solo se consulta: el armado de la pantalla es `PatientView`, que es una
 * función de los datos y no sabe de Supabase. Esa frontera es la que permite
 * mirar el diseño con datos de ejemplo sin duplicar la maqueta.
 *
 * Todo se pide junto y las cinco pestañas se renderizan de una. Cambiar de
 * pestaña no vuelve al servidor; cambiar el período sí, porque ahí cambian los
 * datos.
 */
export default async function PatientPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ dias?: string; t?: string }>;
}) {
  const { id } = await params;
  const { dias, t } = await searchParams;
  const days = RANGES[dias ?? '30'] ?? 30;

  const supabase = await serverClient();

  // La ficha sale de `care_patients`, que ya filtra por permiso vigente.
  const { data: row, error } = await supabase
    .from('care_patients')
    .select(
      'patient_id, patient_name, birth_date, height_cm, share_meals, ' +
        'share_photos, share_body, share_wellbeing, tracking_since',
    )
    .eq('patient_id', id)
    .maybeSingle();

  // ⚠️ "La consulta falló" y "no hay permiso" **no son lo mismo**, y esta línea
  // los confundía: se desestructuraba solo `data`, así que cualquier error
  // dejaba `row` en null y la ficha contestaba 404.
  //
  // Costó una tarde. El panel pedía `tracking_since`, la columna todavía no
  // estaba en el proyecto —las migraciones 40 a 44 estaban escritas y sin
  // aplicar—, PostgREST devolvía 42703, y la pantalla decía "esta persona no
  // existe". Es exactamente la trampa que `lib/queries.ts` ya tenía anotada
  // para `base_calorie_target`: **supabase-js no lanza**, devuelve el error en
  // el resultado, y quien no lo mira lo convierte en un vacío perfectamente
  // creíble.
  //
  // Ahora un fallo dice que es un fallo y con qué columna. El 404 queda para lo
  // único que significa: no hay permiso vigente sobre esa persona.
  if (error) return <ErrorDeCarga detalle={error.message} />;

  // Sin fila no hay acceso, y no se distingue de "no existe" a propósito: decir
  // "existe pero no podés verlo" ya cuenta algo sobre esa persona.
  if (!row) notFound();

  const p = row as unknown as PatientProfile;

  const to = hoyISO();
  // `days - 1` porque hoy cuenta: "últimos 7 días" son siete cuadrados en el
  // calendario y siete en "días con comidas de 7", no ocho.
  const from = haceISO(days - 1);

  const [
    meals,
    weights,
    water,
    activities,
    sleep,
    measurements,
    goal,
    markers,
    alcohol,
  ] = await Promise.all([
    p.share_meals ? fetchMeals(supabase, id, from, to) : [],
    p.share_body ? fetchWeights(supabase, id, from, to) : [],
    p.share_wellbeing ? fetchWater(supabase, id, from, to) : [],
    p.share_wellbeing ? fetchActivities(supabase, id, from, to) : [],
    p.share_wellbeing ? fetchSleep(supabase, id, from, to) : [],
    p.share_body ? fetchMeasurements(supabase, id, from, to) : [],
    p.share_meals ? fetchGoal(supabase, id) : null,
    // El contexto del día se abre con `wellbeing`, la misma llave que la
    // actividad, el agua y el sueño.
    p.share_wellbeing ? fetchDayMarkers(supabase, id, from, to) : [],
    p.share_wellbeing ? fetchAlcohol(supabase, id, from, to) : [],
  ]);

  const photoUrls = p.share_photos
    ? await signPhotos(
        supabase,
        meals.map((m) => m.photo_path).filter((x): x is string => !!x),
      )
    : {};

  return (
    <PatientView
      tab={t}
      data={{
        patient: p,
        days,
        from,
        to,
        // Se calcula acá, una sola vez, y baja armada: si cada métrica la
        // recalculara, la primera que se olvidara de hacerlo volvería a contar
        // como huecos los días anteriores a la cuenta y nadie lo notaría.
        // Ver `docs/contexto-diario.md`.
        ventana: ventanaEfectiva(from, to, p.tracking_since),
        meals,
        weights,
        water,
        activities,
        sleep,
        measurements,
        markers,
        alcohol,
        goal,
        photoUrls,
      }}
    />
  );
}

/**
 * Cuando la consulta falla, decirlo — y decir qué mirar.
 *
 * El caso real que la estrenó fue un esquema desactualizado: el panel pedía una
 * columna que el proyecto todavía no tenía. Con un 404 genérico eso se lee como
 * "el paciente no existe" y se busca el problema en el permiso, que es el lugar
 * equivocado. El mensaje de PostgREST (`column X does not exist`,
 * `Could not find the table Y`) señala el lugar correcto en una línea, así que
 * va a la vista en vez de quedarse solo en la consola del servidor.
 *
 * No filtra nada que la profesional no pueda ver: es el nombre de una columna
 * del esquema, no un dato de nadie.
 */
function ErrorDeCarga({ detalle }: { detalle: string }) {
  return (
    <div className="page">
      <p className="topbar-back caption">
        <Link href="/">← Pacientes</Link>
      </p>
      <h1 style={{ marginTop: 'var(--s4)' }}>No se pudo abrir la ficha</h1>
      <div className="card" style={{ marginTop: 'var(--s5)' }}>
        <p style={{ margin: 0 }}>
          La consulta a la base falló, así que no hay nada que mostrar. No es
          que esta persona te haya sacado el acceso: eso se vería distinto.
        </p>
        <p className="caption" style={{ marginTop: 'var(--s4)' }}>
          Si el mensaje habla de una columna o una tabla que no existe, al
          proyecto le faltan migraciones por aplicar.
        </p>
        <pre className="error-detail">{detalle}</pre>
      </div>
    </div>
  );
}
