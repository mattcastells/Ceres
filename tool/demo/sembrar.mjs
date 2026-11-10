#!/usr/bin/env node
// Siembra el escenario de demostración: una nutricionista con su consultorio,
// sus pacientes con semanas de historial, una colega y dos usuarios del plan
// gratis. Todo con mails de `@demo.ceres.app`, y se borra con `limpiar.mjs`.
//
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=<service_role, la JWT "legacy"> \
//   DEMO_PASSWORD=<contraseña para todas las cuentas demo> \
//   node tool/demo/sembrar.mjs [--dias 42] [--amigo-de tu@mail.com]
//
// Usa la clave de servicio porque crea usuarios y asigna planes, que es lo que
// haría un sistema de altas y cobros; ningún cliente de Ceres la tiene. La
// clave no se imprime ni se escribe en ningún lado.
//
// `--amigo-de` deja a los dos usuarios gratis como pals aceptados de esa
// cuenta (la tuya), con sus últimos días publicados, para mostrar Pals.
//
// Tu cuenta real no se toca: para verte en el panel de la nutricionista, le
// das acceso desde la app con el código que imprime este script, como haría
// cualquier paciente.

import { randomUUID, createHash } from 'node:crypto';
import {
  AMIGOS, DEMO_DOMAIN, DEVOLUCIONES, ORGANIZACION, PACIENTES, PLATOS, PROFESIONALES,
} from './escenario.mjs';

const BASE = process.env.SUPABASE_URL?.replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = process.env.DEMO_PASSWORD;
const args = process.argv.slice(2);
const arg = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const DIAS = Number(arg('--dias') ?? 42);
const AMIGO_DE = arg('--amigo-de');

if (!BASE || !KEY || !PASSWORD) {
  console.error('Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o DEMO_PASSWORD.');
  process.exit(1);
}

const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

