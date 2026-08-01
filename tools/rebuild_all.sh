#!/bin/sh
# Rigenera da zero tutti i dati derivati dal modulo VASSAL e dalla mappa.
#
# L'ordine conta: le annotazioni manuali vanno applicate PER ULTIME, perche'
# build_map_graph.py riscrive map_graph.json azzerando i lati negati.
#
#   uso:  sh tools/rebuild_all.sh
set -e
cd "$(dirname "$0")/.."
PY=tools/.venv/bin/python

echo "== 1. calibrazione del reticolo (lenta, ~2 min) =========================="
$PY tools/refine_lattice.py

echo "== 2. zone del modulo VASSAL ============================================"
$PY tools/extract_zones.py

echo "== 3. decodifica dei salvataggi ========================================="
$PY tools/vsav_extract.py

echo "== 4. validazione del reticolo contro le pedine ufficiali ==============="
$PY tools/validate_lattice.py

echo "== 5. area giocabile ===================================================="
$PY tools/classify_playable.py

echo "== 6. grafo ============================================================="
$PY tools/build_map_graph.py

echo "== 7. rifinitura per connessione del mare ==============================="
$PY tools/refine_playable.py

echo "== 8. annotazioni manuali (lati 'not adjacent', Canale di Kiel) ========="
$PY tools/apply_annotations.py

echo "== 9. scenari =========================================================="
$PY tools/import_scenarios.py

echo "== 10. asset ==========================================================="
$PY tools/prepare_assets.py

echo "== 11. ruolino navi (OCR delle pedine, ~4 min) =========================="
$PY tools/extract_ships.py
$PY tools/merge_ships.py

echo
echo "Fatto. Ora:  godot --headless --path . --script res://tests/run_tests.gd"
