#!/usr/bin/env bash
# Levanta la demo de Ceres en macOS (o Linux). Es el par de levantar.ps1.
#
#   ./tool/demo/levantar.sh               base + funciones + panel (http://localhost:3100)
#   ./tool/demo/levantar.sh --emulador    además abre la app en el emulador de Android
#   ./tool/demo/levantar.sh --resembrar   rehace el escenario (tu cuenta copiada no se toca)
#   ./tool/demo/levantar.sh --sin-panel   sin el panel
#   ./tool/demo/levantar.sh --puerto-base 57320
#
# No toca producción. Todo vive en `.demo/` (ignorado por git) y en contenedores
# de Docker propios ("ceres-demo"). Las funciones y el panel quedan corriendo en
# segundo plano, con su log en `.demo/funciones.log` y `.demo/panel.log`.
# Para bajar todo: ./tool/demo/bajar.sh
#
# Compatible con el bash 3.2 que trae macOS.

set -u

PUERTO_BASE=56320
EMULADOR=0
RESEMBRAR=0
SIN_PANEL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --emulador) EMULADOR=1 ;;
    --resembrar) RESEMBRAR=1 ;;
    --sin-panel) SIN_PANEL=1 ;;
    --puerto-base) shift; PUERTO_BASE="$1" ;;
    --telefono) echo "El túnel al teléfono solo está en levantar.ps1 (Windows). En la Mac, usá el emulador."; exit 1 ;;
    *) echo "Opción desconocida: $1"; exit 1 ;;
  esac
  shift
done

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$RAIZ/.demo"
DEMO="$RAIZ/tool/demo"
cd "$RAIZ"

paso() { printf '\n\033[36m== %s\033[0m\n' "$1"; }
falla() { printf '\n\033[31m✗ %s\033[0m\n' "$1"; exit 1; }
aviso() { printf '\033[33m%s\033[0m\n' "$1"; }
requiere() { command -v "$1" >/dev/null 2>&1 || falla "Falta '$1'. $2"; }
# Lee un campo de un JSON que llega por stdin.
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);const v=process.argv[1].split(".").reduce((a,k)=>a==null?a:a[k],o);process.stdout.write(v==null?"":String(v))})' "$1"; }

# ── 0 · Herramientas ──────────────────────────────────────────────────────
requiere docker   'Instalá Docker Desktop (https://www.docker.com/products/docker-desktop/).'
requiere supabase 'brew install supabase/tap/supabase'
requiere node     'brew install node'
requiere npm      'Viene con Node.'
[ "$EMULADOR" = 1 ] && requiere flutter 'brew install --cask flutter (y Android Studio con un emulador creado).'

# ── 1 · Configuración local (.env.demo) ───────────────────────────────────
ENV_FILE="$DEMO/.env.demo"
if [ ! -f "$ENV_FILE" ]; then
  cp "$DEMO/.env.demo.example" "$ENV_FILE"
  aviso 'Creé tool/demo/.env.demo a partir del ejemplo. Completá GEMINI_API_KEY para que la IA ande.'
fi
cfg() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; s/\r$//'; }
GEMINI_API_KEY="$(cfg GEMINI_API_KEY)"
ANTHROPIC_API_KEY="$(cfg ANTHROPIC_API_KEY)"
PASSWORD="$(cfg DEMO_PASSWORD)"; [ -n "$PASSWORD" ] || PASSWORD='ceres-demo-2026'
[ -n "$GEMINI_API_KEY" ] || aviso 'Sin GEMINI_API_KEY: la base, el panel y la app andan, pero la IA va a responder "no configurada".'

# ── 2 · Docker ────────────────────────────────────────────────────────────
paso 'Docker'
if ! docker info >/dev/null 2>&1; then
  if [ "$(uname)" = Darwin ]; then open -a Docker || falla 'No encontré Docker Desktop.'; fi
  echo 'Esperando a Docker Desktop...'
  i=0
  until docker info >/dev/null 2>&1; do
    i=$((i + 1)); [ $i -gt 60 ] && falla 'Docker no arrancó en 3 minutos.'
    sleep 3
  done
