"""Synthesise Dr. Croc's flask-landing sounds: small glass vials shattering (audio/abilities/).

glass_break_1..3   a sharp crack, a cluster of bright inharmonic glass pings and a short
                   rattle of tinkling shards, with a faint wet fizz of acid underneath.
                   Three variants so a volley of flasks doesn't sound like one sample.

    python3 tools/gen_glass_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/abilities/"


def t_of(d):
    return np.arange(int(SR * d)) / SR


def hp(x, hz, o=2):
    return sosfilt(butter(o, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    if n > 0:
        buf[i:i + n] += snd[:n]


def ping(rng, f, d, decay, amp):
    """One glass fragment ringing: a few inharmonic partials with a click on top."""
    t = t_of(d)
    x = np.zeros_like(t)
    for r, a in ((1.0, 1.0), (2.32, 0.5), (4.25, 0.3), (6.8, 0.15)):
        ff = f * r * (1 + rng.uniform(-0.01, 0.01))
        if ff > SR / 2 - 500:
            continue
        x += a * np.sin(2 * np.pi * ff * t + rng.uniform(0, 6.28)) * np.exp(-t * decay * (0.7 + r * 0.3))
    click = hp(rng.standard_normal(len(t)), 4000) * np.exp(-t * 900) * 0.6
    return (x + click) * amp


def glass(seed, d=0.75):
    rng = np.random.default_rng(seed)
    x = np.zeros(int(SR * d))
    # The crack: a hard broadband snap, highs heavy
    n = rng.standard_normal(int(SR * 0.05))
    crack = hp(n, 1800) * np.exp(-t_of(0.05) * 140) * 1.4
    crack += bp(n, 600, 2400) * np.exp(-t_of(0.05) * 220) * 0.6
    place(x, crack, 0.0)
    # The vial bursting: a dense cluster of pings in the first few ms
    for _ in range(14):
        f = rng.uniform(2200, 7800)
        place(x, ping(rng, f, 0.35, rng.uniform(18, 40), rng.uniform(0.15, 0.4)), rng.uniform(0.0, 0.025))
    # Shards skittering and tinkling down, thinning out
    at = 0.03
    while at < d - 0.12:
        f = rng.uniform(3000, 9500)
        amp = 0.28 * np.exp(-at * 5.0) * rng.uniform(0.4, 1.0)
        place(x, ping(rng, f, 0.12, rng.uniform(45, 90), amp), at)
        at += rng.exponential(0.018) + 0.004
    # A thin wet fizz of acid hitting the ground
    fz = t_of(d)
    fizz = hp(rng.standard_normal(len(fz)), 5000) * (1 - np.exp(-fz * 40)) * np.exp(-fz * 6) * 0.12
    x += fizz * (1 + 0.6 * (rng.random(len(fz)) > 0.995))
    return x


def write(name, x, peak=0.8):
    x = np.tanh(x * 1.2)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.03)
    x[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([x, np.roll(x, int(SR * 0.003))], 1)
    wavfile.write(OUT + name + ".wav", SR, (st * 32767).astype(np.int16))
    print(name, f"{len(x) / SR:.2f}s")


def main():
    for k, seed in enumerate((101, 202, 303)):
        write(f"glass_break_{k + 1}", glass(seed))


if __name__ == "__main__":
    main()
