---
name: publicar
description: Publicar una versión de Ceres y verificarla de verdad. Usar cuando haya que sacar un release, subir la versión, empujar un tag, aplicar migraciones a Supabase, desplegar Edge Functions, o cuando falle una actualización en el teléfono ("no se instaló la app", "no me deja actualizar"). Incluye las trampas que ya nos costaron versiones enteras.
---

# Publicar Ceres

Ceres se distribuye **fuera de Play Store**: cada versión es un release de
GitHub con un APK firmado, y la app se actualiza sola desde Configuración →
Actualizaciones.

Esta skill existe porque publicar acá tiene trampas que no se deducen del
código y que ya costaron tres versiones seguidas.

## Antes que nada: verificar, no suponer

La regla de oro del proyecto. Cada afirmación sobre un artefacto se comprueba
contra el artefacto, no contra el código que debería haberlo producido.

```bash
flutter analyze          # tiene que dar "No issues found!"
flutter test             # todos en verde
```

## Publicar

1. **Subir la versión en `pubspec.yaml`.**

   ```yaml
   version: 1.4.1+5003
   ```

   ⚠️ El número después del `+` es el `versionCode` de Android y **solo puede
   crecer**. Arranca en 5000 por una razón concreta: las versiones 1.3.0 y
   1.3.1 publicaron APK por arquitectura con el corrimiento de Flutter y el más
   alto que quedó instalado fue **4011**. Cualquier número por debajo deja a esa
   gente sin poder actualizar nunca más.

2. **Commit y push a `main`.** Es el procedimiento del repo
   (`docs/releases.md`), no una excepción.

3. **Tag y push del tag.** El tag tiene que coincidir con `pubspec.yaml` o el
   workflow falla antes de compilar.

   ```bash
   git tag v1.4.1 && git push origin v1.4.1
   ```

`release.yml` hace el resto: verifica el tag, corre analyze y tests, restaura
el keystore, compila, **verifica el versionCode con aapt2**, verifica la firma
y publica.

## Verificar el release publicado

Sobre el archivo que va a bajar el teléfono, no sobre el build local:

```bash
V=1.22.0   # la versión recién publicada; los releases anteriores al renombre se llaman nutrimat-<v>-universal.apk
curl -sL -o /tmp/nm.apk "https://github.com/mattcastells/Ceres/releases/download/v$V/ceres-$V-universal.apk"
AAPT=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools"/*/aapt2.exe | tail -1)
"$AAPT" dump badging /tmp/nm.apk | head -1   # versionCode y versionName
APKSIGNER=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools"/*/apksigner.bat | tail -1)
"$APKSIGNER" verify --print-certs /tmp/nm.apk | grep "SHA-256 digest"
```

La firma **siempre** tiene que dar `9294fb83ce08f6438b07518d8914b5aa43452ab326da33ecbf936a19ebe6e8da`.
Si cambia, el APK no instala encima del que la gente tiene.

## Trampas que ya nos mordieron

### "No se instaló la app" — es un downgrade de versionCode

No es el permiso. `--split-per-abi` le suma un corrimiento por arquitectura
(`abi × 1000 + code`), y como el updater baja **siempre el universal**, quien
instaló el de su ABI queda con un código más alto que cualquier versión futura.
Por eso **se publica un solo APK**. No volver a activar `--split-per-abi` sin
antes hacer que el updater elija por arquitectura.

Diagnóstico: mirar el `versionCode` que muestra la pantalla de Actualizaciones
(ej. `1.3.0 (2010)`) y compararlo con el del APK nuevo.

### El instalador necesita permiso por app

`REQUEST_INSTALL_PACKAGES` en el manifest solo habilita a **pedir**. Desde
Android 8 quien autoriza es la persona, por app instaladora. Sin eso
`startActivity` devuelve éxito y el sistema descarta la instalación en
silencio. Está resuelto en `MainActivity.kt` (`canRequestPackageInstalls()`).

### Un build local puede devolver un APK viejo

Ni la duración ni `flutter clean` alcanzan para detectarlo:

```bash
(cd android && ./gradlew --stop)
rm -rf build .dart_tool android/.gradle android/app/build
flutter pub get && flutter build apk --release --dart-define-from-file=env/local.json
```

Para confirmar que el APK es el del código, buscar un texto nuevo dentro de
`libapp.so` (se extrae del APK, que es un zip). Es la única prueba que no
miente.

⚠️ **Y `grep` miente acá.** Dart guarda cada cadena en Latin-1 si le entra, y
en **UTF-16** si tiene aunque sea una letra que no entra — los puntos
suspensivos tipográficos (`…`), una comilla curva, un guion largo—. En UTF-16
la cadena queda como `A\0b\0r\0…`, así que **ni siquiera un prefijo ASCII la
encuentra**: buscar "Abriendo" no da nada aunque "Abriendo el micrófono…" esté
adentro. Lleva a concluir que el APK es viejo cuando no lo es.

