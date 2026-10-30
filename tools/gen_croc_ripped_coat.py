"""Bake Dr. Croc's ripped lab coat (models/dr_croc/dr_croc_ripped.jpg) for his Mutagen form.

Takes the model's albedo atlas (dr_croc_Image_0.jpg), finds the white lab-coat pixels and tears
long jagged rips through them: scaly green hide showing through each rip, a dark shadowed lip
along it, frayed fibres at the edges, and grubby strain creases where the cloth is pulled tight.
Everything that isn't the coat is left alone, so the swap is invisible except on the coat.

    python3 tools/gen_croc_ripped_coat.py
"""
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "models/dr_croc/dr_croc_Image_0.jpg"
OUT = "models/dr_croc/dr_croc_ripped.jpg"
rng = np.random.default_rng(7)


def value_noise(h, w, cells):
    """Smooth value noise, `cells` lattice cells across."""
    g = rng.random((cells + 3, cells + 3))
    ys = np.linspace(0, cells, h, endpoint=False)
    xs = np.linspace(0, cells, w, endpoint=False)
    return ndimage.map_coordinates(g, np.meshgrid(ys, xs, indexing="ij"), order=3, mode="wrap")


def aniso(h, w, cx, cy):
    """Noise stretched along one axis: `cx` cells across, `cy` cells down (two octaves)."""
    out = np.zeros((h, w))
    for o, a in ((1, 1.0), (2, 0.4)):
        g = rng.random((cy * o + 3, cx * o + 3))
        yy = np.linspace(0, cy * o, h, endpoint=False)
        xx = np.linspace(0, cx * o, w, endpoint=False)
        out += ndimage.map_coordinates(g, np.meshgrid(yy, xx, indexing="ij"), order=3, mode="wrap") * a
    return out / 1.4


def fbm(h, w, base, octaves=4):
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(h, w, base * 2 ** o) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def main():
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = img.shape
    mx = img.max(2)
    mn = img.min(2)
    luma = img @ np.array([0.299, 0.587, 0.114])
    coat = (luma > 0.68) & ((mx - mn) < 0.16)
    coat = ndimage.binary_opening(coat, iterations=2)
    coat_soft = ndimage.gaussian_filter(coat.astype(np.float32), 1.0)

    # Gashes: long jagged holes torn along the stretch (anisotropic noise blobs, ragged edges),
    # plus thinner splits running on from them
    gash = np.zeros((h, w))
    for cx, cy, amp in ((3, 16, 1.0), (16, 3, 1.0), (5, 22, 0.5)):
        gash += aniso(h, w, cx, cy) * amp
    gash /= 2.5
    rag = (fbm(h, w, 60, 2) - 0.5) * 0.09
    tear = np.clip((gash + rag - 0.575) / 0.012, 0, 1)
    split = np.abs(fbm(h, w, 6) - 0.5)
    tear = np.maximum(tear, np.clip((0.006 + rag * 0.3 - split) / 0.003, 0, 1) * (gash > 0.5))
    tear *= coat_soft

    # Frayed fibres: loose threads hanging across each rip
    hole = tear > 0.5
    threads = (aniso(h, w, 300, 40) > 0.78) | (aniso(h, w, 40, 300) > 0.8)
    fibres = threads & hole & (ndimage.distance_transform_edt(hole) < 6)

    # Scaly hide showing through, in shadow near the torn edge
    cells = ndimage.distance_transform_edt(fbm(h, w, 70, 1) > 0.5)
    scales = np.clip(cells / 4.0, 0, 1)
    hide = np.stack([0.15 + 0.12 * scales, 0.26 + 0.16 * scales, 0.08 + 0.05 * scales], 2)
    hide *= (0.8 + 0.4 * fbm(h, w, 20, 2))[..., None]
    inner = np.clip(ndimage.distance_transform_edt(hole) / 5.0, 0, 1)
    hide *= (0.35 + 0.65 * inner)[..., None]

    # The torn edge: a dark ragged line, cloth curling round it, strain creases pulled across
    edge = ndimage.binary_dilation(hole, iterations=2) & ~hole
    lip = np.clip(ndimage.gaussian_filter(tear, 3.0) * 2.0 - tear, 0, 1) * coat_soft
    crease = np.abs(np.sin((np.arange(w)[None, :] * 0.9 + np.arange(h)[:, None] * 0.35 + fbm(h, w, 8) * 60.0) * 0.35))
    crease = (1.0 - crease ** 0.25) * 0.06 * coat_soft
    grime = (fbm(h, w, 14) - 0.5) * 0.14 * coat_soft

    out = img.copy()
    out *= (1.0 - crease - lip * 0.35 + grime)[..., None]
    out = out * (1 - tear[..., None]) + hide * tear[..., None]
    out[edge & coat] = out[edge & coat] * 0.35 + np.array([0.18, 0.16, 0.12]) * 0.65
    out[fibres] = np.array([0.88, 0.87, 0.82])
    out = np.clip(out, 0, 1)
    Image.fromarray((out * 255).astype(np.uint8)).save(OUT, quality=92)
    print(OUT, f"coat {coat.mean():.1%} of the atlas, torn {tear.sum() / max(1, coat.sum()):.1%} of it")


if __name__ == "__main__":
    main()