async function api(method, path, body, extra = {}) {
  const r = await fetch(`${BASE}${path}`, {
    method, headers: { ...H, ...extra }, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

async function insert(table, rows) {
  for (let i = 0; i < rows.length; i += 500) {
    await api('POST', `/rest/v1/${table}`, rows.slice(i, i + 500), { Prefer: 'return=minimal' });
  }
}

async function allUsers() {
  const users = [];
  for (let page = 1; ; page++) {
    const r = await api('GET', `/auth/v1/admin/users?page=${page}&per_page=1000`);
    users.push(...(r.users ?? []));
    if ((r.users ?? []).length < 1000) break;
  }
  return users;
}

// ── Azar reproducible ─────────────────────────────────────────────────────
// Mismo escenario cada vez que se siembra: si un ensayo de la demo sale bien,
// el próximo ve los mismos números.
function rng(seed) {
  let a = createHash('sha256').update(seed).digest().readUInt32LE(0);
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const pick = (r, xs) => xs[Math.floor(r() * xs.length)];

// ── Fechas en Argentina ───────────────────────────────────────────────────
const TZ_OFFSET_H = 3; // Argentina no tiene horario de verano.
const todayAR = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(new Date());
const addDays = (d, n) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const atLocal = (date, minutes) => new Date(Date.parse(`${date}T00:00:00Z`) + (minutes + TZ_OFFSET_H * 60) * 60_000);
const isWeekend = (d) => [0, 6].includes(new Date(`${d}T12:00:00Z`).getUTCDay());
const ageOn = (birth) => Math.floor((Date.parse(todayAR) - Date.parse(birth)) / (365.25 * 86_400_000));

const ACTIVITY_FACTOR = { sedentary: 1.2, light: 1.375, moderate: 1.55, high: 1.725 };
function bmr(p) {
  const base = 10 * p.weight + 6.25 * p.height - 5 * ageOn(p.birth);
  return Math.round(p.sex === 'male' ? base + 5 : base - 161);
}

const SHARES = {
  all: { share_meals: true, share_photos: true, share_body: true, share_wellbeing: true },
  meals: { share_meals: true, share_photos: true, share_body: false, share_wellbeing: false },
  meals_wellbeing: { share_meals: true, share_photos: true, share_body: false, share_wellbeing: true },
  meals_body: { share_meals: true, share_photos: false, share_body: true, share_wellbeing: false },
};

const SLOT_SHARE = { breakfast: 0.22, lunch: 0.34, snack: 0.1, dinner: 0.34 };
const SLOT_TIME = { breakfast: 8 * 60, lunch: 13 * 60 + 15, snack: 17 * 60 + 30, dinner: 21 * 60 + 15 };

// ── Un día de una persona ─────────────────────────────────────────────────
function generar(p, userId, activityTypes, r) {
  const analyses = [], meals = [], items = [], weights = [], activities = [], water = [], sleep = [], markers = [], shared = [];
  const days = Math.min(p.days ?? DIAS, DIAS);
  const nowMs = Date.now();

  for (let ago = days - 1; ago >= 0; ago--) {
    const date = addDays(todayAR, -ago);
    if (p.stopsAgo && ago < p.stopsAgo) continue;

    const sick = p.sickAgo !== undefined && (ago === p.sickAgo || ago === p.sickAgo - 1);
    if (sick && ago === p.sickAgo) {
      markers.push({ id: randomUUID(), user_id: userId, local_date: date, kind: 'sick', severity: 2, note: 'Angina' });
    }

    // El peso real sigue la tendencia del patrón, con el ruido de una balanza.
    const kg = p.weight - p.kgWeek * (ago / 7) + (r() - 0.5) * 0.6;
    const loggedToday = r() < p.adh;
    if (loggedToday && r() < 0.55) {
      weights.push({ id: randomUUID(), user_id: userId, local_date: date, weight_kg: Math.round(kg * 10) / 10, source: 'manual' });
    }
    if (!loggedToday) continue;

    const dayFactor = (isWeekend(date) ? p.weekend : 1) * (sick ? 0.7 : 1) * (0.9 + r() * 0.2);
    const dayTarget = p.target * p.eats * dayFactor;
    const dayMeals = [];
    for (const slot of ['breakfast', 'lunch', 'snack', 'dinner']) {
      if (slot === 'snack' && r() < 0.35) continue;
      const lateDinner = slot === 'dinner' && p.late;
      const minutes = (lateDinner ? 23 * 60 + 15 : SLOT_TIME[slot]) + Math.round((r() - 0.5) * 70);
      const eatenAt = atLocal(date, minutes);
      if (eatenAt.getTime() > nowMs) continue; // nada en el futuro

      const [name, base] = pick(r, PLATOS[slot]);
      const baseKcal = base.reduce((a, it) => a + it[3], 0);
      const factor = Math.min(2, Math.max(0.6, (dayTarget * SLOT_SHARE[slot]) / baseKcal));
      const mealId = randomUUID();
      let t = { kcal: 0, p: 0, c: 0, f: 0 };
      base.forEach(([n, qty, unit, kcal, pr, cb, ft], position) => {
        const prot = pr * factor * (p.protein ?? 1);
        const it = {
          id: randomUUID(), meal_id: mealId, name: n, quantity: Math.round(qty * factor), unit,
          kcal: Math.round(kcal * factor - pr * factor * (1 - (p.protein ?? 1)) * 4),
          protein_g: Math.round(prot * 10) / 10, carbs_g: Math.round(cb * factor * 10) / 10,
          fat_g: Math.round(ft * factor * 10) / 10, position,
        };
        items.push(it);
        t = { kcal: t.kcal + it.kcal, p: t.p + it.protein_g, c: t.c + it.carbs_g, f: t.f + it.fat_g };
      });
      const roll = r();
      const source = p.manualOnly ? 'manual'
        : roll < 0.6 ? 'ai_photo' : roll < 0.8 ? 'ai_text' : roll < 0.92 ? 'duplicate' : 'manual';
      meals.push({
        id: mealId, user_id: userId, slot, eaten_at: eatenAt.toISOString(), local_date: date, name,
        total_kcal: t.kcal, total_protein_g: Math.round(t.p * 10) / 10, total_carbs_g: Math.round(t.c * 10) / 10,
        total_fat_g: Math.round(t.f * 10) / 10, source,
      });
      dayMeals.push({ slot, name, kcal: t.kcal });
      // Cada comida cargada con IA tuvo su análisis: es lo que consume el
      // fondo del consultorio. Sin foto real; alcanza con el registro.
      if (source === 'ai_photo' || source === 'ai_text') {
        analyses.push({
          id: randomUUID(), user_id: userId, photo_path: '', status: 'accepted',
          model: 'gemini-3.6-flash', prompt_version: 'v5',
          source: source === 'ai_photo' ? 'photo' : 'text', items: [],
          latency_ms: 8000 + Math.round(r() * 9000), tokens_in: 6600, tokens_out: 260, tokens_thinking: 1370,
          created_at: eatenAt.toISOString(),
        });
      }
    }

    let dayActivities = [];
    if (!sick && r() < p.actPerWeek / 7) {
      const slug = pick(r, p.act);
      const type = activityTypes[slug] ?? activityTypes.walking;
      const duration = 30 + Math.round(r() * 6) * 5;
      const started = atLocal(date, 19 * 60 + Math.round(r() * 60));
      if (started.getTime() < nowMs) {
        const kcal = Math.max(1, Math.round(type.met * kg * duration / 60));
        activities.push({
          id: randomUUID(), user_id: userId, activity_type_id: type.id,
          started_at: started.toISOString(), ended_at: new Date(started.getTime() + duration * 60_000).toISOString(),
          local_date: date, duration_minutes: duration, intensity: 'moderate',
          estimated_calories: kcal, original_calories: kcal, applied_calories: 0,
          exercise_credit_percentage: 0, estimation_method: 'met', met_value: type.met,
          weight_kg_used: Math.round(kg * 10) / 10, source_type: 'manual',
        });
        dayActivities = [{ name: type.name, minutes: duration, kcal }];
      }
    }

    let glasses = null, sleepMin = null, quality = null;
    if (r() < 0.75) { glasses = 3 + Math.floor(r() * 6); water.push({ id: randomUUID(), user_id: userId, local_date: date, glasses }); }
    if (r() < 0.7) {
      sleepMin = 330 + Math.round(r() * 150);
      quality = pick(r, ['poor', 'ok', 'ok', 'good', 'good', 'great']);
      sleep.push({ id: randomUUID(), user_id: userId, local_date: date, minutes: sleepMin, quality });
    }

    // Lo que ven los pals: los últimos ocho días, con la misma forma que
    // publica la app (`PalDay.toRow`).
    if (ago < 8) {
      shared.push({
        user_id: userId, local_date: date, meals: dayMeals,
        activity_minutes: dayActivities.reduce((a, x) => a + x.minutes, 0),
        activity_count: dayActivities.length, activities: dayActivities,
        water_glasses: glasses, sleep_minutes: sleepMin, sleep_quality: quality,
        updated_at: new Date().toISOString(),
      });
    }
  }
  return { analyses, meals, items, weights, activities, water, sleep, markers, shared };
}

// ── Main ──────────────────────────────────────────────────────────────────
const existentes = (await allUsers()).filter((u) => u.email?.endsWith(`@${DEMO_DOMAIN}`));
if (existentes.length > 0) {
  console.error(`Ya hay ${existentes.length} cuentas demo. Corré primero tool/demo/limpiar.mjs.`);
  process.exit(1);
}

const tipos = await api('GET', '/rest/v1/activity_types?select=id,slug,display_name,default_met');
const activityTypes = Object.fromEntries(tipos.map((t) => [t.slug, { id: t.id, met: Number(t.default_met), name: t.display_name }]));

const ids = {};
async function crearCuenta(persona, plan) {
  const email = `${persona.email ?? persona.key}@${DEMO_DOMAIN}`;
  const u = await api('POST', '/auth/v1/admin/users', {
    email, password: PASSWORD, email_confirm: true, user_metadata: { display_name: persona.name },
  });
  ids[persona.key] = u.id;
  await api('PATCH', `/rest/v1/profiles?id=eq.${u.id}`, {
    display_name: persona.name, biological_sex: persona.sex, birth_date: persona.birth,
    height_cm: persona.height, activity_level: persona.activity ?? 'moderate', profile_completed: true,
  }, { Prefer: 'return=minimal' });
  await insert('account_plans', [{ user_id: u.id, plan }]);
  return { id: u.id, email };
}

console.log('· Profesionales y organización');
const codigos = {};
for (const pro of PROFESIONALES) {
  await crearCuenta(pro, 'pro');
  const code = pro.code;
  await api('PATCH', `/rest/v1/profiles?id=eq.${ids[pro.key]}`, { care_code: code }, { Prefer: 'return=minimal' });
  codigos[pro.key] = code;
}
const [org] = await api('POST', '/rest/v1/organizations', ORGANIZACION, { Prefer: 'return=representation' });
await insert('org_members', PROFESIONALES.map((p) => ({ org_id: org.id, user_id: ids[p.key], role: p.role })));

console.log('· Pacientes y amigos');
const totales = { meals: 0, items: 0 };
for (const p of [...PACIENTES, ...AMIGOS]) {
  const { id: userId } = await crearCuenta(p, p.plan);
  const b = bmr(p);
  const tdee = Math.round(b * ACTIVITY_FACTOR[p.activity ?? 'moderate']);
  await insert('goals', [{
    id: randomUUID(), user_id: userId, goal_type: p.goal, base_calorie_target: p.target,
    target_method: 'calculated', bmr_kcal: b, tdee_kcal: tdee,
    protein_g: Math.round(p.weight * (p.goal === 'gain' ? 1.8 : 1.3)),
    carbs_g: Math.round((p.target * 0.45) / 4), fat_g: Math.round((p.target * 0.3) / 9),
    rate_kg_per_week: Math.min(1, Math.abs(p.kgWeek) || 0), starts_on: addDays(todayAR, -(DIAS + 5)),
  }]);

  const g = generar(p, userId, activityTypes, rng(`ceres-demo:${p.key}`));
  await insert('ai_analyses', g.analyses);
  await insert('meals', g.meals);
  await insert('meal_items', g.items);
  await insert('weight_logs', g.weights);
  await insert('activities', g.activities);
  await insert('water_logs', g.water);
  await insert('sleep_logs', g.sleep);
  await insert('day_markers', g.markers);
  if (!p.of) await insert('shared_days', g.shared);
  totales.meals += g.meals.length; totales.items += g.items.length;

  if (p.of) {
    const days = Math.min(p.days ?? DIAS, DIAS);
    await insert('care_grants', [{
      owner_id: userId, professional_id: ids[p.of], status: 'accepted', ...SHARES[p.share],
      accepted_at: atLocal(addDays(todayAR, -days), 10 * 60).toISOString(),
    }]);
  }
}

console.log('· Devoluciones');
await insert('care_feedback', DEVOLUCIONES.map((d) => {
  const at = atLocal(addDays(todayAR, -d.daysAgo), 18 * 60).toISOString();
  return {
    author_id: ids.valentina, patient_id: ids[d.to], kind: d.kind, body: d.body, source: 'manual',
    created_at: at, published_at: d.draft ? null : at,
    read_at: d.read ? atLocal(addDays(todayAR, -d.daysAgo + 1), 9 * 60).toISOString() : null,
  };
}));

if (AMIGO_DE) {
  const real = (await allUsers()).find((u) => u.email?.toLowerCase() === AMIGO_DE.toLowerCase());
  if (!real) {
    console.warn(`  No encontré la cuenta ${AMIGO_DE}: no se crean los pals.`);
  } else {
    console.log('· Pals con tu cuenta');
    await insert('pals', AMIGOS.map((a) => ({
      requester_id: ids[a.key], addressee_id: real.id, status: 'accepted', responded_at: new Date().toISOString(),
    })));
  }
}

console.log(`\nListo: ${Object.keys(ids).length} cuentas, ${totales.meals} comidas, ${totales.items} ítems.`);
console.log(`Organización: ${ORGANIZACION.name}`);
for (const pro of PROFESIONALES) {
  console.log(`  ${pro.name}: ${pro.email}@${DEMO_DOMAIN} · código ${codigos[pro.key]}`);
}
console.log(`\nPara verte en el panel: en la app, Perfil → Mi nutricionista → código ${codigos.valentina}.`);
