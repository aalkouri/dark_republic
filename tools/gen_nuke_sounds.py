"""Synthesise the NUKE power-up's sounds (no samples needed).

audio/powerups/nuke.wav       the detonation: a blinding crack, a huge sub-bass thump that sags
                              in pitch, a roaring fireball, then a long rolling rumble as the
                              mushroom cloud climbs (about 7 s)
audio/powerups/nuke_wind.wav  the shockwave's rushing blast of wind (about 2 s), layered on top

    python3 tools/gen_nuke_sounds.py
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "powerups")


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def boom_channel(t, seed):
    r = np.random.default_rng(seed)
    noise = r.normal(0, 1, t.size)
    # 1) the crack: a bright, very short noise burst
    crack = bandpass(noise, 1200, 9000) * np.exp(-t / 0.03) * 1.4
    # 2) the thump: a sine falling from 70 Hz to 22 Hz (felt more than heard)
    f = 22 + 48 * np.exp(-t / 0.35)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.1) * 1.3
    # 3) the fireball roar: low-passed noise that swells and rolls on
    roar_env = (1 - np.exp(-t / 0.05)) * np.exp(-t / 1.6)
    roar = lowpass(noise, 520) * roar_env * 3.0
    # 4) the long rumble of the rising cloud, with slow swells
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * 0.7 * t + seed) * np.sin(2 * np.pi * 0.23 * t)
    rumble = lowpass(r.normal(0, 1, t.size), 70) * np.exp(-t / 3.2) * 6.0 * swell
    # 5) far-off crackle of debris
    debris = np.zeros_like(t)
    for _ in range(220):
        at = 0.15 + r.exponential(1.2)
        if at >= t[-1] - 0.05:
            continue
        n = int(SR * r.uniform(0.004, 0.03))
        i = int(at * SR)
        pop = r.normal(0, 1, n) * np.exp(-np.linspace(0, 6, n))
        debris[i:i + n] += pop * r.uniform(0.05, 0.3) * np.exp(-at / 2.0)
    debris = bandpass(debris, 400, 4000)
    return crack + thump + roar + rumble + debris


def finish(st, fade_s, peak=0.95, drive=1.3):
    st = np.tanh(st * drive)
    n = st.shape[0]
    fade = np.ones(n)
    fade[-int(SR * fade_s):] = np.linspace(1, 0, int(SR * fade_s)) ** 2
    st *= fade[:, None]
    st /= np.max(np.abs(st)) / peak
    return (st * 32767).astype(np.int16)


def nuke():
    t = np.arange(int(SR * 7.0)) / SR
    st = np.stack([boom_channel(t, 3), boom_channel(t, 4)], axis=1)
    return finish(st, 1.5)


def wind():
    t = np.arange(int(SR * 2.2)) / SR
    chans = []
    for seed in (5, 6):
        r = np.random.default_rng(seed)
        noise = r.normal(0, 1, t.size)
        env = np.minimum(1.0, t / 0.08) * np.exp(-t / 0.6)
        # a sweep from bright to dull as the front rushes past
        bright = highpass(bandpass(noise, 300, 6000), 200) * np.exp(-t / 0.35)
        dull = lowpass(noise, 600) * 2.5
        chans.append((bright + dull) * env)
    return finish(np.stack(chans, axis=1), 0.6, peak=0.8, drive=1.1)


def main():
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, "nuke.wav"), SR, nuke())
    wavfile.write(os.path.join(OUT, "nuke_wind.wav"), SR, wind())
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
