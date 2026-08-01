# Atlantic Chase — versione digitale (Godot 4.7)

Implementazione digitale di *Atlantic Chase* (GMT Games, 2020), a partire dal
modulo VASSAL v2.1 e dai regolamenti in italiano.

---

## ⚠️ Attribuzione e limiti d'uso — leggere prima di tutto

**Atlantic Chase è un gioco di GMT Games LLC. Design: Jeremy White.
Copyright © 2020 GMT Games LLC. Tutti i diritti riservati.**

Questo repository non è affiliato a GMT Games, non è autorizzato da GMT Games,
e **non sostituisce l'acquisto del gioco**. È un progetto amatoriale e senza
scopo di lucro, nato come strumento personale per giocare a una copia del gioco
posseduta.

**Questo repository è PRIVATO**, e per questo contiene anche la mappa, le
pedine e i regolamenti tradotti, per comodità d'uso personale. Sono tutti
materiale © GMT Games (la traduzione italiana di G. Sorio riporta *"PER SOLO
USO PERSONALE – vietata la vendita"*).

**Se un giorno lo rendi pubblico**, rimetti prima le righe indicate in
`.gitignore` per escludere `assets/`, `docs/regolamento/` e `reports/*.png`: un
repository pubblico è distribuzione a chiunque, a prescindere dall'uso che ne
fa il proprietario.

**Se GMT Games chiede la rimozione di questo repository o di parte del suo
contenuto, va rimosso senza discutere.** Per giocare ad Atlantic Chase,
comprate il gioco: <https://www.gmtgames.com>

---

---

## Avvio rapido

```bash
godot --path . --import          # una volta, per costruire la cache
godot --path .                   # avvia
```

Premi **F1** in gioco per l'elenco dei comandi.

### Rigenerare i dati dal modulo VASSAL

Non serve al primo avvio (i dati sono già nel repository), ma se cambia il
modulo o vuoi rifare tutto da capo:

```bash
python3 -m venv tools/.venv && tools/.venv/bin/pip install numpy scipy pillow pymupdf
sh tools/rebuild_all.sh
```

Rifà l'intera catena: calibrazione del reticolo, decodifica dei 22 salvataggi,
grafo della mappa, scenari, asset e ruolino navi. Serve la cartella `images/`
del modulo VASSAL nella directory **superiore** a questa.

### App per macOS

```bash
sh tools/build_macos.sh
```

Produce `build/macos/Atlantic Chase.app` (binario universale, ~173 MB), la
firma e le toglie la quarantena. Si apre con un doppio clic.

**Firma e quarantena sono due cose diverse**, e vengono spesso confuse:

- la **firma** è la firma del codice; senza, macOS non apre l'app. Godot ne
  mette una *ad-hoc*, cioè locale e senza certificato: per un'app che gira su
  questo Mac basta.
- la **quarantena** è un attributo che macOS appiccica a qualunque file
  **scaricato** — browser, GitHub, AirDrop, Mail. Non c'entra con la firma:
  l'app compilata qui non ce l'ha, la stessa app scaricata da GitHub sì, ed è
  quella che fa comparire *"proviene da uno sviluppatore non identificato"*.

Se la scarichi su un altro Mac, lì va tolta di nuovo:

```bash
xattr -dr com.apple.quarantine "/percorso/Atlantic Chase.app"
```

Per non doverlo fare mai più servono un **Developer ID Apple** (99 $/anno) e la
notarizzazione. Se ne hai uno, lo script lo usa al posto della firma ad-hoc:

```bash
AC_SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" sh tools/build_macos.sh
```

### Giocare da iPad (o da un altro dispositivo di casa)

```bash
sh tools/serve_web.sh
```

Esporta in HTML5 e apre un server sulla rete locale; lo script stampa
l'indirizzo da aprire in Safari sull'iPad. Nessuna pubblicazione: resta tutto
in casa.

I gesti touch: **due dita** spostano la mappa e zoomano, **un dito** seleziona e
disegna la Traiettoria, **un tocco prolungato** fa quello che fa il clic destro.

L'export usa `thread_support` disattivato apposta, così il browser non pretende
gli header di cross-origin isolation e basta un server statico banale.

### Test

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

1048 verifiche su 9 suite. Esce con codice 1 al primo fallimento, quindi è
usabile direttamente in CI.

---

## Come è fatto

Il principio è uno solo: **il motore di gioco non sa che Godot esiste**. Tutto
ciò che sta in `core/` è GDScript puro (`RefCounted`, nessun `Node`), quindi
gira headless, si testa in millisecondi e potrà essere riusato per un bot o per
un server senza toccarlo.

```
core/           logica pura, zero dipendenze da Node
  map/          coordinate esagonali, grafo della mappa
  state/        Traiettoria, Task Force, GameState serializzabile
  rules/        Scorrere del Tempo, Totale Traiettoria, Interruzione,
                motore delle Azioni, Risultati Comuni, Completamento,
                Punti Vittoria
  battle/       Mappa di Battaglia: raggi, cannoni, siluri, manovra, fuga
  engine/       RNG con seme, registro comandi con undo/redo
  data/         map_graph.json, tables.json, actions.json, ships.json,
                scenarios/, victory/
ui/             rendering e input (Godot): splash, mappa, battaglia, pannelli
tools/          pipeline Python: calibrazione, estrazione, import
tests/          runner headless senza dipendenze esterne
reports/        diagnostica generata (non versionata)
```

### Il reticolo esagonale

Il modulo VASSAL **non contiene la griglia**: nel `buildFile.xml` non c'è
nessuna `HexGrid`, solo 81 `Zone` per box porto e tracce. In VASSAL le pedine si
trascinano a occhio. Il reticolo è stato quindi ricostruito dall'immagine della
mappa:

| parametro | valore |
|---|---|
| passo centro-centro | 213.50 px |
| rotazione | 44.28° |
| origine | (1745.00, 1692.00) |
| circumraggio / apotema | 123.27 / 106.75 px |
| esagoni giocabili | 156 |

Il reticolo è **ruotato**: GMT ha inclinato la griglia per adattarla alla
geografia dell'Atlantico, quindi le formule standard pointy-top / flat-top non
si applicano e `Hex` usa direttamente i due vettori di base misurati.

**Validazione indipendente:** i 22 salvataggi ufficiali contengono 238 pedine
Traiettoria e Stazione piazzate a mano. Agganciandole al reticolo, **il 100%
cade nell'esagono corretto** (residuo mediano 33 px per le traiettorie e 15 px
per le stazioni, contro un apotema di 106.75). È una verifica che non dipende
da come il reticolo è stato ricavato.

### Le tabelle

Tutte le tabelle sono state lette **dall'immagine della mappa a risoluzione
nativa**, non dall'estrazione testuale dei PDF, che perde le celle e sposta le
righe (verificato: la tabella dell'Interruzione estratta dal PDF ha bande di
righe sbagliate). I simboli dei Risultati Comuni sono stati identificati
renderizzando il regolamento a 150 dpi e guardandoli, non deducendoli:

| icona | risultato |
|---|---|
| occhio con pupilla bianca | Contatto |
| occhio con pupilla rossa | Schermaglia |
| cilindro dorato | Avvistato |
| tessera "Clos" | Ridurre le Distanze |
| barre rosso-bianco-rosso | In Anticipo o In Ritardo |
| barre tutte rosse | Seguire |

Ogni azione in `actions.json` ha un campo `verified`. **Il motore rifiuta di
risolvere un'azione non verificata** invece di inventarsi un risultato: meglio
un errore esplicito che una regola sbagliata applicata in silenzio.

---

## Stato

Vedi `STATO.md` per il dettaglio di cosa è completo, parziale o assente.
