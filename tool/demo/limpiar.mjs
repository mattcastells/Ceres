#!/usr/bin/env node
// Borra el escenario de demostración.
//
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node tool/demo/limpiar.mjs [--si]
//
// Borra todas las cuentas cuyo mail termina en `@demo.ceres.app`. Todo lo que
// cuelga de ellas se va en cascada desde `profiles`: comidas, pesos, planes,
// vínculos con pacientes (incluido el que le diste vos a la nutricionista),
// devoluciones, informes y pals. Después borra las organizaciones que quedaron
// sin miembros.
//
// **Tus datos no se tocan**: el filtro es el dominio del mail, y el tuyo no es
// ese. Sin `--si` solo muestra qué borraría.
//
// Las tablas de la demo (planes y organizaciones) quedan vacías pero existen.
// Para sacarlas también: `supabase/snippets/demo_quitar_tablas.sql`.

import { DEMO_DOMAIN } from './escenario.mjs';

const BASE = process.env.SUPABASE_URL?.replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CONFIRMA = process.argv.includes('--si');
if (!BASE || !KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

async function api(method, path) {
  const r = await fetch(`${BASE}${path}`, { method, headers: H });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

const users = [];
for (let page = 1; ; page++) {
  const r = await api('GET', `/auth/v1/admin/users?page=${page}&per_page=1000`);
  users.push(...(r.users ?? []));
  if ((r.users ?? []).length < 1000) break;
}
const demo = users.filter((u) => u.email?.toLowerCase().endsWith(`@${DEMO_DOMAIN}`));

console.log(`Cuentas demo: ${demo.length} de ${users.length}.`);
for (const u of demo) console.log(`  ${u.email}`);
if (!CONFIRMA) {
  console.log('\nNo se borró nada. Volvé a correrlo con --si para borrar.');
  process.exit(0);
}

for (const u of demo) await api('DELETE', `/auth/v1/admin/users/${u.id}`);

const orgs = await api('GET', '/rest/v1/organizations?select=id,name,org_members(user_id)');
const huerfanas = (orgs ?? []).filter((o) => (o.org_members ?? []).length === 0);
for (const o of huerfanas) await api('DELETE', `/rest/v1/organizations?id=eq.${o.id}`);

console.log(`\nBorradas ${demo.length} cuentas y ${huerfanas.length} organizaciones.`);
