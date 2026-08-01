#!/usr/bin/env python3
"""
Genera le illustrazioni del gioco con ComfyUI (SDXL), in locale.

    tools/.venv/bin/python tools/make_art.py briefing   # miniature scenari
    tools/.venv/bin/python tools/make_art.py icons      # icone delle azioni
    tools/.venv/bin/python tools/make_art.py            # tutte e due

Serve ComfyUI avviato su 127.0.0.1:8188 con sd_xl_base_1.0 fra i checkpoint.

PERCHE' IMMAGINI GENERATE E NON RITAGLI DELLA MAPPA
Le illustrazioni di Atlantic Chase sono di GMT e sono gia' nel gioco. Queste
servono a un'altra cosa: dare un'immagine agli scenari nel briefing e alle
azioni sui pulsanti, senza ritagliare altro materiale altrui. Sono immagini
nuove, prodotte qui, e restano brutte copie utili - non pretendono di essere
arte navale.

LO STILE
Non "foto di guerra": stampa d'epoca. Il gioco ha una tavolozza sobria, carta
e acquamarina, e un'illustrazione fotorealistica ci starebbe male e
sembrerebbe finta. Il prompt chiede una litografia navale anni Quaranta, a
tinte spente, e il post-processing la vira sui colori della mappa.

Ogni immagine ha un seme FISSO derivato dal nome: rigenerando si ottiene la
stessa immagine, e una modifica al prompt di uno scenario non ridisegna gli
altri diciannove.
"""

import hashlib
import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SERVER = "127.0.0.1:8188"
CHECKPOINT = "sd_xl_base_1.0_0.9vae.safetensors"

OUT_BRIEFING = os.path.join(ROOT, "assets", "art", "scenarios")
OUT_ICONS = os.path.join(ROOT, "assets", "art", "actions")

STYLE = ("1941 warship with heavy gun turrets and armoured superstructure, "
         "1940s naval lithograph poster, muted desaturated palette, "
         "aged paper texture, limited ink, engraved line work, "
         "dramatic north atlantic weather, no text, no lettering, "
         "no watermark, no signature")
NEGATIVE = ("tank, armoured vehicle, land battle, soldiers, desert, "
            "diptych, split panel, multiple frames, border, picture frame, "
            "text, letters, words, watermark, signature, logo, modern ship, "
            "jet, helicopter, missile, photorealistic, 3d render, cartoon, "
            "anime, oversaturated, neon, people portrait, faces, "
            # SDXL da solo disegna volentieri un transatlantico edoardiano al
            # posto di una corazzata: va detto esplicitamente cosa NON e'
            "ocean liner, cruise ship, passenger steamer, paddle steamer, "
            "sailing ship, tall ship, victorian steamship, funnels only")

# L'unica eccezione: in Op1 la nave e' davvero un transatlantico, il Bremen.
NEGATIVE_LINER = ("text, letters, words, watermark, signature, logo, "
                  "modern ship, jet, photorealistic, 3d render, cartoon, "
                  "anime, oversaturated, neon, faces, warship, gun turrets")

