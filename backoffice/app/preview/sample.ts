/**
 * Datos de ejemplo para mirar el diseño del panel sin una sesión.
 *
 * TEMPORAL: esta carpeta se borra antes de desplegar. Una ruta sin auth en un
 * panel clínico no se deja puesta.
 */
import type { PatientData } from '@/components/patient-view';
import type {
  AlcoholLog,
  DayMarker,
  Meal,
  MealItem,
} from '@/lib/queries';
import { haceISO, hoyISO, rangoDeFechas } from '@/lib/format';
import { ventanaEfectiva } from '@/lib/tracking';

/** LCG: el mismo dibujo en cada render, así una captura se compara con otra. */
function rng(seed: number) {
  let s = seed;
  return () => ((s = (s * 1103515245 + 12345) % 2147483648) / 2147483648);
}

const FOTO = (hue: number) =>
  'data:image/svg+xml;utf8,' +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">` +
      `<rect width="400" height="300" fill="hsl(${hue},35%,62%)"/>` +
      `<circle cx="200" cy="150" r="95" fill="hsl(${(hue + 40) % 360},45%,78%)"/>` +
      `<circle cx="200" cy="150" r="55" fill="hsl(${(hue + 90) % 360},40%,55%)"/>` +
      `</svg>`,
  );

const PLATOS: Record<string, [string, number, number, number, number][]> = {
  breakfast: [
    ['Café con leche', 120, 6, 12, 4],
    ['Tostadas de pan integral', 180, 6, 32, 3],
    ['Queso untable descremada', 70, 5, 3, 4],
    ['Banana', 90, 1, 23, 0],
  ],
  lunch: [
    ['Milanesa de carne al horno', 380, 32, 18, 20],
    ['Puré de calabaza', 150, 3, 30, 2],
    ['Ensalada de tomate y lechuga', 60, 2, 8, 2],
    ['Arroz integral', 210, 5, 44, 2],
    ['Pechuga de pollo grillada', 280, 45, 0, 10],
  ],
  dinner: [
    ['Tortilla de papa', 320, 12, 30, 17],
    ['Sopa de verduras', 110, 4, 18, 2],
    ['Merluza al horno', 240, 38, 2, 8],
    ['Zapallitos rellenos', 190, 9, 20, 8],
  ],
  snack: [
    ['Yogur descremado', 100, 9, 14, 1],
    ['Almendras', 160, 6, 6, 14],
    ['Manzana', 80, 0, 21, 0],
    ['Barra de cereal', 130, 2, 24, 4],
  ],
};

const SLOTS = ['breakfast', 'lunch', 'snack', 'dinner'] as const;
const HORA: Record<string, string> = {
  breakfast: '08:20',
  lunch: '13:10',
  snack: '17:30',
  dinner: '21:15',
};

