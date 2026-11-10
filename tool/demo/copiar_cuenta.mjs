#!/usr/bin/env node
// Copia una cuenta real a la base local de la demo, con sus fotos.
//
// Tres usos:
//
//   1. Producción → carpeta (una "instantánea" portable, para llevar a otra
//      máquina sin acceso a producción):
//        ORIGEN_URL=https://<ref>.supabase.co ORIGEN_KEY=<service_role de producción>
//        node tool/demo/copiar_cuenta.mjs --email tu@mail.com --guardar tool/demo/instantanea
//
//   2. Carpeta → base local (lo que corre `levantar.ps1` en la notebook):
//        DESTINO_URL=http://127.0.0.1:56321 DESTINO_KEY=<service_role local> DEMO_PASSWORD=...
//        node tool/demo/copiar_cuenta.mjs --desde tool/demo/instantanea
//
//   3. Producción → base local directo (las dos variables de arriba juntas,
//      sin `--guardar` ni `--desde`).
//
// **De producción solo lee.** No hay un solo PATCH, POST ni DELETE contra
// ORIGEN, y el script se niega a correr si origen y destino son el mismo.
//
// ⚠️ La instantánea son tus datos de salud y tus fotos, en claro. Está en
// `.gitignore`; no la subas a ningún lado y borrala después de la defensa.
//
// La cuenta copiada tiene el mismo mail y un id nuevo (el de la base local).
// Las fotos van a la carpeta del id nuevo, y cada fila que las nombra se
// reescribe para apuntar ahí.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const O = { url: process.env.ORIGEN_URL?.replace(/\/$/, ''), key: process.env.ORIGEN_KEY };
const D = { url: process.env.DESTINO_URL?.replace(/\/$/, ''), key: process.env.DESTINO_KEY };
const PASSWORD = process.env.DEMO_PASSWORD;
const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const EMAIL = opt('--email');
const GUARDAR = opt('--guardar');
const DESDE = opt('--desde');
const SIN_FOTOS = args.includes('--sin-fotos');

const usaOrigen = !DESDE;
const usaDestino = !GUARDAR;
if ((usaOrigen && (!O.url || !O.key || !EMAIL)) || (usaDestino && (!D.url || !D.key || !PASSWORD))) {
  console.error('Faltan variables. Mirá el encabezado de tool/demo/copiar_cuenta.mjs.');
  process.exit(1);
}
if (usaOrigen && usaDestino && O.url === D.url) {
  console.error('ORIGEN y DESTINO son el mismo proyecto. Esto copia hacia la base local, nada más.');
  process.exit(1);
}

const headers = (k, extra = {}) => ({ apikey: k, Authorization: `Bearer ${k}`, ...extra });
const TABLAS = ['goals', 'weight_logs', 'body_measurements', 'water_logs', 'sleep_logs', 'day_markers', 'alcohol_logs', 'ai_analyses', 'meals', 'activities'];

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

// ── Leer: de producción o de una carpeta ──────────────────────────────────
async function leerDeProduccion() {
  const leer = async (path) => {
    const r = await fetch(`${O.url}${path}`, { headers: headers(O.key) });
    if (!r.ok) throw new Error(`GET origen ${path} → ${r.status} ${(await r.text()).slice(0, 200)}`);
    return r.json();
  };
  const leerTodo = async (table, filter) => {
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
  };

  const origen = (await usuarios(O)).find((u) => u.email?.toLowerCase() === EMAIL.toLowerCase());
  if (!origen) throw new Error(`No existe ${EMAIL} en el origen.`);
  const id = origen.id;
  const [perfil] = await leer(`/rest/v1/profiles?id=eq.${id}&select=*`);
  const tipos = Object.fromEntries((await leer('/rest/v1/activity_types?select=id,slug')).map((t) => [t.id, t.slug]));
  const tablas = {};
  for (const t of TABLAS) tablas[t] = await leerTodo(t, `user_id=eq.${id}`);
  const mealIds = tablas.meals.map((m) => m.id);
  const items = [];
  for (let i = 0; i < mealIds.length; i += 100) {
    items.push(...await leerTodo('meal_items', `meal_id=in.(${mealIds.slice(i, i + 100).join(',')})`));
  }
  const foto = async (path) => {
    const r = await fetch(`${O.url}/storage/v1/object/authenticated/meal-photos/${path}`, { headers: headers(O.key) });
    return r.ok ? { bytes: new Uint8Array(await r.arrayBuffer()), type: r.headers.get('content-type') ?? 'image/jpeg' } : null;
  };
  return { email: origen.email, id, perfil, tipos, tablas, items, foto };
}

async function leerDeCarpeta(dir) {
  const datos = JSON.parse(await readFile(join(dir, 'cuenta.json'), 'utf-8'));
  const foto = async (path) => {
    try {
      return { bytes: await readFile(join(dir, 'fotos', path)), type: 'image/jpeg' };
    } catch {
      return null;
    }
  };
  return { ...datos, foto };
}

function rutasDeFotos(c) {
  const fotos = new Set();
  for (const t of ['meals', 'weight_logs', 'activities']) {
    for (const r of c.tablas[t]) if (typeof r.photo_path === 'string' && r.photo_path.startsWith(`${c.id}/`)) fotos.add(r.photo_path);
  }
  return [...fotos];
}

