#!/bin/sh
# Esporta il gioco per il web e lo serve sulla rete locale, per giocarci da
# iPad o da un altro computer di casa.
#
#   sh tools/serve_web.sh [porta]
#
# L'export usa il preset "Web" di export_presets.cfg, che ha thread_support
# disattivato: cosi' il browser non pretende gli header di cross-origin
# isolation e basta un banale server statico come questo.
set -e
cd "$(dirname "$0")/.."
PORT="${1:-8777}"

echo "== export =="
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html >/dev/null 2>&1
du -sh build/web | awk '{print "  build/web: " $1}'

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
echo
echo "== server =="
echo "  su questo Mac:  http://localhost:$PORT"
[ -n "$IP" ] && echo "  da iPad/altro:  http://$IP:$PORT   (stessa rete Wi-Fi)"
echo "  Ctrl+C per fermare"
echo
cd build/web && exec python3 -m http.server "$PORT" --bind 0.0.0.0
