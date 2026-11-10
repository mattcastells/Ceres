<#
.SYNOPSIS
  Levanta el entorno completo de la demo de Ceres en esta máquina.

.DESCRIPTION
  Base de datos local (Docker), funciones de IA, el escenario de demostración,
  tu cuenta copiada, el panel de la nutricionista y la configuración de la app
  para el emulador (y opcionalmente para el teléfono, por un túnel HTTPS).

  No toca producción en ningún paso. Todo vive en `.demo/` (ignorado por git)
  y en contenedores de Docker propios ("ceres-demo"), separados de los que use
  `supabase start` en el repo.

  Se puede correr las veces que haga falta: lo que ya está levantado o
  sembrado no se repite.

.PARAMETER PuertoBase
  Primer puerto del rango. La API queda en PuertoBase+1 (56321 por defecto).
  Cambialo si Windows tiene reservado ese rango
  (`netsh interface ipv4 show excludedportrange protocol=tcp`).

.PARAMETER Telefono
  Abre un túnel HTTPS (cloudflared) y compila el APK "Ceres Demo" que apunta
  a él, para instalar en un teléfono real.

.PARAMETER Emulador
  Abre la app "Ceres Demo" en el primer emulador disponible.

.PARAMETER Resembrar
  Borra las cuentas de demostración y las vuelve a crear (tu cuenta copiada
  no se toca).

.EXAMPLE
  ./tool/demo/levantar.ps1 -Emulador
  ./tool/demo/levantar.ps1 -Telefono
#>
param(
  [int]$PuertoBase = 56320,
  [switch]$Telefono,
  [switch]$Emulador,
  [switch]$Resembrar,
  [switch]$SinPanel
)

$ErrorActionPreference = 'Stop'
$Raiz = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Work = Join-Path $Raiz '.demo'
$Demo = Join-Path $Raiz 'tool\demo'
Set-Location $Raiz

function Paso($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Falla($t) { Write-Host "`n✗ $t" -ForegroundColor Red; exit 1 }
function Requiere($cmd, $como) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Falla "Falta '$cmd'. $como" }
}

# ── 0 · Herramientas ──────────────────────────────────────────────────────
Requiere docker   'Instalá Docker Desktop.'
Requiere supabase 'Instalá la CLI de Supabase (scoop install supabase, o winget).'
Requiere node     'Instalá Node 20 o más nuevo.'
Requiere npm      'Viene con Node.'
if ($Telefono -or $Emulador) { Requiere flutter 'Instalá Flutter y agregalo al PATH.' }
if ($Telefono) { Requiere cloudflared 'Instalá cloudflared: winget install Cloudflare.cloudflared' }

# ── 1 · Configuración local (.env.demo) ───────────────────────────────────
$EnvFile = Join-Path $Demo '.env.demo'
if (-not (Test-Path $EnvFile)) {
  Copy-Item (Join-Path $Demo '.env.demo.example') $EnvFile
  Write-Host "Creé tool/demo/.env.demo a partir del ejemplo. Completá GEMINI_API_KEY para que la IA ande." -ForegroundColor Yellow
}
$Cfg = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$' } | ForEach-Object {
  $Cfg[$Matches[1]] = $Matches[2].Trim()
}
$Password = if ($Cfg.DEMO_PASSWORD) { $Cfg.DEMO_PASSWORD } else { 'ceres-demo-2026' }
if (-not $Cfg.GEMINI_API_KEY) {
  Write-Host 'Sin GEMINI_API_KEY: la base, el panel y la app andan, pero la IA va a responder "no configurada".' -ForegroundColor Yellow
}

# ── 2 · Docker ────────────────────────────────────────────────────────────
Paso 'Docker'
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  $dd = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
  if (Test-Path $dd) { Start-Process $dd } else { Falla 'Docker no está corriendo y no encontré Docker Desktop.' }
  Write-Host 'Esperando a Docker Desktop...'
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { break }
  }
  if ($LASTEXITCODE -ne 0) { Falla 'Docker no arrancó en 3 minutos.' }
}

