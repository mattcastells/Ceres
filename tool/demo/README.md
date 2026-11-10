# La demo de Ceres, en local

Todo lo que se muestra en la defensa corre en la notebook: la base de datos
(Docker), las funciones de IA, el panel de la nutricionista y la app. **Producción
no se toca**, y lo que se haga en un ensayo no le llega a la cuenta real.

## Qué hay en la demo

| Quién | Mail | Plan | Para qué |
| --- | --- | --- | --- |
| Lic. Valentina Ruiz | `valentina@demo.ceres.app` | Pro, dueña del consultorio · código **`CE-VRUZ26`** | El panel: equipo, devoluciones, informes, organización |
| Lic. Martín Sosa | `martin@demo.ceres.app` | Pro · código `CE-MSSA27` | Segunda profesional del consultorio |
| Vos | tu mail real | Premium | Tus 105+ días reales, copiados de una instantánea |
| Lucía, Diego, Carla, Pablo… (10) | `<nombre>@demo.ceres.app` | Gratis → IA pagada por Valentina | Pacientes con patrones distintos (abajo) |
| Tomás, Julieta | `tomas@`, `julieta@demo.ceres.app` | Gratis | Ven anuncios y no tienen IA; son tus pals |

Contraseña de todas: la de `DEMO_PASSWORD` en `.env.demo` (por defecto
`ceres-demo-2026`).

Los pacientes están armados para que el panel tenga algo que contar:

- **Pablo** dejó de registrar hace 6 días → aparece primero, en ámbar.
- **Diego** registra déficit y la balanza no se mueve → "¿Los números cierran?".
- **Carla** come poca proteína y tiene una indicación vigente.
- **Javier** cena tarde, comparte solo comidas y tiene una indicación sin leer.
- **Sofía** tuvo angina hace 9 días (día de enfermedad marcado).
- **Martina** quiere ganar músculo y come de menos.
- **Camila** empezó hace 10 días.

## La primera vez en la notebook

1. Instalar: Docker Desktop, la CLI de Supabase, Node 20+, Flutter y Android
   Studio (con un emulador creado). Para el teléfono: `winget install Cloudflare.cloudflared`.
2. Clonar el repo y pasarse a la rama `tesis`.
3. Copiar la carpeta **`tool/demo/instantanea/`** desde esta PC (pendrive, no
   por la nube: son tus datos de salud y tus fotos). No está en git a propósito.
4. Copiar `tool/demo/.env.demo.example` a `tool/demo/.env.demo` y poner la
   `GEMINI_API_KEY` (sale de https://aistudio.google.com/apikey).
5. En PowerShell, desde la raíz del repo:

   ```powershell
   ./tool/demo/levantar.ps1 -Emulador
   ```

   La primera vez tarda (baja las imágenes de Docker). Al final imprime las
   cuentas y el código de Valentina.

6. En la app del emulador, entrar con tu mail y, en **Perfil → Mi
   nutricionista**, cargar el código de Valentina (`CE-VRUZ26`, fijo). Desde ahí aparecés en su
   panel. (Esto mismo se puede hacer en vivo en la defensa.)

Panel: http://localhost:3100, con `valentina@demo.ceres.app`.

## Con el teléfono real

```powershell
./tool/demo/levantar.ps1 -Telefono
```

Abre un túnel HTTPS a la base local y compila "Ceres Demo", que se instala
**al lado** de tu app real (otro id: `io.ceres.app.demo`). Si el teléfono está
conectado por USB, lo instala solo.

⚠️ La dirección del túnel gratuito cambia cada vez que se abre: si se cierra,
hay que correr `-Telefono` de nuevo (y reinstalar). El día de la defensa,
levantarlo ahí mismo, con el emulador como plan B.

## Durante la demo, el recorrido

1. **App (vos)**: foto de un plato → revisión → guardar. Texto o voz:
   "un café con leche y dos medialunas".
2. **Panel (Valentina)**: la comida aparece en tu ficha. Pestaña **Informe con
   IA** → generar. **Devoluciones** → "Proponer borrador" → editar → publicar.
3. **App**: la devolución aparece en Inicio, en "De tu nutricionista".
4. **Panel**: "Analizar el equipo con IA" en la portada; **Organización** con
   el fondo de IA del consultorio.
5. **App (Tomás, plan gratis)**: anuncios en Historial/Buscar/Progreso, la IA
   pide Premium → **Planes** → "Pasarme a Premium" (compra simulada) → los
   anuncios desaparecen y la IA se habilita. "Volver al plan Gratis (demo)"
   lo deja listo para repetir.
6. **App (vos)**: Progreso → **Tu semana con IA**.

## Bajar, reiniciar, borrar

```powershell
./tool/demo/bajar.ps1            # baja; la próxima vez arranca con lo que había
./tool/demo/bajar.ps1 -Borrar    # baja y borra: la próxima vez, de cero
./tool/demo/levantar.ps1 -Resembrar   # deja todo igual salvo el escenario, que se rehace
```

## Cómo está hecho (por si preguntan)

- `levantar.ps1` copia `supabase/` a `.demo/` con su propio nombre de proyecto
  (`ceres-demo`) y puertos 56320-56329, así no choca con nada (`-PuertoBase`
  lo cambia si Windows tiene ese rango reservado).
- `sembrar.mjs` / `limpiar.mjs`: el escenario, con mails `@demo.ceres.app`.
  `limpiar.mjs` también sirve contra producción si algún día se siembra ahí:
  borra solo ese dominio.
- `copiar_cuenta.mjs --guardar`: produce la instantánea desde producción (solo
  lectura). `--desde`: la restaura en la base local.
- Los planes (migración 49) y la compra simulada (51) existen solo para las
  cuentas de este escenario: una cuenta sin plan asignado es Premium.

## Después de la defensa

Borrar `tool/demo/instantanea/` de todas las máquinas donde se copió.
