"""Shrink the textures inside a .glb (in place): every embedded image is resized so its longest
side is at most MAX_SIZE and re-encoded (JPEG for colour/roughness, PNG kept for images with
transparency). Meshes, skins and animations are untouched. Higgsfield/Meshy exports carry 2K
PBR maps (~12-17 MB per character); 1K is plenty for a game character and ~4x smaller.

    python3 tools/shrink_glb.py models/<id>/<id>.glb [more.glb ...]
"""
import io
import json
import struct
import sys

from PIL import Image

MAX_SIZE = 1024
JPEG_QUALITY = 88


def shrink(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF", path
    jlen, jtype = struct.unpack("<I4s", data[12:20])
    gltf = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, btype = struct.unpack("<I4s", data[off:off + 8])
    binbuf = data[off + 8:off + 8 + blen]

    image_views = {img["bufferView"]: i for i, img in enumerate(gltf.get("images", [])) if "bufferView" in img}
    new_bin = bytearray()
    for vi, view in enumerate(gltf["bufferViews"]):
        start = view.get("byteOffset", 0)
        chunk = binbuf[start:start + view["byteLength"]]
        if vi in image_views:
            img_meta = gltf["images"][image_views[vi]]
            im = Image.open(io.BytesIO(chunk))
            im.load()
            if max(im.size) > MAX_SIZE:
                scale = MAX_SIZE / max(im.size)
                im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
            out = io.BytesIO()
            if im.mode in ("RGBA", "LA") and im.getextrema()[-1][0] < 255:
                im.save(out, "PNG", optimize=True)
                img_meta["mimeType"] = "image/png"
            else:
                im.convert("RGB").save(out, "JPEG", quality=JPEG_QUALITY, optimize=True)
                img_meta["mimeType"] = "image/jpeg"
            chunk = out.getvalue()
        while len(new_bin) % 4:
            new_bin.append(0)
        view["byteOffset"] = len(new_bin)
        view["byteLength"] = len(chunk)
        new_bin += chunk
    while len(new_bin) % 4:
        new_bin.append(0)
    gltf["buffers"][0]["byteLength"] = len(new_bin)

    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(new_bin)
    out = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(new_bin), b"BIN\x00") + bytes(new_bin)
    before = len(data)
    open(path, "wb").write(out)
    print("%s: %.1f MB -> %.1f MB" % (path, before / 1e6, len(out) / 1e6))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        shrink(p)
