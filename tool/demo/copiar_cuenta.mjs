#!/usr/bin/env node
// Copia una cuenta real de producción a la base local de la demo.
//
//   ORIGEN_URL=https://<ref>.supabase.co  ORIGEN_KEY=<service_role de producción>
//   DESTINO_URL=http://127.0.0.1:55321    DESTINO_KEY=<service_role local>
//   DEMO_PASSWORD=<contraseña para la cuenta copiada>
//   node tool/demo/copiar_cuenta.mjs --email tu@mail.com [--sin-fotos]
//
// **De producción solo lee.** No hay un solo PATCH, POST ni DELETE contra
// ORIGEN: todas las escrituras van a DESTINO, y el script se niega a correr si
// los dos apuntan al mismo lugar.
//
// La cuenta copiada tiene el mismo mail y un id nuevo (el de la base local).
// Las fotos se bajan y se suben a la carpeta del id nuevo, y cada fila que las
// nombra se reescribe para apuntar ahí.

import { randomUUID } from 'node:crypto';

const O = { url: process.env.ORIGEN_URL?.replace(/\/$/, ''), key: process.env.ORIGEN_KEY };
const D = { url: process.env.DESTINO_URL?.replace(/\/$/, ''), key: process.env.DESTINO_KEY };
const PASSWORD = process.env.DEMO_PASSWORD;
const args = process.argv.slice(2);
const EMAIL = args[args.indexOf('--email') + 1];
const SIN_FOTOS = args.includes('--sin-fotos');

if (!O.url || !O.key || !D.url || !D.key || !PASSWORD || !EMAIL || args.indexOf('--email') < 0) {
  console.error('Faltan ORIGEN_URL, ORIGEN_KEY, DESTINO_URL, DESTINO_KEY, DEMO_PASSWORD o --email.');
  process.exit(1);
}
if (O.url === D.url) {
  console.error('ORIGEN y DESTINO son el mismo proyecto. Esto copia hacia la base local, nada más.');
  process.exit(1);
}

const headers = (k, extra = {}) => ({ apikey: k, Authorization: `Bearer ${k}`, ...extra });

