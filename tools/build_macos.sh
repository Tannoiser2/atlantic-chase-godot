#!/bin/sh
# Compila l'app per macOS, la firma e la sblocca da Gatekeeper.
#
#     sh tools/build_macos.sh
#
# Due cose diverse che vengono spesso confuse:
#
#   FIRMA        e' la firma del codice. Senza, macOS non apre proprio l'app.
#                Godot la mette gia' "ad-hoc" (una firma locale senza
#                certificato), e per un'app che gira solo su questo Mac basta.
#
#   QUARANTENA   e' un attributo che macOS appiccica a qualunque file
#                SCARICATO - da un browser, da GitHub, da AirDrop, da Mail. Non
#                c'entra niente con la firma: un'app compilata qui non ce l'ha,
#                la stessa app scaricata da GitHub ce l'ha, ed e' quello che fa
#                comparire "impossibile aprire perche' proviene da uno
#                sviluppatore non identificato".
#
# Questo script toglie la quarantena dall'app appena compilata. Se invece la
# SCARICHI su un altro Mac, li' va tolta di nuovo, con:
#
#     xattr -dr com.apple.quarantine "/percorso/Atlantic Chase.app"
#
# Per non doverlo fare mai piu' servirebbe un Developer ID Apple (99 $/anno) e
# la notarizzazione presso Apple. Se ne hai uno, mettilo in AC_SIGN_IDENTITY e
# lo script lo usa al posto della firma ad-hoc:
#
#     AC_SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" sh tools/build_macos.sh

set -e
cd "$(dirname "$0")/.."

APP="build/macos/Atlantic Chase.app"

echo "==> Esporto l'app"
mkdir -p build/macos
rm -rf "$APP"
godot --headless --path . --export-release "macOS" "$APP" >/dev/null

if [ ! -d "$APP" ]; then
	echo "ERRORE: l'export non ha prodotto $APP" >&2
	exit 1
fi

echo "==> Firmo"
if [ -n "$AC_SIGN_IDENTITY" ]; then
	# firma vera, con certificato: l'app funziona anche scaricata, ma per
	# evitare del tutto l'avviso serve anche la notarizzazione Apple
	codesign --force --deep --options runtime --timestamp \
		--sign "$AC_SIGN_IDENTITY" "$APP"
	echo "    firmata con: $AC_SIGN_IDENTITY"
	echo "    (per togliere l'avviso anche da scaricata serve la"
	echo "     notarizzazione: xcrun notarytool submit)"
else
	# firma ad-hoc, ricorsiva: '-' e' l'identita' locale senza certificato.
	# --deep firma anche quello che sta dentro il bundle, che e' il motivo
	# per cui a volte l'app parte da una cartella e non da un'altra.
	codesign --force --deep --sign - "$APP"
	echo "    firmata ad-hoc (nessun certificato: vale su questo Mac)"
fi

echo "==> Tolgo la quarantena"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Verifica"
codesign --verify --deep --strict "$APP" && echo "    firma valida"
if xattr "$APP" 2>/dev/null | grep -q quarantine; then
	echo "    ATTENZIONE: quarantena ancora presente" >&2
else
	echo "    nessuna quarantena"
fi

SIZE=$(du -sh "$APP" | cut -f1)
echo ""
echo "Fatto: $APP  ($SIZE)"
echo "Aprila con:  open \"$APP\""
