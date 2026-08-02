#!/usr/bin/env python3
"""
Genera gli effetti sonori della Battaglia in assets/audio/.

I suoni sono SINTETIZZATI qui, non campionati: non c'e' nessun file di terzi da
licenziare, e il risultato e' rigenerabile cambiando due numeri invece che
ricercando un campione. Sono tutti mono a 22050 Hz, 16 bit - piu' che
sufficiente per cannonate e schizzi d'acqua, e pesano pochi kB l'uno.

    tools/.venv/bin/python tools/make_sounds.py

I mattoni sono tre: rumore bianco filtrato (l'acqua e le esplosioni), seni con
la frequenza che scende (il tonfo di una bordata, il gemito di una nave che
affonda) e inviluppi esponenziali. Le cannonate della Seconda Guerra Mondiale
registrate da lontano sono quasi tutte bassa frequenza: e' per questo che qui
si filtra cosi' tanto verso il basso.
"""
import os
import struct
import wave

import numpy as np

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "audio")

rng = np.random.default_rng(20200)      # fisso: due esecuzioni danno lo stesso file


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(SR * dur))


def t(dur):
    return np.linspace(0.0, dur, int(SR * dur), endpoint=False)


def lowpass(x, cutoff):
    """Un polo solo. Basta: qui serve togliere brillantezza, non progettare filtri."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1.0 - a) * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sweep_lowpass(x, f0, f1):
    """Passa-basso con la frequenza di taglio che scivola: e' quello che da'
    a un'esplosione la sensazione di allontanarsi invece di spegnersi."""
    cuts = np.linspace(f0, f1, len(x))
    a = np.exp(-2.0 * np.pi * cuts / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1.0 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def env(dur, attack, decay):
    n = int(SR * dur)
    e = np.exp(-np.linspace(0.0, dur, n, endpoint=False) / decay)
    na = max(int(SR * attack), 1)
    e[:na] *= np.linspace(0.0, 1.0, na)
    return e


def chirp(dur, f0, f1):
    """Seno con la frequenza che scende. La fase e' l'integrale della
    frequenza: sbagliare questo e' il modo classico di ottenere un clic."""
    tt = t(dur)
    f = np.linspace(f0, f1, len(tt))
    return np.sin(2.0 * np.pi * np.cumsum(f) / SR)


def save(name, x, peak=0.85):
    x = np.nan_to_num(x)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    # 5 ms di dissolvenza in coda: senza, il taglio secco fa un clic
    nf = min(int(SR * 0.005), len(x))
    if nf:
        x[-nf:] *= np.linspace(1.0, 0.0, nf)
    data = (x * 32767).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("  %-14s %5.2f s  %6d byte" % (name, len(x) / SR, os.path.getsize(path)))


def gun():
    """Bordata. Attacco durissimo, coda bassa: da lontano di una cannonata
    navale arrivano soprattutto i bassi."""
    d = 0.85
    body = sweep_lowpass(noise(d), 900, 120) * env(d, 0.001, 0.16)
    thump = chirp(d, 110, 38) * env(d, 0.002, 0.22) * 1.4
    crack = highpass(noise(d), 2000) * env(d, 0.0005, 0.02) * 0.5
    return body + thump + crack


def splash():
    """Schizzo: il colpo e' caduto in acqua. Attacco piu' morbido di una
    cannonata e niente bassi - e' acqua che sale, non ferro che esplode."""
    d = 0.7
    up = highpass(noise(d), 700) * env(d, 0.02, 0.13)
    fall = lowpass(noise(d), 2500) * env(d, 0.10, 0.30) * 0.6
    return up + fall


def hit():
    """Colpo a segno: esplosione con dentro il suono del metallo."""
    d = 1.1
    blast = sweep_lowpass(noise(d), 3000, 200) * env(d, 0.001, 0.30)
    sub = chirp(d, 90, 30) * env(d, 0.001, 0.35) * 1.2
    metal = (np.sin(2 * np.pi * 430 * t(d)) + np.sin(2 * np.pi * 611 * t(d))) \
        * env(d, 0.002, 0.09) * 0.35
    return blast + sub + metal


def torpedo():
    """Lancio di siluri: aria compressa e poi la scia."""
    d = 1.2
    hiss = highpass(noise(d), 1800) * env(d, 0.01, 0.5) * 0.8
    # la scia: rumore che si apre col passare del tempo
    wake = sweep_lowpass(noise(d), 300, 1600) * env(d, 0.15, 0.6)
    return hiss + wake


def sink():
    """Affondamento: il suono piu' lungo del gioco, e deve esserlo."""
    d = 2.6
    groan = (chirp(d, 150, 42) * 0.9 + chirp(d, 226, 61) * 0.4) \
        * env(d, 0.15, 1.1)
    rumble = lowpass(noise(d), 180) * env(d, 0.05, 1.3) * 1.1
    water = highpass(noise(d), 900) * env(d, 0.5, 0.9) * 0.45
    return groan + rumble + water


def fire():
    """Incendio a bordo: crepitio da mandare in ciclo finche' il marcatore
    resta sulla nave. Impulsi casuali, non rumore continuo: il fuoco schiocca."""
    d = 2.0
    n = int(SR * d)
    out = np.zeros(n)
    for _ in range(420):
        i = rng.integers(0, n - 400)
        ln = int(rng.integers(60, 380))
        out[i:i + ln] += rng.uniform(-1, 1, ln) * np.exp(
            -np.linspace(0, 6, ln)) * rng.uniform(0.2, 1.0)
    body = lowpass(noise(d), 700) * 0.35
    y = lowpass(out, 5000) + body
    # dissolvenza incrociata sui bordi, se no il ciclo fa un colpo secco
    nf = int(SR * 0.15)
    head = y[:nf].copy()
    y[:nf] = y[:nf] * np.linspace(0, 1, nf) + y[-nf:] * np.linspace(1, 0, nf)
    y = y[:-nf]
    return y


def klaxon():
    """Allarme di combattimento: suona una volta all'inizio della Battaglia."""
    d = 1.4
    tt = t(d)
    tone = (np.sin(2 * np.pi * 233 * tt) + 0.5 * np.sin(2 * np.pi * 466 * tt)
            + 0.25 * np.sin(2 * np.pi * 699 * tt))
    # due colpi di tromba
    gate = np.zeros(len(tt))
    for a, b in ((0.02, 0.5), (0.72, 1.30)):
        i, j = int(a * SR), int(b * SR)
        g = np.ones(j - i)
        g[:int(SR * 0.03)] = np.linspace(0, 1, int(SR * 0.03))
        g[-int(SR * 0.08):] = np.linspace(1, 0, int(SR * 0.08))
        gate[i:j] = g
    return tone * gate


def main():
    os.makedirs(OUT, exist_ok=True)
    print("suoni della Battaglia -> %s" % OUT)
    for name, fn in [("gun.wav", gun), ("splash.wav", splash),
                     ("hit.wav", hit), ("torpedo.wav", torpedo),
                     ("sink.wav", sink), ("fire.wav", fire),
                     ("klaxon.wav", klaxon)]:
        save(name, fn())


if __name__ == "__main__":
    main()
