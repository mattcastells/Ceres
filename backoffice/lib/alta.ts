/**
 * El formulario de "Cargar sus datos" (Dar de alta, camino 1): validación y
 * armado de lo que viaja en `care_invites.intake` (migración 60).
 *
 * Las claves y los valores son los que lee la app para proponerlos en el
 * onboarding (`CareInviteIntake` en `lib/domain/models/care_grant.dart`), y
 * los rangos son los mismos que valida esa pantalla: lo que se propone no
 * puede ser algo que la pantalla que lo recibe rechace.
 */

/** Los campos de la anamnesis, en el orden en que se cargan y se leen. La
 *  clave es la de `care_invites.anamnesis`. */
export const ANAMNESIS: { k: string; l: string }[] = [
  { k: 'motivo', l: 'Motivo de consulta' },
  { k: 'patologias', l: 'Patologías' },
  { k: 'medicacion', l: 'Medicación' },
  { k: 'alergias', l: 'Alergias e intolerancias' },
  { k: 'antecedentes', l: 'Antecedentes' },
  { k: 'habitos', l: 'Hábitos' },
  { k: 'notas', l: 'Notas' },
];

/** La anamnesis guardada, como pares título → texto, solo con lo que tiene
 *  contenido y en el orden de `ANAMNESIS`. Una clave desconocida se ignora. */
export function leerAnamnesis(raw: unknown): { titulo: string; texto: string }[] {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return [];
  const o = raw as Record<string, unknown>;
  return ANAMNESIS.flatMap((a) => {
    const v = o[a.k];
    return typeof v === 'string' && v.trim() ? [{ titulo: a.l, texto: v.trim() }] : [];
  });
}

export type DatosAlta = {
  nombre: string;
  email: string;
  sexo: string;
  nacimiento: string;
  altura: string;
  peso: string;
  actividad: string;
  objetivo: string;
  calorias: string;
};

/** "70,5" → 70.5; vacío → null; basura → NaN. */
export function numero(s: string): number | null {
  const t = s.trim().replace(',', '.');
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : NaN;
}

export function validar(f: DatosAlta, hoy: Date = new Date()): string | null {
  if (!f.nombre.trim()) return 'Falta el nombre.';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email.trim())) return 'Revisá el mail.';
  const altura = numero(f.altura);
  if (altura !== null && (Number.isNaN(altura) || altura < 90 || altura > 250))
    return 'La altura va en centímetros, entre 90 y 250.';
  const peso = numero(f.peso);
  if (peso !== null && (Number.isNaN(peso) || peso < 25 || peso > 400))
    return 'El peso va en kilos, entre 25 y 400.';
  const kcal = numero(f.calorias);
  if (kcal !== null && (Number.isNaN(kcal) || kcal < 800 || kcal > 6000))
    return 'Las calorías van entre 800 y 6.000 por día.';
  if (f.nacimiento) {
    const edad = (hoy.getTime() - new Date(f.nacimiento).getTime()) / (365.25 * 86_400_000);
    if (!(edad >= 13 && edad <= 110)) return 'Revisá la fecha de nacimiento: tiene que tener al menos 13 años.';
  }
  return null;
}

/** Solo lo que se completó: un campo vacío no se propone. */
export function intakeDe(f: DatosAlta, flags: string[]): Record<string, unknown> {
  const o: Record<string, unknown> = {};
  if (f.sexo) o.sex = f.sexo;
  if (f.nacimiento) o.birth_date = f.nacimiento;
  const altura = numero(f.altura);
  if (altura) o.height_cm = Math.round(altura);
  const peso = numero(f.peso);
  if (peso) o.weight_kg = Math.round(peso * 10) / 10;
  if (f.actividad) o.activity_level = f.actividad;
  if (f.objetivo) o.goal_type = f.objetivo;
  const kcal = numero(f.calorias);
  if (kcal) o.calorie_target = Math.round(kcal);
  if (flags.length) o.dietary_flags = flags;
  return o;
}