# ── 3 · Directorio de trabajo (.demo/supabase) ────────────────────────────
# Una copia de `supabase/` con su propio nombre de proyecto y su propio rango
# de puertos: así no choca con el `supabase start` del repo ni con los puertos
# que Windows a veces reserva (54321-54340 en algunas máquinas).
Paso 'Preparando .demo/'
New-Item -ItemType Directory -Force (Join-Path $Work 'supabase') | Out-Null
foreach ($d in 'migrations', 'functions') {
  robocopy (Join-Path $Raiz "supabase\$d") (Join-Path $Work "supabase\$d") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Falla "No pude copiar supabase/$d." }
}
$conf = Get-Content (Join-Path $Raiz 'supabase\config.toml') -Raw
$conf = [regex]::Replace($conf, '(?m)^project_id\s*=.*$', 'project_id = "ceres-demo"')
$conf = [regex]::Replace($conf, '(?m)^(\s*(?:port|shadow_port)\s*=\s*)5[45]3(\d\d)\s*$', {
  param($m) $m.Groups[1].Value + ($PuertoBase + [int]$m.Groups[2].Value - 20)
})
Set-Content -Path (Join-Path $Work 'supabase\config.toml') -Value $conf -Encoding utf8
$ApiPort = $PuertoBase + 1

# ── 4 · Base de datos ─────────────────────────────────────────────────────
Paso "Base de datos local (API en el puerto $ApiPort)"
supabase start --workdir $Work -x realtime,imgproxy,studio,logflare,vector,supavisor,edge-runtime
if ($LASTEXITCODE -ne 0) { Falla 'supabase start falló. Si es un tema de puertos, probá con -PuertoBase 57320.' }
supabase migration up --workdir $Work --local | Out-Null
$st = supabase status --workdir $Work -o json | ConvertFrom-Json
$Api = $st.API_URL
$Pub = if ($st.PUBLISHABLE_KEY) { $st.PUBLISHABLE_KEY } else { $st.ANON_KEY }
$Srv = $st.SERVICE_ROLE_KEY
if (-not $Api -or -not $Pub -or -not $Srv) { Falla 'No pude leer las claves de la base local.' }

# ── 5 · Escenario y tu cuenta ─────────────────────────────────────────────
Paso 'Escenario de demostración'
$env:SUPABASE_URL = $Api
$env:SUPABASE_SERVICE_ROLE_KEY = $Srv
$env:DESTINO_URL = $Api
$env:DESTINO_KEY = $Srv
$env:DEMO_PASSWORD = $Password

$Instantanea = Join-Path $Demo 'instantanea'
$MiMail = $null
if (Test-Path (Join-Path $Instantanea 'cuenta.json')) {
  $MiMail = (Get-Content (Join-Path $Instantanea 'cuenta.json') -Raw | ConvertFrom-Json).email
  node (Join-Path $Demo 'copiar_cuenta.mjs') --desde $Instantanea
  if ($LASTEXITCODE -ne 0) { Falla 'No pude copiar tu cuenta desde la instantánea.' }
} else {
  Write-Host 'No hay instantánea de tu cuenta (tool/demo/instantanea/): la demo sigue solo con el escenario.' -ForegroundColor Yellow
}

if ($Resembrar) { node (Join-Path $Demo 'limpiar.mjs') --si }
$sembrarArgs = @((Join-Path $Demo 'sembrar.mjs'))
if ($MiMail) { $sembrarArgs += @('--amigo-de', $MiMail) }
node @sembrarArgs
# Sale con 1 si el escenario ya estaba: no es un error.

# ── 6 · Funciones de IA ───────────────────────────────────────────────────
Paso 'Funciones de IA (ventana aparte)'
$FnEnv = Join-Path $Work 'functions.env'
@(
  "GEMINI_API_KEY=$($Cfg.GEMINI_API_KEY)"
  "ANTHROPIC_API_KEY=$($Cfg.ANTHROPIC_API_KEY)"
  'GEMINI_PROMPT_VERSION=v5'
) | Set-Content -Path $FnEnv -Encoding utf8
Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$Raiz'; `$host.UI.RawUI.WindowTitle = 'Ceres demo · funciones'; supabase functions serve --workdir '$Work' --env-file '$FnEnv'"

# ── 7 · Panel de la nutricionista ─────────────────────────────────────────
if (-not $SinPanel) {
  Paso 'Panel (ventana aparte, http://localhost:3100)'
  $bo = Join-Path $Raiz 'backoffice'
  if (-not (Test-Path (Join-Path $bo 'node_modules'))) {
    Push-Location $bo; npm ci; Pop-Location
  }
  # Las variables del proceso le ganan a `.env.local`, así que el panel apunta
  # a la base local aunque ese archivo tenga las de producción.
  Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$bo'; `$host.UI.RawUI.WindowTitle = 'Ceres demo · panel'; `$env:NEXT_PUBLIC_SUPABASE_URL='$Api'; `$env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='$Pub'; npm run dev -- -p 3100"
}