# --- gli scenari -------------------------------------------------------------
# Una riga per scenario: il soggetto storico, non la meccanica. Il briefing e'
# il momento in cui si decide se giocarlo, e un'immagine che racconta la
# situazione vale piu' di una che illustra una regola.
SCENARIOS = {
    "Op1 Homecoming":
        "a large ocean liner steaming alone at night through north atlantic "
        "fog, running dark, distant warship silhouettes on the horizon",
    "Op2 First Test":
        "two german battlecruisers sortieing into a grey north sea at dawn, "
        "heavy swell, smoke from four funnels",
    "Op3 Norway":
        "german warships escorting troop transports up a narrow norwegian "
        "fjord, snow covered cliffs, low winter light",
    "Op4 Berlin":
        "two battlecruisers hunting a merchant convoy in the open atlantic, "
        "scattered freighters on a wide grey horizon",
    "Op5 Rheinubung":
        "a great battleship at speed in heavy atlantic seas, bow wave "
        "breaking high, a heavy cruiser following astern",
    "Op6 New Friends":
        "an arctic convoy of freighters under a pale midnight sun, pack ice "
        "on the water, escorting cruisers on the flank",
    "Op7 Non Compos Mentis":
        "german capital ships anchored in a norwegian fjord under camouflage "
        "netting, mountains and low cloud",
    "Op8 Cat and Mouse":
        "a lone battleship shadowing an arctic convoy through snow squalls, "
        "visibility closing in",
    "Op9 Actic Calamity":
        "merchant ships scattering across an arctic sea, smoke on the "
        "horizon, a battleship bearing down",
    "MS1 Cornered":
        "a pocket battleship engaged by three light cruisers off a distant "
        "coast, gun flashes, shell splashes rising",
    "MS2 Escape":
        "a damaged pocket battleship running for a neutral harbour at dusk, "
        "smoke trailing, cruisers in pursuit",
    "MS3 Norwegian Patrol":
        "a lone battlecruiser and destroyers in a heavy northern gale, "
        "green water over the bows",
    "MS4 Chance Encounter":
        "an aircraft carrier caught in the open by two battlecruisers, "
        "flight deck empty, shell splashes closing",
    "MS5 With Friends Like These":
        "a fleet at anchor in a mediterranean harbour under fire from a "
        "squadron offshore, breakwater and shore batteries",
    "MS6 Hard Lesson":
        "a pocket battleship among a scattering merchant convoy, freighters "
        "burning on a winter sea",
    "MS7 Clash on the High Sea":
        "an old battleship standing between two battlecruisers and a convoy, "
        "heavy atlantic swell",
    "MS8 Another Opportunity":
        "two battlecruisers breaking off from a defended convoy, a lone "
        "battleship silhouetted against the smoke",
    "MS9 Sink the Bismarck":
        # la prima versione usciva come dittico, due riquadri affiancati:
        # chiedere una scena sola, con un punto di vista solo
        "single wide scene of a battleship firing broadside in the denmark "
        "strait while a stricken battlecruiser burns astern, one continuous "
        "seascape",
    "MS10 Three Days Later":
        "a crippled battleship steering in circles under fire from two "
        "battleships, heavy seas, smoke everywhere",
    "MS11 Skirmish on the Barents Sea":
        # "artico" + "neve" da soli portavano SDXL a disegnare una battaglia
        # TERRESTRE con i carri armati sulla neve: va detto che e' in mare
        "warships at sea on open arctic water exchanging gunfire in twilight, "
        "snow squalls over the waves, distant convoy smoke, no land in sight",
    "MS12 Finale":
        "a battleship trapped in polar darkness by radar-guided gunfire, "
        "star shell light, arctic night",
    "Campaign":
        "a wide north atlantic chart with warship silhouettes on every "
        "horizon, storm light, the whole ocean as a battlefield",
    "BL1 Raiders of the North Atlantic":
        "a lone commerce raider slipping through the blockade in heavy "
        "weather, merchant smoke far off",
}

# --- le azioni ---------------------------------------------------------------
# Icone quadrate, soggetto unico e leggibilissimo a 64 px: sono pulsanti, non
# quadri. Per questo il prompt chiede una silhouette e non una scena.
ACTIONS = {
    "ENGAGE": "two warship silhouettes closing head on, gun flash between them",
    "NAVAL_SEARCH": "a warship silhouette with a searching lookout and "
                    "binocular arcs sweeping the horizon",
    "AIR_STRIKE": "torpedo bombers in silhouette diving toward a warship",
    # la prima versione usciva come una torre, indistinguibile dal faro di
    # COMPLETION: serve il sommergibile INTERO, visto sopra e sotto la linea
    # d'acqua, non il solo periscopio
    "STEALTH_ATTACK": "a U-boat submarine surfaced on the sea, long low hull, "
                      "conning tower, side view",
    "TRAJECTORY": "a dotted course line curving across a sea chart with a "
                  "ship silhouette at one end",
    "COMPLETION": "a warship silhouette entering a harbour past a breakwater "
                  "and a lighthouse",
    "PASS": "an hourglass over a calm empty sea horizon",
    "REORGANIZE": "two ship silhouettes changing station, curved arrows "
                  "between them",
    "SIGNAL": "signal flags on a halyard against a warship mast",
}

ICON_STYLE = ("simple black ink pictogram on plain cream paper, one single "
              "centered subject, bold clean silhouette, thick strokes, "
              "vintage naval recognition manual plate, very high contrast, "
              "minimal detail, plenty of empty margin, no text, no lettering, "
              "no border")


def seed_for(name):
    """Seme stabile: rigenerare non ridisegna quello che non e' cambiato."""
    return int(hashlib.sha256(name.encode()).hexdigest()[:12], 16) % (2 ** 31)