fi

# ── 3 · Directorio de trabajo (.demo/supabase) ────────────────────────────
# Una copia de `supabase/` con su propio nombre de proyecto y su propio rango de
# puertos, para no chocar con un `supabase start` del repo.
paso 'Preparando .demo/'
mkdir -p "$WORK/supabase"
for d in migrations functions; do
  rsync -a --delete "$RAIZ/supabase/$d/" "$WORK/supabase/$d/" || falla "No pude copiar supabase/$d."
done
PUERTO_BASE="$PUERTO_BASE" perl -pe '
  s/^project_id\s*=.*$/project_id = "ceres-demo"/;
  s/^(\s*(?:port|shadow_port)\s*=\s*)5[45]3(\d\d)\s*$/$1 . ($ENV{PUERTO_BASE} + $2 - 20) . "\n"/e;
' "$RAIZ/supabase/config.toml" > "$WORK/supabase/config.toml"
API_PORT=$((PUERTO_BASE + 1))

# ── 4 · Base de datos ─────────────────────────────────────────────────────
paso "Base de datos local (API en el puerto $API_PORT)"
EXCLUIR='imgproxy,studio,logflare,vector,supavisor,edge-runtime'
if ! supabase start --workdir "$WORK" -x "$EXCLUIR"; then
  echo 'La base todavía estaba arrancando; espero y reintento...'
  i=0
  while [ "$(docker inspect -f '{{.State.Health.Status}}' supabase_db_ceres-demo 2>/dev/null)" != healthy ]; do
    i=$((i + 1)); [ $i -gt 45 ] && break
    sleep 4
  done
  supabase start --workdir "$WORK" -x "$EXCLUIR" || falla 'supabase start falló. Si es un tema de puertos, probá con --puerto-base 57320.'
fi
supabase migration up --workdir "$WORK" --local >/dev/null || falla 'No pude aplicar las migraciones.'
ST="$(supabase status --workdir "$WORK" -o json 2>/dev/null)"
API="$(printf '%s' "$ST" | json API_URL)"
PUB="$(printf '%s' "$ST" | json PUBLISHABLE_KEY)"; [ -n "$PUB" ] || PUB="$(printf '%s' "$ST" | json ANON_KEY)"
SRV="$(printf '%s' "$ST" | json SERVICE_ROLE_KEY)"
[ -n "$API" ] && [ -n "$PUB" ] && [ -n "$SRV" ] || falla 'No pude leer las claves de la base local.'

# ── 5 · Escenario y tu cuenta ─────────────────────────────────────────────
paso 'Escenario de demostración'
export SUPABASE_URL="$API" SUPABASE_SERVICE_ROLE_KEY="$SRV" DESTINO_URL="$API" DESTINO_KEY="$SRV" DEMO_PASSWORD="$PASSWORD"

INSTANTANEA="$DEMO/instantanea"
MI_MAIL=''
if [ -f "$INSTANTANEA/cuenta.json" ]; then
  MI_MAIL="$(json email < "$INSTANTANEA/cuenta.json")"
  node "$DEMO/copiar_cuenta.mjs" --desde "$INSTANTANEA" || falla 'No pude copiar tu cuenta desde la instantánea.'
else
  aviso 'No hay instantánea de tu cuenta (tool/demo/instantanea/): la demo sigue solo con el escenario.'
fi

[ "$RESEMBRAR" = 1 ] && node "$DEMO/limpiar.mjs" --si
if [ -n "$MI_MAIL" ]; then
  node "$DEMO/sembrar.mjs" --amigo-de "$MI_MAIL" || true   # sale con 1 si el escenario ya estaba
else
  node "$DEMO/sembrar.mjs" || true
fi

