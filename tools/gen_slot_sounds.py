"""Synthesise the chest slot machine sounds (no samples needed) into audio/ui/.

slot_pull.wav    - the lever: a ratchety mechanical clack-clack and a spring thunk
slot_tick.wav    - one reel detent clicking past (played rapidly while the reels spin)
slot_stop.wav    - a reel locking into place: a solid clunk
slot_win.wav     - a short bright three-note chime (+1 level)
slot_jackpot.wav - three of a kind: a rising arpeggio, bells and a shower of coins

    python3 tools/gen_slot_sounds.py
"""
import numpy as np
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(11)
OUT = "audio/ui/"


def env(n, attack=0.002, decay=10.0):
    t = np.arange(n) / SR
    a = np.minimum(1.0, t / max(attack, 1e-4))
    return a * np.exp(-decay * t)


def click(dur=0.03, freq=2400, noise=0.6, decay=160.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * freq * t) * 0.5 + rng.normal(0, noise, n)
    return s * env(n, 0.0005, decay)


def thunk(dur=0.18, freq=120, decay=28.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = freq * (1 + 0.6 * np.exp(-30 * t))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * rng.normal(0, 1, n) * np.exp(-60 * t)
    return s * env(n, 0.001, decay)


def bell(freq, dur=0.6, decay=5.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for k, (r, a) in enumerate([(1, 1.0), (2.0, 0.45), (3.01, 0.25), (4.2, 0.12)]):
        s += a * np.sin(2 * np.pi * freq * r * t) * np.exp(-decay * (1 + k * 0.6) * t)
    return s * env(n, 0.003, 0.0)


def mix(parts, total):
    out = np.zeros(int(SR * total))
    for at, snd, gain in parts:
        i = int(SR * at)
        j = min(len(out), i + len(snd))
        out[i:j] += snd[: j - i] * gain
    return out


def save(name, s, peak=0.85):
    s = s / (np.max(np.abs(s)) + 1e-9) * peak
    wavfile.write(OUT + name, SR, (s * 32767).astype(np.int16))


# Lever: ratchet clicks going down, a spring thunk at the bottom, a lighter clack coming back
pull_parts = [(0.012 * k, click(0.025, 1800 + 120 * k, 0.5), 0.55) for k in range(9)]
pull_parts += [(0.13, thunk(0.22, 95, 22), 1.0), (0.3, click(0.04, 1500, 0.7, 90), 0.6)]
save("slot_pull.wav", mix(pull_parts, 0.5))

save("slot_tick.wav", mix([(0.0, click(0.035, 2600, 0.45, 200), 1.0)], 0.04), 0.5)

save("slot_stop.wav", mix([(0.0, thunk(0.2, 140, 30), 1.0), (0.0, click(0.03, 1200, 0.8, 120), 0.5)], 0.22))

notes = [784.0, 988.0, 1175.0]   # G5 B5 D6
save("slot_win.wav", mix([(0.09 * k, bell(f, 0.7, 4.5), 1.0) for k, f in enumerate(notes)], 1.0), 0.7)

arp = [523.3, 659.3, 784.0, 1046.5, 1318.5, 1568.0]
jack = [(0.075 * k, bell(f, 0.9, 3.5), 1.0) for k, f in enumerate(arp)]
jack += [(0.5, bell(2093.0, 1.4, 2.2), 0.9), (0.5, bell(1568.0, 1.4, 2.2), 0.7)]
for _ in range(40):   # coins
    f = rng.uniform(2600, 3600)
    jack.append((rng.uniform(0.45, 1.6), bell(f, 0.15, 30.0), rng.uniform(0.15, 0.35)))
save("slot_jackpot.wav", mix(jack, 2.0), 0.8)
print("slot sounds written to", OUT)
