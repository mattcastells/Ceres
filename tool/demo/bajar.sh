#!/usr/bin/env bash
# Baja la demo en macOS (o Linux). Es el par de bajar.ps1.
#
#   ./tool/demo/bajar.sh            la base queda guardada: la próxima vez arranca con lo que había
#   ./tool/demo/bajar.sh --borrar   baja y borra: la próxima vez, de cero
set -u
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$RAIZ/.demo"
if [ ! -f "$WORK/supabase/config.toml" ]; then
  echo 'No hay entorno de demo en esta máquina.'
  exit 0
fi
for f in funciones panel; do
  if [ -f "$WORK/$f.pid" ]; then
    pid="$(cat "$WORK/$f.pid")"
    # El panel corre como `npm run dev`, que arranca a `next` como hijo.
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    rm -f "$WORK/$f.pid"
  fi
done
lsof -ti tcp:3100 2>/dev/null | xargs kill 2>/dev/null   # `next`, si quedó vivo
if [ "${1:-}" = --borrar ]; then
  supabase stop --workdir "$WORK" --no-backup
else
  supabase stop --workdir "$WORK"
fi
echo 'Demo abajo.'