Buscar en las tres codificaciones, no en una:

```bash
node -e '
const b = require("fs").readFileSync("lib/arm64-v8a/libapp.so");
for (const s of process.argv.slice(1)) {
  const d = ["latin1","utf16le","utf8"]
    .filter(e => b.indexOf(Buffer.from(s, e)) >= 0);
  console.log((d.length ? "OK  " : "NO  ") + s + "  " + d.join(" "));
}' "Tu texto nuevo" "Otro con acentós…"
```

### Sin `--dart-define-from-file` el APK no tiene servidor

Compila y arranca igual, en modo local: no autentica y los datos no salen del
teléfono. Un APK así entregado para probar no sirve para nada que use cuenta.

## Supabase

### Migraciones

`supabase db push --linked` **no anda desde esta máquina** (host directo IPv6).
Con el session pooler sí, sin Docker y sin `supabase login`:

```bash
set -a; . ./supabase/.env.local; set +a
PWENC=$(node -e 'process.stdout.write(encodeURIComponent(String(process.env.SUPABASE_DB_PASSWORD)))')
DBURL="postgresql://postgres.ifincvqdsotorvmwzpos:${PWENC}@aws-0-sa-east-1.pooler.supabase.com:5432/postgres"

supabase db push --db-url "$DBURL" --dry-run
supabase db push --db-url "$DBURL"
supabase migration list --db-url "$DBURL"   # verificar
```

Sin Docker tira warnings de `failed to connect to the docker API`: son del
caché del catálogo, no de la migración. **Confirmar siempre con
`migration list`.**

### Edge Functions

⚠️ **No se despliegan con el release.** Cambiar una función y publicar una
versión de la app deja el código nuevo en el repo y el viejo corriendo.

```bash
supabase functions deploy analyze-meal-photo --project-ref ifincvqdsotorvmwzpos
supabase functions deploy analyze-meal-text  --project-ref ifincvqdsotorvmwzpos
supabase functions deploy food-search        --project-ref ifincvqdsotorvmwzpos
```

`analyze-meal-photo` y `analyze-meal-text` comparten `_shared/estimation.ts`:
si tocás una, **desplegá las dos** — el bundler copia el módulo dentro de cada
función.

Antes de desplegar, parsear (CI ya lo hace, pero acá es instantáneo):

```bash
npx esbuild@0.24.0 --bundle supabase/functions/<f>/index.ts \
  --format=esm --platform=neutral --external:jsr:* --outfile=/dev/null
```

⚠️ **TypeScript no concatena literales adyacentes.** `'a' 'b'` es válido en
Dart y un error de sintaxis en TS. Escribir siempre `'a' + 'b'`. Este error
tumbó dos funciones enteras.

### Diagnosticar contra la base real

Read-only, con `pg` desde Node. Sirve para responder con datos en vez de
suponer: latencias de la IA (`ai_analyses.latency_ms`), si existe el respaldo
de alguien (`storage.objects` del bucket `backups`), políticas RLS, sesiones.

## Invariantes que no se negocian

Salieron de un día perdiendo datos de un usuario real.

1. **Lo que no se puede leer se aparta, no se borra.** `LocalStore` nunca hace
   `remove()` sobre un documento que no pudo interpretar.
2. **Cada registro se lee por separado.** Uno malo no se lleva puesto el resto.
3. **Un documento sin un solo registro no se sube jamás.** Es la última línea
   de defensa del respaldo y no depende de que la puerta de `openAfterRestore`
   esté bien.
4. **Una lectura fallida y un teléfono vacío no se pueden ver igual.**
   `RestoreOutcome` los distingue y la app lo dice en Inicio.
5. **Todo `await` contra la red lleva timeout propio.** Una espera eterna es la
   peor forma de contar un fallo: no se distingue de estar por terminar.
6. **Ningún número de nutrición se inventa ni se muestra sin validar.** Los
   datos de ARGENFOODS se validan contra Atwater (4/4/9) en el parser y otra
   vez como test sobre el archivo publicado.
7. **El respaldo no se pisa a sí mismo.** Cada subida escribe la copia "última"
   y una fechada en `{uid}/history/`, de las que se conservan diez. Un archivo
   único que se sobrescribe es un punto de falla, no un respaldo.
8. **No se sube nada que no se pueda releer.** Antes de viajar, el documento
   tiene que parsear y traer la clave `profile` — lo mismo que `importJson`
   exige para aceptarlo. Un respaldo que la propia app rechazaría al restaurar
   no es un respaldo.

## Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| Estado del proyecto y las mordidas | `ESTADO.md` |
| Procedimiento de release | `docs/releases.md` |
| Backend, migraciones, funciones | `supabase/README.md` |
| Fuente de verdad funcional | `docs/handoff/` |