// ── Guardar en una carpeta ────────────────────────────────────────────────
async function guardar(c, dir) {
  const { foto, ...datos } = c;
  await mkdir(join(dir, 'fotos'), { recursive: true });
  await writeFile(join(dir, 'cuenta.json'), JSON.stringify(datos));
  let ok = 0;
  if (!SIN_FOTOS) {
    const lista = rutasDeFotos(c);
    for (let i = 0; i < lista.length; i += 6) {
      await Promise.all(lista.slice(i, i + 6).map(async (path) => {
        const f = await foto(path);
        if (!f) return;
        const destino = join(dir, 'fotos', path);
        await mkdir(dirname(destino), { recursive: true });
        await writeFile(destino, f.bytes);
        ok++;
      }));
    }
  }
  console.log(`Instantánea en ${dir}: ${c.tablas.meals.length} comidas, ${ok} fotos.`);
}

// ── Escribir en la base local ─────────────────────────────────────────────
async function escribirEnDestino(c) {
  const escribir = async (method, path, body, extra = {}) => {
    const r = await fetch(`${D.url}${path}`, {
      method, headers: headers(D.key, { 'Content-Type': 'application/json', ...extra }),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await r.text();
    if (!r.ok) throw new Error(`${method} destino ${path} → ${r.status} ${text.slice(0, 300)}`);
    return text ? JSON.parse(text) : null;
  };
  const insertar = async (table, rows) => {
    for (let i = 0; i < rows.length; i += 500) {
      await escribir('POST', `/rest/v1/${table}`, rows.slice(i, i + 500), { Prefer: 'return=minimal' });
    }
  };

  if ((await usuarios(D)).some((u) => u.email?.toLowerCase() === c.email.toLowerCase())) {
    console.log(`${c.email} ya está en la base local: no se copia de nuevo.`);
    return;
  }
  const nuevo = await escribir('POST', '/auth/v1/admin/users', {
    email: c.email, password: PASSWORD, email_confirm: true,
    user_metadata: { display_name: c.perfil?.display_name ?? 'Yo' },
  });
  const OLD = c.id;
  const NEW = nuevo.id;

  // Perfil: todo menos los códigos, que en la base local se generan de nuevo.
  const { id: _i, pal_code: _p, care_code: _c, created_at: _ca, updated_at: _u, ...perfil } = c.perfil ?? {};
  await escribir('PATCH', `/rest/v1/profiles?id=eq.${NEW}`, perfil, { Prefer: 'return=minimal' });

  // Los ids de `activity_types` no coinciden entre proyectos: se traducen por slug.
  const tiposD = Object.fromEntries((await escribir('GET', '/rest/v1/activity_types?select=id,slug')).map((t) => [t.slug, t.id]));
  const mover = (p) => (typeof p === 'string' && p.startsWith(`${OLD}/`) ? `${NEW}/${p.slice(OLD.length + 1)}` : p);
  const conDueno = (rows, extra = (x) => x) => rows.map((r) => extra({ ...r, user_id: NEW }));
  const t = c.tablas;

  await insertar('goals', conDueno(t.goals));
  await insertar('weight_logs', conDueno(t.weight_logs, (r) => ({ ...r, photo_path: mover(r.photo_path) })));
  await insertar('body_measurements', conDueno(t.body_measurements));
  await insertar('water_logs', conDueno(t.water_logs));
  await insertar('sleep_logs', conDueno(t.sleep_logs));
  await insertar('day_markers', conDueno(t.day_markers));
  await insertar('alcohol_logs', conDueno(t.alcohol_logs));
  await insertar('ai_analyses', conDueno(t.ai_analyses, (r) => ({ ...r, photo_path: mover(r.photo_path) ?? '' })));
  // `logged_at` lo escribe la base (migración 45, compatibilidad).
  await insertar('meals', conDueno(t.meals, ({ logged_at: _l, ...r }) => ({ ...r, photo_path: mover(r.photo_path) })));
  // Los ítems no apuntan al catálogo de origen: esos ids no existen acá.
  await insertar('meal_items', c.items.map(({ food_id: _f, cache_food_id: _cf, ...r }) => r));
  await insertar('activities', conDueno(t.activities, (r) => ({
    ...r, photo_path: mover(r.photo_path),
    activity_type_id: tiposD[c.tipos[r.activity_type_id]] ?? tiposD.custom,
  })));
  console.log(`· ${t.meals.length} comidas, ${c.items.length} ítems, ${t.weight_logs.length} pesos, ${t.activities.length} actividades`);

  if (!SIN_FOTOS) {
    let ok = 0, faltan = 0;
    const lista = rutasDeFotos(c);
    for (let i = 0; i < lista.length; i += 6) {
      await Promise.all(lista.slice(i, i + 6).map(async (path) => {
        const f = await c.foto(path);
        if (!f) { faltan++; return; }
        const up = await fetch(`${D.url}/storage/v1/object/meal-photos/${mover(path)}`, {
          method: 'POST', headers: headers(D.key, { 'Content-Type': f.type, 'x-upsert': 'true' }), body: f.bytes,
        });
        if (up.ok) ok++; else faltan++;
      }));
    }
    console.log(`· Fotos: ${ok} copiadas, ${faltan} que no estaban o fallaron`);
  }
  console.log(`Listo: ${c.email} entra en la base local con DEMO_PASSWORD.`);
}

// ── Main ──────────────────────────────────────────────────────────────────
const cuenta = DESDE ? await leerDeCarpeta(DESDE) : await leerDeProduccion();
if (GUARDAR) await guardar(cuenta, GUARDAR);
else await escribirEnDestino(cuenta);