# ── 6 · Funciones de IA (segundo plano) ───────────────────────────────────
paso 'Funciones de IA (log en .demo/funciones.log)'
FN_ENV="$WORK/functions.env"
cat > "$FN_ENV" <<EOF
GEMINI_API_KEY=$GEMINI_API_KEY
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
GEMINI_PROMPT_VERSION=v5
AI_DAILY_QUOTA=100000
WEEKLY_REPORT_QUOTA=100000
CARE_REPORT_QUOTA=100000
EOF
# Sin topes diarios en la demo: se prueba Premium sin que una cuota corte la
# prueba a la mitad. Producción mantiene los suyos.
detener() { [ -f "$1" ] && kill "$(cat "$1")" 2>/dev/null; rm -f "$1"; }
detener "$WORK/funciones.pid"
nohup supabase functions serve --workdir "$WORK" --env-file "$FN_ENV" > "$WORK/funciones.log" 2>&1 &
echo $! > "$WORK/funciones.pid"

# ── 7 · Panel de la nutricionista (segundo plano) ─────────────────────────
if [ "$SIN_PANEL" = 0 ]; then
  paso 'Panel (http://localhost:3100, log en .demo/panel.log)'
  BO="$RAIZ/backoffice"
  [ -d "$BO/node_modules" ] || (cd "$BO" && npm ci) || falla 'npm ci falló en backoffice/.'
  detener "$WORK/panel.pid"
  lsof -ti tcp:3100 2>/dev/null | xargs kill 2>/dev/null   # un panel viejo en el mismo puerto
  # Las variables del proceso le ganan a `.env.local`: el panel apunta a la
  # base local aunque ese archivo tenga las de producción.
  cd "$BO"
  NEXT_PUBLIC_SUPABASE_URL="$API" NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="$PUB" \
    nohup npm run dev -- -p 3100 > "$WORK/panel.log" 2>&1 &
  echo $! > "$WORK/panel.pid"
  cd "$RAIZ"
fi

# ── 8 · App ───────────────────────────────────────────────────────────────
paso 'Configuración de la app'
mkdir -p "$RAIZ/env"
cat > "$RAIZ/env/demo-emulador.json" <<EOF
{ "SUPABASE_URL": "http://10.0.2.2:$API_PORT", "SUPABASE_PUBLISHABLE_KEY": "$PUB", "CERES_DEMO": "true" }
EOF

if [ "$EMULADOR" = 1 ]; then
  # La primera fila con '•' es la de títulos ("Id • Name • …"): se saltea.
  EMU_ID="$(flutter emulators 2>/dev/null | grep '•' | grep -v -E '^[[:space:]]*Id[[:space:]]' | head -1 | cut -d'•' -f1 | xargs)"
  [ -n "$EMU_ID" ] && flutter emulators --launch "$EMU_ID" >/dev/null 2>&1
fi

# ── 9 · Resumen ───────────────────────────────────────────────────────────
CODIGO="$(curl -s -H "apikey: $SRV" -H "Authorization: Bearer $SRV" \
  "$API/rest/v1/profiles?select=care_code&care_code=not.is.null&display_name=eq.Lic.%20Valentina%20Ruiz" | json 0.care_code)"
paso 'Listo'
cat <<EOF
Panel:       http://localhost:3100   (tarda unos segundos la primera vez)
  Nutricionista: valentina@demo.ceres.app  /  $PASSWORD
  Su código:     $CODIGO
App (emulador): CERES_DEMO=1 flutter run --dart-define-from-file=env/demo-emulador.json
  Vos:           ${MI_MAIL:-(sin instantánea)}  /  $PASSWORD
  Gratis:        tomas@demo.ceres.app  /  $PASSWORD   (ve anuncios, sin IA)
  Premium:       julieta@demo.ceres.app  /  $PASSWORD   (toda la IA, sin anuncios ni topes)
  Paciente Pro:  lucia@demo.ceres.app  /  $PASSWORD
Para verte en el panel: en la app, Perfil → Mi nutricionista → $CODIGO
Para bajar todo: ./tool/demo/bajar.sh
EOF
if [ "$EMULADOR" = 1 ]; then
  echo
  echo 'Abriendo la app en el emulador (Ctrl+C la cierra; la base y el panel siguen)...'
  CERES_DEMO=1 flutter run --dart-define-from-file=env/demo-emulador.json
fi
