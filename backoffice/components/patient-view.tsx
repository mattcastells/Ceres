import Link from 'next/link';
import {
  METRIC_LABEL,
  QUALITY_LABEL,
  TOPE_COMIDAS,
  type Activity,
  type AlcoholLog,
  type CareFeedback,
  type CareReport,
  type DayMarker,
  type Goal,
  type Meal,
  type Measurement,
  type SleepLog,
  type WaterLog,
  type WeightLog,
} from '@/lib/queries';
import {
  conSigno,
  dec,
  fechaCorta,
  horas,
  miles,
  num,
  rangoDeFechas,
} from '@/lib/format';
import type { Ventana } from '@/lib/tracking';
import { currentGoal, goalForDay, targetsByDay } from '@/lib/goals';
import {
  alimentosFrecuentes,
  balanceEnergetico,
  diasBajoBasal,
  horarios as calcularHorarios,
  semanas as calcularSemanas,
} from '@/lib/analysis';
import {
  BalanceCard,
  FrecuentesTable,
  HorariosStrip,
  SemanasTable,
} from '@/components/consult-analysis';
import { FeedbackPanel } from '@/components/feedback-panel';
import { AiReport } from '@/components/ai-report';
import { WeightChart } from '@/components/weight-chart';
import { CaloriesChart } from '@/components/calories-chart';
import { BarChart, type Point } from '@/components/bar-chart';
import { DayCalendar } from '@/components/day-calendar';
import { DayModalProvider } from '@/components/day-modal';
import { VASOS_META, type DayBundle } from '@/components/day-detail';
import { SlotSplit } from '@/components/slot-split';
import { MacroSplit } from '@/components/macro-split';
import { PhotoGallery } from '@/components/photo-gallery';
import { MeasureCard } from '@/components/measure-card';
import { Kpi, KpiRow, Stat, StatRow, Section } from '@/components/stat';
import { Spark } from '@/components/spark';
import { RangePicker } from '@/components/range-picker';
import { SignOut } from '@/components/sign-out';
import { Tabs, type Tab } from '@/components/tabs';

export type PatientProfile = {
  patient_id: string;
  patient_name: string | null;
  birth_date: string | null;
  height_cm: number | null;
  share_meals: boolean;
  share_photos: boolean;
  share_body: boolean;
  share_wellbeing: boolean;
  /** El primer día del que hay algo cargado. Lo calcula `public.tracking_since`. */
  tracking_since: string | null;
};

export type PatientData = {
  patient: PatientProfile;
  days: number;
  from: string;
  to: string;
  /** El período efectivo, ya calculado en la página. Ver `lib/tracking.ts`. */
  ventana: Ventana;
  meals: Meal[];
  weights: WeightLog[];
  water: WaterLog[];
  activities: Activity[];
  sleep: SleepLog[];
  measurements: Measurement[];
  markers: DayMarker[];
  alcohol: AlcoholLog[];
  /** Los objetivos vigentes en algún día del período, del más viejo al más
   *  nuevo. Cada día se compara con el suyo: ver `lib/goals.ts`. */
  goals: Goal[];
  photoUrls: Record<string, string>;
  /** Las comidas llegaron a `TOPE_COMIDAS` y puede haber más. */
  mealsTruncated?: boolean;
  /** Lo que esta profesional le escribió a este paciente. */
  feedback: CareFeedback[];
  /** El último informe de consulta guardado, si hay. */
  report: CareReport | null;
  /** `effective_plan()` de quien mira; `null` si no se pudo saber. */
  plan: string | null;
  /** El id de quien mira: es el `author_id` de lo que escribe. */
  viewerId: string;
};

/**
 * La ficha de un paciente, en ocho pestañas.
 *
 * Es una función pura de los datos: no consulta nada. Quien la usa —la página—
 * es quien pide, y por eso esta vista se puede renderizar con datos de ejemplo
 * para mirar el diseño sin una sesión. Lo que se mira ahí es el componente que
 * se despliega, no una maqueta parecida que se desincroniza al primer cambio.
 *
 * Las pestañas son las cuatro categorías que el paciente concede —comidas,
 * fotos, cuerpo, hábitos— más el resumen, el día a día, y las dos que son de la
 * profesional: el informe con IA y las devoluciones. Las de categoría no son
 * una división de diseño: es la misma división con la que se dio el permiso,
 * así que "esta pestaña está apagada" y "esto no me lo compartieron" son la
 * misma frase. Las dos nuevas no tienen punto ámbar porque no dependen de una
 * categoría: lo que escribe la profesional es suyo.
 */
