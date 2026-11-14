# Roadmap hasta la defensa de la tesis

Interno. Ordena lo que falta para dar Ceres por terminada como MVP y pasar a la
presentación. Se trabaja en la rama `tesis`; nada se publica a producción hasta
el final.

**Fecha de este documento:** 13 de noviembre de 2026.

**Actualización del 14 de noviembre.** Etapas 2 a 5 hechas en una tirada,
pendientes de revisión: alta por invitación desde el panel, una sola
nutricionista por persona, cuentas profesionales propias, baja de los dos
lados (migraciones 55 a 57); el consultorio con pacientes de todas,
reasignar, sumar y sacar profesionales y números agregados; comentarios sobre
una comida o su foto; búsqueda y orden del equipo; hoja de consulta
imprimible (§8) y días con alcohol o enfermedad contra sin (§7); la tabla de
planes y las reglas de la publicidad en `docs/planes.md`. §9 (síntomas y
ánimo) quedó afuera a propósito.

```
  1. App del paciente       ✔ terminada (sujeta a retoques chicos)
  2. Backoffice             ✔ hecho el 14/11 · a revisar
  3. Paciente ↔ nutricionista ✔ hecho el 14/11 · a revisar
  4. Pacientes y organizaciones ✔ hecho el 14/11 · a revisar
  5. Planes y funciones premium ✔ docs/planes.md · a revisar
  6. Presentación de la tesis  ← primer borrador de las slides
```

El orden importa: cada etapa define lo que la siguiente necesita. Los planes
(5) van después de tener claro qué hace cada rol, porque un plan es la lista de
capacidades que habilita.

---

## 1 · App del paciente — terminada

Revisada pantalla por pantalla con el usuario entre el 10 y el 13 de noviembre:
Inicio, Progreso, Pals, Perfil, Medidas, Preferencias, Objetivo y macros,
comidas con "Sumar un ítem", foto de perfil, avisos de pals por Realtime,
reporte con IA por período (semana, mes, trimestre, año), artículos y objetivo
recomendado de la nutricionista.

Queda abierto, para cuando haga falta:

- "Mi nutricionista" está reducida a lo mínimo a propósito: se termina de
  pulir junto con la etapa 3.
- Avisos de pals con la app cerrada: hoy suenan con la app abierta o al
  volver a ella. Con la app cerrada hace falta push (Firebase).
- Ritmo del objetivo: los subtítulos de cada opción podrían ir a un tooltip,
  como el resto de "Cómo se calcula".

## 2 · Backoffice de la nutricionista — siguiente

El panel web (`backoffice/`, Next.js) ya tiene tablero del equipo, ficha del
paciente con análisis (balance contra peso, horarios, qué come, semanas,
cintura/altura, días bajo el basal), devoluciones e indicaciones, objetivo
recomendado, informe de consulta con IA, artículos y recetas, y una vista de
organización.

Lo que hay que hacer en esta etapa:

- **Revisarlo entero desde el rol de la nutricionista**, igual que se hizo con
  la app: qué ve al entrar, qué hace en una consulta, qué le sobra y qué le
  falta. Mantener el look and feel.
- **Definir sus capacidades** como lista cerrada: qué puede ver, qué puede
  escribirle al paciente, qué puede cambiarle (objetivo, indicaciones), qué
  genera con IA.
- Lo que quedó sin hacer de `docs/panel-proximas-features.md` (§7, §8, §9),
  si después de la revisión sigue teniendo sentido.

## 3 · Cómo interactúan paciente y nutricionista

Hoy existe: el paciente da acceso con el código `CE-…` y elige qué categorías
ve la profesional. Ella le escribe devoluciones e indicaciones, le fija un
objetivo recomendado que el paciente aplica, y publica artículos y recetas.

A definir:

- El circuito completo, de punta a punta, en los dos lados a la vez: alta del
  vínculo, primera consulta, seguimiento semanal, cierre o corte del acceso.
- Qué avisos recibe cada uno y cuándo (devolución nueva, objetivo nuevo,
  paciente que dejó de registrar).
- La pantalla "Mi nutricionista" de la app, rediseñada con ese circuito ya
  claro.

## 4 · Pacientes y organizaciones

- **Flujo de "Pacientes"** de la nutricionista: lista, alta e invitación,
  estados (activo, en pausa, de alta), ficha, búsqueda y orden.
- **Organizaciones** para administrarlos: un consultorio o equipo con varias
  profesionales; miembros y roles (dueña, profesional); a qué profesional
  pertenece cada paciente y quién más puede verlo; pasar un paciente de una
  profesional a otra.
- La base ya tiene organizaciones (migración 49) y la vista
  `/organizacion` del panel: hay que llevarlo a un flujo completo y usable.

## 5 · Planes y funciones premium

Con los roles y capacidades definidos, armar la tabla final de planes:

| Plan | Para quién | Hoy |
|---|---|---|
| Gratis | Paciente | Registro completo, sin IA, con anuncios simulados |
| Premium | Paciente | Toda la IA, sin anuncios |
| Pro | Nutricionista | Panel, informes con IA, IA incluida para sus pacientes |
| Organización | Consultorio | A definir en la etapa 4 |

Regla vigente: **todo lo que usa IA es premium**. Hay que decidir qué capacidad
del panel y de la organización entra en cada plan, y que la app y el panel lo
hagan cumplir igual (`effective_plan()`, error 402 en las funciones con IA).
La compra sigue siendo simulada.

## 6 · Presentación de la tesis

Recién con 2 a 5 cerrados. Foco en negocio y rentabilidad; la técnica va de
respaldo. Insumos ya armados: el plan del escritorio
(`Ceres-plan-tesis.html`), la demo local en Docker (`tool/demo/`) y los datos
de uso reales medidos en producción.

---

## Pendientes transversales (antes de cualquier publicación)

- Aplicar las migraciones 48 a 54 en producción y desplegar `care-report`: la
  app de esta rama ya depende de columnas nuevas.
- Cargar `GEMINI_API_KEY` en `tool/demo/.env.demo` para que la IA responda en
  la demo.
- Pushear la rama `tesis` cuando se decida (hoy solo está en esta PC).
- Copiar `tool/demo/instantanea/` a la notebook de la defensa (datos de salud:
  no se sube a ningún lado).
