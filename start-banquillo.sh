#!/bin/bash
# Arranca "Sporting Banquillo" en un servidor local (necesario para que
# las fotos se puedan cargar y guardar: el navegador bloquea la lectura
# de archivos locales cuando la página se abre con doble clic, file://).
set -e
cd "$(dirname "$0")"

PORT=8744

echo "Sirviendo Sporting Banquillo en http://localhost:$PORT/sporting-banquillo.html"
open "http://localhost:$PORT/sporting-banquillo.html" 2>/dev/null || true

python3 -m http.server "$PORT"