export function PatientView({ data, tab }: { data: PatientData; tab?: string }) {
  const {
    patient: p,
    days,
    from,
    to,
    ventana,
    meals,
    weights,
    activities,
    measurements,
    goals,
    photoUrls,
  } = data;

  // ⚠️ Agua, sueño, contexto y alcohol se recortan a la ventana efectiva.
  //
  // `tracking_since` sale de comidas, actividad y peso (ver
  // `public.tracking_since`), así que alguien puede tener agua anotada antes de
  // su "primer día". Esas filas llegaban con el período entero y se contaban
  // contra los días de la ventana: la auditoría encontró "12 de 10 días" en el
  // agua. Contar sobre la ventana y mostrar filas de afuera son dos cosas que
  // no pueden convivir; se quedan las de adentro.
  const enVentana = <T extends { local_date: string }>(xs: T[]) =>
    xs.filter((x) => x.local_date >= ventana.desdeEfectivo);
  const water = enVentana(data.water);
  const sleep = enVentana(data.sleep);
  const markers = enVentana(data.markers);
  const alcohol = enVentana(data.alcohol);

  // El objetivo de la cabecera y de los macros es el vigente al final del
  // período; la comparación día por día usa el de cada día (`objetivos`).
  const goal = currentGoal(goals, to);
  const target = goal?.base_calorie_target ?? null;

  // ⚠️ Dos listas de fechas, y la diferencia importa.
  //
  // `fechas` es el **calendario** del período pedido, del más viejo al más
  // nuevo: de acá sale el orden de las series de los gráficos.
  //
  // `ventana.fechas` es lo que **se cuenta**: todo denominador sale de ahí.
  // Alguien que empezó el 18 registró 13 de 13 días, no 13 de 30. Ver
  // `docs/contexto-diario.md`.
  const fechas = rangoDeFechas(from, to);
  const diasEfectivos = ventana.dias;
  const porDia = new Map<string, Meal[]>();
  for (const m of meals) {
    porDia.set(m.local_date, [...(porDia.get(m.local_date) ?? []), m]);
  }

  const kcalPorDia = new Map<string, number>();
  for (const [fecha, delDia] of porDia) {
    kcalPorDia.set(
      fecha,
      delDia.reduce((a, m) => a + m.total_kcal, 0),
    );
  }

  const serieKcal: Point[] = fechas
    .filter((d) => kcalPorDia.has(d))
    .map((d) => ({ date: d, value: kcalPorDia.get(d) ?? 0 }));

  const diasConComida = serieKcal.length;
  const promedioKcal = diasConComida
    ? Math.round(serieKcal.reduce((a, x) => a + x.value, 0) / diasConComida)
    : 0;

  // Cada día contra **su** objetivo. Un día sin objetivo vigente no cuenta ni
  // como dentro ni como fuera: no hay contra qué compararlo.
  const objetivos = targetsByDay(goals, fechas);
  const conObjetivo = serieKcal.filter((x) => objetivos.get(x.date));
  const dentro = conObjetivo.filter((x) => x.value <= objetivos.get(x.date)!).length;
  const objetivoCambio =
    new Set(conObjetivo.map((x) => objetivos.get(x.date))).size > 1;
  // El objetivo "promedio" de los días con comida: contra eso se pone el
  // promedio de kcal cuando el objetivo cambió en el medio. Con uno solo es el
  // mismo número.
  const targetPromedio = conObjetivo.length
    ? Math.round(
        conObjetivo.reduce((a, x) => a + objetivos.get(x.date)!, 0) /
          conObjetivo.length,
      )
    : target;
  const serieCalorias = serieKcal.map((x) => ({
    date: x.date,
    kcal: x.value,
    target: objetivos.get(x.date) ?? null,
  }));

  const proteinaPorDia: Point[] = serieKcal.map((x) => ({
    date: x.date,
    value: (porDia.get(x.date) ?? []).reduce(
      (a, m) => a + Number(m.total_protein_g),
      0,
    ),
  }));

  const aguaPorDia: Point[] = water.map((w) => ({
    date: w.local_date,
    value: w.glasses,
  }));
  const suenoPorDia: Point[] = sleep.map((s) => ({
    date: s.local_date,
    value: s.minutes / 60,
  }));
  const actPorDia = agrupar(
    activities.map((a) => ({ date: a.local_date, value: a.duration_minutes })),
  );

  const ultimoPeso = weights.length
    ? Number(weights[weights.length - 1].weight_kg)
    : null;
  const deltaPeso =
    weights.length >= 2 ? ultimoPeso! - Number(weights[0].weight_kg) : null;

  // El IMC sale de dos datos que ya estaban en la ficha y no se cruzaban. Es
  // grueso —no distingue músculo de grasa— pero es el número con el que se
  // habla en una consulta, y calcularlo a mano mirando la pantalla es trabajo
  // que la pantalla puede hacer.
  const indice =
    ultimoPeso && p.height_cm ? ultimoPeso / Math.pow(p.height_cm / 100, 2) : null;

  const porMetrica = new Map<string, Measurement[]>();
  for (const m of measurements) {
    porMetrica.set(m.metric, [...(porMetrica.get(m.metric) ?? []), m]);
  }
  const cinturas = porMetrica.get('waist') ?? [];
  const ultimaCintura = cinturas.length
    ? Number(cinturas[cinturas.length - 1].value)
    : null;
  const cinturaAltura =
    ultimaCintura && p.height_cm ? ultimaCintura / p.height_cm : null;


  /* ── El contexto del día ───────────────────────────────────────────────
     Se indexa una sola vez y lo usan el día a día, los gráficos y el resumen.
     Con un `.filter()` adentro de cada fila, un año de historial recorre la
     lista entera trescientas sesenta y cinco veces. */
  const marcasPorDia = new Map<string, DayMarker[]>();
  for (const m of markers) {
    marcasPorDia.set(m.local_date, [
      ...(marcasPorDia.get(m.local_date) ?? []),
      m,
    ]);
  }

  const alcoholPorDia = new Map<string, AlcoholLog[]>();
  for (const a of alcohol) {
    alcoholPorDia.set(a.local_date, [
      ...(alcoholPorDia.get(a.local_date) ?? []),
      a,
    ]);
  }

  const enfermos = markers.filter((m) => m.kind === 'sick');
  const descansos = markers.filter((m) => m.kind === 'rest');

  const ubePorDia = new Map<string, number>();
  for (const a of alcohol) {
    ubePorDia.set(a.local_date, (ubePorDia.get(a.local_date) ?? 0) + a.std_drinks);
  }
  const diasConAlcohol = ubePorDia.size;
  const ubeTotal = [...ubePorDia.values()].reduce((acc, v) => acc + v, 0);
  const kcalAlcohol = alcohol.reduce((acc, a) => acc + a.kcal, 0);

  // Las semanas del período, para poner las UBE contra el umbral semanal —que
  // es como está escrito en las guías— y no contra un total que crece con el
  // período elegido y no se puede comparar con nada.
  const semanas = diasEfectivos > 0 ? diasEfectivos / 7 : 0;
  const ubePorSemana = semanas > 0 ? ubeTotal / semanas : 0;

  /* ── Cada día con algo, en una bolsa ─────────────────────────────────────
     Es lo que viaja al calendario del día a día. Se indexa todo una vez y
     se arma una bolsa por día con registro; los días vacíos no viajan, los
     dibuja el calendario a partir del período. Un día marcado como enfermedad,
     o con alcohol, **es** un día con algo: si no entrara acá, el día que la
     persona estuvo en cama y no registró nada no se podría abrir, que es justo
     el día que hay que poder abrir para entender la semana. */
  const actividadPorDia = new Map<string, Activity[]>();
  for (const a of activities) {
    actividadPorDia.set(a.local_date, [
      ...(actividadPorDia.get(a.local_date) ?? []),
      a,
    ]);
  }
  const aguaPorFecha = new Map(water.map((w) => [w.local_date, w]));
  const suenoPorFecha = new Map(sleep.map((s) => [s.local_date, s]));

  const bolsas: DayBundle[] = fechas
    .filter(
      (d) =>
        porDia.has(d) ||
        actividadPorDia.has(d) ||
        aguaPorFecha.has(d) ||
        suenoPorFecha.has(d) ||
        marcasPorDia.has(d) ||
        alcoholPorDia.has(d),
    )
    .map((d) => ({
      date: d,
      meals: porDia.get(d) ?? [],
      activities: actividadPorDia.get(d) ?? [],
      water: aguaPorFecha.get(d) ?? null,
      sleep: suenoPorFecha.get(d) ?? null,
      markers: marcasPorDia.get(d) ?? [],
      alcohol: alcoholPorDia.get(d) ?? [],
      // El objetivo de ese día, para que la celda y el modal comparen contra
      // la meta que tenía entonces y no contra la de hoy.
      goal: goalForDay(goals, d),
    }));


  // Con el nombre de su pestaña: es la misma palabra que tiene el punto ámbar
  // arriba y la que el paciente ve en la app al elegir qué comparte.
  const apagadas = [
    !p.share_meals && 'Comidas',
    !p.share_photos && 'Fotos',
    !p.share_body && 'Cuerpo',
    !p.share_wellbeing && 'Hábitos',
  ].filter(Boolean) as string[];

  const header = (
    <div className="topbar-id">
      <div style={{ minWidth: 0 }}>
        <p className="topbar-back caption">
          <Link href="/">← Tu equipo</Link>
        </p>
        <h1>{p.patient_name || 'Sin nombre'}</h1>
        <p className="topbar-sub caption">
          {[
            p.birth_date ? `${edad(p.birth_date)} años` : null,
            p.height_cm ? `${Math.round(p.height_cm)} cm` : null,
            goal?.goal_type ? OBJETIVO[goal.goal_type] : null,
            target ? `objetivo ${miles(target)} kcal` : null,
          ]
            .filter(Boolean)
            .join(' · ')}
        </p>
      </div>

      <div className="row" style={{ flex: 'none' }}>
        <RangePicker current={String(days)} />
        <SignOut />
      </div>
    </div>
  );

  /* ── Los números que comparten el resumen y las pestañas ──────────── */
  const minutosTotales = activities.reduce((a, x) => a + x.duration_minutes, 0);
  const kcalActividad = activities.reduce(
    (a, x) => a + (x.estimated_calories ?? 0),
    0,
  );
  const minutosPorSemana = semanas > 0 ? minutosTotales / semanas : 0;
  const proteinaPromedio = diasConComida
    ? meals.reduce((a, m) => a + Number(m.total_protein_g), 0) / diasConComida
    : 0;
  const aguaPromedio = water.length
    ? water.reduce((a, w) => a + w.glasses, 0) / water.length
    : 0;
  const diasConOchoVasos = water.filter((w) => w.glasses >= VASOS_META).length;
  const suenoPromedioMin = sleep.length
    ? Math.round(sleep.reduce((a, s) => a + s.minutes, 0) / sleep.length)
    : 0;
  const nochesCortas = sleep.filter((s) => s.minutes < 6 * 60).length;

  /* ── Resumen ────────────────────────────────────────────────────────── */
  // El tablero. Pocas tarjetas y cada una dice tres cosas: el número, una línea
  // de contexto y una mini-visual. Antes eran dieciséis fichas de un número en
  // cuatro grupos, y había que leerlas todas para armarse la imagen; acá la
  // forma —si sube, si baja, si está salteado— está al lado del número. El
  // detalle de cada cosa sigue en su pestaña.
  //
  // Los números de contexto —enfermedad, alcohol— están siempre, también en
  // cero: una semana limpia tiene que distinguirse de una semana sin compartir.
  // Ver `docs/contexto-diario.md`.
  const ultimosCatorce = ventana.fechas.slice(-14);
  const pctObjetivo =
    targetPromedio && promedioKcal
      ? Math.round((promedioKcal / targetPromedio) * 100)
      : null;

  /* ── Análisis de consulta ─────────────────────────────────────────────
     Aritmética sobre lo que ya llegó, sin IA ni consultas nuevas. Ver
     `lib/analysis.ts` y `docs/panel-proximas-features.md`. Solo los días de
     la ventana efectiva: los anteriores no son días sin registro. */
  const kcalEnVentana = new Map(
    [...kcalPorDia].filter(([d]) => d >= ventana.desdeEfectivo),
  );
  const balance = p.share_meals
    ? balanceEnergetico({
        kcalPorDia: kcalEnVentana,
        goals,
        weights: p.share_body ? weights : [],
      })
    : null;
  const frecuentes = p.share_meals ? alimentosFrecuentes(meals) : [];
  const bajoBasal = p.share_meals
    ? diasBajoBasal(kcalEnVentana, goals)
    : { dias: [], basal: null };
  const horariosDelPeriodo = p.share_meals ? calcularHorarios(meals) : null;
  const semanasDelPeriodo = calcularSemanas({
    fechas: ventana.fechas,
    kcalPorDia,
    proteinaPorDia: new Map(proteinaPorDia.map((x) => [x.date, x.value])),
    minutosPorDia: new Map(actPorDia.map((x) => [x.date, x.value])),
    weights,
    diasEnfermedad: new Set(enfermos.map((m) => m.local_date)),
    diasConAlcohol: new Set(ubePorDia.keys()),
  });

  const avisoTope = data.mealsTruncated ? <AvisoTope /> : null;

  const resumen = (
    <>
      {avisoTope}
      <Section
        title="Resumen del período"
        hint={`Últimos ${days} días · del ${fechaCorta(from)} al ${fechaCorta(to)}`}
      >
        {(p.share_meals || p.share_body) && (
          <KpiRow>
            {p.share_meals && (
              <>
                <Kpi
                  label="Calorías por día"
                  value={promedioKcal ? miles(promedioKcal) : '—'}
                  unit="kcal"
                  sub={
                    targetPromedio
                      ? objetivoCambio
                        ? `el objetivo cambió en el período · ${dentro} de ${conObjetivo.length} días dentro del suyo`
                        : `objetivo ${miles(targetPromedio)} · ${dentro} de ${conObjetivo.length} días dentro`
                      : 'sin objetivo cargado'
                  }
                >
                  {/* La pista contra el objetivo: ámbar si el promedio lo pasa,
                      el mismo ámbar del gráfico. */}
                  {targetPromedio && pctObjetivo !== null ? (
                    <div className="kpi-track">
                      <div className="split-track" aria-hidden>
                        <div
                          className="split-fill"
                          style={{
                            width: `${Math.min(pctObjetivo, 100)}%`,
                            background:
                              pctObjetivo > 100
                                ? 'var(--chart-over)'
                                : 'var(--chart-intake)',
                          }}
                        />
                      </div>
                      <span
                        className="caption tnum"
                        style={
                          pctObjetivo > 100
                            ? { color: 'var(--caution)' }
                            : undefined
                        }
                      >
                        {pctObjetivo} %
                      </span>
                    </div>
                  ) : (
                    <Spark values={serieKcal.map((x) => x.value)} />
                  )}
                </Kpi>

                {/* El denominador es la ventana efectiva y no `days`: alguien
                    que empezó el 18 registró 13 de 13, no 13 de 30. Los puntos
                    son las dos últimas semanas, que es lo que se pregunta en la
                    consulta: "¿y estos días?". */}
                <Kpi
                  label="Días con comidas"
                  value={`${diasConComida}`}
                  unit={diasEfectivos > 0 ? `de ${diasEfectivos}` : undefined}
                  sub={
                    diasEfectivos === 0
                      ? 'sin registros todavía'
                      : diasConComida < diasEfectivos
                        ? `${diasEfectivos - diasConComida} sin registrar`
                        : 'completo'
                  }
                >
                  {ultimosCatorce.length > 0 && (
                    <div>
                      <div className="week-dots kpi-dots" aria-hidden>
                        {ultimosCatorce.map((d) => (
                          <span
                            key={d}
                            className="week-dot"
                            data-on={kcalPorDia.has(d) ? '1' : '0'}
                            title={`${fechaCorta(d)} · ${kcalPorDia.has(d) ? 'con comidas' : 'sin registro'}`}
                          />
                        ))}
                      </div>
                      <div className="caption tnum" style={{ marginTop: 4 }}>
                        últimos {ultimosCatorce.length} días
                      </div>
                    </div>
                  )}
                </Kpi>

                <Kpi
                  label="Proteínas por día"
                  value={diasConComida ? miles(proteinaPromedio) : '—'}
                  unit="g"
                  sub={
                    goal?.protein_g
                      ? `objetivo ${miles(goal.protein_g)} g · ${
                          proteinaPromedio
                            ? Math.round((proteinaPromedio / goal.protein_g) * 100)
                            : 0
                        } % del objetivo`
                      : 'sin objetivo cargado'
                  }
                >
                  <Spark
                    values={proteinaPorDia.map((x) => x.value)}
                    color="var(--chart-protein)"
                  />
                </Kpi>
              </>
            )}

            {p.share_body && (
              <Kpi
                label="Peso"
                value={ultimoPeso === null ? '—' : dec(ultimoPeso)}
                unit="kg"
                sub={
                  ultimoPeso === null
                    ? 'sin registros'
                    : [
                        deltaPeso !== null
                          ? `${conSigno(deltaPeso)} kg en el período`
                          : `${weights.length} pesaje`,
                        indice !== null
                          ? `IMC ${dec(indice)} · ${categoriaIMC(indice)}`
                          : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')
                }
              >
                <Spark
                  values={weights.map((w) => Number(w.weight_kg))}
                  kind="line"
                  color="var(--chart-weight)"
                />
              </Kpi>
            )}
          </KpiRow>
        )}

        {/* Un día por debajo del basal casi nunca es un día así: es un día a
            medio anotar. Se dice y no se saca del promedio (§6 de
            `docs/panel-proximas-features.md`). */}
        {bajoBasal.dias.length > 0 && bajoBasal.basal !== null && (
          <p className="caption" style={{ margin: 'var(--s3) 0 0' }}>
            {bajoBasal.dias.length}{' '}
            {bajoBasal.dias.length === 1 ? 'día registrado' : 'días registrados'} muy
            por debajo del basal ({miles(bajoBasal.basal)} kcal): suelen ser días a medio
            anotar. El promedio los incluye.
          </p>
        )}

        {p.share_wellbeing && (
          <KpiRow>
            <Kpi
              label="Actividad"
              value={miles(minutosPorSemana)}
              unit="min/sem"
              sub={`${actPorDia.length} de ${diasEfectivos} días · ${activities.length} ${activities.length === 1 ? 'sesión' : 'sesiones'} · ≈ ${miles(kcalActividad)} kcal`}
            >
              <Spark
                values={actPorDia.map((x) => x.value)}
                color="var(--chart-walking)"
              />
            </Kpi>
            <Kpi
              label="Agua"
              value={water.length ? dec(aguaPromedio) : '—'}
              unit="vasos/día"
              sub={
                water.length
                  ? `${water.length} ${water.length === 1 ? 'día' : 'días'} · llegó a ${VASOS_META} en ${diasConOchoVasos}`
                  : 'sin registros'
              }
            >
              <Spark
                values={aguaPorDia.map((x) => x.value)}
                color="var(--info)"
              />
            </Kpi>
            <Kpi
              label="Sueño"
              value={sleep.length ? horas(suenoPromedioMin) : '—'}
              sub={
                sleep.length
                  ? `${sleep.length} ${sleep.length === 1 ? 'noche' : 'noches'} · ${nochesCortas} de menos de 6 h`
                  : 'sin registros'
              }
            >
              <Spark
                values={suenoPorDia.map((x) => x.value)}
                color="var(--chart-weight)"
              />
            </Kpi>
            {/* Por semana y no el total: el umbral de las guías está escrito
                por semana, y un total crece con el período elegido y no se
                puede comparar con nada. Sin semáforo: la pantalla muestra
                distancias, no notas. */}
            <Kpi
              label="Alcohol y enfermedad"
              value={num(ubePorSemana)}
              unit="tragos/sem"
              sub={[
                `${diasConAlcohol} ${diasConAlcohol === 1 ? 'día' : 'días'} con alcohol`,
                `${enfermos.length} de enfermedad`,
                descansos.length
                  ? `${descansos.length} ${descansos.length === 1 ? 'descanso' : 'descansos'}`
                  : null,
              ]
                .filter(Boolean)
                .join(' · ')}
            >
              <Spark
                values={[...ubePorDia.entries()]
                  .sort((a, b) => a[0].localeCompare(b[0]))
                  .map(([, v]) => v)}
                color="var(--info)"
              />
            </Kpi>
          </KpiRow>
        )}
      </Section>

      {/* Las dos curvas que se miran primero, sin cambiar de pestaña. El
          detalle —macros, reparto, medidas— sigue estando en la suya: acá van
          las dos que contestan "¿cómo viene?" de un vistazo. Qué días quedaron
          cargados lo muestra el calendario del día a día. */}
      {(p.share_meals || p.share_body) && (
        <Section title="Cómo viene">
          <div className="grid grid--auto">
            {p.share_meals && (
              <div className="card">
                <h3>Calorías por día</h3>
                <div style={{ marginTop: 'var(--s3)' }}>
                  <CaloriesChart days={serieCalorias} target={target} />
                </div>
              </div>
            )}
            {p.share_body && (
              <div className="card">
                <h3>Peso</h3>
                <div style={{ marginTop: 'var(--s3)' }}>
                  <WeightChart logs={weights} />
                </div>
              </div>
            )}
          </div>
        </Section>
      )}

      {balance && (
        <Section
          title="¿Los números cierran?"
          hint="El déficit registrado contra la balanza. Es una estimación, no un diagnóstico."
        >
          <BalanceCard b={balance} shareBody={p.share_body} />
        </Section>
      )}

      {semanasDelPeriodo.length >= 2 && (
        <Section
          title="Semana contra semana"
          hint="De lunes a domingo."
        >
          <SemanasTable
            semanas={semanasDelPeriodo}
            shareMeals={p.share_meals}
            shareBody={p.share_body}
            shareWellbeing={p.share_wellbeing}
          />
        </Section>
      )}

      {apagadas.length > 0 && (
        <Section title="Lo que no está compartido">
          <div className="card">
            <p className="muted" style={{ margin: 0 }}>
              No comparte {enumerar(apagadas, 'ni')}. Se activa desde la app, en
              Perfil → Mi nutricionista.
            </p>
          </div>
        </Section>
      )}
    </>
  );

  /* ── Comidas ────────────────────────────────────────────────────────── */
  const comidas = !p.share_meals ? (
    <NoCompartido que="Las comidas" />
  ) : (
    <>
      {avisoTope}
      <Section
        title="Calorías por día"
        hint="Días con comidas. La línea punteada es el objetivo; en ámbar, los días que lo pasaron."
      >
        <div className="card">
          <CaloriesChart days={serieCalorias} target={target} />
        </div>
      </Section>

      {/* Lo que más se repite y a qué hora: las dos preguntas de consulta que
          antes se contestaban de memoria teniendo el dato medido. Ver
          `docs/panel-proximas-features.md` §2 y §3. */}
      <Section
        title="Lo que más se repite"
        hint="Los que aparecen dos veces o más en el período."
      >
        <FrecuentesTable items={frecuentes} />
      </Section>

      {horariosDelPeriodo && (
        <Section
          title="Horarios"
          hint="Un punto por comida; la raya va de la primera a la última del día."
        >
          <HorariosStrip h={horariosDelPeriodo} />
        </Section>
      )}

      <Section
        title="Cómo se compone el día"
        hint={`Promedio de ${diasConComida} ${diasConComida === 1 ? 'día' : 'días'} con comidas.`}
      >
        <div className="grid grid--auto grid--parejo">
          <div>
            <div className="section-header" style={{ marginTop: 0 }}>
              Macros
            </div>
            <MacroSplit
              meals={meals}
              diasConComida={diasConComida}
              goal={goal}
            />
          </div>
          <div>
            <div className="section-header" style={{ marginTop: 0 }}>
              Momento del día
            </div>
            <SlotSplit meals={meals} diasConComida={diasConComida} />
          </div>
        </div>
      </Section>

      <Section title="Proteínas por día">
        <div className="card">
          {/* Sin la raya del objetivo: el objetivo de proteína ya está en el
              cuadro de macros de arriba, y acá la raya quedaba muy por encima
              de todas las barras y aplastaba el gráfico contra el piso. */}
          <BarChart
            points={proteinaPorDia}
            unit="g"
            color="var(--chart-protein)"
            height={180}
          />
        </div>
      </Section>
    </>
  );

  /* ── Fotos ──────────────────────────────────────────────────────────── */

  // Se filtra acá, del lado del servidor: mandarle al navegador las comidas sin
  // foto para que las descarte sería pagar el peso de un año de tablas de
  // ítems para no dibujar ninguna.
  const conFoto = p.share_photos
    ? meals.filter((m) => m.photo_path && photoUrls[m.photo_path])
    : [];

  const fotos = !p.share_photos ? (
    <NoCompartido que="Las fotos" />
  ) : !p.share_meals ? (
    <Section title="Fotos">
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Las fotos se ven con las comidas, y Comidas no está compartida.
        </p>
      </div>
    </Section>
  ) : (
    <Section
      title="Fotos de las comidas"
      hint={
        conFoto.length
          ? `${conFoto.length} ${conFoto.length === 1 ? 'foto' : 'fotos'} en el período. Tocá una para ver el detalle.`
          : undefined
      }
    >
      <PhotoGallery meals={conFoto} photoUrls={photoUrls} />
    </Section>
  );

  /* ── Cuerpo ─────────────────────────────────────────────────────────── */
  const cuerpo = !p.share_body ? (
    <NoCompartido que="El peso y las medidas" />
  ) : (
    <>
      <Section
        title="Dónde está hoy"
        hint={`Último registro del período · ${weights.length} ${weights.length === 1 ? 'pesaje' : 'pesajes'}.`}
      >
        <StatRow>
          <Stat
            label="Peso"
            value={ultimoPeso === null ? '—' : dec(ultimoPeso)}
            unit="kg"
            caption={
              weights.length
                ? fechaCorta(weights[weights.length - 1].local_date)
                : 'sin registros'
            }
          />
          <Stat
            label="Variación en el período"
            value={deltaPeso === null ? '—' : conSigno(deltaPeso)}
            unit="kg"
            caption={
              weights.length >= 2
                ? `desde ${dec(Number(weights[0].weight_kg))} kg`
                : 'hace falta más de un pesaje'
            }
          />
          <Stat
            label="IMC"
            value={indice === null ? '—' : dec(indice)}
            caption={
              indice === null
                ? p.height_cm
                  ? 'sin peso cargado'
                  : 'falta la altura en el perfil'
                : categoriaIMC(indice)
            }
          />
          {/* Mejor indicador de riesgo cardiometabólico que el IMC y no
              confunde músculo con grasa (§5 de
              `docs/panel-proximas-features.md`). Sin color, como el IMC. La
              altura ya está en la cabecera. */}
          <Stat
            label="Cintura / altura"
            value={cinturaAltura === null ? '—' : dec(cinturaAltura, 2)}
            caption={
              cinturaAltura !== null
                ? 'referencia: 0,5'
                : p.height_cm
                  ? 'sin cintura cargada'
                  : 'falta la altura en el perfil'
            }
          />
        </StatRow>
      </Section>

      <Section
        title="Peso"
        hint="Un punto por pesaje; la línea es la media móvil de 7 días."
      >
        <div className="card">
          <WeightChart logs={weights} />
        </div>
      </Section>

      <Section
        title="Medidas corporales"
        hint="Perímetros y bioimpedancia (estimada: varía con la hidratación)."
      >
        {porMetrica.size === 0 ? (
          <div className="card">
            <p className="muted" style={{ margin: 0 }}>
              Sin medidas cargadas en este período.
            </p>
          </div>
        ) : (
          <div className="grid grid--3">
            {[...porMetrica.entries()].map(([metric, serie]) => (
              <MeasureCard
                key={metric}
                title={METRIC_LABEL[metric] ?? metric}
                unit={serie[0].unit === 'pct' ? '%' : 'cm'}
                points={serie.map((s) => ({
                  date: s.local_date,
                  value: Number(s.value),
                }))}
              />
            ))}
          </div>
        )}
      </Section>
    </>
  );

  /* ── Hábitos ────────────────────────────────────────────────────────── */
  const habitos = !p.share_wellbeing ? (
    <NoCompartido que="La actividad, el agua, el sueño y el contexto del día" />
  ) : (
    <Section
      title="Actividad, agua, sueño y contexto"
      hint="Las calorías del ejercicio son una estimación por MET."
    >
      <div className="grid grid--3">
        <div className="card habito">
          <h3>Actividad</h3>
          <p className="caption">
            {actPorDia.length} de {diasEfectivos} días con movimiento ·{' '}
            {miles(minutosPorSemana)} min por semana
          </p>
          {/* Acá es donde el contexto vale más: el hueco de actividad es el que
              más se parece a abandono y el que más seguido tiene una
              explicación. Las bandas van al pie del gráfico, no como color de
              la barra: un día de enfermedad con 20 minutos de caminata sigue
              siendo 20 minutos. Ver `docs/contexto-diario.md`. */}
          <BarChart
            points={actPorDia}
            unit="min"
            color="var(--chart-walking)"
            height={150}
            sickDays={enfermos.map((m) => m.local_date)}
            drinkDays={[...ubePorDia.keys()]}
          />
          {(enfermos.length > 0 || diasConAlcohol > 0) && (
            <p className="caption chart-legend">
              {enfermos.length > 0 && (
                <span>
                  <i className="swatch swatch--sick" /> día de enfermedad
                </span>
              )}
              {diasConAlcohol > 0 && (
                <span>
                  <i className="swatch swatch--drink" /> con alcohol
                </span>
              )}
            </p>
          )}
          <dl className="habito-pie">
            <div>
              <dt className="caption">Sesiones</dt>
              <dd className="tnum">{activities.length}</dd>
            </div>
            <div>
              <dt className="caption">Total</dt>
              <dd className="tnum">{miles(minutosTotales)} min</dd>
            </div>
            <div>
              <dt className="caption">Por sesión</dt>
              <dd className="tnum">
                {activities.length
                  ? `${miles(minutosTotales / activities.length)} min`
                  : '—'}
              </dd>
            </div>
            <div>
              <dt className="caption">Gasto estimado</dt>
              {/* En ámbar y con el "≈", como en la app: una estimación por MET
                  no se presenta con la misma cara que una medición. */}
              <dd className="tnum estimate">≈ {miles(kcalActividad)} kcal</dd>
            </div>
          </dl>
          {/* La intensidad se guardaba por sesión y no se veía en ningún lado:
              veinte caminatas y veinte sesiones intensas suman los mismos
              minutos y no son el mismo plan. */}
          {activities.length > 0 && (
            <div className="habito-chips">
              <div className="caption">Intensidad</div>
              <div className="chips" style={{ marginTop: 'var(--s2)' }}>
                {intensidades(activities).map(([k, n]) => (
                  <span key={k} className="chip chip--on tnum">
                    {INTENSIDAD[k] ?? k} · {n}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="card habito">
          <h3>Agua</h3>
          <p className="caption">
            {water.length ? `${dec(aguaPromedio)} vasos por día` : 'sin registros'}
          </p>
          <BarChart
            points={aguaPorDia}
            unit="vasos"
            color="var(--info)"
            height={150}
          />
          <dl className="habito-pie">
            <div>
              <dt className="caption">Días registrados</dt>
              <dd className="tnum">
                {water.length} de {diasEfectivos}
              </dd>
            </div>
            <div>
              <dt className="caption">Llegó a {VASOS_META} vasos</dt>
              <dd className="tnum">{diasConOchoVasos} días</dd>
            </div>
            <div>
              <dt className="caption">Menos de 4 vasos</dt>
              <dd className="tnum">
                {water.filter((w) => w.glasses < 4).length} días
              </dd>
            </div>
            <div>
              <dt className="caption">Máximo</dt>
              <dd className="tnum">
                {water.length
                  ? `${Math.max(...water.map((w) => w.glasses))} vasos`
                  : '—'}
              </dd>
            </div>
          </dl>
        </div>

        <div className="card habito">
          <h3>Sueño</h3>
          <p className="caption">
            {sleep.length ? `${horas(suenoPromedioMin)} por noche` : 'sin registros'}
          </p>
          <BarChart
            points={suenoPorDia}
            unit="h"
            color="var(--chart-weight)"
            height={150}
            decimals={1}
          />
          <dl className="habito-pie">
            <div>
              <dt className="caption">Noches</dt>
              <dd className="tnum">
                {sleep.length} de {diasEfectivos}
              </dd>
            </div>
            <div>
              <dt className="caption">Menos de 6 h</dt>
              <dd className="tnum">{nochesCortas} noches</dd>
            </div>
            <div>
              <dt className="caption">Más corta</dt>
              <dd className="tnum">
                {sleep.length
                  ? horas(Math.min(...sleep.map((s) => s.minutes)))
                  : '—'}
              </dd>
            </div>
            <div>
              <dt className="caption">Más larga</dt>
              <dd className="tnum">
                {sleep.length
                  ? horas(Math.max(...sleep.map((s) => s.minutes)))
                  : '—'}
              </dd>
            </div>
          </dl>
          {/* La calidad se guardaba y no se mostraba en ningún resumen: siete
              horas de sueño malo y siete de sueño bueno son dos cosas
              distintas, y era el único dato del que solo se veía la duración. */}
          {sleep.length > 0 && (
            <div className="habito-chips">
              <div className="caption">Cómo lo calificó</div>
              <div className="chips" style={{ marginTop: 'var(--s2)' }}>
                {calidades(sleep).map(([q, n]) => (
                  <span key={q} className="chip chip--on tnum">
                    {QUALITY_LABEL[q] ?? q} · {n}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>

      </div>

      {/* El contexto —enfermedad, descansos, alcohol— va como una franja debajo
          de las tres cartas y no como una cuarta carta: una carta de la misma
          altura que las otras, con un período sin nada que contar, era un
          cuadro vacío con una frase en el medio. La franja mide lo que tiene
          que decir: los números siempre, y el gráfico de tragos por día solo
          si hubo alcohol. Los días de enfermedad ya están como banda en el
          gráfico de actividad, que es donde explican algo. */}
      <div className="card contexto">
        <dl className="habito-pie contexto-datos">
          <div>
            <dt className="caption">Enfermedad</dt>
            <dd className="tnum">
              {enfermos.length} {enfermos.length === 1 ? 'día' : 'días'}
            </dd>
            <dd className="caption">
              {enfermos.length ? resumenEnfermedad(enfermos) : 'ninguno'}
            </dd>
          </div>
          <div>
            <dt className="caption">Descansos planificados</dt>
            <dd className="tnum">{descansos.length}</dd>
            <dd className="caption">
              {descansos.length ? 'marcados como descanso' : 'ninguno'}
            </dd>
          </div>
          <div>
            <dt className="caption">Días con alcohol</dt>
            <dd className="tnum">
              {diasConAlcohol}
              {diasEfectivos > 0 && (
                <span className="muted"> de {diasEfectivos}</span>
              )}
            </dd>
            <dd className="caption">
              {diasConAlcohol ? `${num(ubeTotal)} tragos en total` : 'ninguno'}
            </dd>
          </div>
          <div>
            <dt className="caption">Tragos por semana</dt>
            <dd className="tnum">{num(ubePorSemana)}</dd>
            <dd className="caption">referencia: hasta 9–14 según sexo</dd>
          </div>
          <div>
            <dt className="caption">Calorías del alcohol</dt>
            <dd className="tnum estimate">≈ {miles(kcalAlcohol)} kcal</dd>
            <dd className="caption">aparte de las comidas</dd>
          </div>
        </dl>

        {diasConAlcohol > 0 && (
          <div className="contexto-grafico">
            <div className="caption" style={{ marginBottom: 'var(--s2)' }}>
              Tragos por día
            </div>
            <BarChart
              points={[...ubePorDia.entries()]
                .map(([date, value]) => ({ date, value }))
                .sort((a, b) => a.date.localeCompare(b.date))}
              unit="tragos"
              color="var(--info)"
              height={120}
              decimals={1}
            />
          </div>
        )}
      </div>
    </Section>
  );

  /* ── Día a día ──────────────────────────────────────────────────────── */
  const diario = (
    <>
    {avisoTope}
    <Section
      title="Día a día"
      hint="Tocá un día para ver el detalle."
    >
      {!p.share_meals && !p.share_wellbeing ? (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Nada compartido para mostrar acá.
          </p>
        </div>
      ) : (
        <DayCalendar
          // El calendario arranca donde arrancó la persona, no donde arranca
          // el período: los días anteriores al primer registro no son huecos y
          // no se dibujan. Ver `lib/tracking.ts`.
          desde={ventana.vacia ? from : ventana.desdeEfectivo}
          hasta={to}
          hoy={to}
          dias={bolsas}
          targetKcal={target}
          shareMeals={p.share_meals}
          shareWellbeing={p.share_wellbeing}
        />
      )}
    </Section>
    </>
  );

  /* ── Informe con IA y devoluciones ─────────────────────────────────────
     Las dos pestañas que no son del paciente sino de la profesional: lo que
     prepara para la consulta y lo que le escribe de vuelta. Son islas de
     cliente porque escriben —son lo único que el panel escribe— y reciben ya
     cargado lo que estaba guardado, para no pagar un informe nuevo ni una
     consulta más por abrir la pestaña. */
  const informe = (
    <AiReport
      patientId={p.patient_id}
      patientName={p.patient_name}
      initial={data.report}
      plan={data.plan}
    />
  );

  const devoluciones = (
    <FeedbackPanel
      patientId={p.patient_id}
      authorId={data.viewerId}
      initial={data.feedback}
      hoy={to}
      plan={data.plan}
      objetivoActual={p.share_meals ? goal : null}
      conoceObjetivo={p.share_meals}
    />
  );

  // El orden es el de uso: lo que se mira primero en una consulta —el resumen,
  // el informe para prepararla, lo que se le escribe después—, luego el
  // calendario del día a día y los hábitos, y al final el detalle por
  // categoría. Las cuatro categorías del permiso siguen teniendo una pestaña
  // cada una, con su punto ámbar si no está compartida.
  const tabs: Tab[] = [
    { id: 'resumen', label: 'Resumen', content: resumen },
    { id: 'informe', label: 'Informe con IA', content: informe },
    { id: 'devoluciones', label: 'Devoluciones', content: devoluciones },
    { id: 'diario', label: 'Día a día', content: diario },
    {
      id: 'habitos',
      label: 'Hábitos',
      off: !p.share_wellbeing,
      content: habitos,
    },
    { id: 'comidas', label: 'Comidas', off: !p.share_meals, content: comidas },
    { id: 'fotos', label: 'Fotos', off: !p.share_photos, content: fotos },
    { id: 'cuerpo', label: 'Cuerpo', off: !p.share_body, content: cuerpo },
  ];

  // El provider del modal del día envuelve a toda la ficha: lo abren el
  // calendario y el gráfico de calorías, que son islas de cliente separadas.
  // Ver `components/day-modal.tsx`.
  return (
    <DayModalProvider
      dias={bolsas}
      targetKcal={target}
      goal={goal}
      photoUrls={photoUrls}
      shareMeals={p.share_meals}
      sharePhotos={p.share_photos}
      shareWellbeing={p.share_wellbeing}
    >
      <Tabs header={header} tabs={tabs} initial={tab ?? 'resumen'} />
    </DayModalProvider>
  );
}

const OBJETIVO: Record<string, string> = {
  lose: 'Bajar de peso',
  maintain: 'Mantener',
  gain: 'Subir de peso',
};

/** Las categorías de la OMS, con el nombre con el que se habla en consulta.
 *
 *  Va como aclaración del número y no como color: el IMC no distingue músculo
 *  de grasa, y pintar de rojo un 26 de alguien que entrena sería un diagnóstico
 *  que esta pantalla no está en condiciones de dar. */
function categoriaIMC(v: number): string {
  if (v < 18.5) return 'bajo peso';
  if (v < 25) return 'normal';
  if (v < 30) return 'sobrepeso';
  if (v < 35) return 'obesidad grado I';
  if (v < 40) return 'obesidad grado II';
  return 'obesidad grado III';
}

/** Las comidas llegaron al tope duro y puede haber más.
 *
 *  Va arriba de cada pestaña que cuenta comidas porque el tope existe para que
 *  un dato roto no baje la tabla entera, y un tope que corta en silencio es
 *  exactamente el corte de mil filas de PostgREST que la paginación vino a
 *  arreglar: promedios sobre lo que llegó, presentados como el período. */
function AvisoTope() {
  return (
    <div className="card aviso" role="status" style={{ marginTop: 'var(--s5)' }}>
      <strong>Se muestran las primeras {miles(TOPE_COMIDAS)} comidas del período.</strong>{' '}
      <span className="muted">
        Los promedios usan solo esas. Elegí un período más corto para verlo
        completo.
      </span>
    </div>
  );
}

function NoCompartido({ que }: { que: string }) {
  return (
    <Section title={que}>
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Esta categoría no está compartida. Se activa desde la app, en Perfil →
          Mi nutricionista.
        </p>
      </div>
    </Section>
  );
}

/** "2 seguidos · 12 y 13 de agosto" — de qué días se está hablando.
 *
 *  El número solo ("2 días") no alcanza: dos días sueltos en un mes y dos días
 *  pegados son dos cosas distintas, y la segunda es la que explica el hueco de
 *  la semana. */
function resumenEnfermedad(marcas: DayMarker[]): string {
  const fechas = marcas.map((m) => m.local_date).sort();
  const partes = fechas.slice(0, 3).map((f) => fechaCorta(f));
  const resto = fechas.length - 3;
  return resto > 0 ? `${partes.join(', ')} +${resto}` : partes.join(', ');
}

/** "a, b y c" — con la "y" del final, que es como se lee en castellano. */
function enumerar(items: string[], conjuncion: 'y' | 'ni' = 'y'): string {
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(', ')} ${conjuncion} ${items[items.length - 1]}`;
}

/** Cuántas noches de cada calidad, de la mejor a la peor.
 *
 *  El orden es el de la escala y no el de la cuenta: una lista ordenada por
 *  frecuencia cambia de orden entre pacientes y entre períodos, y entonces hay
 *  que leer las etiquetas para comparar dos fichas. */
const ESCALA_SUENO = ['great', 'good', 'ok', 'poor', 'bad'];

function calidades(sleep: SleepLog[]): [string, number][] {
  const cuenta = new Map<string, number>();
  for (const s of sleep) {
    const q = s.quality ?? 'ok';
    cuenta.set(q, (cuenta.get(q) ?? 0) + 1);
  }
  return ESCALA_SUENO.filter((q) => cuenta.has(q)).map((q) => [
    q,
    cuenta.get(q)!,
  ]);
}

/** Cuántas sesiones de cada intensidad, de la más suave a la más fuerte.
 *
 *  Los valores son los de `Intensity` en `lib/domain/enums` de la app. */
const ESCALA_INTENSIDAD = ['light', 'moderate', 'vigorous'];

const INTENSIDAD: Record<string, string> = {
  light: 'Suave',
  moderate: 'Moderada',
  vigorous: 'Intensa',
};

function intensidades(activities: Activity[]): [string, number][] {
  const cuenta = new Map<string, number>();
  for (const a of activities) {
    const k = a.intensity || 'moderate';
    cuenta.set(k, (cuenta.get(k) ?? 0) + 1);
  }
  const conocidas = ESCALA_INTENSIDAD.filter((k) => cuenta.has(k));
  const otras = [...cuenta.keys()].filter((k) => !ESCALA_INTENSIDAD.includes(k));
  return [...conocidas, ...otras].map((k) => [k, cuenta.get(k)!]);
}

/** Suma los valores que caen en el mismo día. */
function agrupar(points: Point[]): Point[] {
  const out = new Map<string, number>();
  for (const p of points) out.set(p.date, (out.get(p.date) ?? 0) + p.value);
  return [...out.entries()]
    .map(([date, value]) => ({ date, value }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

export function edad(birthDate: string): number {
  const n = new Date(birthDate);
  const h = new Date();
  let a = h.getFullYear() - n.getFullYear();
  const mes = h.getMonth() - n.getMonth();
  if (mes < 0 || (mes === 0 && h.getDate() < n.getDate())) a--;
  return a;
}