# ── 8 · App ───────────────────────────────────────────────────────────────
Paso 'Configuración de la app'
New-Item -ItemType Directory -Force (Join-Path $Raiz 'env') | Out-Null
$EmuJson = Join-Path $Raiz 'env\demo-emulador.json'
@{ SUPABASE_URL = "http://10.0.2.2:$ApiPort"; SUPABASE_PUBLISHABLE_KEY = $Pub; CERES_DEMO = 'true' } |
  ConvertTo-Json | Set-Content -Path $EmuJson -Encoding utf8

if ($Emulador) {
  $emu = (flutter emulators 2>$null | Select-String '•' | Select-Object -First 1)
  if ($emu) {
    $id = ($emu.ToString() -split '•')[0].Trim()
    flutter emulators --launch $id | Out-Null
  }
  Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$Raiz'; `$host.UI.RawUI.WindowTitle = 'Ceres demo · app'; `$env:CERES_DEMO='1'; adb wait-for-device; flutter run --dart-define-from-file=env/demo-emulador.json"
}

if ($Telefono) {
  Paso 'Túnel HTTPS para el teléfono'
  $log = Join-Path $Work 'cloudflared.log'
  Remove-Item $log -ErrorAction SilentlyContinue
  Start-Process cloudflared -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$ApiPort" -RedirectStandardError $log -WindowStyle Minimized
  $url = $null
  for ($i = 0; $i -lt 40 -and -not $url; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $log) {
      $m = Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1
      if ($m) { $url = $m.Matches[0].Value }
    }
  }
  if (-not $url) { Falla 'El túnel no dio una dirección. Revisá la conexión a internet.' }
  $TelJson = Join-Path $Raiz 'env\demo-telefono.json'
  @{ SUPABASE_URL = $url; SUPABASE_PUBLISHABLE_KEY = $Pub; CERES_DEMO = 'true' } |
    ConvertTo-Json | Set-Content -Path $TelJson -Encoding utf8
  Write-Host "Túnel: $url"
  Paso 'Compilando "Ceres Demo" para el teléfono'
  $env:CERES_DEMO = '1'
  flutter build apk --debug --dart-define-from-file=env/demo-telefono.json
  if ($LASTEXITCODE -ne 0) { Falla 'No compiló el APK.' }
  $apk = Join-Path $Raiz 'build\app\outputs\flutter-apk\app-debug.apk'
  if (adb devices | Select-String "`tdevice$") {
    adb install -r $apk
  } else {
    Write-Host 'No hay un teléfono conectado por USB: instalá el APK a mano.' -ForegroundColor Yellow
  }
  Write-Host "APK: $apk (se instala como 'Ceres Demo', al lado de tu app real)"
  Write-Host '⚠️ La dirección del túnel cambia cada vez: si lo cerrás, hay que volver a correr con -Telefono.' -ForegroundColor Yellow
}

# ── 9 · Resumen ───────────────────────────────────────────────────────────
$h = @{ apikey = $Srv; Authorization = "Bearer $Srv" }
$vale = Invoke-RestMethod -Headers $h -Uri "$Api/rest/v1/profiles?select=care_code,display_name&care_code=not.is.null&display_name=eq.Lic.%20Valentina%20Ruiz"
Paso 'Listo'
Write-Host @"
Panel:       http://localhost:3100
  Nutricionista: valentina@demo.ceres.app  /  $Password
  Su código:     $($vale[0].care_code)
App (emulador): flutter run --dart-define-from-file=env/demo-emulador.json  (con `$env:CERES_DEMO='1')
  Vos:           $(if ($MiMail) { "$MiMail  /  $Password" } else { '(sin instantánea)' })
  Gratis:        tomas@demo.ceres.app  /  $Password   (ve anuncios, sin IA)
  Paciente Pro:  lucia@demo.ceres.app  /  $Password
Para verte en el panel: en la app, Perfil → Mi nutricionista → $($vale[0].care_code)
Para bajar todo: ./tool/demo/bajar.ps1
"@