def workflow(prompt, negative, seed, width, height, steps=28, cfg=6.5):
    return {
        "4": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": CHECKPOINT}},
        "6": {"class_type": "CLIPTextEncode",
              "inputs": {"text": prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode",
              "inputs": {"text": negative, "clip": ["4", 1]}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": width, "height": height, "batch_size": 1}},
        "3": {"class_type": "KSampler",
              "inputs": {"seed": seed, "steps": steps, "cfg": cfg,
                         "sampler_name": "dpmpp_2m", "scheduler": "karras",
                         "denoise": 1.0, "model": ["4", 0],
                         "positive": ["6", 0], "negative": ["7", 0],
                         "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode",
              "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": "ac", "images": ["8", 0]}},
    }


def post(path, payload):
    req = urllib.request.Request(
        "http://%s%s" % (SERVER, path),
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read())


def run(wf, timeout=600):
    pid = post("/prompt", {"prompt": wf})["prompt_id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(2)
        hist = json.loads(urllib.request.urlopen(
            "http://%s/history/%s" % (SERVER, pid)).read())
        if pid in hist:
            outs = hist[pid]["outputs"]
            imgs = outs.get("9", {}).get("images", [])
            if not imgs:
                raise RuntimeError("nessuna immagine prodotta")
            im = imgs[0]
            q = urllib.parse.urlencode(
                {"filename": im["filename"], "subfolder": im.get("subfolder", ""),
                 "type": im.get("type", "output")})
            return urllib.request.urlopen(
                "http://%s/view?%s" % (SERVER, q)).read()
    raise TimeoutError("ComfyUI non ha risposto entro %ds" % timeout)


def tone(data, size, sepia=True):
    """Vira l'immagine sui colori della mappa e la ridimensiona."""
    from PIL import Image, ImageEnhance
    im = Image.open(io.BytesIO(data)).convert("RGB")
    im = im.resize(size, Image.LANCZOS)
    if sepia:
        # la mappa e' carta e acquamarina: si smorza la saturazione e si
        # sposta il bianco verso la carta, per non stonare accanto ad essa
        im = ImageEnhance.Color(im).enhance(0.55)
        im = ImageEnhance.Contrast(im).enhance(1.08)
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b = px[x, y]
                px[x, y] = (min(255, int(r * 1.06)), min(255, int(g * 1.02)),
                            int(b * 0.94))
    return im


def generate(items, outdir, size, style, negative, sepia=True, steps=28,
             gen=None):
    """`gen` e' la risoluzione di GENERAZIONE, che non e' quella finale.

    SDXL e' addestrato a 1024x1024 e sotto i 700 px circa smette di comporre:
    le prime icone, generate a 256, sono uscite come macchie di colore
    astratte, irriconoscibili. Si genera grande e si rimpicciolisce.
    """
    os.makedirs(outdir, exist_ok=True)
    made, skipped = 0, 0
    for name in sorted(items):
        path = os.path.join(outdir, name.replace(" ", "_") + ".png")
        if os.path.exists(path):
            skipped += 1
            continue
        prompt = "%s, %s" % (items[name], style)
        neg = NEGATIVE_LINER if name.startswith("Op1") else negative
        print("  %-36s ..." % name[:36], end="", flush=True)
        t0 = time.time()
        gw, gh = gen if gen else (size[0] * 2, size[1] * 2)
        data = run(workflow(prompt, neg, seed_for(name), gw, gh, steps=steps))
        tone(data, size, sepia).save(path)
        made += 1
        print(" %.0fs" % (time.time() - t0))
    print("  fatte %d, gia' presenti %d -> %s"
          % (made, skipped, os.path.relpath(outdir, ROOT)))


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    try:
        urllib.request.urlopen("http://%s/system_stats" % SERVER, timeout=5)
    except Exception:
        print("ComfyUI non risponde su %s.\n"
              "Avvialo con:  cd ~/ComfyUI && venv/bin/python main.py" % SERVER)
        return 1
    if what in ("all", "briefing"):
        print("Miniature degli scenari:")
        generate(SCENARIOS, OUT_BRIEFING, (512, 288), STYLE, NEGATIVE,
                 gen=(1344, 768))
    if what in ("all", "icons"):
        print("Icone delle azioni:")
        generate(ACTIONS, OUT_ICONS, (128, 128), ICON_STYLE, NEGATIVE,
                 sepia=False, steps=26, gen=(1024, 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
