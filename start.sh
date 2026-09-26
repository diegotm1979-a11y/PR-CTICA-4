#!/bin/bash
# Arranca la web app de jugadores: vigilancia del Numbers + servidor local.
set -e
cd "$(dirname "$0")"

PORT=8743

echo "Iniciando vigilancia del archivo Numbers (exporta y actualiza datos automáticamente)..."
python3 scripts/watch_and_export.py &
WATCH_PID=$!

cleanup() {
  echo "Deteniendo..."
  kill "$WATCH_PID" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

sleep 1
echo "Sirviendo la web app en http://localhost:$PORT"
open "http://localhost:$PORT" 2>/dev/null || true

cd webapp
python3 -m http.server "$PORT"

cleanup
