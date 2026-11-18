# Handoff · Tesis de Ceres (defensa: viernes 20 de noviembre de 2026)

Estado al 18 de noviembre de 2026, rama `tesis` (local, sin pushear).

## Qué hay en la rama

- App (Flutter) y panel del profesional (Next.js, `backoffice/`) con todo lo que
  se muestra en la defensa: alta de pacientes desde el panel (con datos iniciales
  y anamnesis), organización, resumen semanal por paciente, ficha día a día,
  análisis con IA, devoluciones, artículos con adjuntos, tablero con bienestar.
- Migraciones hasta `20261115000400_articulos_con_adjuntos.sql`. **Ninguna está
  en producción**: viven en la base local de la demo.
- La demo local completa en `tool/demo/` (ver su `README.md`), ahora también
  para macOS con `levantar.sh` / `bajar.sh`.

Todo lo de panel, publicidad, planes y organizaciones es **para la demo**:
después de la defensa se descarta y queda la app para uso personal.

## Mañana: armar la Mac

Objetivo: poder mostrar el panel en vivo si hace falta, y de reserva la app en
un emulador de Android.

1. **Instalar**
   - [Homebrew](https://brew.sh), y después:
     `brew install supabase/tap/supabase node git`
   - [Docker Desktop](https://www.docker.com/products/docker-desktop/) (la
     versión para el chip de la Mac). Abrirlo una vez y aceptar los permisos.
   - Solo para el emulador: `brew install --cask flutter android-studio`. Abrir
     Android Studio, dejar que baje el SDK, y en **Device Manager** crear un
     teléfono (Pixel, imagen arm64). Después `flutter doctor --android-licenses`
     y `flutter doctor` hasta que Android quede en verde.
2. **Traer el repo** a la Mac, con la rama `tesis`. Hoy la rama no está en
   GitHub. Dos caminos:
   - Pushearla (`git push -u origin tesis`) y clonar en la Mac.
   - Sin pushear: el bundle `ceres-tesis.bundle` del escritorio, por pendrive:
     `git clone -b tesis ceres-tesis.bundle Ceres`.
3. **Copiar por pendrive** (no por la nube):
   - `tool/demo/instantanea/` → misma ruta en la Mac. Son tus datos de salud y
     fotos; no está en git a propósito.
   - `tool/demo/.env.demo` (tiene `GEMINI_API_KEY`). Si no se copia, el script
     lo crea vacío y hay que completar la clave.
   - La carpeta `Ceres-presentacion/` del escritorio (la presentación).
4. **Levantar**, desde la raíz del repo:

   ```bash
   ./tool/demo/levantar.sh              # base, funciones y panel
   ./tool/demo/levantar.sh --emulador   # además, la app en el emulador
   ```

   La primera vez tarda (baja las imágenes de Docker; y la primera compilación
   de Android, varios minutos más). Panel en http://localhost:3100 con
   `valentina@demo.ceres.app` / `ceres-demo-2026`. Los logs quedan en
   `.demo/panel.log` y `.demo/funciones.log`.
5. **Ensayar el recorrido** de `tool/demo/README.md` → "Durante la demo".
6. Bajar: `./tool/demo/bajar.sh` (o `--borrar` para empezar de cero).

⚠️ `levantar.sh` **no se corrió nunca en una Mac**: se escribió hoy como par de
`levantar.ps1` y se probaron sus partes (la copia del `config.toml` con los
puertos da lo mismo que en Windows). Si algo falla, cada paso del script es un
comando suelto y se puede correr a mano en el mismo orden. Lo más probable de
fallar: permisos de Docker la primera vez, o un puerto ocupado
(`--puerto-base 57320`).

El túnel al teléfono real (`-Telefono`) quedó solo en Windows.

## La presentación

`C:\Users\gulin\Desktop\Ceres-presentacion\Ceres-presentacion.html`, 42
láminas. Se abre en Chrome: flechas para avanzar, **N** muestra las notas, **F**
pantalla completa. Copiar la carpeta entera (imágenes y videos al lado).

Decisiones de negocio que quedaron en el deck:

- Modelos por tarea: Gemini 3.5 Flash-Lite para registrar, Claude Opus 5.5 para
  resúmenes, informes y análisis; respaldo mutuo.
- Profesionales: $10 fijos del panel + escalonado por paciente activo (1-10 a
  $2, 11-30 a $1,70, 31+ a $1,50). Cada paciente: 90 análisis por mes (máx. 8
  por día), 4 resúmenes y 1 informe, sin fondo compartido. Recarga: 500
  análisis por $9.
- Personas: Free con 1 análisis por día del día completo, solo por texto, con
  anuncios (banner + un video al pedir el análisis); Premium $4,99 con 150
  análisis por mes, foto y voz, «¿Qué como?» y resumen semanal.
- Escenario: 20 profesionales y 20 personas → +$347 por mes, 51 % de margen.

## Follow-ups

**Lo que el deck presenta y el código todavía no hace** (si preguntan, es la
propuesta, no lo construido):

- Modelos: el código sigue con Gemini 3.6 Flash de principal y Claude Opus 5 de
  respaldo para todo. Cambiar a Flash-Lite + Opus 5.5 es otra tarea, y la
  precisión de Flash-Lite no está medida.
- Planes por tramos, 90 análisis por paciente, recargas: la base hoy tiene
  topes diarios y un fondo por consultorio.
- Free con el análisis del día completo (hoy Free no tiene IA) y los videos de
  publicidad (los anuncios son simulados).
- Micronutrientes (la app calcula calorías y macros). Verificar que la SARA 2
  traiga micronutrientes antes de afirmarlo.
- `docs/costos-y-precios.xlsx` tiene los números viejos.

**Pendientes de la app**

- Avisos de pals con la app cerrada: hoy llegan solo con la app abierta
  (Realtime). Falta decidir entre una tarea periódica en segundo plano o
  Firebase Cloud Messaging. Los recordatorios para registrar ya existen.

**Presentación**

- El título de la portada es provisorio.
- Regenerar el PDF si se cambia algo más.

**Después de la defensa**

- Borrar `tool/demo/instantanea/` de todas las máquinas donde se copió.
- Descartar panel, publicidad, planes y organizaciones; no subir estas
  migraciones a producción.
