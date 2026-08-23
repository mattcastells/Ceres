# Publicar una versión

Ceres no está en Play Store. Cada versión es un **release de GitHub** con el
APK firmado adjunto, y la app se actualiza sola desde Configuración →
Actualizaciones.

---

## Configuración por única vez

Antes del primer release hay que cargar cuatro secretos en el repositorio:
`Settings → Secrets and variables → Actions → New repository secret`.

| Secreto | Qué va |
| --- | --- |
| `KEYSTORE_BASE64` | El `android/ceres-upload.jks` codificado en base64 |
| `KEYSTORE_PASSWORD` | `storePassword` de `android/key.properties` |
| `KEY_PASSWORD` | `keyPassword` de `android/key.properties` |
| `KEY_ALIAS` | `ceres` |
| `SUPABASE_URL` | `https://ifincvqdsotorvmwzpos.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | La `sb_publishable_…` de `env/local.json` |

Los dos últimos no son secretos de verdad — la publishable key está pensada para
viajar en el cliente — pero van como secretos igual para que no queden escritos
en los registros de cada compilación.

Para generar el base64 del keystore, desde la raíz del proyecto:

```powershell
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\ceres-upload.jks")) | Set-Clipboard
```

```bash
# bash
base64 -w0 android/ceres-upload.jks
```

> 🔑 **El keystore es irreemplazable.** Android exige que todas las versiones de
> una app estén firmadas con la misma clave. Si se pierde, no se puede publicar
> nunca más una actualización de Ceres: habría que sacar una app nueva, con
> otro `applicationId`, y nadie podría actualizar desde la vieja. Guardá una
> copia de `android/ceres-upload.jks` y `android/key.properties` fuera de
> esta máquina — gestor de contraseñas o un Drive privado.

Subirlo como secreto de GitHub **no cuenta como respaldo**: los secretos se
escriben pero no se pueden volver a leer.

---

## Compilar en tu máquina

La conexión a Supabase entra por `--dart-define`. Copiá
[`env/local.json.example`](../env/local.json.example) a `env/local.json`,
completá los dos valores y usalo en todos los comandos:

```bash
flutter run   --dart-define-from-file=env/local.json
flutter build apk --release --dart-define-from-file=env/local.json
```

`env/local.json` está en `.gitignore`. **Sin ese archivo la app compila y
arranca igual**, pero en modo local: no se puede iniciar sesión y los datos
viven solo en el teléfono. Es a propósito — así `flutter test` y un clon recién
bajado funcionan sin credenciales.

---

## Publicar

1. **Subir la versión** en `pubspec.yaml`. El formato es `semver+build`:

   ```yaml
   version: 1.1.0+2
   ```

   El número antes del `+` es lo que compara el updater; el de después es el
   `versionCode` de Android, que **tiene que crecer en cada release** o el
   teléfono se niega a instalar encima.

2. **Commitear y pushear** ese cambio a `main`.

3. **Tagear y pushear el tag**:

   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

El workflow [`release.yml`](../.github/workflows/release.yml) hace el resto:
verifica que el tag coincida con `pubspec.yaml`, corre `analyze` y los tests,
restaura el keystore, compila, verifica la firma y publica el release.

Si el tag y `pubspec.yaml` no coinciden, falla antes de compilar. Es a
propósito: un APK que dice `1.0.0` publicado bajo el tag `v1.1.0` rompe la
comparación de versiones del updater.

### Qué se publica

| Archivo | Para qué |
| --- | --- |
| `ceres-<v>-universal.apk` | **El único.** Anda en cualquier teléfono |

⚠️ El nombre es un contrato con la app: `GithubReleasesClient` busca el asset
que termina en `-universal.apk`. Si se cambia, el updater deja de encontrar la
actualización.

### Por qué hay un solo APK

Hasta la 1.3.1 se publicaban además tres APK por arquitectura, que pesaban la
mitad. Se dejaron de publicar porque rompían la actualización.

`--split-per-abi` le suma a cada APK un corrimiento por arquitectura en el
`versionCode` (`abi × 1000 + versionCode`). En la 1.3.1 quedó así:

| Archivo | `versionCode` |
| --- | --- |
| universal | 11 |
| armeabi-v7a | 1011 |
| arm64-v8a | 2011 |
| x86_64 | 4011 |

Eso existe para Play Store, donde la tienda elige el APK por dispositivo. Acá
el updater baja **siempre el universal**, así que quien había instalado el de
su arquitectura quedaba en 2011: la app le ofrecía la versión nueva, la
descargaba, y Android rechazaba la instalación por downgrade (2011 → 12). El
diálogo dice **"No se instaló la app"** y nada más, y no hay salida sin
desinstalar —perdiendo los datos locales.

Se intentó igualar los códigos desde `build.gradle.kts` con
`androidComponents.onVariants` y **no alcanza**: el plugin de Flutter los pisa
con la API vieja en un `afterEvaluate` posterior. Verificado con `aapt2 dump
badging`.

Por eso además el `versionCode` arrancó de nuevo en **5000**: cualquier número
por debajo de 4011 dejaría sin actualizar a quien tenga instalado un APK por
arquitectura de la 1.3.0 o la 1.3.1.

Si algún día vuelven los APK chicos, **primero** hay que hacer que el updater
elija el de la arquitectura del teléfono. El workflow verifica el `versionCode`
de todo lo que publica y falla si no coincide con `pubspec.yaml`.

---

## Cómo actualiza la app

`Configuración → Actualizaciones` consulta
`api.github.com/repos/mattcastells/Ceres/releases/latest`, compara con la
versión instalada y, si hay una posterior, ofrece bajar el APK universal y
abrirlo con el instalador de Android.

Tres decisiones detrás de eso:

- **La descarga es manual; el chequeo, no.** Al abrir la app se consulta si hay
  una versión nueva y, si la hay, se ofrece — nadie avisa de un release cuando
  se distribuye fuera de Play Store, y con la comprobación solo manual el
  resultado fue gente corriendo versiones de meses atrás. Lo que se hace sin
  permiso es **preguntar**: la consulta es un JSON de unos kilobytes, y los
  25 MB del APK siguen necesitando que alguien los pida. Con tres frenos para
  que no sea ruido: como mucho una consulta cada 6 horas, "Ahora no" calla esa
  versión y no las que vengan, y si la consulta falla no se dice nada porque no
  la pidió nadie (`presentation/screens/settings/update_prompt.dart`).
- **No hay token en el APK.** El repositorio es público y la API se consulta sin
  credenciales. Un token embebido en un APK es un token filtrado.
- **La app no instala nada.** Escribe el archivo y se lo pasa al instalador de
  paquetes; el diálogo de confirmación lo muestra Android.

La primera vez, Android pide habilitar a Ceres como origen de instalación
(`Ajustes → Apps → Ceres → Instalar apps desconocidas`). Eso lo concede la
persona, una sola vez, y no se puede evitar.

⚠️ **`REQUEST_INSTALL_PACKAGES` en el manifest no alcanza**: solo habilita a
*pedir* ese permiso. Hasta la 1.3.0 la app no lo chequeaba, y como lanzar el
intent devuelve éxito igual —el sistema descarta la instalación sin avisar—, la
pantalla decía "Android está instalando" y no pasaba nada. Desde la 1.3.0 el
instalador vive en `MainActivity.kt` con su propio `FileProvider`, consulta
`canRequestPackageInstalls()` **antes** de descargar y ofrece un botón que abre
esa pantalla de Ajustes ya filtrada por la app.

Como consecuencia, **una versión instalada anterior a la 1.3.0 no puede
actualizarse sola**: hay que bajar el `-universal.apk` a mano una vez.

### Si el repositorio pasara a privado

El updater deja de funcionar y **no alcanza con ponerle un token al cliente**.
Habría que mover la consulta a una Edge Function de Supabase que guarde el token
del lado del servidor y le devuelva a la app la URL de descarga.

### Si algún día va a Play Store

Hay que sacar el permiso `REQUEST_INSTALL_PACKAGES` del manifest y la descarga:
Google lo rechaza salvo para gestores de paquetes. El updater tendría que
limitarse a avisar que hay versión nueva y abrir la ficha de Play.

---

## Verificación continua

[`ci.yml`](../.github/workflows/ci.yml) corre en cada push a `main` y en cada
pull request: `flutter analyze --fatal-infos`, `flutter test`, y las suites
pgTAP de RLS y Storage contra un Postgres limpio con las 32 migraciones
aplicadas desde cero.