export function sampleData(days = 30, empiezaEnMedio = false): PatientData {
  const to = hoyISO();
  const from = haceISO(days - 1);
  const fechas = rangoDeFechas(from, to);
  const r = rng(20260819);

  // Con `empiezaEnMedio` la cuenta arranca a mitad del período, que es el caso
  // que hay que poder mirar: es donde se ve si los denominadores respetan la
  // ventana efectiva o siguen contando el calendario. Ver `lib/tracking.ts`.
  const primerDia = empiezaEnMedio
    ? fechas[Math.floor(fechas.length * 0.55)]
    : fechas[0];
  const conDatos = fechas.filter((f) => f >= primerDia);

  const meals: Meal[] = [];
  const photoUrls: Record<string, string> = {};
  let n = 0;

  for (const fecha of conDatos) {
    // Un par de días sin registrar, que es justamente lo que la pantalla
    // tiene que dejar ver como hueco y no como cero.
    if (r() < 0.12) continue;

    for (const slot of SLOTS) {
      if (slot === 'snack' && r() < 0.45) continue;
      const catalogo = PLATOS[slot];
      const cuantos = 1 + Math.floor(r() * 2);
      const elegidos = [...catalogo]
        .sort(() => r() - 0.5)
        .slice(0, cuantos);

      const items: MealItem[] = elegidos.map(([name, kcal, p, c, f], i) => {
        const q = 0.8 + r() * 0.6;
        return {
          id: `it-${n}-${i}`,
          name,
          quantity: Math.round(q * 100),
          unit: 'g',
          kcal: Math.round(kcal * q),
          protein_g: Math.round(p * q),
          carbs_g: Math.round(c * q),
          fat_g: Math.round(f * q),
          ai_confidence: r() < 0.5 ? 0.6 + r() * 0.35 : null,
        };
      });

      const conFoto = r() < 0.55;
      const path = conFoto ? `demo/${fecha}-${slot}.jpg` : null;
      if (path) photoUrls[path] = FOTO(Math.floor(r() * 360));

      meals.push({
        id: `m-${n}`,
        slot,
        local_date: fecha,
        eaten_at: `${fecha}T${HORA[slot]}:00-03:00`,
        name: null,
        total_kcal: items.reduce((a, x) => a + x.kcal, 0),
        total_protein_g: items.reduce((a, x) => a + x.protein_g, 0),
        total_carbs_g: items.reduce((a, x) => a + x.carbs_g, 0),
        total_fat_g: items.reduce((a, x) => a + x.fat_g, 0),
        source: conFoto ? 'ai_photo' : r() < 0.4 ? 'ai_text' : 'catalog',
        photo_path: path,
        meal_items: items,
      });
      n++;
    }
  }

  const weights = conDatos
    .filter((_, i) => i % 3 === 0)
    .map((fecha, i) => ({
      local_date: fecha,
      weight_kg: Math.round((78.4 - i * 0.18 + (r() - 0.5) * 0.5) * 10) / 10,
    }));

  const water = conDatos
    .filter(() => r() < 0.8)
    .map((fecha) => ({ local_date: fecha, glasses: 3 + Math.floor(r() * 6) }));

  const sleep = conDatos
    .filter(() => r() < 0.75)
    .map((fecha) => ({
      local_date: fecha,
      minutes: Math.round(330 + r() * 180),
      quality: ['bad', 'poor', 'ok', 'good', 'great'][Math.floor(r() * 5)],
    }));

  const activities = conDatos
    .filter(() => r() < 0.45)
    .map((fecha, i) => ({
      id: `a-${i}`,
      local_date: fecha,
      started_at: `${fecha}T19:00:00-03:00`,
      duration_minutes: 25 + Math.floor(r() * 50),
      estimated_calories: 180 + Math.floor(r() * 260),
      intensity: ['light', 'moderate', 'vigorous'][Math.floor(r() * 3)],
    }));

  const measurements = conDatos
    .filter((_, i) => i % 7 === 0)
    .flatMap((fecha, i) => [
      { local_date: fecha, metric: 'waist', value: 92 - i * 0.6, unit: 'cm' },
      { local_date: fecha, metric: 'hip', value: 101 - i * 0.3, unit: 'cm' },
      { local_date: fecha, metric: 'arm', value: 32 + i * 0.1, unit: 'cm' },
    ]);

  // Dos días de enfermedad pegados, con el hueco de registro encima: es el caso
  // que la feature existe para explicar.
  const diaEnfermo = conDatos[Math.floor(conDatos.length * 0.4)];
  const diaEnfermo2 = conDatos[Math.floor(conDatos.length * 0.4) + 1];
  const markers: DayMarker[] = [
    {
      local_date: diaEnfermo,
      kind: 'sick',
      severity: 2,
      note: 'Angina, fiebre a la tarde',
      tags: null,
    },
    {
      local_date: diaEnfermo2,
      kind: 'sick',
      severity: 1,
      note: 'Mejor, sin fiebre',
      tags: null,
    },
    {
      local_date: conDatos[Math.floor(conDatos.length * 0.7)],
      kind: 'rest',
      severity: null,
      note: null,
      tags: null,
    },
  ].filter((m) => m.local_date);

  const alcohol: AlcoholLog[] = conDatos
    .filter((f) => new Date(`${f}T12:00`).getDay() === 6)
    .flatMap((fecha, i) => [
      {
        id: `al-${i}`,
        local_date: fecha,
        drink_type: i % 2 === 0 ? 'wine' : 'beer',
        quantity: 1 + Math.floor(r() * 3),
        std_drinks: 1.5 + r() * 3,
        kcal: 180 + Math.floor(r() * 320),
        note: null,
      },
    ]);

  return {
    patient: {
      patient_id: 'demo',
      patient_name: 'Paciente de ejemplo',
      birth_date: '1989-04-12',
      height_cm: 172,
      share_meals: true,
      share_photos: true,
      share_body: true,
      share_wellbeing: true,
      tracking_since: primerDia,
    },
    days,
    from,
    to,
    ventana: ventanaEfectiva(from, to, primerDia),
    meals,
    weights,
    water,
    activities,
    sleep,
    measurements,
    markers,
    alcohol,
    goal: {
      base_calorie_target: 2000,
      protein_g: 120,
      carbs_g: 220,
      fat_g: 65,
      goal_type: 'lose',
    },
    photoUrls,
  };
}