// ── Lectura (origen) ──────────────────────────────────────────────────────
async function leer(path) {
  const r = await fetch(`${O.url}${path}`, { headers: headers(O.key) });
  if (!r.ok) throw new Error(`GET origen ${path} → ${r.status} ${(await r.text()).slice(0, 200)}`);
  return r.json();
}
async function leerTodo(table, filter) {
  const out = [];
  for (let from = 0; ; from += 1000) {
    const r = await fetch(`${O.url}/rest/v1/${table}?select=*&${filter}`, {
      headers: headers(O.key, { Range: `${from}-${from + 999}`, 'Range-Unit': 'items' }),
    });
    if (!r.ok) throw new Error(`GET origen ${table} → ${r.status} ${(await r.text()).slice(0, 200)}`);
    const rows = await r.json();
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}

// ── Escritura (destino) ───────────────────────────────────────────────────
async function escribir(method, path, body, extra = {}) {
  const r = await fetch(`${D.url}${path}`, {
    method, headers: headers(D.key, { 'Content-Type': 'application/json', ...extra }),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} destino ${path} → ${r.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}
async function insertar(table, rows) {
  for (let i = 0; i < rows.length; i += 500) {
    await escribir('POST', `/rest/v1/${table}`, rows.slice(i, i + 500), { Prefer: 'return=minimal' });
  }
}
async function usuarios(base) {
  const out = [];
  for (let page = 1; ; page++) {
    const r = await fetch(`${base.url}/auth/v1/admin/users?page=${page}&per_page=1000`, { headers: headers(base.key) });
    if (!r.ok) throw new Error(`usuarios ${r.status}`);
    const j = await r.json();
    out.push(...(j.users ?? []));
    if ((j.users ?? []).length < 1000) return out;
  }
}

// ── Main ──────────────────────────────────────────────────────────────────
const origen = (await usuarios(O)).find((u) => u.email?.toLowerCase() === EMAIL.toLowerCase());
if (!origen) { console.error(`No existe ${EMAIL} en el origen.`); process.exit(1); }
if ((await usuarios(D)).some((u) => u.email?.toLowerCase() === EMAIL.toLowerCase())) {
  console.error(`${EMAIL} ya existe en la base local. Borrala primero si querés copiarla de nuevo.`);
  process.exit(1);
}
const OLD = origen.id;

const [perfil] = await leer(`/rest/v1/profiles?id=eq.${OLD}&select=*`);
const nuevo = await escribir('POST', '/auth/v1/admin/users', {
  email: EMAIL, password: PASSWORD, email_confirm: true,
  user_metadata: { display_name: perfil?.display_name ?? 'Matías' },
});
const NEW = nuevo.id;
console.log(`· Cuenta local creada (${EMAIL})`);

// Perfil: todo menos los códigos, que en la base local se generan de nuevo.
const { id: _i, pal_code: _p, care_code: _c, created_at: _ca, updated_at: _u, ...perfilCopiable } = perfil ?? {};
await escribir('PATCH', `/rest/v1/profiles?id=eq.${NEW}`, perfilCopiable, { Prefer: 'return=minimal' });

// Los ids de `activity_types` no coinciden entre proyectos: se traducen por slug.
const tiposO = Object.fromEntries((await leer('/rest/v1/activity_types?select=id,slug')).map((t) => [t.id, t.slug]));
const tiposD = Object.fromEntries((await escribir('GET', '/rest/v1/activity_types?select=id,slug')).map((t) => [t.slug, t.id]));

const mover = (path) => (typeof path === 'string' && path.startsWith(`${OLD}/`) ? `${NEW}/${path.slice(OLD.length + 1)}` : path);
const conDueno = (rows, extra = (x) => x) => rows.map((r) => extra({ ...r, user_id: NEW }));

const tablas = {};
for (const t of ['goals', 'weight_logs', 'body_measurements', 'water_logs', 'sleep_logs', 'day_markers', 'alcohol_logs', 'ai_analyses', 'meals', 'activities']) {
  tablas[t] = await leerTodo(t, `user_id=eq.${OLD}`);
}
const mealIds = tablas.meals.map((m) => m.id);
const items = [];
for (let i = 0; i < mealIds.length; i += 100) {
  items.push(...await leerTodo('meal_items', `meal_id=in.(${mealIds.slice(i, i + 100).join(',')})`));
}

// Columnas generadas o de compatibilidad que la base escribe sola.
const sinCompat = (r) => { const { logged_at: _l, ...x } = r; return x; };

await insertar('goals', conDueno(tablas.goals));
await insertar('weight_logs', conDueno(tablas.weight_logs, (r) => ({ ...r, photo_path: mover(r.photo_path) })));
await insertar('body_measurements', conDueno(tablas.body_measurements));
await insertar('water_logs', conDueno(tablas.water_logs));
await insertar('sleep_logs', conDueno(tablas.sleep_logs));
await insertar('day_markers', conDueno(tablas.day_markers));
await insertar('alcohol_logs', conDueno(tablas.alcohol_logs));
await insertar('ai_analyses', conDueno(tablas.ai_analyses, (r) => ({ ...r, photo_path: mover(r.photo_path) ?? '' })));
await insertar('meals', conDueno(tablas.meals, (r) => sinCompat({ ...r, photo_path: mover(r.photo_path) })));
await insertar('meal_items', items.map(({ food_id: _f, cache_food_id: _cf, ...r }) => r));
await insertar('activities', conDueno(tablas.activities, (r) => ({
  ...r, photo_path: mover(r.photo_path),
  activity_type_id: tiposD[tiposO[r.activity_type_id]] ?? tiposD.custom,
})));
console.log(`· ${tablas.meals.length} comidas, ${items.length} ítems, ${tablas.weight_logs.length} pesos, ${tablas.activities.length} actividades`);

// ── Fotos ─────────────────────────────────────────────────────────────────
if (!SIN_FOTOS) {
  const fotos = new Set();
  for (const t of ['meals', 'weight_logs', 'activities']) {
    for (const r of tablas[t]) if (typeof r.photo_path === 'string' && r.photo_path.startsWith(`${OLD}/`)) fotos.add(r.photo_path);
  }
  const lista = [...fotos];
  let ok = 0, faltan = 0;
  const copiar = async (path) => {
    const r = await fetch(`${O.url}/storage/v1/object/authenticated/meal-photos/${path}`, { headers: headers(O.key) });
    if (!r.ok) { faltan++; return; }
    const bytes = new Uint8Array(await r.arrayBuffer());
    const up = await fetch(`${D.url}/storage/v1/object/meal-photos/${mover(path)}`, {
      method: 'POST', headers: headers(D.key, { 'Content-Type': r.headers.get('content-type') ?? 'image/jpeg', 'x-upsert': 'true' }), body: bytes,
    });
    if (up.ok) ok++; else faltan++;
  };
  for (let i = 0; i < lista.length; i += 6) await Promise.all(lista.slice(i, i + 6).map(copiar));
  console.log(`· Fotos: ${ok} copiadas, ${faltan} que no estaban o fallaron`);
}

console.log(`\nListo. Entrá en la base local con ${EMAIL} y la contraseña de DEMO_PASSWORD.`);
void randomUUID;
